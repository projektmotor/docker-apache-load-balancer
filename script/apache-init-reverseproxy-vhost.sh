#!/bin/bash

function is_empty() {
    if [[ "${1}" = "" ]]; then
        return 0
    fi

    return 1
}

function is_falsly() {
    if [[ "${1}" = "n" ]] || [[ "${1}" = "N" ]]; then
        return 0
    fi

    return 1
}

function is_truely() {
    if [[ "${1}" = "y" ]] || [[ "${1}" = "Y" ]]; then
        return 0
    fi

    return 1
}


APACHE_VHOST_PATH=/etc/apache2/sites-available/
APACHE_MAINTENANCE_PATH=/etc/apache2/maintenance-pages
APACHE_MAINTENANCE_PATH_ESCAPED=\\/etc\\/apache2\\/maintenance-pages
CERTBOT_BIN=/usr/bin/certbot
SSL_ENABLED=""
SERVER_ALIAS=""

while getopts d:i:p:a:m:s:l: option
do
case "${option}"
in
d) SERVER_NAME=${OPTARG};;
i) TARGET_IP=${OPTARG};;
p) TARGET_PORT=${OPTARG};;
a) SERVER_ALIAS=${OPTARG};;
m) WITH_MAINTENANCE=${OPTARG};;
s) SSL_ENABLED=${OPTARG};;
l) SSL_ENABLED_INTERN=${OPTARG};;
esac
done

if is_empty ${SERVER_NAME}; then
    read -p 'Domain (e.q. acme.com; shortcut d): ' SERVER_NAME
fi

if is_empty ${TARGET_IP}; then
    read -p 'Target IP/DNS (shortcut i): ' TARGET_IP
fi

if is_empty ${TARGET_PORT}; then
    read -p 'Target PORT (shortcut p): ' TARGET_PORT
fi

if is_empty ${SERVER_ALIAS} && ! is_falsly ${SERVER_ALIAS}; then
    read -p 'Domain Alias (comma separated, optional; shortcut: a): ' SERVER_ALIAS
    if is_empty ${SERVER_ALIAS}; then
        SERVER_ALIAS="n"
    fi
fi

if is_empty ${WITH_MAINTENANCE}; then
    read -p 'With maintenance page (shortcut: m) [Y|n]: ' WITH_MAINTENANCE
fi
if is_empty ${WITH_MAINTENANCE}; then
    WITH_MAINTENANCE="y"
fi

if is_empty ${SSL_ENABLED}; then
    read -p 'Enable SSL (shortcut: s) [Y|n]: ' SSL_ENABLED
fi
if is_empty ${SSL_ENABLED}; then
    SSL_ENABLED="Y"
fi

if is_truely ${SSL_ENABLED}; then
    if is_empty ${SSL_ENABLED_INTERN}; then
        read -p 'Does intern host use SSL? (shortcut: l) [Y|n]: ' SSL_ENABLED_INTERN
    fi
    if is_empty ${SSL_ENABLED_INTERN}; then
        SSL_ENABLED_INTERN="y"
    fi
else
    SSL_ENABLED_INTERN="n"
fi

echo ""
echo "One-liner to rerun this script:"
echo "apache-init-reverseproxy-vhost.sh -d ${SERVER_NAME} -i ${TARGET_IP} -p ${TARGET_PORT} -a ${SERVER_ALIAS} -m ${WITH_MAINTENANCE} -s ${SSL_ENABLED} -l ${SSL_ENABLED_INTERN}"
echo ""

VHOST_FILENAME="${SERVER_NAME}.conf"
VHOST_SSL_FILENAME="${SERVER_NAME}.ssl.conf"
VHOST_SSL_MAINTENANCE_FILENAME="${SERVER_NAME}.ssl.conf_maintenance"
VHOST_SSL_RUNNING_FILENAME="${SERVER_NAME}.ssl.conf_running"
HTML_MAINTENANCE_FILENAME="${SERVER_NAME}.maintenance.html"

if is_truely ${SSL_ENABLED_INTERN}; then
    VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.ssl.https.conf.dist"
elif is_falsly ${SSL_ENABLED_INTERN}; then
    VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.ssl.http.conf.dist"
else
    echo "Please provide n or y for 'Does intern host use SSL?'"
    exit 1
fi

if [ -z "${SERVER_NAME}" ] || [ -z "${TARGET_IP}" ] || [ -z "${TARGET_PORT}" ]; then
    echo "Please provide at least Domain, IP & Port"
    exit 1
fi

VHOST_COUNT=`ls -1 ${APACHE_VHOST_PATH} | grep "^${VHOST_FILENAME}" | wc -l`

if [ ${VHOST_COUNT} -gt 0 ]; then
    echo "vhost '${SERVER_NAME}' already exists ... skipping"
    exit
fi

# OBTAIN CERTIFICATE FOR DOMAIN USING CERTBOT (LETSENCRYPT) WITH WEBROOT-PLUGIN
# see: https://certbot.eff.org/docs/using.html#webroot
# notice: apache plugin requires apache restart, which ends up in container shutdown.
#         webroot plugin does not execute the restart.
if is_truely ${SSL_ENABLED}; then
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

if is_truely ${SSL_ENABLED}; then
    cp "${APACHE_VHOST_PATH}/${VHOST_SSL_TEMPLATE_FILENAME}" "${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}"
    echo "HTTPS-VHost template creation: OK";
fi

if is_truely ${WITH_MAINTENANCE}; then
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
if is_truely ${SSL_ENABLED}; then
    sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    sed -i "s/\[TARGET_IP]/${TARGET_IP}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    sed -i "s/\[TARGET_PORT]/${TARGET_PORT}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}

    echo "HTTPS-VHost personalization: OK";

    if is_truely ${WITH_MAINTENANCE}; then
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

if is_truely ${WITH_MAINTENANCE}; then
    echo "Do not forget to adopt the html of your maintenance page in ${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}";

    cp ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME} ${APACHE_VHOST_PATH}/${VHOST_SSL_RUNNING_FILENAME}
fi
