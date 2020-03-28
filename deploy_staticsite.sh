#!/bin/bash
#
# Usage:
#	$ deploy_staticsite.sh <domainname> <repository>

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

DOMAINNAME=$1
REPOSITORY=$2

# 檢查是否有輸入主網域
if [ "$DOMAINNAME" == "" ]; then
  echo "Usage:"
  echo " $ deploy.sh <domain>"
  echo "輸入已申請 Wildcard SSL 的主網域，例如 punk.com；應用名稱將會自動設置成 punk。"
  exit 1
fi

# 檢查主網域是否已存有 Let's Encrypt Wildcard SSL 紀錄
if [ ! -d "/etc/letsencrypt/live/$DOMAINNAME" ]; then
  echo "主機上找不到 $DOMAINNAME 已申請 Let's Encrypt Wildcard SSL 的紀錄，"
  echo "請檢查 /etc/letsencrypt/live/，或先執行 certbot_wildcard.sh 指令。"
  exit 1
fi

# 設置主網域應用名稱、專案目錄
# 若 DOMAINNAME = readpunk.com，取第一段做應用名稱 APPNAME = readpunk
APPNAME=$(echo "$DOMAINNAME" | cut -d"." -f 1)
GROUPNAME=webapps
# 專案會擺在 /webapps/readpunk_project
APPFOLDER=$APPNAME\_project
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

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
echo "Creating folders..."
mkdir logs nginx run service || error_exit "Error creating static folders"
EOF

# 建立 Django 應用（使用專案模版、django-environ）
echo "Installing django project from my template..."
su -l $APPNAME << EOF
mkdir $APPNAME
cd $APPNAME
if [ -z "$REPOSITORY" ]
then
  echo "複製預設的靜態網站模板⋯⋯"
  git clone https://github.com/wastemobile/static-project-template.git .
else
  echo "複製自行提供的靜態網站倉儲⋯⋯"
  git clone "$REPOSITORY" .
fi
EOF

# ###################################################################
# 自動生成 Nginx Server Block
# ###################################################################
echo "自動修改 Nginx Server Block"
mkdir -p $APPFOLDERPATH/nginx
cat > $APPFOLDERPATH/nginx/$APPNAME.conf << EOF
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

  root $APPFOLDERPATH/$APPNAME;
  index index.html index.htm;
}
EOF

# 建立到 /etc/nginx/sites-enabled 的軟連結
ln -sf $APPFOLDERPATH/nginx/$APPNAME.conf /etc/nginx/sites-enabled/$APPNAME.conf

# 檢查專屬用戶是否有擺放 ssh key（供後續 automated git deploy 使用）
function generate_key
{
  ssh-keygen -o -a 100 -t ed25519 -f id_$APPNAME -N ""
}

if [ ! -f "$APPFOLDERPATH/.ssh/authorized_keys" ]; then
  mkdir -p $APPFOLDERPATH/.ssh/
  cd $APPFOLDERPATH/.ssh/
  generate_key
  cat id_$APPNAME.pub >> authorized_keys
  chown $APPNAME:$GROUPNAME authorized_keys
  chmod 0700 authorized_keys
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
# echo "讓專屬用戶能在自動連續部署完成後，執行重啟 django gunicorn process"
# APPNAMEU=${APPNAME^^}
# cat > /tmp/$APPNAME << EOF
# Cmnd_Alias CMD_RESTART_$APPNAMEU = /bin/systemctl restart $APPNAME
# $APPNAME ALL=(root:root) NOPASSWD: CMD_RESTART_$APPNAMEU
# EOF

# mv /tmp/$APPNAME /etc/sudoers.d/
# chmod 0440 /etc/sudoers.d/$APPNAME

# 新增自動 git deploy 使用的 deploy_ci.sh（供後續 automated git deploy 使用）
echo "設置自動連續部署使用的 deploy_ci.sh"
cat > /tmp/deploy_ci.sh << EOF
#!/bin/bash
cd $APPNAME
git pull
EOF

mv /tmp/deploy_ci.sh $APPFOLDERPATH/
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/deploy_ci.sh
chmod u+x $APPFOLDERPATH/deploy_ci.sh

echo "ˊ重新載入 Nginx 服務靜態網站，試著瀏覽網站 https://$FULLDOMAIN"
systemctl reload nginx

