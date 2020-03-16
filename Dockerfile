FROM debian:stretch-slim

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y apache2 rsync cron ssl-cert-check curl iproute2 unzip && \
    apt-get clean

RUN echo "deb http://ftp.debian.org/debian stretch-backports main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y python-certbot-apache -t stretch-backports && \
    apt-get clean

RUN cd /tmp && \
    curl -LJO https://github.com/certbot/certbot/archive/v0.36.0.zip && \
    unzip -q certbot-0.36.0.zip && \
    cp /tmp/certbot-0.36.0/certbot-apache/certbot_apache/options-ssl-apache.conf /etc/letsencrypt/options-ssl-apache.conf && \
    rm -rf /tmp/certbot-0.36.0

ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2

RUN mkdir /var/www/html/balancer-manager
RUN mkdir /etc/apache2/maintenance-pages

RUN echo 'AuthType Basic'                   > /var/www/html/balancer-manager/.htaccess && \
    echo 'AuthName "Members Only"'          >> /var/www/html/balancer-manager/.htaccess && \
    echo 'AuthUserFile /var/.htpasswd'      >> /var/www/html/balancer-manager/.htaccess && \
    echo '<limit GET PUT POST>'             >> /var/www/html/balancer-manager/.htaccess && \
    echo 'require valid-user'               >> /var/www/html/balancer-manager/.htaccess && \
    echo '</limit>'                         >> /var/www/html/balancer-manager/.htaccess

RUN rm -rf /etc/apache2/sites-available/* && \
    mkdir -p /tmp/crontab

COPY sites-available/* /etc/apache2/sites-available/
COPY sites-template/* /etc/apache2/sites-template/
COPY conf-available/* /etc/apache2/conf-available/
COPY conf-loadbalancer /etc/apache2/conf-loadbalancer/
COPY script/* /usr/local/bin/
COPY maintenance-pages/* /etc/apache2/maintenance-pages/
COPY cron/* /tmp/crontab/

RUN mkdir -p /var/log/letsencrypt && \
    crontab /tmp/crontab/letsencrypt

RUN rm -f /etc/apache2/conf-available/proxy.conf && \
    cp /etc/apache2/conf-available/proxy.conf.dist /etc/apache2/conf-available/proxy.conf

RUN a2enmod proxy proxy_balancer proxy_http proxy_wstunnel status lbmethod_byrequests rewrite headers remoteip ssl && \
    a2enconf proxy proxy-balancer-manager

RUN cp -r /etc/apache2 /tmp/apache2 && \
    cp -r /etc/letsencrypt /tmp/letsencrypt

ENV TIME_ZONE=Europe/Berlin
RUN ln -snf /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime && echo ${TIME_ZONE} > /etc/timezone



COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
