FROM debian:stretch-slim

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y apache2 python-certbot-apache rsync && \
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

COPY sites-available/* /etc/apache2/sites-available/
COPY conf-available/* /etc/apache2/conf-available/
COPY conf-loadbalancer /etc/apache2/conf-loadbalancer/
COPY script/* /usr/local/bin/

RUN find /etc/apache2/sites-available/ -type f -not -name '000-default.conf' -not -name 'default-ssl.conf' -not -name 'vhost.conf.dist' -delete && \
    rm -f /etc/apache2/conf-available/proxy.conf && \
    cp /etc/apache2/conf-available/proxy.conf.dist /etc/apache2/conf-available/proxy.conf

RUN a2enmod proxy proxy_balancer proxy_http status lbmethod_byrequests rewrite headers && \
    a2enconf proxy proxy-balancer-manager

RUN mkdir /tmp/apache2 && \
    cp -r /etc/apache2/* /tmp/apache2 && \
    mkdir /tmp/letsencrypt && \
    cp -r /etc/letsencrypt/* /tmp/letsencrypt && \

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]