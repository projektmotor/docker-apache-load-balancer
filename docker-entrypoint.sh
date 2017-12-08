#!/bin/bash

APACHE_LOADBALANCER_CONF=/etc/apache2/conf-loadbalancer/loadbalancer.conf

BALANCER_MANAGER_USER=${BALANCER_MANAGER_USER:-'root'}
BALANCER_MANAGER_PASS=${BALANCER_MANAGER_PASS:-'root'}

CLUSTER_NAME=""
VHOST_URI=""
NODES_CONF=""

addNode()
{
#    echo "apache-add-cluster-node.sh ${CLUSTER_NAME} $1"
    apache-add-cluster-node.sh ${CLUSTER_NAME} $1
}

init()
{
#    echo "apache-init-cluster.sh ${CLUSTER_NAME}"
#    echo "apache-init-host.sh ${VHOST_URI} ${CLUSTER_NAME}"
    apache-init-cluster.sh ${CLUSTER_NAME}
    apache-init-host.sh ${VHOST_URI} ${CLUSTER_NAME}

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
        NODES_CONF=""
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

    if [ "${LINE_DATA[0]}" == "cluster" ]; then
        CLUSTER_NAME=${LINE_DATA[1]}
    fi

    if [ "${LINE_DATA[0]}" == "nodes" ]; then
        NODES_CONF=${LINE_DATA[1]}
    fi

    # all config available? init & reset local vars
    if [ -n "${VHOST_URI}" ] && [ -n "${CLUSTER_NAME}" ] && [ -n "${NODES_CONF}" ]; then
        init
        CLUSTER_NAME=""
        VHOST_URI=""
        NODES_CONF=""
    fi

done < ${APACHE_LOADBALANCER_CONF}

htpasswd -bc /var/.htpasswd ${BALANCER_MANAGER_USER} ${BALANCER_MANAGER_PASS}

/usr/sbin/apache2ctl -DFOREGROUND