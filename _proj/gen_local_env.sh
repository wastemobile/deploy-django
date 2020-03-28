#!/bin/bash
#
# gen_local_env.sh <appname>

APPNAME=$1

if [ "$APPNAME" == "" ]; then
  echo "使用方式："
  echo " $ gen_local_env.sh <appname>"
  exit 1
fi

parent_path=$(cd ../"$(dirname "${BASH_SOURCE[0]}")" && pwd -P )

if [ ! -d "$parent_path/$APPNAME" ]; then
	echo "沒有符合名稱的應用程式可設定"
	exit 1
fi

echo "Generating Django secret key..."
DJANGO_SECRET_KEY=`openssl rand -base64 32`
if [ $? -ne 0 ]; then
    echo "Error creating secret key."
    exit 1
fi

cat > /tmp/.env << EOF
# local development
DEBUG=True
ALLOWED_HOSTS=.localhost,127.0.0.1
SECRET_KEY=$DJANGO_SECRET_KEY
DATABASE_URL=sqlite:///db.sqlite3
EOF

mv /tmp/.env $parent_path/$APPNAME/.env

echo "done!"