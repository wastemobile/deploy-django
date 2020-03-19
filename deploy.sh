#!/bin/bash
#
# Usage:
#	$ deploy <appname> <domainname>

# Exits the script with a message and exit code 1
function error_exit
{
    echo "$1" 1>&2
    exit 1
}
# check if we're being run as root
function check_root
{
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
}

check_root

# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2
PYTHON_VERSION=3

# check appname was supplied as argument
if [ "$APPNAME" == "" ] || [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ create_django_project_run_env <project> <domain> [python-version]"
	echo
	echo "  Python version is 2 or 3 and defaults to 3 if not specified. Subversion"
	echo "  of Python will be determined during runtime. The required Python version"
	echo "  has to be installed and available globally."
	echo
	exit 1
fi

GROUPNAME=webapps
# app folder name under /webapps/<appname>_project
APPFOLDER=$1_project
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

# Determine requested Python version & subversion
PYTHON_VERSION_STR=`python3 -c 'import sys; ver = "{0}.{1}".format(sys.version_info[:][0], sys.version_info[:][1]); print(ver)'`

# Verify required python version is installed
echo "Python version: $PYTHON_VERSION_STR"

# ###################################################################
# Create the app folder
# ###################################################################
echo "建立專案目錄 '$APPFOLDERPATH'..."
mkdir -p /$GROUPNAME/$APPFOLDER || error_exit "Could not create app folder"

# test the group 'webapps' exists, and if it doesn't create it
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    echo "替自動化程序、新建群組 '$GROUPNAME'..."
    groupadd --system $GROUPNAME || error_exit "Could not create group 'webapps'"
fi

# create the app user account, same name as the appname
grep "$APPNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    echo "自動建立專案用戶 '$APPNAME'...（家目錄即為 '$APPFOLDERPATH $APPNAME'）"
    useradd --system --gid $GROUPNAME --shell /bin/bash --home $APPFOLDERPATH $APPNAME || error_exit "Could not create automation user account '$APPNAME'"
fi

# change ownership of the app folder to the newly created user account
echo "設定 $APPFOLDERPATH 與其下各層之擁有者皆為 $APPNAME:$GROUPNAME..."
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH || error_exit "Error setting ownership"
# give group execution rights in the folder;
# TODO: is this necessary? why?
chmod g+x $APPFOLDERPATH || error_exit "Error setting group execute flag"

# install python virtualenv in the APPFOLDER
echo "替 django 應用建立虛擬環境..."
su -l $APPNAME << 'EOF'
pwd
echo "Setting up python virtualenv..."
virtualenv -p python3 . || error_exit "Error installing Python 3 virtual environment to app folder"

EOF

# ###################################################################
# In the new app specific virtual environment:
# 	1. Upgrade pip
#	2. Install django in it.
#	3. Create following folders:-
#		static -- Django static files (to be collected here)
#		media  -- Django media files
#		logs   -- nginx, gunicorn & supervisord logs
#		nginx  -- nginx configuration for this domain
#		ssl	   -- SSL certificates for the domain(NA if LetsEncrypt is used)
# ###################################################################
su -l $APPNAME << 'EOF'
source ./bin/activate
# upgrade pip
pip install --upgrade pip || error_exist "Error upgrading pip to the latest version"
# install prerequisite python packages for a django app using pip
echo "Installing base python packages for the app..."
# Standard django packages which will be installed. If any of these fail, script will abort
DJANGO_PKGS=('django' 'django-environ' 'psycopg2-binary' 'gunicorn' 'setproctitle')
for dpkg in "${DJANGO_PKGS[@]}"
    do
        echo "Installing $dpkg..."
        pip install $dpkg || error_exit "Error installing $dpkg"
    done
# create the default folders where we store django app's resources
echo "Creating static file folders..."
mkdir logs nginx run service || error_exit "Error creating static folders"
# Create the UNIX socket file for WSGI interface
echo "Creating WSGI interface UNIX socket file..."
python -c "import socket as s; sock = s.socket(s.AF_UNIX); sock.bind('./run/$APPNAME.sock')"
EOF

# Now create a quasi django project that can be run using a GUnicorn script
echo "Installing django project from my template..."
su -l $APPNAME << EOF
source ./bin/activate
mkdir $APPNAME
cd $APPNAME
django-admin.py startproject --template https://github.com/wastemobile/django-project-template/archive/master.zip config .
EOF

# ###################################################################
# 產生 Django 正式環境密鑰
# ###################################################################
echo "Generating Django secret key..."
DJANGO_SECRET_KEY=`openssl rand -base64 32`
if [ $? -ne 0 ]; then
    error_exit "Error creating secret key."
fi
# ###################################################################
# 產生 PostgreSQL 資料庫密碼
# ###################################################################
echo "Creating secure password for database role..."
DBPASSWORD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
if [ $? -ne 0 ]; then
    error_exit "Error creating secure password for database role."
fi

echo "Creating .env"
cat > /tmp/.env << EOF
DEBUG=False
SECRET_KEY=$DJANGO_SECRET_KEY
ALLOWED_HOSTS=.$DOMAINNAME
DATABASE_URL=psql://$APPNAME:$DBPASSWORD@127.0.0.1/$APPNAME
CSRF_COOKIE_SECURE=True
SESSION_COOKIE_SECURE=True
SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO', 'https')
EOF
mv /tmp/.env $APPFOLDERPATH/$APPNAME/config
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/$APPNAME/config/.env
# ###################################################################
# Create the PostgreSQL database and associated role for the app
# Database and role name would be the same as the <appname> argument
# ###################################################################
echo "新增 PostgreSQL 使用者（role）： '$APPNAME'..."
su - postgres -c "createuser -S -D -R -w $APPNAME"
echo "設置密碼..."
su - postgres -c "psql -c \"ALTER USER $APPNAME WITH PASSWORD '$DBPASSWORD';\""
echo "新增同名 '$APPNAME' 資料庫..."
su - postgres -c "createdb --owner $APPNAME $APPNAME"

# 新增一個 gunicorn process 處理連線
echo "新增一個 gunicorn process 處理連線"
cat > /tmp/process.socket << EOF
[Unit]
Description=$APPNAME gunicorn socket
[Socket]
ListenStream=$APPFOLDERPATH/run/$APPNAME.sock
[Install]
WantedBy=sockets.target
EOF
mv /tmp/process.socket $APPFOLDERPATH/service/$APPNAME.socket
ln -sf $APPFOLDERPATH/service/$APPNAME.socket /etc/systemd/system/$APPNAME.socket

# 新增一個 systemd service
echo "新增一個 systemd service"
cat > /tmp/process.service << EOF
[Unit]
Description=$APPNAME gunicorn daemon
Requires=$APPNAME.socket
After=network.target

[Service]
User=$APPNAME
Group=$GROUPNAME
WorkingDirectory=$APPFOLDERPATH/$APPNAME
ExecStart=$APPFOLDERPATH/bin/gunicorn \
        --access-logfile - \
        --workers 3 \
        --bind unix:$APPFOLDERPATH/run/$APPNAME.sock \
        config.wsgi:application

[Install]
WantedBy=multi-user.target
EOF
mv /tmp/process.service $APPFOLDERPATH/service/$APPNAME.service
ln -sf $APPFOLDERPATH/service/$APPNAME.service /etc/systemd/system/$APPNAME.service

# ###################################################################
# Create nginx template in $APPFOLDERPATH/nginx
# ###################################################################
echo "自動修改 Nginx Server Block"
mkdir -p $APPFOLDERPATH/nginx
APPSERVERNAME=$APPNAME
APPSERVERNAME+=_gunicorn
cat > $APPFOLDERPATH/nginx/$APPNAME.conf << EOF
upstream $APPSERVERNAME {
    server unix:$APPFOLDERPATH/run/$APPNAME.sock fail_timeout=0;
}
server {
    listen 80;
    server_name $DOMAINNAME;

    location / {
       rewrite ^ https://\$http_host\$request_uri? permanent;
    }
    
}

server {
   listen 443 default ssl;
   server_name $DOMAINNAME www.$DOMAINNAME;

   client_max_body_size 5M;
   keepalive_timeout 5;

   ssl_certificate /etc/letsencrypt/live/$DOMAINNAME/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$DOMAINNAME/privkey.pem;
   include /etc/letsencrypt/options-ssl-nginx.conf;
   ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

   access_log $APPFOLDERPATH/logs/nginx-access.log;
   error_log $APPFOLDERPATH/logs/nginx-error.log;

   location /media  {
       alias $APPFOLDERPATH/$APPNAME/media;
   }
   location /static {
       alias $APPFOLDERPATH/$APPNAME/static;
   }
   location / {
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header Host \$http_host;
       proxy_set_header X-Forwarded-Proto \$scheme;
       proxy_redirect off;
       proxy_pass http://$APPSERVERNAME;
   }
}
EOF
# make a symbolic link to the nginx conf file in sites-enabled
ln -sf $APPFOLDERPATH/nginx/$APPNAME.conf /etc/nginx/sites-enabled/$APPNAME.conf

echo "啟動 Gunicorn 與 Nginx，試著瀏覽網站 https://$DOMAINNAME"
systemctl enable --now $APPNAME.socket
systemctl restart nginx

