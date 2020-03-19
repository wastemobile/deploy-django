#!/bin/bash
#
# Usage:
#	$ certbot_wildcard <domainname>

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

if [ "$DOMAINNAME" == "" ]; then
	echo "使用方法："
	echo "  $ certbot_wildcard <domain>"
	exit 1

if [ ! -f '~/.secrets/cloudflare.ini' ]; then
  error_exit "請先將 cloudflare Global API Key 寫至 ~/.secrets/cloudflare.ini"
fi

# ###################################################################
# 執行 certbot 建立 wildcard 認證（僅適用 cloudflare DNS）
# ###################################################################
echo "執行 certbot、連線 cloudflare，自動取得 Wildcard 證書"

certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAINNAME,*.$DOMAINNAME --preferred-challenges dns-01 -i nginx

echo "請手動執行 sudo certbot renew --dry-run 設置每日自動更新檢查！"