#!/bin/bash

APACHE_TRUSTED_DOCKER_PROXIES=/etc/apache2/conf-available/trusted-docker-proxies.conf

ip -h -o address | grep eth | awk '{ print $4 }' > ${APACHE_TRUSTED_DOCKER_PROXIES}