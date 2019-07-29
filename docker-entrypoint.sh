#!/bin/bash

/etc/init.d/cron restart

BALANCER_MANAGER_USER=${BALANCER_MANAGER_USER:-'root'}
BALANCER_MANAGER_PASS=${BALANCER_MANAGER_PASS:-'root'}

rsync -qlru --exclude=conf-loadbalancer/loadbalancer.conf /tmp/apache2/ /etc/apache2/
rsync -qlru /tmp/letsencrypt/ /etc/letsencrypt/

chown -R root:root /etc/apache2 /etc/letsencrypt

apache-reload-cluster-conf.sh
apache-remoteip-init-docker-networks.sh

htpasswd -bc /var/.htpasswd ${BALANCER_MANAGER_USER} ${BALANCER_MANAGER_PASS}

/usr/sbin/apache2ctl -DFOREGROUND