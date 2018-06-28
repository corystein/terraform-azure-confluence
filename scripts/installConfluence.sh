#!/bin/bash
###################################################################
# Script Name	:  installConfluence.sh
# Description	:  Install and configure Confluence
# Args          :  None
# Author        :  Cory R. Stein
###################################################################

echo "Executing [$0]..."
PROGNAME=$(basename $0)

set -e

####################################################################
# Execute updates
####################################################################
yum update -y
####################################################################

####################################################################
# Base install
####################################################################
yum install -y wget git openssl
####################################################################

####################################################################
# Disable SELINUX
####################################################################
echo "Disable SELINUX..."
setsebool -P httpd_can_network_connect 1
sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
setenforce 0
sestatus
echo "Successfully disabled SELINUX"
####################################################################

####################################################################
# Install Java (Confluence does not work with Open JDK)
####################################################################
echo "Installing Java..."
JAVA_DOWNLOAD_URL=http://download.oracle.com/otn-pub/java/jdk/8u171-b11/512cd62ec5174c3487ac17c61aaa89e8/jdk-8u171-linux-x64.rpm
JAVA_BIT_VERSION=x64
JAVA_KEY_VERSION=8u171
JAVA_VERSION=1.8.0_171
cd /tmp

wget -q --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "${JAVA_DOWNLOAD_URL}"

if [ -f jdk-${JAVA_KEY_VERSION}-linux-${JAVA_BIT_VERSION}.rpm ]; then
	echo "Installing Java..."
	rpm -ivh --force jdk-${JAVA_KEY_VERSION}-linux-${JAVA_BIT_VERSION}.rpm
	echo "Update environment variables complete"
fi

java -version
echo "Successfully installed Java"
####################################################################

####################################################################
# Install/Configure Confluence
####################################################################
echo "Installing Confluence..."
CONFLUENCE_VERSION=6.10.0
TEMP_DIR=/tmp/confluence
# https://confluence.atlassian.com/adminjiraserver071/unattended-installation-855475683.html
pushd /tmp >/dev/null

# Create application directory
TARGET_DIR=/opt/atlassian/confluence
echo "Creating [${TARGET_DIR}]..."
mkdir -p ${TARGET_DIR}

# Download archive
echo "Downloadng archive..."
ARCHIVE_NAME=atlassian-confluence-software.tar.gz
wget -q -O ${ARCHIVE_NAME} https://www.atlassian.com/software/confluence/downloads/binary/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz
echo "Completed downloading archive"

echo "Untar archive..."
rm -rf ${TEMP_DIR} >/dev/null
mkdir ${TEMP_DIR} >/dev/null
tar -xzf ${ARCHIVE_NAME} -C ${TEMP_DIR} --strip 1
cp -R ${TEMP_DIR}/* ${TARGET_DIR}
echo "Completed untaring archive"

# Create user
APP_USER=confluence
if ! id -u ${APP_USER} >/dev/null 2>&1; then
	echo "Create Confluence user..."
	/usr/sbin/useradd --create-home --comment "Account for running Confluence Software" --shell /bin/bash ${APP_USER}
	echo "Completed creating Confluence user"
else
	echo "Confluence user already exists"
fi

# Set installer permissions
echo "Setting permissions..."
chown -R ${APP_USER} ${TARGET_DIR}
chmod -R u=rwx,go-rwx ${TARGET_DIR}
echo "Completed setting permissions"

# Create home directory
echo "Create home directory..."
HOME_DIR=/var/confluencesoftware-home
mkdir -p ${HOME_DIR} >/dev/null
chown -R ${APP_USER} ${HOME_DIR}
chmod -R u=rwx,go-rwx ${HOME_DIR}
echo "Completed creating home directory"

# Set user home for application
echo "Set user home for application..."
echo "export CONFLUENCE_HOME=${HOME_DIR}" >>/home/${APP_USER}/.bash_profile
#echo "export CONFLUENCE_OPTS=-Datlassian.darkfeature.jira.onboarding.feature.disabled=true" >>/home/jira/.bash_profile
echo "Completed setting user home for application"

# Configure application ports
#echo "Configure application ports..."
#SEARCH=
#REPLACE=
#sed -i -e "s|$SEARCH|$REPLACE|g" ${TARGET_DIR}/conf/server.xml
#echo "Completed configuring application ports"

# Configure memory
# Ref: https://confluence.atlassian.com/adminjiraserver073/increasing-jira-application-memory-861253796.html
echo "Configure CONFLUENCE JVM memory..."
sed -i -e "s|JVM_MAXIMUM_MEMORY=/"768m/"|JVM_MAXIMUM_MEMORY=/"2048m/"|g" ${TARGET_DIR}/bin/setenv.sh
echo "Completed configuring CONFLUENCE JVM memory"

# Create systemd file
# Ref: https://community.atlassian.com/t5/Jira-questions/CentOS-7-systemd-startup-scripts-for-Jira-Fisheye/qaq-p/157575
echo "Create systemd file..."
cat >/usr/lib/systemd/system/confluence.service <<EOL
[Unit]
Description=CONFLUENCE Service
After=network.target

[Service]
Type=forking
User=confluence
Environment=CONFLUENCE_HOME=${HOME_DIR}
#Environment=JIRA_OPTS=-Datlassian.darkfeature.jira.onboarding.feature.disabled=true
PIDFile=${TARGET_DIR}/work/catalina.pid
ExecStart=${TARGET_DIR}/bin/start-confluence.sh
ExecStop=${TARGET_DIR}/bin/stop-confluence.sh
ExecReload=${TARGET_DIR}/bin/stop-confluence.sh | sleep 60 | /${TARGET_DIR}/bin/start-confluence.sh

[Install]
WantedBy=multi-user.target
EOL

echo "Enable Confluence service..."
systemctl enable confluence.service
echo "Completed enabling Confluence service"
echo "Starting Confluence service..."
systemctl start confluence.service
echo "Completed starting Confluence service"
echo "Confluence service status..."
systemctl status confluence.service
echo "Completed Confluence status"
echo "Completed creating systemd file"

popd >/dev/null
echo "Completed installing Confluence"
####################################################################

####################################################################
# Install/Configure Nginx
####################################################################
# https://confluence.atlassian.com/jirakb/integrating-jira-with-nginx-426115340.html
# https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-centos-7
echo "Adding Nginx repository..."
yum -y install epel-release
echo "Completed adding Nginx repository"

echo "Installing Nginx..."
yum -y install nginx
echo "Completed installing Nginx"

# Configure Nginx Sites For
echo "Creating directories..."
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /var/cache/nginx/client_temp
chmod 0777 /var/cache/nginx/client_temp
echo "Completed creating directories"

# Update config file
echo "Editing [/etc/nginx/nginx.conf]..."
SEARCH="include \/etc\/nginx\/conf.d\/\*.conf;"
REPLACE="include \/etc\/nginx\/sites-enabled\/\*.conf;"
sed -i -e "s|$SEARCH|$REPLACE|g" /etc/nginx/nginx.conf
sed -i -e "s|        listen       80 default_server;|#        listen       80 default_server;|g" /etc/nginx/nginx.conf
sed -i -e "s|        listen       \[::\]:80 default_server;|#        listen       \[::\]:80 default_server;|g" /etc/nginx/nginx.conf
sed -i -e "s|        server_name  _;|#        server_name  _;|g" /etc/nginx/nginx.conf
sed -i -e "s|        root         /usr/share/nginx/html;|#        root         /usr/share/nginx/html;|g" /etc/nginx/nginx.conf
echo Return Code: $?
echo "Completed editing [/etc/nginx/nginx.conf]"

# Remove contents of /etc/nginx/conf.d
echo "Removing [/etc/nginx/conf.d/*]..."
rm -f /etc/nginx/conf.d/*
echo "Completed [/etc/nginx/conf.d/*]"

# HTTP/S Configuration
SERVER_NAME="localhost"
DNS="yourdomain.com"
SERVER_PORT="80"
cat >/etc/nginx/sites-available/confluence.conf <<EOL
#server {
#       listen 80 default_server;
#        listen [::]:80 default_server;
#        server_name _;
#        return 301 http://\$host\$request_uri;
#		#return 301 https://\$host\$request_uri;
#}


server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name localhost;

        # SSL listener
        #listen 443 ssl;
        #listen [::]:443 default_server;
        #server_name ${SERVER_NAME} ${DNS} ;

        # SSL Certificates / Configuration
        #ssl on;
        #ssl_certificate     /etc/ssl/${DNS}.cer;
        #ssl_certificate_key /etc/ssl/${DNS}.key;

        # allow large uploads of files - refer to nginx documentation
        client_max_body_size 1G;
        # optimize downloading files larger than 1G - refer to nginx doc before adjusting
        #proxy_max_temp_file_size 2G;
        
        location / {
			proxy_set_header Host \$host;
        	proxy_set_header X-Real-IP \$remote_addr;
        	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        	#proxy_set_header X-Forwarded-Proto "https";
			proxy_set_header X-Forwarded-Proto "http";
            proxy_pass http://localhost:8080/;
        }
}

EOL

# Enable the configuration by creating symbolic link (Incomplete)
ln -sf /etc/nginx/sites-available/confluence.conf /etc/nginx/sites-enabled/confluence.conf

# Validate nginx configuration file
echo "Validating Nginx confiugration file..."
nginx -t
echo "Completed validating Nginx confiugration file"

# Allow http and https ports through firewall
if [ $(systemctl -q is-active firewalld) ]; then
	firewall-cmd --permanent --zone=public --add-service=http
	firewall-cmd --permanent --zone=public --add-service=https
	firewall-cmd --reload
fi

# Restart Nginx
echo "Starting Nginx service..."
systemctl start nginx
systemctl enable nginx
# Configure selinux
#setsebool -P httpd_can_network_connect 1
echo "Completed restarting Nginx service"

####################################################################

echo "Executing [$0] complete"
exit 0
