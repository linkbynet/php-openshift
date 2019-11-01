
echo "USER_NAME: $(id)"
echo "TZ: ${TZ}"
echo "PHP_TIMEZONE: ${PHP_TIMEZONE}"
echo "PHP version: ${PHP_VERSION}"

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion.d/yii ]; then
    . /etc/bash_completion.d/yii
  fi
fi