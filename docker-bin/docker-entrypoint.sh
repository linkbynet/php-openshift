#!/bin/bash

if [ -f "/etc/environment" ]; then
    echo "Source /etc/environment"
    . /etc/environment
fi

basedir=$(dirname $0)

# Set default username if not override
USER_NAME="${USER_NAME:-default}"

# Insert username into pwd
if ! whoami &> /dev/null; then
  if [ -w "/etc/passwd" ]; then
    echo "${USER_NAME}:x:$(id -u):0:${USER_NAME} user:${USER_HOME}:/sbin/bash" >> /etc/passwd
  fi
else
	USER_NAME=$(whoami)
fi

echo "USER_NAME: $(id)"

# Php - Define timezone
if [ -n "${PHP_TIMEZONE}"]; then
	export PHP_TIMEZONE="${TZ}"
fi

echo "TZ: ${TZ}"
echo "PHP_TIMEZONE: ${PHP_TIMEZONE}"
echo "PHP_VERSION: $(php -v | head -n1)"

# Loop on WAIT_FOR_IT_LIST
if [ -n "${WAIT_FOR_IT_LIST}" ]; then
	for hostport in $(echo "${WAIT_FOR_IT_LIST}" | sed -e 's/,/ /g'); do
		${basedir}/wait-for-it.sh -s -t 0 ${hostport}
	done
else
	echo "No WAIT_FOR_IT_LIST"
fi

# Enable xdebug by ENV variable (compatibility with upstream)
if [ 0 -ne "${PHP_ENABLE_XDEBUG:-0}" ] ; then
    PHP_ENABLE_EXTENSION="${PHP_ENABLE_EXTENSION},xdebug"
fi

# Enable extension by ENV variable
if [ -n "${PHP_ENABLE_EXTENSION}" ] ; then
	for extension in $(echo "${PHP_ENABLE_EXTENSION}" | sed -e 's/,/ /g'); do
    	if docker-php-ext-enable ${extension}; then
			echo "Enabled ${extension}"
		else
		    echo "Failed to enable ${extension}"
		fi
		echo ""
	done
else
	echo "PHP_ENABLE_EXTENSION: no extension to load at runtime"
fi

# Optimise opcache.max_accelerated_files, if not set
if [ -z "${PHP_OPCACHE_MAX_ACCELERATED_FILES}" ]; then
	echo "Set PHP_OPCACHE_MAX_ACCELERATED_FILES to PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT"
	export PHP_OPCACHE_MAX_ACCELERATED_FILES=${PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT:-7000}
fi

echo "PHP_OPCACHE_MAX_ACCELERATED_FILES: ${PHP_OPCACHE_MAX_ACCELERATED_FILES:-none}"

# Do database migration
if [ -n "${YII_DB_MIGRATE}" -a "${YII_DB_MIGRATE}" = "true" ]; then
	php yii migrate/up --interactive=0
fi

# Do rbac migration (add/Update/delete rbac permissions/roles)
if [ -n "${YII_RBAC_MIGRATE}" -a "${YII_RBAC_MIGRATE}" = "true" ]; then
    php yii rbac/load rbac.yml
fi

if [ -n "${1}" ]; then
	echo "Command line: ${@}"
fi

if [ "${1}" = "yii" ]; then
	exec php ${@}
elif [ "${1}" = "cron" ]; then
	if [ -n "${CRON_DEBUG}" -a "${CRON_DEBUG}" = "true" ] || [ "${YII_ENV}" = "dev" ]; then
		echo "Cron debug enabled"
		args="-debug"
	fi
	exec /usr/local/bin/supercronic ${args} /etc/crontab
elif [ "${1}" = "bash" -o "${1}" = "php" -o "${1}" = "composer" ]; then
	exec ${@}
elif [ "${1}" = "worker" ]; then
    nb_worker=${2}
    shift 2
    for i in $(seq -w 1 ${nb_worker}); do
        echo "Prepare worker ${i}"
        mkdir -p "/etc/service/worker_${i}"
        echo -e "#!/bin/bash\ncd /app\nexec ${@}\n" > "/etc/service/worker_${i}/run"
        chmod +x "/etc/service/worker_${i}/run"
    done
    exec runsvdir /etc/service/
elif [ "${1}" = "loop" ]; then
	shift
	while true; do
		${@}
		if [ $? -ne 0 ]; then
			echo "failed, exiting" 1>&2
			exit 1
		fi
		echo "Wait for .. ${LOOP_TIMEOUT:-1d}"
		sleep ${LOOP_TIMEOUT:-1d}
	done
else
	# Apache - User
	export APACHE_RUN_USER="${USER_NAME}"
	export APACHE_RUN_GROUP="root"
	echo "APACHE_RUN_USER: ${APACHE_RUN_USER}"
	echo "APACHE_RUN_GROUP: ${APACHE_RUN_GROUP}"
	
	# Apache - Syslog
	if ls -1 /etc/apache2/conf-enabled/ | grep -q '^syslog.conf$'; then
		# APACHE_SYSLOG_HOST not defined but SYSLOG_HOST is
		if [ -n "${SYSLOG_HOST}" -a -z "${APACHE_SYSLOG_HOST}" ]; then
			export APACHE_SYSLOG_HOST=${SYSLOG_HOST}
		fi
		if [ -n "${SYSLOG_PORT}" -a -z "${APACHE_SYSLOG_PORt}" ]; then
			export APACHE_SYSLOG_PORT=${SYSLOG_PORT}
		fi
		echo "APACHE Syslog enabled"
		echo "APACHE_SYSLOG_HOST: ${APACHE_SYSLOG_HOST}"
		echo "APACHE_SYSLOG_PORT: ${APACHE_SYSLOG_PORT}"
		echo "APACHE_SYSLOG_PROGNAME: ${APACHE_SYSLOG_PROGNAME}"
	fi

	echo "APACHE_REMOTE_IP_HEADER: ${APACHE_REMOTE_IP_HEADER}"
	echo "APACHE_REMOTE_IP_TRUSTED_PROXY: ${APACHE_REMOTE_IP_TRUSTED_PROXY}"
	echo "APACHE_REMOTE_IP_INTERNAL_PROXY: ${APACHE_REMOTE_IP_INTERNAL_PROXY}"

	if which php-fpm 2>&1 > /dev/null; then
		echo "No command line running Apache HTTPD server with php-fpm"
		export PHP_CGI_FIX_PATHINFO=1
		mkdir -p /etc/service/{apache,php-fpm}
		echo -e "#!/bin/bash\nif [ \$(id -u \${APACHE_RUN_USER}) -eq 0 ]; then\n\tunset APACHE_RUN_USER\nfi\nexec apachectl -DFOREGROUND\n" > "/etc/service/apache/run"
		echo -e "#!/bin/bash\nexec php-fpm --nodaemonize --force-stderr --allow-to-run-as-root\n" > "/etc/service/php-fpm/run"
		chmod +x /etc/service/*/run
		exec runsvdir /etc/service/
	else
		echo "No command line running Apache HTTPD server with mod_php"
		exec "apache2-foreground"
	fi
fi
