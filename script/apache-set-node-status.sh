#!/bin/bash

APACHE_PROXY_CONFIG=/etc/apache2/conf-available/proxy.conf

CLUSTER_NAME=$1
NODE=$2
NODE_STATUS=${3:-'+H'}

usage() { echo "Usage: $0 CLUSTER_NAME NODE_IP|NODE_URI[:PORT] [STATUS]" 1>&2; exit 1; }

if [ -z "${CLUSTER_NAME}" ] || [ -z "${NODE}" ] || [ -z "${NODE_STATUS}" ]; then
    usage
fi

APACHE_PROXY_CONFIG_TMP="${APACHE_PROXY_CONFIG}.tmp"
cat /dev/null > ${APACHE_PROXY_CONFIG_TMP}

IN_CLUSTER_BLOCK=false

while IFS= read -r line
do
    if [[ $line =~ \<\/Proxy\> ]] && ${IN_CLUSTER_BLOCK}; then
        IN_CLUSTER_BLOCK=false
        echo -e "$line" >> ${APACHE_PROXY_CONFIG_TMP}
        continue
    fi

    # continue on comments
    if [[ $line =~ \<Proxy.*balancer:\/\/${CLUSTER_NAME} ]]; then
        IN_CLUSTER_BLOCK=true
        echo -e "$line" >> ${APACHE_PROXY_CONFIG_TMP}
        continue
    fi

    if ! ${IN_CLUSTER_BLOCK}; then
        echo -e "$line" >> ${APACHE_PROXY_CONFIG_TMP}
        continue
    fi

    if [[ $line =~ BalancerMember.*http:\/\/${NODE} ]]; then

        if [[ "$line" =~ status ]]; then
            line=$(sed "s/\(status=\)\(.*\)/\1${NODE_STATUS}/g" <<< "$line")
        else
            line=`echo "$line status=${NODE_STATUS}"`
        fi

        echo "$line" >> ${APACHE_PROXY_CONFIG_TMP}
    else
        echo "$line" >> ${APACHE_PROXY_CONFIG_TMP}
    fi

done < ${APACHE_PROXY_CONFIG}

mv ${APACHE_PROXY_CONFIG_TMP} ${APACHE_PROXY_CONFIG}