#!/bin/bash

APACHE_VHOST_PATH=/etc/apache2/sites-available/

usage() { echo "Usage: $0 [-a SERVER_ALIASES] SERVER_NAME CLUSTER_NAME USE_SSL" 1>&2; exit 1; }

while getopts a opt
do
   case $opt in
       a) SERVER_ALIAS=${OPTARG};;
       *) usage ;;
   esac
done

SERVER_NAME=$1
SERVER_SSL=$2
CLUSTER_NAME=$3
NODE_SSL=$4
VHOST_NAME=${SERVER_NAME/\./-}
VHOST_FILENAME="$VHOST_NAME.conf"

if [ -z "${SERVER_NAME}" ] || [ -z "${CLUSTER_NAME}" ]; then
    usage
fi

VHOST_COUNT=`ls -1 ${APACHE_VHOST_PATH} | grep "${VHOST_FILENAME}" | wc -l`

if [ ${VHOST_COUNT} -gt 0 ]; then
    echo "vhost '${VHOST_NAME}' already exists ... skipping"
    exit
fi

if [ -n $SERVER_SSL ] && [ "$SERVER_SSL" == "true" ]; then

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

    if [ -n $NODE_SSL ] && [ "$NODE_SSL" == "true" ]; then
        cp "$APACHE_VHOST_PATH/cluster-vhost.ssl.node-ssl.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    else
        cp "$APACHE_VHOST_PATH/cluster-vhost.ssl.node-no-ssl.conf" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    fi

    sed -i "s/SSLCertificateKeyFile.*/SSLCertificateKeyFile \/etc\/ssl_ca\/keys\/${SERVER_NAME}.key/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
    sed -i "s/SSLCertificateFile.*/SSLCertificateFile \/etc\/ssl_ca\/certs\/${SERVER_NAME}.crt/" ${APACHE_VHOST_PATH}/${VHOST_FILENAME}
else
    if [ -n $NODE_SSL ] && [ "$NODE_SSL" == "true" ]; then
        cp "$APACHE_VHOST_PATH/cluster-vhost.no-ssl.node-ssl.conf.dist" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    else
        cp "$APACHE_VHOST_PATH/cluster-vhost.no-ssl.node-no-ssl.conf" "$APACHE_VHOST_PATH/$VHOST_FILENAME"
    fi
fi

sed -i "s/\(ServerName\s*\)\(.*\)/\1$SERVER_NAME/" $APACHE_VHOST_PATH/$VHOST_FILENAME
sed -i "s/\(balancer:\/\/\)\[\(.*\)\]\//\1$CLUSTER_NAME\//" $APACHE_VHOST_PATH/$VHOST_FILENAME

if [ -z "${SERVER_ALIAS}" ]; then
    sed -i '/ServerAlias/d' $APACHE_VHOST_PATH/$VHOST_FILENAME
else
    sed -i "s/\(ServerAlias\s*\)\(.*\)/\1$SERVER_ALIAS /" $APACHE_VHOST_PATH/$VHOST_FILENAME
fi

a2ensite ${VHOST_FILENAME} # 2>&1 > /dev/null

echo "vhost '${VHOST_NAME}' initialized & enabled!"