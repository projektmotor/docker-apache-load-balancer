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
APACHE_VHOST_TEMPLATE_PATH=/etc/apache2/sites-template/
APACHE_MAINTENANCE_PATH=/etc/apache2/maintenance-pages
APACHE_MAINTENANCE_PATH_ESCAPED=\\/etc\\/apache2\\/maintenance-pages
APACHE_TRUSTED_DOCKER_PROXIES=\\/etc\\/apache2\\/conf-available\\/trusted-docker-proxies.conf
CERTBOT_BIN=/usr/bin/certbot
INCOMING_SSL_ENABLED=""
OUTGOING_SSL_ENABLED=""
SERVER_ALIAS=""
REVERSE_PROXY_ADDRESS=""
INCOMING_SSL_SELF_SIGNED=""
INCLUDE_TRUSTED_DOCKER_PROXIES=""
REWRITE_WEBSOCKET_REQUESTS=""

while getopts d:i:p:a:m:s:e:l:r:q:w: option
do
case "${option}"
in
d) SERVER_NAME=${OPTARG};;
i) TARGET_IP=${OPTARG};;
p) TARGET_PORT=${OPTARG};;
a) SERVER_ALIAS=${OPTARG};;
m) WITH_MAINTENANCE=${OPTARG};;
s) INCOMING_SSL_ENABLED=${OPTARG};;
e) INCOMING_SSL_SELF_SIGNED=${OPTARG};;
l) OUTGOING_SSL_ENABLED=${OPTARG};;
r) REVERSE_PROXY_ADDRESS=${OPTARG};;
q) INCLUDE_TRUSTED_DOCKER_PROXIES=${OPTARG};;
w) REWRITE_WEBSOCKET_REQUESTS=${OPTARG};;
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

if is_empty ${INCOMING_SSL_ENABLED}; then
    read -p 'Enable SSL for incoming connections - from browser (shortcut: s) [Y|n]: ' INCOMING_SSL_ENABLED
fi
if is_empty ${INCOMING_SSL_ENABLED}; then
    INCOMING_SSL_ENABLED="Y"
fi

if is_truely ${INCOMING_SSL_ENABLED}; then
    if is_empty ${INCOMING_SSL_SELF_SIGNED}; then
        read -p 'Use self-signed certificate for incoming connections - from browser (only used when SSL for incoming connections is enabled; when N is used then certbot certificate is generated; shortcut: e) [y|N]: ' INCOMING_SSL_SELF_SIGNED
    fi
    if is_empty ${INCOMING_SSL_ENABLED}; then
        INCOMING_SSL_ENABLED="N"
    fi
fi

if is_empty ${OUTGOING_SSL_ENABLED}; then
    read -p 'Enable SSL for outgoing connections - to docker container (shortcut: l) [Y|n]: ' OUTGOING_SSL_ENABLED
fi
if is_empty ${OUTGOING_SSL_ENABLED}; then
    OUTGOING_SSL_ENABLED="y"
fi

if is_empty ${INCLUDE_TRUSTED_DOCKER_PROXIES}; then
    read -p 'Include Docker networks as trusted proxies - needed if behind another reverse proxy / load balancer to make RemoteIP work (shortcut: q) [y|N]: ' INCLUDE_TRUSTED_DOCKER_PROXIES
fi
if is_empty ${INCLUDE_TRUSTED_DOCKER_PROXIES}; then
    INCLUDE_TRUSTED_DOCKER_PROXIES="N"
fi

if is_falsly ${INCLUDE_TRUSTED_DOCKER_PROXIES}; then
    if is_empty ${REVERSE_PROXY_ADDRESS} || is_falsly ${REVERSE_PROXY_ADDRESS}; then
        read -p 'Reverse-Proxy or Load-Balancer IP/DNS - needed if behind another reverse proxy / load balancer which is not reachable over docker interfaces (shortcut: r): ' REVERSE_PROXY_ADDRESS
    fi
fi


if is_empty ${REWRITE_WEBSOCKET_REQUESTS}; then
    read -p 'Rewrite websocket requests - needed for e.g. webpack dev server (shortcut: w) [y|N]: ' REWRITE_WEBSOCKET_REQUESTS
fi
if is_empty ${REWRITE_WEBSOCKET_REQUESTS}; then
    REWRITE_WEBSOCKET_REQUESTS="N"
fi

echo ""
echo "One-liner to rerun this script:"
echo "apache-init-reverseproxy-vhost.sh \
-d ${SERVER_NAME} \
-i ${TARGET_IP} \
-p ${TARGET_PORT} \
-a ${SERVER_ALIAS} \
-m ${WITH_MAINTENANCE} \
-s ${INCOMING_SSL_ENABLED} \
-e ${INCOMING_SSL_SELF_SIGNED} \
-l ${OUTGOING_SSL_ENABLED} \
-r ${REVERSE_PROXY_ADDRESS} \
-w ${REWRITE_WEBSOCKET_REQUESTS} \
-q ${INCLUDE_TRUSTED_DOCKER_PROXIES} "
echo ""

VHOST_CERTBOT_FILENAME="${SERVER_NAME}_certbot.conf"
VHOST_FILENAME="${SERVER_NAME}.conf"
VHOST_MAINTENANCE_FILENAME="${SERVER_NAME}.conf_maintenance"
VHOST_RUNNING_FILENAME="${SERVER_NAME}.conf_running"
VHOST_SSL_FILENAME="${SERVER_NAME}.ssl.conf"
VHOST_SSL_MAINTENANCE_FILENAME="${SERVER_NAME}.ssl.conf_maintenance"
VHOST_SSL_RUNNING_FILENAME="${SERVER_NAME}.ssl.conf_running"
HTML_MAINTENANCE_FILENAME="${SERVER_NAME}.maintenance.html"

if is_truely ${INCOMING_SSL_ENABLED}; then
    if is_truely ${OUTGOING_SSL_ENABLED}; then
        VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.incoming_https.outgoing_https.conf.dist"
    else
        VHOST_SSL_TEMPLATE_FILENAME="reverseproxy-vhost.incoming_https.outgoing_http.conf.dist"
    fi
else
    if is_truely ${OUTGOING_SSL_ENABLED}; then
        VHOST_TEMPLATE_FILENAME="reverseproxy-vhost.incoming_http.outgoing_https.conf.dist"
    else
        VHOST_TEMPLATE_FILENAME="reverseproxy-vhost.incoming_http.outgoing_http.conf.dist"
    fi
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

# COPY VHOST TEMPLATES
if is_truely ${INCOMING_SSL_ENABLED}; then
    cp "${APACHE_VHOST_TEMPLATE_PATH}/${VHOST_SSL_TEMPLATE_FILENAME}" "${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}"
    cp "${APACHE_VHOST_TEMPLATE_PATH}/reverseproxy-vhost.incoming_https.redirect_http.conf.dist" "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
    echo "HTTPS-VHost template creation: OK";
else
    cp "${APACHE_VHOST_TEMPLATE_PATH}/${VHOST_TEMPLATE_FILENAME}" "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
    echo "HTTP-VHost template creation: OK";
fi

if is_truely ${INCOMING_SSL_ENABLED}; then
    if is_truely ${INCOMING_SSL_SELF_SIGNED}; then
        ROOT_CERTIFICATE_FILE="/etc/myCA.pem"
        ROOT_CERTIFICATE_KEY="/etc/myCA.key"
        CERTIFICATION_BASE_PATH="/root/ssl-certification"

        if [ ! -f "${ROOT_CERTIFICATE_FILE}" ] || [ ! -f "${ROOT_CERTIFICATE_KEY}" ]; then
            rm "${APACHE_VHOST_PATH}/${VHOST_FILENAME}"
            rm "${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}"

            echo "to use a self-sign certificate, you need a root-ca & -key mounted under: /etc/myCA.pem & /etc/myCA.key"
            echo "see readme for more information!"
            echo ""
            echo "VHost creation failed!"
            exit 1
        fi

        # reset folder for temp certification files
        mkdir -p ${CERTIFICATION_BASE_PATH}
        rm -rf ${CERTIFICATION_BASE_PATH}/*

        # create certificate with mounted root-ca & -key
        # private key:
        openssl genrsa -out ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.key 2048
        chmod 644 ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.key
        # create csr (certificate sign request):
        openssl req \
            -new \
            -key ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.key \
            -out ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.csr \
            -subj "/CN=${SERVER_NAME}/O=ProjektMOTOR GmbH/C=DE"

        # create config file for certification process
        echo "authorityKeyIdentifier=keyid,issuer"                                              >  ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo "basicConstraints=CA:FALSE"                                                        >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo "keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment"   >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo "subjectAltName = @alt_names"                                                      >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo ""                                                                                 >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo "[alt_names]"                                                                      >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        echo "DNS.1 = ${SERVER_NAME}"                                                           >> ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext
        # create self sign certificate
        openssl x509 \
            -req \
            -in ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.csr \
            -CA ${ROOT_CERTIFICATE_FILE} \
            -CAkey ${ROOT_CERTIFICATE_KEY} \
            -CAcreateserial \
            -out ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.crt \
            -days 1825 \
            -sha256 \
            -extfile ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.ext

        # move key & certificate to its final path (used in vhost configs)
        mkdir -p /etc/ssl_ca/certs /etc/ssl_ca/keys
        mv ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.key /etc/ssl_ca/keys
        mv ${CERTIFICATION_BASE_PATH}/${SERVER_NAME}.crt /etc/ssl_ca/certs
        # cleanup
        rm -rf ${CERTIFICATION_BASE_PATH}/*

        sed -i "s/SSLCertificateKeyFile.*/SSLCertificateKeyFile \/etc\/ssl_ca\/keys\/${SERVER_NAME}.key/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
        sed -i "s/SSLCertificateFile.*/SSLCertificateFile \/etc\/ssl_ca\/certs\/${SERVER_NAME}.crt/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
        sed -i "s/SSLCertificateChainFile.*//" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    else
        # OBTAIN CERTIFICATE FOR DOMAIN USING CERTBOT (LETSENCRYPT) WITH WEBROOT-PLUGIN
        # see: https://certbot.eff.org/docs/using.html#webroot
        # notice: apache plugin requires apache restart, which ends up in container shutdown.
        #         webroot plugin does not execute the restart.
        mkdir -p /var/www/certbot-webroot
        cp "${APACHE_VHOST_TEMPLATE_PATH}/certbot-vhost-webroot.conf.dist" "${APACHE_VHOST_PATH}/${VHOST_CERTBOT_FILENAME}"

        # PERSONALIZE HTTP-VHOST
        sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_CERTBOT_FILENAME}

        a2ensite ${VHOST_CERTBOT_FILENAME} > /dev/null 2>&1
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
            a2dissite ${VHOST_CERTBOT_FILENAME} > /dev/null 2>&1
            rm "${APACHE_VHOST_PATH}/${VHOST_CERTBOT_FILENAME}"
            /etc/init.d/apache2 force-reload > /dev/null 2>&1

            exit 1
        fi

        echo "Certification retrieval: OK";

        # cleanup temp vhost conf
        a2dissite ${VHOST_CERTBOT_FILENAME} > /dev/null 2>&1
        rm "${APACHE_VHOST_PATH}/${VHOST_CERTBOT_FILENAME}"
        /etc/init.d/apache2 force-reload > /dev/null 2>&1
    fi
fi

if is_truely ${WITH_MAINTENANCE}; then
    if is_truely ${INCOMING_SSL_ENABLED}; then
        cp "${APACHE_VHOST_TEMPLATE_PATH}/reverseproxy-vhost.incoming_https.conf_maintenance.dist" "${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}"
    else
        cp "${APACHE_VHOST_TEMPLATE_PATH}/reverseproxy-vhost.incoming_http.conf_maintenance.dist" "${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}"
    fi

    cp "${APACHE_MAINTENANCE_PATH}/maintenance.html.dist" "${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}"
    echo "HTTP(S)-VHost maintenance template creation: OK";
fi

# PERSONALIZE HTTP-VHOST
sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

if is_falsly ${SERVER_ALIAS}; then
    sed -i '/ServerAlias/d' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
else
    sed -i "s/\[SERVER_ALIAS]/$SERVER_ALIAS/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
fi

# PERSONALIZE HTTPS-VHOST
if is_truely ${INCOMING_SSL_ENABLED}; then

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
else
    sed -i "s/\[TARGET_IP]/${TARGET_IP}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i "s/\[TARGET_PORT]/${TARGET_PORT}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

    echo "HTTP-VHost personalization: OK";

    if is_truely ${WITH_MAINTENANCE}; then
        sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
        sed -i "s/\[APACHE_MAINTENANCE_PATH]/${APACHE_MAINTENANCE_PATH_ESCAPED}/" ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
        sed -i "s/\[SERVER_NAME]/${SERVER_NAME}/" ${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}

        echo "HTTP-VHost maintenance personalization: OK";

        cp ${APACHE_VHOST_PATH}/${VHOST_FILENAME} ${APACHE_VHOST_PATH}/${VHOST_RUNNING_FILENAME}
    fi
fi

# add extra config if behind another reverse proxy / load balancer
if is_truely ${INCLUDE_TRUSTED_DOCKER_PROXIES}; then
    INSERTION="\n    RemoteIPHeader X-Real-Client-IP"
    INSERTION+="\n    RemoteIPInternalProxyList ${APACHE_TRUSTED_DOCKER_PROXIES}"

    if ! is_empty ${REVERSE_PROXY_ADDRESS} && ! is_falsly ${REVERSE_PROXY_ADDRESS}; then
        INSERTION+="\n    RemoteIPInternalProxy ${REVERSE_PROXY_ADDRESS}"
    fi

    # update http config
    sed -i -E "s/(RequestHeader set X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

    # update https config (if incoming ssl enabled)
    if is_truely ${INCOMING_SSL_ENABLED}; then
        sed -i -E "s/(RequestHeader setifempty X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
        sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    fi

    # update maintainence config
    if is_truely ${WITH_MAINTENANCE}; then
        if is_truely ${INCOMING_SSL_ENABLED}; then
            sed -i -E "s/(DocumentRoot.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
            sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
        else
            sed -i -E "s/(DocumentRoot.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
            sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
        fi
    fi
elif ! is_falsly ${REVERSE_PROXY_ADDRESS} && ! is_empty ${REVERSE_PROXY_ADDRESS}; then
    INSERTION="\n    RemoteIPHeader X-Real-Client-IP"
    INSERTION+="\n    RemoteIPInternalProxy ${REVERSE_PROXY_ADDRESS}"

    # update http config
    sed -i -E "s/(RequestHeader set X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}

    # update https config (if incoming ssl enabled)
    if is_truely ${INCOMING_SSL_ENABLED}; then
        sed -i -E "s/(RequestHeader setifempty X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
        sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
    fi

    # update maintainence config
    if is_truely ${WITH_MAINTENANCE}; then
        if is_truely ${INCOMING_SSL_ENABLED}; then
            sed -i -E "s/(DocumentRoot.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
            sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_SSL_MAINTENANCE_FILENAME}
        else
            sed -i -E "s/(DocumentRoot.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
            sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_MAINTENANCE_FILENAME}
        fi
    fi
fi


# add extra config if using websockets
if is_truely ${REWRITE_WEBSOCKET_REQUESTS}; then
    INSERTION="\n\n    # Rewrite websocket requests"
    INSERTION+="\n    RewriteEngine on"
    INSERTION+="\n    RewriteCond %{HTTP:Upgrade} websocket [NC]"
    INSERTION+="\n    RewriteCond %{HTTP:Connection} upgrade [NC]"
    INSERTION+="\n    RewriteRule .* \"wss:\/\/${TARGET_IP}:${TARGET_PORT}%{REQUEST_URI}\" [P]"

    sed -i -E "s/(RequestHeader set X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_SSL_FILENAME}
fi

a2ensite ${VHOST_FILENAME} > /dev/null 2>&1

if is_truely ${INCOMING_SSL_ENABLED}; then
    a2ensite ${VHOST_SSL_FILENAME} > /dev/null 2>&1
fi

/etc/init.d/apache2 force-reload > /dev/null

if [ $? != 0 ]; then
    echo "vhost '${SERVER_NAME}' initialization failed!"
    exit 1
fi

echo "vhost '${SERVER_NAME}' initialized & enabled!"

if is_truely ${WITH_MAINTENANCE}; then
    echo "Do not forget to adopt the html of your maintenance page in ${APACHE_MAINTENANCE_PATH}/${HTML_MAINTENANCE_FILENAME}";
fi
