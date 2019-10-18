# PHP docker image

This Docker image be used for any PHP application. This inherits from the official [yii2-docker](https://github.com/yiisoft/yii2-docker) image, and is based on the PHP Apache Debian version, with changes made to the configuration to ensure compatibility with the [OpenShift security policy](https://docs.openshift.com/container-platform/3.11/creating_images/guidelines.html). 

If you want to make modifications to the image, your `Dockerfile` should look something like this, ensuring the PHP version is updated in the FROM image descriptor:

```Dockerfile
FROM linkbn/php-openshift:X.X
ARG USER_ID=2000
USER root
COPY src/ /app/
RUN /docker-bin/docker-build.sh
USER ${USER_ID}
```

You can also used the php-fpm variant that php-fpm and apache. Image `linkbn/php-openshift:X.X-fpm`, that include php-fpm and apache HTTPD server with fcgi.

## Entry-point specificity

The entry-point script provides a wait for the service availability to be listed. Before running your command or service, you may be need to wait for supporting services to be up and listening (for example, waiting for you database server to be up and running on port 3306). You can provide the environment variable `WAIT_FOR_IT_LIST` with the list of service to test before starting up the application.

If you want to wait for a MySQL server on port 3306 and an SMTP server on port 25, just provide:

```
WAIT_FOR_IT_LIST=mysql:3306,smtp:25
```

Entry-point can be use for the following actions:

### Run Apache HTTPD

This is the default command, which is run if no other commands are provided. Apache is running on port `8080`.

### Run cron daemon

If the `cron` command is provided.
 
### Run php, bash, composer or yii commands

You can provide the command with a list of arguments.

### Run N instance of a command

If you enter a command with `worker N my_command_to_run`, the command provided will be run in parallel **N** times, if one of the process die, it will be restarted  to keep **N** instances in paralelle.

### Run a command periodically.

If you enter a command with `loop my_command_to_run`, the command provided will be run every **LOOP_TIMEOUT** by default `1d`, so `my_command_to_run` will be executed, and when it's finished it will be run again in **LOOP_TIMEOUT**.

## Image Configuration at buildtime

With docker build arguments (`docker build --build-arg VAR_NAME=VALUE`), if you want to change some of them you will need to run the command as root in your Dockerfile inheriting from the image in the script `/docker-bin/docker-build.sh`.

### System configuration (buildtime)

* **USER_ID**: Id of the user that will run the container (default: `2000`)
* **USER_HOME**: Home directory of the user defined by `USER_ID` (default: `/home/user`)
* **TZ**: System timezone will be used for cron and logs (default: `UTC`, done by `docker-build.sh`)
* **CA_HOSTS_LIST**: List of host CA certificate to add to system CA list, example: `my-server1.local.net:443 my-server2.local.local:8443` (default: `none`, done by `docker-build.sh`)

### Apache HTTPD configuration  (buildtime)

Log format by default is `combined` on container stdout, and apache is listening on port 8080 (http) or 8443 (https). Document root of Apache is `${APP_DIR}/web`.

* **remoteip**: By default remoteip configuration is enabled, see runtime part of the documentation to configure it.
* **serve-cgi-bin**: Is disabled by default.
* **syslog**: You can enable Apache HTTPD logging to syslog, using `a2enconf syslog` in your docker build.

### Cron configuration (buildtime)

We're using [supercronic](https://github.com/aptible/supercronic) as cron dameon. You can put your cronfile in:
*  `/etc/cron.d/` in the normal cron format '`minute` `hour` `day of month` `month` `day of week` `user` (NB: user will not be taken into consideration if our cron is not run as root) will be merged by `docker-build.sh` script at build time.
* or create the file `/etc/crontab` in [supercronic supported format](https://github.com/gorhill/cronexpr).

### Php configuration (buildtime)

List of already embedded modules (defaults are marked with (`*`)):

* apcu (`*`)
* bcmath (`*`)
* exif
* gd
* gearman
* gmp (`*`)
* igbinary (`*`)
* imagick
* intl (`*`)
* mongodb
* pcntl
* pdo_mysql
* pdo_pgsql
* redis (`*`)
* soap
* sockets
* sodium (`*`)
* yaml (`*`)
* xdebug
* Zend OPcache (`*`)
* zip

If you want your specific application to enable one of the above:

```
docker-php-ext-enable extension-name
```

If the module you need is missing you can add them in your `Dockerfile`, see [php docker](https://hub.docker.com/_/php/) image documentation for "[How to install more PHP extensions](https://github.com/docker-library/docs/blob/master/php/README.md#how-to-install-more-php-extensions)".

* **PHP_VERSION**: Version of php used to do the build (default: `7.3`).
* **PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT**: 

### Application configuration (buildtime)

The `docker-build.sh` script will (if `APP_DIR` is not empty):
* Remove the `.git*` file and directories,
* Set execution right to shell script inside `tests` directory if it exist.
* Give read right on files and directories inside `APP_DIR`,
* If there is `composer.json` file, composer will be run,
* Define a value for `PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT` based on the number of php file.

* **APP_DIR**: You PHP application should be installed in that directory (default: `/app`).
* **APP_WRITE_DIRECTORIES**: List of directory in which the application need to be able to write (default: `runtime web/assets web/runtime tests/_output tests/_support/_generated`).

### Documentation Generation configuration (buildtime)

You can generate a static documentation with [daux.io](https://github.com/dauxio/daux.io) to be include in your application, if you've got a documentation directory inside your code.

* **DOC_GENERATE**: Do you want to generate the static doc (default: `yes`).
* **DOC_DIR_SRC**: Source directory of your documentation inside the `/app/` (default: `docs`).
* **DOC_DIR_DST**: Destination directory of the generated documentation in `/app/web/` (default: `doc`).

### Composer configuration (buildtime)

* **COMPOSER_DEV**: Install composer development dependencies (default: `no`, done by `docker-build.sh`).

### Yii configuration (buildtime)

* **YII_ENV**: If set at buildtime and is set to `test` or `dev` **COMPOSER_DEV** will be set to `yes`, so composer development dependencies are installed (`gii`, `codeception`, ...).

## Image Configuration at runtime

With environment variables (`docker run  -e VAR_NAME=VALUE`).

### System configuration (runtime)

* **USER_NAME**: Name of the user that will run the container will have the id defined by **USER_ID** and home defined by **USER_HOME** (default: `default`)

### Apache HTTPD configuration (runtime)

* **APACHE_RUN_USER**: Username of the user that will run apache (default: `$USER_NAME`).
* **APACHE_SERVER_NAME**: Set Apache ServerName (default: `__default__`).

#### Apache HTTPD remoteip configuration (runtime)

* **APACHE_REMOTE_IP_HEADER**: Set `RemoteIPHeader` directive of the [remote_ip module](https://httpd.apache.org/docs/trunk/mod/mod_remoteip.html) (default: `X-Forwarded-For`)
* **APACHE_REMOTE_IP_TRUSTED_PROXY**: Set `RemoteIPtrustedProxy` directive of the [remote_ip module](https://httpd.apache.org/docs/trunk/mod/mod_remoteip.html) (default: `10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`)
* **APACHE_REMOTE_IP_INTERNAL_PROXY**: Set `RemoteIPInternalProxy` directive of the [remote_ip module](https://httpd.apache.org/docs/trunk/mod/mod_remoteip.html) (default: `10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`)

#### Apache HTTPD syslog configuration (runtime)

Will be used only if you add `a2enconf syslog` in your `Dockerfile`.

* **APACHE_SYSLOG_HOST**: IP or DNS of the UDP syslog server (default: `$SYSLOG_HOST`).
* **APACHE_SYSLOG_PORT**: Port of syslog server (default: `$SYSLOG_PORT or 514`).
* **APACHE_SYSLOG_PROGNAME**: Value of logsource field in syslog (default: `httpd`).

### Cron configuration (runtime)

* **CRON_DEBUG**: Enable debug mode of [supercronic](https://github.com/aptible/supercronic).

### PHP configuration (runtime)

You can enable extensions at runtime with the environment variable `PHP_ENABLE_EXTENSION`, you can provide a list of extension by separating them with with comma (`,`).

```
PHP_ENABLE_EXTENSION=gd,exif
```

You can override some PHP configuration setting by defining the following environment variables:

#### General configuration

* **PHP_CGI_FIX_PATHINFO**: [cgi.fix_pathinfo](https://www.php.net/manual/en/ini.core.php#ini.cgi.fix-pathinfo) (default: `0` for mod_php and `1` for fpm)
* **PHP_TIMEZONE**: [date.timezone](http://php.net/manual/en/datetime.configuration.php#ini.date.timezone) (default: `$TZ`)
* **PHP_UPLOAD_MAX_FILESIZE**: [upload_max_filesize](http://php.net/manual/en/ini.core.php#ini.upload-max-filesize) (default: `2m`)
* **PHP_POST_MAX_SIZE**: [post_max_size](http://php.net/manual/en/ini.core.php#ini.post-max-size) (default: `8m`)
* **PHP_MAX_EXECUTION_TIME**: [max_execution_time](http://php.net/manual/en/info.configuration.php#ini.max-execution-time) (default: `30`)
* **PHP_MEMORY_LIMIT**: [memory_limit](http://php.net/manual/en/ini.core.php#ini.memory-limit) (default: `64m`)
* **PHP_REALPATH_CACHE_SIZE**: [realpath_cache_size](http://php.net/manual/en/ini.core.php#ini.realpath-cache-size) (default: `256k`)
* **PHP_REALPATH_CACHE_TTL**: [realpath_cache_ttl](http://php.net/manual/en/ini.core.php#ini.realpath-cache-ttl) (default: `3600`)
* **PHP_DEFAULT_SOCKET_TIMEOUT**: [default_socket_timeout](https://www.php.net/manual/en/filesystem.configuration.php#ini.default-socket-timeout) (default: `60`)

#### Opcache configuration

* **PHP_OPCACHE_ENABLE**: [opcache.enable](http://php.net/manual/en/opcache.configuration.php#ini.opcache.enable) enable Opcache (default: `1` = On)
* **PHP_OPCACHE_ENABLE_CLI**: [opcache.enable_cli](http://php.net/manual/en/opcache.configuration.php#ini.opcache.enable-cli) enable opcache for PHP in CLI (default: `1` = On)
* **PHP_OPCACHE_MEMORY**: [opcache.memory_consumption](http://php.net/manual/en/opcache.configuration.php#ini.opcache.memory-consumption) (default: `64m`)
* **PHP_OPCACHE_VALIDATE_TIMESTAMP**: [opcache.validate_timestamps](http://php.net/manual/en/opcache.configuration.php#ini.opcache.validate-timestamps) (default: `0` = Off)
* **PHP_OPCACHE_REVALIDATE_FREQ**: [opcache.revalidate_freq](http://php.net/manual/en/opcache.configuration.php#ini.opcache.revalidate-freq) (default: `600` seconds)
* **PHP_OPCACHE_MAX_ACCELERATED_FILES**: [opcache.max_accelerated_files](http://php.net/manual/en/opcache.configuration.php#ini.opcache.max-accelerated-files) (default: `PHP_OPCACHE_MAX_ACCELERATED_FILES_DEFAULT` calculate at buildtime by `docker-build.sh`)

### Yii configuration (runtime)

* **YII_DB_MIGRATE**: Enable database schema migration at container start up if set to `true` for more detail refer to [Yii2 databse migration](https://www.yiiframework.com/doc/guide/2.0/en/db-migrations).
* **YII_RBAC_MIGRATE**: Enable creation/update of your list of static roles and permissions on your authManager at container start up if set to `true`. For more detail refer to [macfly/yii2-rbac-cli](https://github.com/marty-macfly/yii2-rbac-cli).
