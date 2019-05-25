#!/bin/bash

APACHE_PROXY_CONFIG=/etc/apache2/conf-available/proxy.conf
CLUSTER_NAME=$1
NODE=$2
USE_SSL=$3
PROTOCOL="http"
NODE_DATA=(${NODE//:/ })
NODE_IP=${NODE_DATA[0]}
NODE_PORT=${NODE_DATA[1]:-80}

usage() { echo "Usage: $0 CLUSTER_NAME NODE_IP|NODE_URI[:PORT] USE_SSL" 1>&2; exit 1; }

while getopts a: opt
do
   case $opt in
       a) SERVER_ALIAS=${OPTARG};;
       *) usage ;;
   esac
done

if [ -z "${CLUSTER_NAME}" ] || [ -z "${NODE_IP}" ] || [ -z "${NODE_PORT}" ]; then
    usage
fi

CLUSTER_CONFIG=`sed -e "1,/${CLUSTER_NAME}/ d" -e '/ProxySet/,$ d' ${APACHE_PROXY_CONFIG}`
NODE_EXISTS=`echo $CLUSTER_CONFIG | grep "$NODE_IP:$NODE_PORT" | wc -l`

if [ ${NODE_EXISTS} -gt 0 ]; then
    echo "node '${NODE_IP}:${NODE_PORT}' already exists in cluster '${CLUSTER_NAME}' ... skipping"
    exit
fi

NODE_COUNT=`echo $CLUSTER_CONFIG | grep BalancerMember | wc -l`
NEW_NODE_NUMBER=$(($NODE_COUNT + 1))

if [ $NEW_NODE_NUMBER -eq 1 ]; then
    NEW_NODE_STATUS=""
else
    NEW_NODE_STATUS="status=+H"
fi

if [ -n $USE_SSL ] && [ "$USE_SSL" == "true" ]; then
    PROTOCOL="https"
    NODE_PORT=443
fi

NEW_NODE_CONFIG="BalancerMember $PROTOCOL:\/\/$NODE_IP:$NODE_PORT route=balancer.web$NEW_NODE_NUMBER loadfactor=45 $NEW_NODE_STATUS"

SEARCH="# INSERT $CLUSTER_NAME NODES BEFORE THIS"
REPLACEMENT="${NEW_NODE_CONFIG}\n        # INSERT $CLUSTER_NAME NODES BEFORE THIS"

sed -i "s/$SEARCH/$REPLACEMENT/" $APACHE_PROXY_CONFIG

echo "node '${NODE_IP}:${NODE_PORT}' added to cluster '${CLUSTER_NAME}'!"