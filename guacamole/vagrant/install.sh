#!/bin/bash

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHT_CYAN='\033[1;36m'
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
print_notice(){
    print_info $LIGHT_CYAN "$1" $2
}
print_progress(){
    print_info $BLUE "$1" $2
}

# Log Location
LOG="/tmp/guacamole_${GUACVERSION}_build.log"
# Tomcat version
TOMCAT="tomcat8"

# Set MySQL root password
debconf-set-selections <<< "mysql-server mysql-server/root_password password $MSQL_ROOT_PASS"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MSQL_ROOT_PASS"

# Ubuntu 18.04 does not include universe repo by default
source /etc/os-release
if [[ "${VERSION_ID}" == "18.04" ]]
then
    sed -i 's/bionic main$/bionic main universe/' /etc/apt/sources.list
fi
if [[ "${VERSION_ID}" == "16.04" ]]
then
    LIBPNG="libpng12-dev"
else
    LIBPNG="libpng-dev"
fi

# Install features
apt-get -qq update
print_progress 'Installing dependencies'

apt-get -qqy install build-essential libcairo2-dev libjpeg-turbo8-dev ${LIBPNG} libossp-uuid-dev libavcodec-dev libavutil-dev \
libswscale-dev libfreerdp-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
libvorbis-dev libwebp-dev mysql-server mysql-client mysql-common mysql-utilities libmysql-java ${TOMCAT} freerdp-x11 \
ghostscript wget dpkg-dev
if [ $? -ne 0 ]; then
    print_error ' ---> Install failed'
    exit 1
else
    print_success ' ---> Install success'
fi

# If apt fails to run completely the rest of this isn't going to work...
if [ $? -ne 0 ]; then
    print_error 'apt-get failed to install all required dependencies'
    exit 1
fi

# Set SERVER to be the preferred download server from the Apache CDN
SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"
print_progress 'Downloading Files...' 1
# Download Guacamole Server
wget -qO guacamole-server-${GUACVERSION}.tar.gz ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    print_error " ---> Failed to download guacamole-server-${GUACVERSION}.tar.gz"
    print_error " ---> ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz"
    exit 1
fi
print_success " ---> Downloaded guacamole-server-${GUACVERSION}.tar.gz"

# Download Guacamole Client
wget -qO guacamole-${GUACVERSION}.war ${SERVER}/binary/guacamole-${GUACVERSION}.war
if [ $? -ne 0 ]; then
    print_error " ---> Failed to download guacamole-${GUACVERSION}.war"
    print_error " ---> ${SERVER}/binary/guacamole-${GUACVERSION}.war"
    exit 1
fi
print_success " ---> Downloaded guacamole-${GUACVERSION}.war"

# Download Guacamole authentication extensions
wget -qO guacamole-auth-jdbc-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    print_error " ---> Failed to download guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    print_error " ---> ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    exit 1
fi
print_success " ---> Downloaded guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
print_success ' ---> Downloading complete'

# Extract Guacamole files
tar -xzf guacamole-server-${GUACVERSION}.tar.gz
tar -xzf guacamole-auth-jdbc-${GUACVERSION}.tar.gz

# Make directories
mkdir -p /etc/guacamole/lib
mkdir -p /etc/guacamole/extensions

# Install guacd
cd guacamole-server-${GUACVERSION}

# Patch for Guacamole Server 0.9.14
wget -qO ./src/terminal/cd0e48234a079813664052b56c501e854753303a.patch https://github.com/apache/guacamole-server/commit/cd0e48234a079813664052b56c501e854753303a.patch
if [ $? -ne 0 ]; then
    print_error ' ---> Failed to download cd0e48234a079813664052b56c501e854753303a.patch'
    print_error ' ---> https://github.com/apache/guacamole-server/commit/cd0e48234a079813664052b56c501e854753303a.patch'
    print_error ' ---> Attempting to proceed without patch...'
else
    patch ./src/terminal/typescript.c ./src/terminal/cd0e48234a079813664052b56c501e854753303a.patch
fi

# Hack for gcc7
if [[ $(gcc --version | head -n1 | grep -oP '\)\K.*' | awk '{print $1}' | grep "^7" | wc -l) -gt 0 ]]
then
    print_progress 'Building Guacamole with GCC6...'
    apt-get -qqy install gcc-6
    if [ $? -ne 0 ]; then
        print_error ' ---> apt-get failed to install gcc-6'
        exit 1
    else
        print_success ' ---> GCC6 Installed'
    fi
    CC="gcc-6"

else
    print_progress 'Building Guacamole with GCC7...'
    CC="gcc-7"
fi

print_progress 'Configuring...'
./configure --with-init-dir=/etc/init.d  &>> ${LOG}
if [ $? -ne 0 ]; then
    print_error ' ---> Install failed'
    exit 1
else
    print_success ' ---> Install success'
fi

print_progress 'Running Make...'
make &>> ${LOG}
if [ $? -ne 0 ]; then
    print_error ' ---> Failed'
    exit 1
else
    print_success ' ---> OK'
fi
print_progress 'Running Make Install...'
make install &>> ${LOG}
if [ $? -ne 0 ]; then
   print_error ' ---> Failed'
   exit 1
else
   print_success ' ---> OK'
fi

ldconfig
systemctl enable guacd
cd ..

# Get build-folder
BUILD_FOLDER=$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)

# Move files to correct locations
mv guacamole-${GUACVERSION}.war /etc/guacamole/guacamole.war
ln -sfn /etc/guacamole/guacamole.war /var/lib/${TOMCAT}/webapps/
ln -sfn /usr/local/lib/freerdp/guac*.so /usr/lib/${BUILD_FOLDER}/freerdp/
ln -sfn /usr/share/java/mysql-connector-java.jar /etc/guacamole/lib/
ln -sfn /etc/guacamole/ /usr/share/${TOMCAT}/.guacamole
cp guacamole-auth-jdbc-${GUACVERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACVERSION}.jar /etc/guacamole/extensions/

# Configure guacamole.properties to use MySQL database for authentication
if [ -z "$(grep 'guacd-hostname: localhost' /etc/guacamole/guacamole.properties)" ]; then
    echo "guacd-hostname: localhost" >> /etc/guacamole/guacamole.properties
    echo "guacd-port: 4822" >> /etc/guacamole/guacamole.properties
    echo "mysql-hostname: localhost" >> /etc/guacamole/guacamole.properties
    echo "mysql-port: 3306" >> /etc/guacamole/guacamole.properties
    echo "mysql-database: ${DB_NAME}" >> /etc/guacamole/guacamole.properties
    echo "mysql-username: ${DB_USER}" >> /etc/guacamole/guacamole.properties
    echo "mysql-password: ${DB_PASS}" >> /etc/guacamole/guacamole.properties
fi

# restart tomcat
print_progress 'Restarting tomcat...'

service ${TOMCAT} restart
if [ $? -ne 0 ]; then
    print_error ' ---> Failed'
    exit 1
else
    print_success ' ---> OK'
fi

# Create guacamole_db and grant guacamole_user permissions to it
print_progress 'Create guacamole_db and grant guacamole_user permissions to it. Then adding db tables...' 1
# SQL code
SQLCODE="
-- DROP DATABASE IF EXISTS ${DB_NAME};
-- DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' identified by \"${DB_PASS}\";
GRANT SELECT,INSERT,UPDATE,DELETE ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;"
#if [ -z $(mysql -u root -p${MSQL_ROOT_PASS} -sN -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '${DB_NAME}'" information_schema) ]; then
#if [ -z $(mysql -u root -p${MSQL_ROOT_PASS} -sN -e "SHOW DATABASES" | grep ${DB_NAME}) ]; then
if [ -z $(mysql -u root -p${MSQL_ROOT_PASS} --skip-column-names -sN -e "SHOW DATABASES LIKE '${DB_NAME}'") ]; then
    # Execute SQL code
    echo ${SQLCODE} | mysql -u root -p${MSQL_ROOT_PASS}
    
    # Add Guacamole schema to newly created database
    cat guacamole-auth-jdbc-${GUACVERSION}/mysql/schema/*.sql | mysql -u root -p${MSQL_ROOT_PASS} ${DB_NAME}
    if [ $? -ne 0 ]; then
        print_error ' ---> Failed'
        exit 1
    else
        print_success ' ---> OK'
    fi
else
    print_progress 'Database exists, skip...' 1
fi

# Ensure guacd is started
service guacd start

# Install XFCE and TightVNC
print_progress 'Installing XFCE and TightVNC...' 1
apt-get -qqy install xfce4 xfce4-goodies tightvncserver
if [ -d ~/.vnc ]; then
    rm -rf ~/.vnc
    pgrep vnc | xargs kill -9
    
    rm -f /tmp/.X*-lock
    rm -f  /tmp/.X11-unix/X*
fi
mkdir ~/.vnc
echo $VNC_PASS | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Update vncserver configs
cat > ~/.vnc/xstartup <<EOF
#!/bin/sh
def
export XKL_XMODMAP_DISABLE=1
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

xrdb $HOME/.Xresources
xsetroot -solid grey

startxfce4 &
EOF
chmod +x ~/.vnc/xstartup

print_progress 'Updating SystemD service...' 1
cat > /etc/systemd/system/vncserver@.service <<EOF
[Unit]
Description=Start TightVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=$USER
PAMName=login
PIDFile=/home/$USER/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1280x720 :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver@1.service
if [ $? -ne 0 ]; then
    print_error ' ---> Failed'
    exit 1
else
    print_success ' ---> OK'
fi

print_progress 'Starting TightVNC Server...' 1
vncserver
if [ $? -ne 0 ]; then
    print_error ' ---> Failed'
    exit 1
else
    print_success ' ---> OK'
fi

print_progress 'Adding Vagrant insecure public key...' 1
VAGRANT_PUB_KEY="`wget -qO - https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub`"
if [ -z "$(grep 'vagrant insecure public key' ~/.ssh/authorized_keys)" ]; then
    echo "$VAGRANT_PUB_KEY" >> ~/.ssh/authorized_keys
fi

# Cleanup
print_progress 'Cleanup install files...'
rm -rf guacamole-*
if [ $? -ne 0 ]; then
    print_error ' ---> Failed'
    exit 1
else
    print_success ' ---> OK'
fi

if [ -z "$(grep $HOST_URL /etc/hosts)" ]; then
    echo "127.0.0.1 $HOST_URL $HOST_URL" >> /etc/hosts
fi

print_progress 'Installation Complete'
print_notice "http://${HOST_URL}:8080/guacamole/"
print_notice "Default login ${RED}guacadmin:guacadmin$RED"
print_notice 'Be sure to change the password'
