ARG PHP_VERSION=7.4
ARG PHP_MOD=apache-buster
ARG PHP_BASE_IMAGE_VERSION
# Need to hard code the version until this is resolved https://github.com/renovatebot/renovate/issues/5626
FROM php:7.4-apache-buster@sha256:335634d693b8cdefdc84de91f676ff7b81aa9daa13f06931b87a60f5658216e1
ENV DEBIAN_FRONTEND=noninteractive
ARG USER_ID=2000
ARG APP_DIR=/app
ARG USER_HOME=/home/user
ARG TZ=UTC
ARG CA_HOSTS_LIST
ARG YII_ENV
# System - Application path
ENV APP_DIR ${APP_DIR}
# System - Update embded package
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install --no-install-recommends \
            g++ \
            git \
            curl \
            gnupg2 \
            imagemagick \
            libcurl3-dev \
            libicu-dev \
            libfreetype6-dev \
            libjpeg-dev \
            libjpeg62-turbo-dev \
            libmagickwand-dev \
            libpq-dev \
            libpng-dev \
            libxml2-dev \
            libzip-dev \
            zlib1g-dev \
            openssh-client \
            nano \
            unzip \
            libcurl4-openssl-dev \
            libssl-dev \
            netcat \
            runit
# System - Set default timezone
ENV TZ ${TZ}
# System - Define HOME directory
ENV USER_HOME ${USER_HOME}
RUN mkdir -p ${USER_HOME} && \
    chgrp -R 0 ${USER_HOME} && \
    chmod -R g=u ${USER_HOME}
# System - Set path
ENV PATH=/app:/app/vendor/bin:/root/.composer/vendor/bin:$PATH
# System - Set terminal type
ENV TERM=linux
# System - Install Yii framework bash autocompletion
RUN curl -sSL https://raw.githubusercontent.com/yiisoft/yii2/master/contrib/completion/bash/yii \
        -o /etc/bash_completion.d/yii
# Apache - install apache and mod fcgi if php-fpm
ENV PHPFPM_PM_MAX_CHILDREN 10
ENV PHPFPM_PM_START_SERVERS 5
ENV PHPFPM_PM_MIN_SPARE_SERVERS 2
ENV PHPFPM_PM_MAX_SPARE_SERVERS 5
RUN rm -f /etc/apache2/sites-available/000-default.conf
RUN which apache2 2>&1 > /dev/null || (apt-get install --no-install-recommends -y apache2 && a2enmod proxy_fcgi && \
    sed -i -e 's#^export \([^=]\+\)=\(.*\)$#export \1=${\1:=\2}#' /etc/apache2/envvars && \
    sed -i -e 's#\(listen *= *\).*$#\1/var/run/php-fpm/fpm.sock#g' \
        -e 's#^\(user *= *\).*$#\1${APACHE_RUN_USER}#g' \
        -e 's#^\(group *= *\).*$#\1${APACHE_RUN_GROUP}#g' \
        -e 's#^\(pm.max_children *= *\).*$#\1${PHPFPM_PM_MAX_CHILDREN}#g' \
        -e 's#^\(pm.start_servers *= *\).*$#\1${PHPFPM_PM_START_SERVERS}#g' \
        -e 's#^\(pm.min_spare_servers *= *\).*$#\1${PHPFPM_PM_MIN_SPARE_SERVERS}#g' \
        -e 's#^\(pm.max_spare_servers *= *\).*$#\1${PHPFPM_PM_MAX_SPARE_SERVERS}#g' \
        /usr/local/etc/php-fpm.d/*.conf)
# All - Add configuration files
COPY image-files/ /
RUN chgrp -R 0 /etc/service.tpl && \
    chmod -R g=u /etc/service.tpl
# Apache - Enable mod rewrite and headers
RUN a2enmod headers rewrite
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
RUN mkdir -p /var/lock/apache2 /var/run/apache2 /var/run/php-fpm && \
    chgrp -R 0 /run /var/lock/apache2 /var/log/apache2 /var/run/apache2 /etc/service /var/run/php-fpm && \
    chmod -R g=u /etc/passwd /run /var/lock/apache2 /var/log/apache2 /var/run/apache2 /etc/service
RUN rm -f /var/log/apache2/*.log && \
    ln -s /proc/self/fd/2 /var/log/apache2/error.log && \
    ln -s /proc/self/fd/1 /var/log/apache2/access.log
RUN sed -i -e 's/80/8080/g' -e 's/443/8443/g' /etc/apache2/ports.conf
EXPOSE 8080 8443
# Cron - use supercronic (https://github.com/aptible/supercronic)
ENV SUPERCRONIC_VERSION=0.1.11
ENV SUPERCRONIC_SHA1SUM=a2e2d47078a8dafc5949491e5ea7267cc721d67c
RUN curl -sSL "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64" > "/usr/local/bin/supercronic" && \
 echo "${SUPERCRONIC_SHA1SUM}" "/usr/local/bin/supercronic" | sha1sum -c - && \
 chmod a+rx "/usr/local/bin/supercronic"
ENV DOC_GENERATE yes
ENV DOC_DIR_SRC docs
ENV DOC_DIR_DST doc
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
ENV PHP_OPCACHE_MEMORY 64m
ENV PHP_OPCACHE_VALIDATE_TIMESTAMP 0
ENV PHP_OPCACHE_REVALIDATE_FREQ 600
# Php - update pecl protocols
RUN pecl channel-update pecl.php.net
# Php - Install extensions required for Yii 2.0 Framework
RUN apt-get install -y --no-install-recommends libonig$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 6 ] && echo "5" || echo "4") libonig-dev &&\
    docker-php-ext-configure gd $([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 6 -a $(echo "${PHP_VERSION}" | cut -f2 -d.) -gt 3 -o $(echo "${PHP_VERSION}" | cut -f1 -d.) -eq 8 ] && echo "--with-freetype --with-jpeg" || echo "--with-freetype-dir=/usr/include/ --with-png-dir=/usr/include/ --with-jpeg-dir=/usr/include/")
RUN docker-php-ext-configure bcmath && \
    docker-php-ext-install \
        soap \
        zip \
        curl \
        bcmath \
        exif \
        gd \
        iconv \
        intl \
        mbstring \
        opcache \
        pdo_mysql \
        pdo_pgsql && \
    apt-get remove -y libonig-dev
# Php - Install image magick (see http://stackoverflow.com/a/8154466/291573 for usage of `printf`)
# need to wait for https://github.com/Imagick/imagick/issues/358
RUN [ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 7 ] || (printf "\n" | pecl install imagick && \
    docker-php-ext-enable imagick)
# Php - Mongodb with SSL
RUN apt-get install -y --no-install-recommends libssl1.1 libssl-dev &&\
    pecl uninstall mongodb && \
    pecl install mongodb && \
    apt-get remove -y libssl-dev
# Add GITHUB_API_TOKEN support for composer
RUN chmod 700 \
        /usr/local/bin/docker-php-entrypoint \
        /usr/local/bin/composer
# Composer - Install composer
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN curl -sS https://getcomposer.org/installer | php -- \
        --filename=composer.phar \
        --install-dir=/usr/local/bin && \
    chmod a+rx "/usr/local/bin/composer"
# Php - Cache & Session support
# Php - Redis (for php 5.X use 4.3.0 last compatible version)
RUN pecl install redis$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-4.3.0") && \
    docker-php-ext-enable redis
# Php - Yaml (for php 5.X use 1.3.2 last compatible version)
RUN apt-get install -y --no-install-recommends libyaml-dev libyaml-0-2 && \
    pecl install yaml$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-1.3.2") && \
    docker-php-ext-enable yaml && \
    apt-get remove -y libyaml-dev
# Php - GMP
RUN apt-get install -y --no-install-recommends libgmp-dev libgmpxx4ldbl && \
    ln -s /usr/include/x86_64-linux-gnu/gmp.h /usr/include/gmp.h && \
    docker-php-ext-install gmp && \
    apt-get remove -y libgmp-dev
# Php - Gearman (for php 5.X use 1.1.X last compatible version, not supported on php 8)
RUN [ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 7 ] || (apt-get install -y --no-install-recommends git unzip libgearman-dev libgearman$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 6 ] && echo "8" || echo "7") && \
    [ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 6 ] && (git clone https://github.com/wcgallego/pecl-gearman.git && cd pecl-gearman && phpize && ./configure && make && make install && cd - && rm -rf pecl-gearman) || pecl install gearman && \
    apt-get remove -y libgearman-dev)
# Php - pcntl
RUN docker-php-ext-install pcntl
# Php - Xdebug (for php 5.X use 2.5.5 last compatible version)
ENV PHP_ENABLE_XDEBUG=0
ENV PHP_XDEBUG_MODE=debug
RUN pecl install xdebug$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-2.5.5")
# Php - Sockets
RUN docker-php-ext-install sockets
# Php - Igbinary (for php 5.X use 2.0.8 last compatible version)
RUN pecl install igbinary$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-2.0.8") && \
    docker-php-ext-enable igbinary && \
    echo "session.serialize_handler=igbinary" >> /usr/local/etc/php/conf.d/docker-php-ext-igbinary.ini
RUN pecl install apcu$([ $(echo "${PHP_VERSION}" | cut -f1 -d.) -lt 6 ] && echo "-4.0.11") && \
    docker-php-ext-enable apcu && \
    echo "apc.serializer=igbinary" >> /usr/local/etc/php/conf.d/docker-php-ext-igbinary.ini && \
    echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini
# Pinpoint - Collector agent
ENV PINPOINT_COLLECTOR_AGENT_VERSION 0.4.0
ARG PINPOINT_COLLECTOR_AGENT_DIR=/opt/pinpoint-collector-agent
ENV PINPOINT_COLLECTOR_AGENT_DIR ${PINPOINT_COLLECTOR_AGENT_DIR}
ENV PINPOINT_COLLECTOR_AGENT_TYPE 1500
ENv PINPOINT_COLLECTOR_AGENT_LOGDIR /var/log/pinpoint-collector-agent
ENV PINPOINT_COLLECTOR_AGENT_LOGLEVEL ERROR
ENV PINPOINT_COLLETOR_AGENT_ADDRESS unix:/var/run/pinpoint-collector-agent/collector-agent.sock

ENV PINPOINT_COLLECTOR_GRPC_AGENT_PORT 9991
ENV PINPOINT_COLLECTOR_GRPC_STAT_PORT 9992
ENV PINPOINT_COLLECTOR_GRPC_SPAN_PORT 9993
# Pinpoint - Fetch source
RUN git clone https://github.com/naver/pinpoint-c-agent.git /opt/pinpoint-c-agent/ && \
    cd /opt/pinpoint-c-agent && \
    git checkout v${PINPOINT_COLLECTOR_AGENT_VERSION} && \
    mv collector-agent ${PINPOINT_COLLECTOR_AGENT_DIR}
# Pinpoint - Install pinpoint collector agent
RUN apt-get update && \
    apt-get install -y python3-pip && \
    cd /opt/pinpoint-collector-agent && \
    pip3 install -r requirements.txt && \
    pip3 install grpcio-tools && \
    python3 -m grpc_tools.protoc -I./Proto/grpc --python_out=./Proto/grpc --grpc_python_out=./Proto/grpc ./Proto/grpc/*.proto && \
    mkdir -p ${PINPOINT_COLLECTOR_AGENT_LOGDIR} /var/run/pinpoint-collector-agent && \
    chgrp -R 0 ${PINPOINT_COLLECTOR_AGENT_DIR} ${PINPOINT_COLLECTOR_AGENT_LOGDIR} /var/run/pinpoint-collector-agent && \
    chmod -R g=u ${PINPOINT_COLLECTOR_AGENT_DIR} ${PINPOINT_COLLECTOR_AGENT_LOGDIR} /var/run/pinpoint-collector-agent
# Pinpoint - Php module configuration
ENV PINPOINT_PHP_COLLETOR_AGENT_HOST ${PINPOINT_COLLETOR_AGENT_ADDRESS}
ENV PINPOINT_PHP_SEND_SPAN_TIMEOUT_MS 0
ENV PINPOINT_PHP_TRACE_LIMIT -1
# Pinpoint - Install pinpoint php module (disalbe on php 8 waiting for https://github.com/pinpoint-apm/pinpoint-c-agent/issues/249)
RUN [ $(echo "${PHP_VERSION}" | cut -f1 -d.) -gt 7 ] || (apt-get update && \
    apt-get install -y cmake && \
    cd /opt/pinpoint-c-agent/ && \
    phpize && \
    ./configure && \
    make && \
    make test TESTS=src/PHP/tests/ && \
    make install && \
    make clean && \
    rm -rf /opt/pinpoint-c-agent)
# Php - Disable extension should be enable by user if needed
RUN chmod g=u /usr/local/etc/php/conf.d/ && \
    chown root:root -R /usr/local/etc/php/conf.d && \
    rm -f /usr/local/etc/php/conf.d/docker-php-ext-exif.ini \
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
# System - Clean apt
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN mkdir -p ${APP_DIR}
RUN chmod a+rx /docker-bin/*.sh && \
    /docker-bin/docker-build.sh
WORKDIR ${APP_DIR}
USER ${USER_ID}
ENTRYPOINT ["/docker-bin/docker-entrypoint.sh"]
