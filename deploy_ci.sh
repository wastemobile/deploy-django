#!/bin/bash
#
# Usage:
#	$ deploy_ci <appname>
# 實際應該是擺在某專案的家目錄下，例 /webapps/readcoil/
# 

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

# conventional values that we'll use throughout the script
APPNAME=$1
PYTHON_VERSION=3

# check appname was supplied as argument
if [ "$APPNAME" == "" ]; then
	echo "Usage:"
	echo "  $ deploy_ci <project>"
	exit 1
fi

GROUPNAME=webapps
# app folder name under /webapps/<appname>_project
APPFOLDER=$1_project
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

# Determine requested Python version & subversion
PYTHON_VERSION_STR=`python3 -c 'import sys; ver = "{0}.{1}".format(sys.version_info[:][0], sys.version_info[:][1]); print(ver)'`
echo "Python version: $PYTHON_VERSION_STR"

# Check the app folder
echo "檢查專案目錄 '$APPFOLDERPATH' 是否存在..."
if [ ! -d "$APPFOLDERPATH"]; then
  error_exit "找不到專案目錄，停止更新"
fi

# test the group 'webapps' exists, and if it doesn't, abort
echo "檢查群組 '$GROUPNAME' 是否存在..."
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    error_exit "找不到預設 'webapps' 群組，停止更新"
fi

# test the app user account, same name as the appname
echo "檢查專案用戶 '$APPNAME' 是否存在..."
grep "$APPNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    error_exit "找不到 '$APPNAME'，停止更新"
fi

# 進入專案目錄、執行更新
echo "更新中..."
su -l $APPNAME << EOF
source ./bin/activate
# upgrade pip
# pip install --upgrade pip || error_exist "Error upgrading pip to the latest version"
# install python packages for a django app using pip
cd $APPNAME
git pull
echo "Updating python packages for the app..."
if [ -f 'requirements.txt']; then
  pip install -r requirements.txt || error_exist "找不到 requirements.txt，停止更新"
fi
python manage.py migrate
deactivate
EOF

echo "更新完成，重新啟動 gunicorn 服務"
systemctl restart $APPNAME

