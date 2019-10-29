ARG PHP_VERSION=7.2
ARG PHP_MOD=apache
FROM yiisoftware/yii2-php:${PHP_VERSION}-${PHP_MOD}
ARG USER_ID=2000
ARG APP_DIR=/app
ARG USER_HOME=/home/user
ARG TZ=UTC
ARG CA_HOSTS_LIST
ARG YII_ENV
# System - Application path
ENV APP_DIR ${APP_DIR}
# System - Update embded package
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get install -y netcat runit
# System - Set default timezone
ENV TZ ${TZ}
# System - Define HOME directory
ENV USER_HOME ${USER_HOME}
RUN mkdir -p ${USER_HOME} \
    && chgrp -R 0 ${USER_HOME} \
    && chmod -R g=u ${USER_HOME}
# Apache - install apache and mod fcgi if php-fpm
RUN rm -f /etc/apache2/sites-available/000-default.conf
RUN which apache2 2>&1 > /dev/null || (apt-get install -y apache2 && a2enmod headers proxy_fcgi rewrite \
        && sed -i -e 's#^export \([^=]\+\)=\(.*\)$#export \1=${\1:=\2}#' /etc/apache2/envvars \
        && sed -i -e 's#\(listen *= *\).*$#\1/var/run/php-fpm/fpm.sock#g' -e 's#^\(user *= *\).*$#\1${APACHE_RUN_USER}#g' -e 's#^\(group *= *\).*$#\1${APACHE_RUN_GROUP}#g' /usr/local/etc/php-fpm.d/*.conf)
# Apache - configuration
COPY apache2/conf-available/ /etc/apache2/conf-available/
# Apache - Disable useless configuration
RUN a2disconf serve-cgi-bin
# Apache - remoteip module
RUN a2enmod remoteip
RUN sed -i 's/%h/%a/g' /etc/apache2/apache2.conf
ENV APACHE_REMOTE_IP_HEADER X-Forwarded-For
ENV APACHE_REMOTE_IP_TRUSTED_PROXY 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
ENV APACHE_REMOTE_IP_INTERNAL_PROXY 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
RUN a2enconf remoteip
# Apache - Hide version
RUN sed -i 's/^ServerTokens OS$/ServerTokens Prod/g' /etc/apache2/conf-available/security.conf
# Apache - Avoid warning at startup
ENV APACHE_SERVER_NAME __default__
RUN a2enconf servername
# Apache - Logging
RUN sed -i -e 's/vhost_combined/combined/g' -e 's/other_vhosts_access/access/g' /etc/apache2/conf-available/other-vhosts-access-log.conf
# Apache - Syslog Log
ENV APACHE_SYSLOG_PORT 514
ENV APACHE_SYSLOG_PROGNAME httpd
# Apache- Prepare to be run as non root user
RUN mkdir -p /var/lock/apache2 /var/run/php-fpm\
    && chgrp -R 0 /run /var/lock/apache2 /var/log/apache2 /etc/service /var/run/php-fpm \
    && chmod -R g=u /etc/passwd /run /var/lock/apache2 /var/log/apache2 /etc/service
RUN rm -f /var/log/apache2/*.log \
    && ln -s /proc/self/fd/2 /var/log/apache2/error.log \
    && ln -s /proc/self/fd/1 /var/log/apache2/access.log
RUN sed -i -e 's/80/8080/g' -e 's/443/8443/g' /etc/apache2/ports.conf
EXPOSE 8080 8443
# Apache - default virtualhost configuration
COPY apache2/sites-available/ /etc/apache2/sites-available/
# Cron - use supercronic (https://github.com/aptible/supercronic)
ENV SUPERCRONIC_VERSION=0.1.9
ENV SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85
RUN curl -sSL "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64" > "/usr/local/bin/supercronic" \
 && echo "${SUPERCRONIC_SHA1SUM}" "/usr/local/bin/supercronic" | sha1sum -c - \
 && chmod a+rx "/usr/local/bin/supercronic"
# Composer - make it usable by everyone
RUN chmod a+rx "/usr/local/bin/composer"
ENV DOC_GENERATE yes
ENV DOC_DIR_SRC docs
ENV DOC_DIR_DST doc
# Php - update pecl protocols
RUN pecl channel-update pecl.php.net
# Php - Cache & Session support
# Php - Redis (for php 5.X use 4.3.0 last compatible version)
RUN pecl install redis$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-4.3.0") \
    && docker-php-ext-enable redis
# Php - Yaml (for php 5.X use 1.3.2 last compatible version)
RUN apt-get install -y --no-install-recommends libyaml-dev libyaml-0-2 \
    && pecl install yaml$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-1.3.2") \
    && docker-php-ext-enable yaml \
    && apt-get remove -y libyaml-dev
# Php - GMP
RUN apt-get install -y --no-install-recommends libgmp-dev libgmpxx4ldbl \
    && ln -s /usr/include/x86_64-linux-gnu/gmp.h /usr/include/gmp.h \
    && docker-php-ext-install gmp \
    && apt-get remove -y libgmp-dev
# Php - Gearman (for php 5.X use 1.1.X last compatible version)
RUN apt-get install -y --no-install-recommends git unzip libgearman-dev libgearman7 \
    && [ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 6 ] && (git clone https://github.com/wcgallego/pecl-gearman.git && cd pecl-gearman && phpize && ./configure && make && make install && cd - && rm -rf pecl-gearman) || pecl install gearman \
    && apt-get remove -y libgearman-dev
# Php - pcntl
RUN docker-php-ext-install pcntl
# Php - Mongodb with SSL
RUN apt-get install -y --no-install-recommends libssl1.0.2 libssl-dev \
    && pecl uninstall mongodb \
    && pecl install mongodb \
    && apt-get remove -y libssl-dev
# Php - Xdebug (for php 5.X use 2.5.5 last compatible version)
RUN pecl install xdebug$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-2.5.5")
# Php - Sockets
RUN docker-php-ext-install sockets
# Php - Igbinary (for php 5.X use 2.0.8 last compatible version)
RUN pecl install igbinary$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-2.0.8") \
    && docker-php-ext-enable igbinary \
    && echo "session.serialize_handler=igbinary" >> /usr/local/etc/php/conf.d/docker-php-ext-igbinary.ini
RUN pecl install apcu$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-4.0.11") \
    && docker-php-ext-enable apcu \
    && echo "apc.serializer=igbinary" >> /usr/local/etc/php/conf.d/docker-php-ext-igbinary.ini \
    && echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini
# Php - Disable extension should be enable by user if needed
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-exif.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-gd.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-gearman.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-mongodb.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-pcntl.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-pdo_pgsql.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-soap.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-sockets.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-zip.ini
COPY php/conf.d/ /usr/local/etc/php/conf.d/
# Php - Set default php.ini config variables (can be override at runtime)
ENV PHP_CGI_FIX_PATHINFO 0
ENV PHP_UPLOAD_MAX_FILESIZE 2m
ENV PHP_POST_MAX_SIZE 8m
ENV PHP_MAX_EXECUTION_TIME 30
ENV PHP_MEMORY_LIMIT 64m
ENV PHP_REALPATH_CACHE_SIZE 256k
ENV PHP_REALPATH_CACHE_TTL 3600
ENV PHP_DEFAULT_SOCKET_TIMEOUT 60
# Php - Opcache extension configuration
ENV PHP_OPCACHE_ENABLE 1
ENV PHP_OPCACHE_ENABLE_CLI 1
ENV PHP_OPCACHE_MEMORY 64
ENV PHP_OPCACHE_VALIDATE_TIMESTAMP 0
ENV PHP_OPCACHE_REVALIDATE_FREQ 600
# System - Clean apt
RUN apt-get autoremove -y
COPY docker-bin/ /docker-bin/
RUN chmod a+rx /docker-bin/*.sh \
    && /docker-bin/docker-build.sh
WORKDIR ${APP_DIR}
USER ${USER_ID}
ENTRYPOINT ["/docker-bin/docker-entrypoint.sh"]
