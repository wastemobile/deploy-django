#!/bin/bash
#
# Usage:
#   $ install_pre.sh

# 檢查是否以 root 身份執行
function check_root
{
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
}

PYTHON_VERSION=3

# Prerequisite standard packages. If any of these are missing,
# script will attempt to install it. If installation fails, it will abort.
PIP="pip3"
LINUX_REPO=('universe' 'ppa:certbot/certbot')
LINUX_PREREQ=('git' 'build-essential' 'python3-dev' 'python3-pip' 'nginx' 'postgresql' 'postgresql-contrib' 'libpq-dev' 'software-properties-common' 'certbot' 'python-certbot-nginx' 'python3-certbot-dns-cloudflare')
PYTHON_PREREQ=('virtualenv')

# upgrade pip
echo "upgrade Global pip3 to lastest"

# Test prerequisites
echo "Checking if required packages are installed..."
declare -a MISSING

for repo in "${LINUX_REPO[@]}"
    do
        echo "add repoitory..."
        add-apt-repository $repo
        if [ $? -ne 0 ]; then
            echo "Error adding repository '$repo'"
            exit 1
        fi
    done

apt-get update

for pkg in "${LINUX_PREREQ[@]}"
    do
        echo "Installing '$pkg'..."
        apt-get -y install $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing system package '$pkg'"
            exit 1
        fi
    done

$PIP install --upgrade pip

for ppkg in "${PYTHON_PREREQ[@]}"
    do
        echo "Installing Python package '$ppkg'..."
        $PIP install $ppkg
        if [ $? -ne 0 ]; then
            echo "Error installing python package '$ppkg'"
            exit 1
        fi
    done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo "Following required packages are missing, please install them first."
    echo ${MISSING[*]}
    exit 1
fi

echo "All required packages have been installed!"

