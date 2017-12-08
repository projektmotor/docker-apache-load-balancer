#!/bin/bash

APACHE_VHOST_PATH=/etc/apache2/sites-available/

usage() { echo "Usage: $0 [-a SERVER_ALIASES] SERVER_NAME CLUSTER_NAME" 1>&2; exit 1; }

while getopts a opt
do
   case $opt in
       a) SERVER_ALIAS=${OPTARG};;
       *) usage ;;
   esac
done

SERVER_NAME=$1
CLUSTER_NAME=$2
VHOST_NAME=${SERVER_NAME/\./-}
VHOST_FILENAME="$VHOST_NAME.conf"

if [ -z "${SERVER_NAME}" ] || [ -z "${CLUSTER_NAME}" ]; then
    usage
fi

VHOST_COUNT=`ls -1 ${APACHE_VHOST_PATH} | grep "${VHOST_FILENAME}" | wc -l`

if [ ${VHOST_COUNT} -gt 0 ]; then
    echo "vhost '${VHOST_NAME}' already exists ... skipping"
    exit
fi

cp "$APACHE_VHOST_PATH/vhost.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"

sed -i "s/\(ServerName\s*\)\(.*\)/\1$SERVER_NAME/" $APACHE_VHOST_PATH/$VHOST_FILENAME
sed -i "s/\(balancer:\/\/\)\[\(.*\)\]\//\1$CLUSTER_NAME\//" $APACHE_VHOST_PATH/$VHOST_FILENAME

if [ -z "${SERVER_ALIAS}" ]; then
    sed -i '/ServerAlias/d' $APACHE_VHOST_PATH/$VHOST_FILENAME
else
    sed -i "s/\(ServerAlias\s*\)\(.*\)/\1$SERVER_ALIAS /" $APACHE_VHOST_PATH/$VHOST_FILENAME
fi

a2ensite $VHOST_NAME 2>&1 > /dev/null

echo "vhost '${VHOST_NAME}' initialized & enabled!"