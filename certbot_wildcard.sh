#!/bin/bash
#
# Usage:
#	$ certbot_wildcard <domainname>

# check if we're being run as root
function check_root
{
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
}

DOMAINNAME=$1

if [ ! -f '~/.secrets/cloudflare.ini' ]; then
  error_exit "請先將 cloudflare Global API Key 寫至 ~/.secrets/cloudflare.ini"
fi

# ###################################################################
# 執行 certbot 建立 wildcard 認證（僅適用 cloudflare DNS）
# ###################################################################
echo "run certbot wildcard process with cloudflare dns plugin"

certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAINNAME,*.$DOMAINNAME --preferred-challenges dns-01 -i nginx