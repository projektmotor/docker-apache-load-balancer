#!/bin/bash

APACHE_LOADBALANCER_CONF=/etc/apache2/conf-loadbalancer/loadbalancer.conf

CLUSTER_NAME=""
VHOST_URI=""
INCOMING_SSL=""
INCOMING_SSL_SELF_SIGNED=""
NODES_CONF=""
OUTGOING_SSL=""
PROXY_ADDRESS=""
INCLUDE_TRUSTED_DOCKER_PROXIES=""

addNode()
{
#    echo "apache-add-cluster-node.sh ${CLUSTER_NAME} $1"
    apache-add-cluster-node.sh ${CLUSTER_NAME} $1 ${OUTGOING_SSL}
}

init()
{
    apache-init-cluster.sh ${CLUSTER_NAME}
    apache-init-cluster-vhost.sh \
        ${VHOST_URI} \
        ${CLUSTER_NAME} \
        ${INCOMING_SSL} \
        ${INCOMING_SSL_SELF_SIGNED} \
        ${OUTGOING_SSL} \
        ${INCLUDE_TRUSTED_DOCKER_PROXIES} \
        ${PROXY_ADDRESS}

    NODES_CONF="${NODES_CONF/\[/}"
    NODES_CONF="${NODES_CONF/\]/}"

    NODE_DATA=(${NODES_CONF//;/ })

    for i in "${NODE_DATA[@]}";  do
       addNode $i
    done
}

while read line
do
    # continue on comments
    if [[ $line =~ ^\s*#.*$ ]]; then
        continue
    fi

    # reset data on [HEADER] line & continue
    if [[ $line =~ ^\s*\[.*\]$ ]]; then

        # all config available? init & reset local vars
        if [ -n "${VHOST_URI}" ] && [ -n "${INCOMING_SSL}" ] && [ -n "${CLUSTER_NAME}" ] && [ -n "${NODES_CONF}" ] && [ -n "${OUTGOING_SSL}" ]; then
            init
        fi

        CLUSTER_NAME=""
        VHOST_URI=""
        INCOMING_SSL=""
        NODES_CONF=""
        OUTGOING_SSL=""
        PROXY_ADDRESS=""
        INCLUDE_TRUSTED_DOCKER_PROXIES=""
        continue
    fi

    LINE_DATA=(${line//=/ })

    # continue if no KEY = VALUE line found
    if [ ! -n "${LINE_DATA[0]}" ] || [ ! -n "${LINE_DATA[1]}" ]; then
        continue
    fi

    # ####################
    # collect config data
    # ####################

    if [ "${LINE_DATA[0]}" == "uri" ]; then
        VHOST_URI=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "ssl" ]; then
        INCOMING_SSL=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "ssl_self_signed" ]; then
        INCOMING_SSL_SELF_SIGNED=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "cluster" ]; then
        CLUSTER_NAME=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "nodes" ]; then
        NODES_CONF=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "node_ssl" ]; then
        OUTGOING_SSL=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "reverse_proxy_address" ]; then
        PROXY_ADDRESS=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "include_trusted_docker_proxies" ]; then
        INCLUDE_TRUSTED_DOCKER_PROXIES=${LINE_DATA[1]}
    fi

done < ${APACHE_LOADBALANCER_CONF}

# all config available? init & reset local vars
if [ -n "${VHOST_URI}" ] && [ -n "${CLUSTER_NAME}" ] && [ -n "${NODES_CONF}" ]; then
    init
fi