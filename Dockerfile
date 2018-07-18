FROM debian:stretch-slim

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y apache2 rsync cron && \
    apt-get clean

RUN echo "deb http://ftp.debian.org/debian stretch-backports main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y python-certbot-apache -t stretch-backports && \
    apt-get clean

ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2

RUN mkdir /var/www/html/balancer-manager

RUN echo 'AuthType Basic'                   > /var/www/html/balancer-manager/.htaccess && \
    echo 'AuthName "Members Only"'          >> /var/www/html/balancer-manager/.htaccess && \
    echo 'AuthUserFile /var/.htpasswd'      >> /var/www/html/balancer-manager/.htaccess && \
    echo '<limit GET PUT POST>'             >> /var/www/html/balancer-manager/.htaccess && \
    echo 'require valid-user'               >> /var/www/html/balancer-manager/.htaccess && \
    echo '</limit>'                         >> /var/www/html/balancer-manager/.htaccess

RUN rm -rf /etc/apache2/sites-available/*

COPY sites-available/* /etc/apache2/sites-available/
COPY conf-available/* /etc/apache2/conf-available/
COPY conf-loadbalancer /etc/apache2/conf-loadbalancer/
COPY script/* /usr/local/bin/

RUN rm -f /etc/apache2/conf-available/proxy.conf && \
    cp /etc/apache2/conf-available/proxy.conf.dist /etc/apache2/conf-available/proxy.conf

RUN a2enmod proxy proxy_balancer proxy_http status lbmethod_byrequests rewrite headers ssl && \
    a2enconf proxy proxy-balancer-manager

RUN cp -r /etc/apache2 /tmp/apache2 && \
    cp -r /etc/letsencrypt /tmp/letsencrypt

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
