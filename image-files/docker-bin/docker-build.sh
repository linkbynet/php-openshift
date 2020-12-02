#!/bin/bash

set -e

if [ $(id -u) -ne 0 ]; then
    echo "Script should be run as root during buildtime."
    exit 1
else
    echo "Running as root that's cool :)"
fi

# System - set exec on scripts in /docker-bin/
echo "Set exec mode on '/docker-bin/*.sh'"
chmod a+rx /docker-bin/*.sh 

# System - set the proper timezone
if [ -n "${TZ}" ]; then
	ln -snf "/usr/share/zoneinfo/$TZ" "/etc/localtime"
	echo "$TZ" > /etc/timezone
fi

# System - Add extra ca-certificate to system certificates
if [ -n "${CA_HOSTS_LIST}" ]; then
    for hostAndPort in ${CA_HOSTS_LIST}; do
        echo "Adding ca-certificate of ${hostAndPort}"
        openssl s_client -connect ${hostAndPort} -showcerts < /dev/null | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; out="/usr/local/share/ca-certificates/'${hostAndPort}'"a".crt"; print >out}'
    done
    update-ca-certificates
fi

tz=$(ls -l "/etc/localtime" | awk '{print $NF}' | sed -e 's#/usr/share/zoneinfo/##g')
echo "TZ: ${TZ:-default} (effective ${tz})"

# Cron - Merge all files in /etc/cron.d into /etc/crontab
if [ -d "/etc/cron.d" ]; then
	# Remove the user name and merge into one file
    echo "Merging cron in '/etc/cron.d' into '/etc/crontab'"
	sed -r 's/(\s+)?\S+//6' /etc/cron.d/* > /etc/crontab
fi

if [ -f "/etc/crontab" ]; then
    echo "Set mode g=rw on '/etc/crontab'"
    chmod 664 /etc/crontab
fi

# Apache - Fix upstream link error
if [ -d /var/www/html ]; then
    rm -rf /var/www/html
    ln -s ${APP_DIR}/web/ /var/www/html
fi

# Apache - fix cache directory
if [ -d /var/cache/apache2 ]; then
    chgrp -R 0 /var/cache/apache2
    chmod -R g=u /var/cache/apache2
fi

# Application - cutomization
APP_DIR="${APP_DIR:-.}"
echo -e "\nAPP_DIR: ${APP_DIR}\n"

if [ -z "$(ls -A ${APP_DIR})" ]; then
    echo -e "APP_DIR is empty"
    exit 0
fi

# Application - remove development directory
cd ${APP_DIR}
for file in .git .gitlab*; do
    if [ -e "${file}" ]; then
        echo -e "\tCleanup: ${file}"
        rm -rf ${file}
    fi
done

# Application - set execution right to sh script in tests
if [ -d "tests" ]; then
    echo -e "\tSet exec mode on 'tests/*.sh'"
    find tests/ -type f -name '*.sh' -exec chmod a+rx {} \;
fi

# Application - set read right to everything to every one.
echo -e "\tSet '${APP_DIR}' mode ugo=r for file and ugo=rx for directory"
find . -path ./vendor -prune -o -type d -exec chmod 555 {} \;
find . -path ./vendor -prune -o -type f -exec chmod 444 {} \;

# Application - create directory where the application need to write.
for dir in ${APP_WRITE_DIRECTORIES:-runtime web/assets web/runtime tests/_output tests/_support/_generated}; do
    if [ ! -d "${dir}" ]; then
        echo -e "\tCreate directory: ${dir}"
        mkdir -p "${dir}"
    fi
    echo -e "\tSet mode ug=rwx on directory: ${dir}"
    chmod 775 "${dir}"
done

# Install dev dependencies if test and dev
if [ "${YII_ENV}" = "test" -o "${YII_ENV}" = "dev" ]; then
    echo -e "\tYII_ENV: ${YII_ENV:-not set} so composer will install dev dependencies."
    COMPOSER_DEV="yes"
fi

# Install/Update composer
if [ -f "composer.json" ]; then
    if [ "${COMPOSER_DEV}" != "yes" ]; then
        args="--no-dev"
    fi
    echo -e "\tRunning composer ${args}"
    composer -n ${args} -o update
    
    if [ "${DOC_GENERATE}" = "yes" -a -d "${DOC_DIR_SRC}" ]; then
        composer global require daux/daux.io
        echo "Create doc from ${DOC_DIR_SRC} to web/${DOC_DIR_DST}"
        ~/.composer/vendor/bin/daux generate -s ${DOC_DIR_SRC} -d web/${DOC_DIR_DST}
    fi
    # Clean composer cache
    composer clear-cache

    if [ "${COMPOSER_DEV}" != "yes" ]; then
        rm -rf ${USER_HOME}/.composer
    fi
fi

# Optimise opcache.max_accelerated_files, if settings is too small
nb_files=$(find . -type f -name '*.php' -print | wc -l)
if [ ${nb_files} -gt 0 ]; then
    echo "Set PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT to ${nb_files}"
	echo "export PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT=${nb_files}" >> /etc/environment
fi

cd - > /dev/null
echo 
