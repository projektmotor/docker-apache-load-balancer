#!/bin/bash

APACHE_VHOST_PATH=/etc/apache2/sites-available/
APACHE_MAINTENANCE_PATH=/etc/apache2/maintenance-pages
APACHE_MAINTENANCE_PATH_ESCAPED=\\/etc\\/apache2\\/maintenance-pages
CERTBOT_BIN=/usr/bin/certbot
SSL_ENABLED=0
SERVER_ALIAS=""

read -p 'Domain (e.q. acme.com): ' SERVER_NAME
read -p 'Target IP/DNS: ' TARGET_IP
read -p 'Target PORT: ' TARGET_PORT
read -p 'Domain Alias (comma separated, optional): ' SERVER_ALIAS
read -p 'With maintenance page [y|n]: ' WITH_MAINTENANCE
read -p 'Enable SSL [y|n]: ' SSL_ENABLED

if [ "${SSL_ENABLED}" = "y" ]; then
    read -p 'Does intern host use SSL? [y|n]: ' SSL_ENABLED_INTERN
else
    SSL_ENABLED_INTERN="n"
fi

VHOST_FILENAME="${SERVER_NAME}.conf"
VHOST_SSL_FILENAME="${SERVER_NAME}.ssl.conf"
VHOST_SSL_MAINTENANCE_FILENAME="${SERVER_NAME}.ssl.conf_maintenance"
VHOST_SSL_RUNNING_FILENAME="${SERVER_NAME}.ssl.conf_running"
HTML_MAINTENANCE_FILENAME="${SERVER_NAME}.maintenance.html"

if [ "${SSL_ENABLED_INTERN}" = "y" ]; then
    VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.ssl.https.conf.dist"
elif [ "${SSL_ENABLED_INTERN}" = "n" ]; then
    VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.ssl.http.conf.dist"
else
    echo "Please provide n or y for 'Does intern host use SSL?'"
    exit 1
fi

if [ -z "${SERVER_NAME}" ] || [ -z "${TARGET_IP}" ] || [ -z "${TARGET_PORT}" ]; then
    echo "Please provide at least Domain, IP & Port"
    exit 1
fi

VHOST_COUNT=`ls -1 ${APACHE_VHOST_PATH} | grep "${VHOST_FILENAME}" | wc -l`

if [ ${VHOST_COUNT} -gt 0 ]; then
    echo "vhost '${SERVER_NAME}' already exists ... skipping"
    exit
fi

# OBTAIN CERTIFICATE FOR DOMAIN USING CERTBOT (LETSENCRYPT) WITH WEBROOT-PLUGIN
# see: https://certbot.eff.org/docs/using.html#webroot
# notice: apache plugin requires apache restart, which ends up in container shutdown.
#         webroot plugin does not execute the restart.
if [ "${SSL_ENABLED}" = "y" ]; then
    mkdir -p /var/www/certbot-webroot
    cp "${APACHE_VHOST_PATH}/reverseproxy-vhost-ssl-webroot.conf.dist" "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"

    # PERSONALIZE HTTP-VHOST
    sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

    a2ensite ${VHOST_FILENAME} > /dev/null 2>&1
    /etc/init.d/apache2 force-reload > /dev/null 2>&1

    echo "Temporary vhost creation for webroot-plugin: OK";

    # RETRIEVE SSL CERTIFICATE WITH WEBROOT PLUGIN
    ${CERTBOT_BIN} certonly --webroot -w /var/www/certbot-webroot \
        -d ${SERVER_NAME} \
        -n --agree-tos --email admin@${SERVER_NAME} \
        >> /var/log/certbot-${SERVER_NAME}.log 2>&1

    if [ $? != 0 ]; then
        echo "Certification retrieval: FAILED";
        echo "Error while retrieving SSL-Certificate (see: /var/log/certbot-${SERVER_NAME}.log)"

        # cleanup temp vhost conf
        a2dissite ${VHOST_FILENAME} > /dev/null 2>&1
        rm "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
        /etc/init.d/apache2 force-reload > /dev/null 2>&1

        exit 1
    fi

    echo "Certification retrieval: OK";

    # cleanup temp vhost conf
    a2dissite ${VHOST_FILENAME} > /dev/null 2>&1
    rm "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
    /etc/init.d/apache2 force-reload > /dev/null 2>&1
fi

# COPY VHOST TEMPLATES
cp "${APACHE_VHOST_PATH}/reverseproxy-vhost.conf.dist" "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
echo "HTTP-VHost template creation: OK";

if [ "${SSL_ENABLED}" = "y" ]; then
    cp "${APACHE_VHOST_PATH}/${VHOST_SSL_TEMPLATE_FILENAME}" "${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}"
    echo "HTTPS-VHost template creation: OK";
fi

if [ "${WITH_MAINTENANCE}" = "y" ]; then
    cp "${APACHE_VHOST_PATH}/reverseproxy-vhost.ssl.conf_maintenance.dist" "${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}"
    cp "${APACHE_MAINTENANCE_PATH}/maintenance.html.dist" "${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}"
    echo "HTTPS-VHost maintenance template creation: OK";
fi

# PERSONALIZE HTTP-VHOST
sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

if [ -z "${SERVER_ALIAS}" ]; then
    sed -i '/ServerAlias/d' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
else
    sed -i "s/\[SERVER_ALIAS]/$SERVER_ALIAS/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
fi

echo "HTTP-VHost personalization: OK";

# PERSONALIZE HTTPS-VHOST
if [ "${SSL_ENABLED}" = "y" ]; then
    sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    sed -i "s/\[TARGET_IP]/${TARGET_IP}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    sed -i "s/\[TARGET_PORT]/${TARGET_PORT}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}

    echo "HTTPS-VHost personalization: OK";

    if [ "${WITH_MAINTENANCE}" = "y" ]; then
        sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
        sed -i "s/\[APACHE_MAINTENANCE_PATH]/${APACHE_MAINTENANCE_PATH_ESCAPED}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
        sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}

        echo "HTTPS-VHost maintenance personalization: OK";

        cp ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME} ${APACHE_VHOST_PATH}/${VHOST_SSL_RUNNING_FILENAME}
    fi
fi

a2ensite ${VHOST_FILENAME} > /dev/null 2>&1
a2ensite ${VHOST_SSL_FILENAME} > /dev/null 2>&1
/etc/init.d/apache2 force-reload > /dev/null 2>&1

echo "vhost '${SERVER_NAME}' initialized & enabled!"

if [ "${WITH_MAINTENANCE}" = "y" ]; then
    echo "Do not forget to adopt the html of your maintenance page in ${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}";

    cp ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME} ${APACHE_VHOST_PATH}/${VHOST_SSL_RUNNING_FILENAME}
fi
