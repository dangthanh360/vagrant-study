#!/bin/bash

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_info(){
    NL=""
    if [ -n $3 ] || [ $3 -eq 1 ]; then
        NL="\n"
    fi
    echo -e "${NL}$1$2${NC}"
}
print_success(){
    print_info $GREEN "$1" $2
}
print_error(){
    print_info $RED "$1" $2
}
print_progress(){
    print_info $BLUE "$1" $2
}

# Set timezone
timedatectl set-timezone $TIME_ZONE

apt-get -y update

# Install Apache, MySQL, PHP and modules
print_progress 'Install Apache, MySQL, PHP and modules' 1

export DEBIAN_FRONTEND=noninteractive
echo "mysql-server mysql-server/root_password password $MSQL_PASS" | sudo debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MSQL_PASS" | sudo debconf-set-selections

apt-get -yq install apache2 \
mysql-server mysql-client \
php7.2 libapache2-mod-php7.2 php7.2-mysql php7.2-curl php7.2-gd php7.2-intl php-pear php-imagick php7.2-imap php-memcache php7.2-sqlite3 php7.2-xmlrpc php7.2-xsl php7.2-mbstring php-gettext \
zip unzip pv
if [ $? -ne 0 ]; then
    print_error 'Install failed'
    exit 1
else
    print_success 'Install success'
fi

# Install Composer
print_progress 'Installing Composer' 1
curl -sS https://getcomposer.org/installer | php
if [ $? -ne 0 ]; then
    print_error 'Failed to download Composer'
    exit 1
fi
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer
print_success 'Install Composer success'

# Create Yii2 basic project
# We may run "vagrant provision" many times, if project exists, skips create it to avoid create project error)
print_progress 'Create Yii2 basic project' 1
if [ ! -d $WEB_ROOT_DIR ]; then
    mkdir $WEB_ROOT_DIR
    cd $WEB_ROOT_DIR
    composer create-project yiisoft/yii2-app-basic .
fi

# Hide warning: "AH00558: apache2: Could not reliably determine the server's fully qualified domain name, using 127.0.1.1. Set the 'ServerName' directive globally to suppress this message"
if [ -f /etc/apache2/conf-available/servername.conf ]; then
    rm /etc/apache2/conf-available/servername.conf
fi
echo "ServerName localhost" >> /etc/apache2/conf-available/servername.conf
sudo a2enconf servername

# Update /etc/hosts file (skips if host already added)
print_progress 'Update virtual host' 1
if [ -z "$(grep $WEB_HOST /etc/hosts)" ]; then
    echo "127.0.0.1 $WEB_HOST $WEB_HOST" >> /etc/hosts
fi
# Update Apache virtual host
if [ -n "$(apache2ctl -S | grep $WEB_HOST)" ]; then
    a2dissite dev_vhost
fi
if [ -f /etc/apache2/sites-available/dev_vhost.conf ]; then
    rm /etc/apache2/sites-available/dev_vhost.conf
fi
cat /vagrant/dev_vhost_template.conf | sed -e "s|{{root_dir}}|$WEB_ROOT_DIR|gI" -e "s|{{host}}|$WEB_HOST|gI" > /tmp/dev_vhost.conf
cp /tmp/dev_vhost.conf /etc/apache2/sites-available/dev_vhost.conf

a2enmod rewrite headers
systemctl restart apache2
a2ensite dev_vhost
systemctl reload apache2

print_progress 'Installation complete' 1
print_progress "Visit http://${WEB_HOST} to view demo project"
