#!/bin/bash
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

echo "複製 blacklist.conf 到 /etc/nginx/conf.d/"
wget https://github.com/mariusv/nginx-badbot-blocker/raw/master/VERSION_2/conf.d/blacklist.conf -O /etc/nginx/conf.d/blacklist.conf

mkdir /etc/nginx/bots.d

echo "複製 blockbots.conf 到 /etc/nginx/bots.d"
wget https://github.com/mariusv/nginx-badbot-blocker/raw/master/VERSION_2/bots.d/blockbots.conf -O /etc/nginx/bots.d/blockbots.conf

echo "複製 ddos.conf 到 /etc/nginx/bots.d"
wget https://github.com/mariusv/nginx-badbot-blocker/raw/master/VERSION_2/bots.d/ddos.conf -O /etc/nginx/bots.d/ddos.conf

echo "複製 whitelist-ips.conf 到 /etc/nginx/bots.d"
wget https://github.com/mariusv/nginx-badbot-blocker/raw/master/VERSION_2/bots.d/whitelist-domains.conf -O /etc/nginx/bots.d/whitelist-domains.conf

echo "複製 whitelist-domains.conf 到 /etc/nginx/bots.d"
wget https://github.com/mariusv/nginx-badbot-blocker/raw/master/VERSION_2/bots.d/whitelist-ips.conf -O /etc/nginx/bots.d/whitelist-ips.conf



