#!/bin/bash

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PLUGINS_DIR=/var/lib/jenkins/plugins

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
print_notice(){
    print_info $LIGHT_CYAN "$1" $2
}

install_plugin(){
    if [ -f ${PLUGINS_DIR}/${1}.hpi -o -f ${PLUGINS_DIR}/${1}.jpi ]; then
        if [ "$2" == "1" ]; then
            return 1
        fi
        
        return 0
    else
        echo "Installing: $1"
        curl -L --silent --output ${PLUGINS_DIR}/${1}.hpi  https://updates.jenkins-ci.org/latest/${1}.hpi
        return 0
    fi
}
install_plugin_and_dependecies(){
    plugins=($PLUGINS_LIST)
    for plugin in ${plugins[@]}
    do
        install_plugin "$plugin"
    done

    changed=1
    maxloops=100
    while [ "$changed"  == "1" ]; do
        echo "Check for missing dependecies ..."
        if  [ $maxloops -lt 1 ]; then
            echo "Max loop count reached - probably a bug in this script: $0"
            exit 1
        fi

        ((maxloops--))
        changed=0
        for f in ${PLUGINS_DIR}/*.hpi; do
            DEPENDS=$( unzip -p ${f} META-INF/MANIFEST.MF | tr -d '\r' | sed -e ':a;N;$!ba;s/\n //g' | grep -e "^Plugin-Dependencies: " | awk '{ print $2 }' | tr ',' '\n' | awk -F ':' '{ print $1 }' | tr '\n' ' ' )
            if [ ! -z "$DEPENDS" ]; then
                for p in $DEPENDS; do
                    install_plugin "$p" 1 && changed=1
                done
            fi
        done
    done

    echo "fixing permissions"
    chown jenkins.jenkins ${PLUGINS_DIR} -R
}

# Set timezone
timedatectl set-timezone $TIME_ZONE

# Update repository
print_progress 'Updating repository...' 1
apt-get --allow-releaseinfo-change update
add-apt-repository ppa:webupd8team/java -y
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections

wget -qO - https://pkg.jenkins.io/debian/jenkins.io.key | apt-key add -
echo "deb http://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list

apt-get -qy update

# Install dependencies
print_progress 'Installing dependencies...' 1
apt-get install -qqy oracle-java8-installer jenkins unzip
if [ $? -ne 0 ]; then
    print_error ' ---> Install failed'
    exit 1
else
    print_success ' ---> Install success'
fi

# Install plugins
print_progress 'Installing some suggested plugins...' 1
if [ ! -d /var/lib/jenkins/plugins ]; then
    mkdir /var/lib/jenkins/plugins
fi

install_plugin_and_dependecies
service jenkins restart

# Setup Jenkins
print_progress 'Sleep for 30 seconds to wait for Jenkins configures system and then set up admin password...' 1
sleep 30
# Set admin password
PASS="$(echo -n $ADMIN_PASS{$ADMIN_PASS_SALT} | sha256sum | sed 's/ .*-//')"
sed -i "s|<passwordHash>.*</passwordHash>|<passwordHash>${ADMIN_PASS_SALT}:${PASS}</passwordHash>|" /var/lib/jenkins/users/admin/config.xml

# Start Jenkins to init some configurations file
print_progress 'Starting Jenkins...' 1
service jenkins restart
if [ $? -ne 0 ]; then
    print_error ' ---> Start Jenkins failed'
    exit 1
else
    print_success ' ---> Start Jenkins success'
fi

# Disable setup wizard
sed -i 's|JAVA_ARGS="-Djava.awt.headless=true"|JAVA_ARGS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"|' /etc/default/jenkins;
if [ ! -d /var/lib/jenkins/init.groovy.d ]; then
    mkdir /var/lib/jenkins/init.groovy.d
fi
/bin/cp -rf /vagrant/disable_setup_wizard.groovy /var/lib/jenkins/init.groovy.d/
chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d/

# At the first time access Jenkins from browser (after setup completed), if we skip setup wizard --> blank page is shown
# Restart Jenkins to fix this issue, maybe this is a bug
CRUMB=$(curl -u admin:{$ADMIN_PASS} -s "http://{$HOST_IP}:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
curl -X POST -u admin:{$ADMIN_PASS} -H "$CRUMB" "http//{$HOST_IP}:8080/restart"

print_notice 'Installation complete' 1
print_notice "Visit http://${HOST_IP}:8080/configure with username and password ${RED}admin:admin${NC} to update configurations"
