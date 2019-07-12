#!/bin/bash

APACHE_LOADBALANCER_CONF=/etc/apache2/conf-loadbalancer/loadbalancer.conf

CLUSTER_NAME=""
VHOST_URI=""
VHOST_SSL=""
NODES_CONF=""
NODE_SSL=""
PROXY_ADDRESS=""

addNode()
{
#    echo "apache-add-cluster-node.sh ${CLUSTER_NAME} $1"
    apache-add-cluster-node.sh ${CLUSTER_NAME} $1 ${NODE_SSL}
}

init()
{
    apache-init-cluster.sh ${CLUSTER_NAME}

    if [ -n "${PROXY_ADDRESS}" ]; then
        apache-init-cluster-vhost.sh -p ${PROXY_ADDRESS} ${VHOST_URI} ${VHOST_SSL} ${CLUSTER_NAME} ${NODE_SSL}
    else
        apache-init-cluster-vhost.sh ${VHOST_URI} ${VHOST_SSL} ${CLUSTER_NAME} ${NODE_SSL}
    fi

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
        CLUSTER_NAME=""
        VHOST_URI=""
        VHOST_SSL=""
        NODES_CONF=""
        NODE_SSL=""
        PROXY_ADDRESS=""
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
        VHOST_SSL=${LINE_DATA[1]}
    fi


    if [ "${LINE_DATA[0]}" == "cluster" ]; then
        CLUSTER_NAME=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "nodes" ]; then
        NODES_CONF=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "node_ssl" ]; then
        NODE_SSL=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "reverse_proxy_address" ]; then
        PROXY_ADDRESS=${LINE_DATA[1]}
    fi


    # all config available? init & reset local vars
    if [ -n "${VHOST_URI}" ] && [ -n "${VHOST_SSL}" ] && [ -n "${CLUSTER_NAME}" ] && [ -n "${NODES_CONF}" ] && [ -n "${NODE_SSL}" ]; then
        init
        CLUSTER_NAME=""
        VHOST_URI=""
        VHOST_SSL=""
        NODES_CONF=""
        NODE_SSL=""
        PROXY_ADDRESS=""
    fi

done < ${APACHE_LOADBALANCER_CONF}