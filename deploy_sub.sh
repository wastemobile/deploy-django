#!/bin/bash
#
# Usage:
#	$ deploy_sub.sh <fulldomainname>

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

FULLDOMAIN=$1

# 檢查是否輸入網域
if [ "$FULLDOMAIN" == "" ]; then
  echo "使用方法：輸入帶次域名的網域全名，例如 cyber.punk.com"
  echo "（請確認已使用 certbot 申請過 punk.com wildcard 證書！）"
  echo "  $ deploy_sub <sub.domain.com>"
  exit 1
fi

DOMAINNAME=${FULLDOMAIN#*.}

# 檢查主網域是否已存有 Let's Encrypt Wildcard SSL 紀錄
if [ ! -d "/etc/letsencrypt/live/$DOMAINNAME" ]; then
  echo "主機上找不到 $DOMAINNAME 已申請 Let's Encrypt Wildcard SSL 的紀錄，"
  echo "請檢查 /etc/letsencrypt/live/，或先執行 certbot_wildcard.sh 指令。"
  exit 1
fi

# ###################################################################
# 若輸入的網域為 cyber.punk.com：
#   1. 專案頂層目錄為 cyber_punk_proj
#   2. Django 專案目錄為 cyber_punk
#   3. 
# ###################################################################
SUBNAME=$(echo "$FULLDOMAIN" | cut -d"." -f 1)
DOMAIN=$(echo "$FULLDOMAIN" | cut -d"." -f 2)

APPNAME=$SUBNAME\_$DOMAIN
GROUPNAME=webapps
APPFOLDER=$APPNAME\_proj
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

# 只支援 Python 3
PYTHON_VERSION=3
PYTHON_VERSION_STR=`python3 -c 'import sys; ver = "{0}.{1}".format(sys.version_info[:][0], sys.version_info[:][1]); print(ver)'`

# 顯示一下目前系統全域的 Python 版本（Ubuntu 18.04 預設為 3.6.9）
echo "Python version: $PYTHON_VERSION_STR"

# 設置專案目錄
echo "建立專案目錄 '$APPFOLDERPATH'..."
mkdir -p /$GROUPNAME/$APPFOLDER || error_exit "Could not create app folder"

# 檢查 webapps 群組是否存在；找不到就新建
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    echo "替自動化程序、新建群組 '$GROUPNAME'..."
    groupadd --system $GROUPNAME || error_exit "Could not create group 'webapps'"
fi

# 檢查應用同名的用戶是否存在；找不到就新建，並將上層專案目錄設置為家目錄
grep "$APPNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    echo "自動建立專案用戶 '$APPNAME'...（家目錄即為 '$APPFOLDERPATH $APPNAME'）"
    useradd --system --gid $GROUPNAME --shell /bin/bash --home $APPFOLDERPATH $APPNAME || error_exit "Could not create automation user account '$APPNAME'"
fi

# 設定專案目錄及其下檔案的擁有者與權限
echo "設定 $APPFOLDERPATH 與其下各層之擁有者皆為 $APPNAME:$GROUPNAME..."
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH || error_exit "Error setting ownership"
# give group execution rights in the folder;
# TODO: is this necessary? why?
chmod g+x $APPFOLDERPATH || error_exit "Error setting group execute flag"

# 設置 virtualenv 虛擬環境
echo "替 django 應用建立虛擬環境..."
su -l $APPNAME << 'EOF'
pwd
echo "Setting up python virtualenv..."
virtualenv -p python3 . || error_exit "Error installing Python 3 virtual environment to app folder"

EOF

# ###################################################################
# 進入剛剛設置的專案虛擬環境，進行初始配置：
#   1. 升級 pip
#   2. 安裝必要套件（django, django-environ, psycopg2-binary, gunicorn
#   3. 建立目錄： logs, nginx, run, service
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

# 建立 Django 應用（使用專案模版、django-environ）
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

# 自動建立 Django 正式環境設定檔 .env
echo "Creating .env"
cat > /tmp/.env << EOF
DEBUG=False
SECRET_KEY=$DJANGO_SECRET_KEY
ALLOWED_HOSTS=.$FULLDOMAIN
DATABASE_URL=psql://$APPNAME:$DBPASSWORD@127.0.0.1/$APPNAME
CSRF_COOKIE_SECURE=True
SESSION_COOKIE_SECURE=True
SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO', 'https')
EOF

mv /tmp/.env $APPFOLDERPATH/$APPNAME/config
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/$APPNAME/config/.env

# ###################################################################
# 建立 PostgreSQL 資料庫、角色與權限
# ：均使用 $APPNAME 為名，使用剛剛建立的強密碼
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
        --name $APPNAME \
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
# 自動生成 Nginx Server Block
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
    server_name $FULLDOMAIN;

    location / {
       rewrite ^ https://\$http_host\$request_uri? permanent;
    }
    
}

server {
   listen 443 ssl;
   server_name $FULLDOMAIN;

   client_max_body_size 5M;
   keepalive_timeout 5;

   ssl_certificate /etc/letsencrypt/live/$DOMAINNAME/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$DOMAINNAME/privkey.pem;
   include /etc/letsencrypt/options-ssl-nginx.conf;
   ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

   # include /etc/nginx/bots.d/blockbots.conf;
   # include /etc/nginx/bots.d/ddos.conf;

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

# 建立到 /etc/nginx/sites-enabled 的軟連結
ln -sf $APPFOLDERPATH/nginx/$APPNAME.conf /etc/nginx/sites-enabled/$APPNAME.conf

# 檢查專屬用戶是否有擺放 ssh key（供後續 automated git deploy 使用）
if [ ! -f "$APPFOLDERPATH/.ssh/authorized_keys" ]; then
  mkdir -p $APPFOLDERPATH/.ssh/
  touch $APPFOLDERPATH/.ssh/authorized_keys
  chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH/.ssh
  chmod u+rw $APPFOLDERPATH/.ssh/authorized_keys
  echo "請自行添加 pub key 到 $APPFOLDERPATH/.ssh/authorized_keys"
fi

# 檢查用戶是否有設置 git global config（供後續 automated git deploy 使用）
if [ ! -f "$APPFOLDERPATH/.gitconfig" ]; then
  cp ./gitconfig $APPFOLDERPATH/.gitconfig
  chown $APPNAME:$GROUPNAME $APPFOLDERPATH/.gitconfig
  echo "請修改設置 $APPFOLDERPATH/.gitconfig 中的使用者電郵與名稱"
fi

# 檢查用戶是否有設置 git global credentials（供後續 automated git deploy 使用）
if [ ! -f "$APPFOLDERPATH/.git-credentials" ]; then
  cp ./git-credentials $APPFOLDERPATH/.git-credentials
  chown $APPNAME:$GROUPNAME $APPFOLDERPATH/.git-credentials
  echo "請修改設置 $APPFOLDERPATH/.git-credentials 中的用戶與 personal token"
fi

# 替專屬用戶增加重啟服務的特殊權限（供後續 automated git deploy 使用）
echo "讓專屬用戶能在自動連續部署完成後，執行重啟 django gunicorn 服務"
cat > /tmp/$APPNAME << EOF
Cmnd_Alias CMD_RESTART_APP = /bin/systemctl restart $APPNAME
$APPNAME ALL=(root:root) NOPASSWD: CMD_RESTART_APP
EOF

mv /tmp/$APPNAME /etc/sudoers.d/
chmod 0440 /etc/sudoers.d/$APPNAME

# 新增自動 git deploy 使用的 deploy_ci.sh（供後續 automated git deploy 使用）
echo "設置自動連續部署使用的 deploy_ci.sh"
cat > /tmp/deploy_ci.sh << EOF
#!/bin/bash
source ./bin/activate
cd $APPNAME
git pull
pip install -r requirements.txt
python manage.py migrate
deactivate
sudo /bin/systemctl restart $APPNAME
EOF

mv /tmp/deploy_ci.sh $APPFOLDERPATH/
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/deploy_ci.sh
chmod u+x $APPFOLDERPATH/deploy_ci.sh

echo "啟動 Gunicorn 與 Nginx，試著瀏覽網站 https://$FULLDOMAIN"
systemctl enable --now $APPNAME.socket
systemctl restart nginx

