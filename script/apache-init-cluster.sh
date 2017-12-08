#!/bin/bash

APACHE_PROXY_CONFIG=/etc/apache2/conf-available/proxy.conf
CLUSTER_NAME=$1

usage() { echo "Usage: $0 CLUSTER_NAME" 1>&2; exit 1; }

if [ -z "${CLUSTER_NAME}" ]; then
    usage
fi

if grep -q $CLUSTER_NAME "$APACHE_PROXY_CONFIG"; then
    echo "cluster '$CLUSTER_NAME' already exists ... skipping"
    exit
fi

# temporary remove last line
sed -i '/<\/IfModule>/d' $APACHE_PROXY_CONFIG

# add new cluster (including module closing tag)
echo "    <Proxy balancer://$CLUSTER_NAME/>"                            >> $APACHE_PROXY_CONFIG
echo "        # INSERT $CLUSTER_NAME NODES BEFORE THIS"                 >> $APACHE_PROXY_CONFIG
echo "        ProxySet lbmethod=byrequests stickysession=BALANCE_ID"    >> $APACHE_PROXY_CONFIG
echo "    </Proxy>"                                                     >> $APACHE_PROXY_CONFIG
echo ""                                                                 >> $APACHE_PROXY_CONFIG
echo "</IfModule>"                                                      >> $APACHE_PROXY_CONFIG

echo "cluster '${CLUSTER_NAME}' initialized!"