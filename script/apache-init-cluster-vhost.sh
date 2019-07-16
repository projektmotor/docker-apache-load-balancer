#!/bin/bash

APACHE_VHOST_PATH=/etc/apache2/sites-available/
APACHE_TEMPLATE_PATH=/etc/apache2/sites-template
CERTBOT_BIN=/usr/bin/certbot

usage() { echo "Usage: $0 [-a SERVER_ALIASES] SERVER_NAME CLUSTER_NAME INCOMING_SSL INCOMING_SSL_SELF_SIGNED OUTGOING_SSL INCLUDE_TRUSTED_DOCKER_PROXIES REVERSE_PROXY_ADDRESS" 1>&2; exit 1; }

while getopts a opt
do
   case $opt in
       a) SERVER_ALIAS=${OPTARG};;
       *) usage ;;
   esac
done

SERVER_NAME=$1
CLUSTER_NAME=$2
INCOMING_SSL=$3
INCOMING_SSL_SELF_SIGNED=$4
OUTGOING_SSL=$5
INCLUDE_TRUSTED_DOCKER_PROXIES=$6
REVERSE_PROXY_ADDRESS=$7
VHOST_NAME=${SERVER_NAME/\./-}
VHOST_FILENAME="$VHOST_NAME.conf"
VHOST_CERTBOT_FILENAME="${VHOST_NAME}_certbot.conf"
APACHE_TRUSTED_DOCKER_PROXIES=\\/etc\\/apache2\\/conf-available\\/trusted-docker-proxies.conf

if [ -z "${SERVER_NAME}" ] || [ -z "${CLUSTER_NAME}" ]; then
    usage
fi

VHOST_COUNT=`ls -1 ${APACHE_VHOST_PATH} | grep "${VHOST_FILENAME}" | wc -l`

if [ ${VHOST_COUNT} -gt 0 ]; then
    echo "vhost '${VHOST_NAME}' already exists ... skipping"
    exit
fi

if [ -n ${INCOMING_SSL} ] && [ "${INCOMING_SSL}" == "true" ]; then

    if [ -n ${INCOMING_SSL_SELF_SIGNED} ] && [ "${INCOMING_SSL_SELF_SIGNED}" == "true" ]; then
        ROOT_CERTIFICATE_FILE="/etc/myCA.pem"
        ROOT_CERTIFICATE_KEY="/etc/myCA.key"
        CERTIFICATION_BASE_PATH="/root/ssl-certification"

        if [ ! -f "${ROOT_CERTIFICATE_FILE}" ] || [ ! -f "${ROOT_CERTIFICATE_KEY}" ]; then
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

        if [ -n ${OUTGOING_SSL} ] && [ "${OUTGOING_SSL}" == "true" ]; then
            cp "${APACHE_TEMPLATE_PATH}/cluster-vhost.incoming_https.outgoing_https.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
        else
            cp "${APACHE_TEMPLATE_PATH}/cluster-vhost.incoming_https.outgoing_http.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
        fi

        sed -i "s/SSLCertificateKeyFile.*/SSLCertificateKeyFile \/etc\/ssl_ca\/keys\/${SERVER_NAME}.key/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
        sed -i "s/SSLCertificateFile.*/SSLCertificateFile \/etc\/ssl_ca\/certs\/${SERVER_NAME}.crt/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
        sed -i "s/SSLCertificateChainFile.*//" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    else
        # OBTAIN CERTIFICATE FOR DOMAIN USING CERTBOT (LETSENCRYPT) WITH WEBROOT-PLUGIN
        # see: https://certbot.eff.org/docs/using.html#webroot
        # notice: apache plugin requires apache restart, which ends up in container shutdown.
        #         webroot plugin does not execute the restart.
        mkdir -p /var/www/certbot-webroot
        cp "${APACHE_TEMPLATE_PATH}/certbot-vhost-webroot.conf.dist" "${APACHE_VHOST_PATH}/${VHOST_CERTBOT_FILENAME}"

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
else
    if [ -n ${OUTGOING_SSL} ] && [ "${OUTGOING_SSL}" == "true" ]; then
        cp "${APACHE_TEMPLATE_PATH}/cluster-vhost.incoming_http.outgoing_https.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    else
        cp "${APACHE_TEMPLATE_PATH}/cluster-vhost.incoming_http.outgoing_http.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    fi
fi

sed -i "s/\(ServerName\s*\)\(.*\)/\1$SERVER_NAME/" $APACHE_VHOST_PATH/$VHOST_FILENAME
sed -i "s/\(balancer:\/\/\)\[\(.*\)\]\//\1$CLUSTER_NAME\//" $APACHE_VHOST_PATH/$VHOST_FILENAME

if [ -z "${SERVER_ALIAS}" ]; then
    sed -i '/ServerAlias/d' $APACHE_VHOST_PATH/$VHOST_FILENAME
else
    sed -i "s/\(ServerAlias\s*\)\(.*\)/\1$SERVER_ALIAS /" $APACHE_VHOST_PATH/$VHOST_FILENAME
fi

if [ -n "${INCLUDE_TRUSTED_DOCKER_PROXIES}" ]; then
    INSERTION="\n    RemoteIPHeader X-Real-Client-IP"
    INSERTION+="\n    RemoteIPInternalProxyList ${APACHE_TRUSTED_DOCKER_PROXIES}"

    # update http config
    sed -i -E "s/(RequestHeader set X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
elif [ -n "${REVERSE_PROXY_ADDRESS}" ]; then
    INSERTION="\n    RemoteIPHeader X-Real-Client-IP"
    INSERTION+="\n    RemoteIPInternalProxy ${REVERSE_PROXY_ADDRESS}"

    # update http config
    sed -i -E "s/(RequestHeader set X-Real-Client-IP.*)/\1${INSERTION}/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i -E 's/(LogFormat.*)%h(.*)/\1%a\2/' ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
fi

a2ensite ${VHOST_FILENAME} # 2>&1 > /dev/null

echo "vhost '${VHOST_NAME}' initialized & enabled!"