# APACHE2 Load Balancer

[![Build Status](https://travis-ci.org/projektmotor/docker-apache-load-balancer.svg?branch=master)](https://travis-ci.org/projektmotor/docker-apache-load-balancer) 

## Use Cases

* as reverse proxy to serve multiple (docker-) web apps on a single host
* as load balancer between multiple worker nodes
* as a combination of the first two things

What else:

* using as reverse-proxy / load balancer in a development env, including local https with local CA

## Table of Content

1. [General Usage](#1-general-usage)
    * [Self-Signed Certificates with local CA Usage](#self-signed-certificateswwith-local-ca)
    * [Persistence](#persistence)
    * [Logging](#logging)
2. [Load Balancer Mode](#2-load-balancer-mode)
    * [Load Balancer with Self-Signed Certificate](#load-balancer-with-self-signed-certificate)
3. [Reverse Proxy Mode](#3-reverse-proxy-mode)
    * [Reverse Proxy with Self-Signed Certificate](#reverse-proxy-with-self-signed-certificate)
4. [Build-In Scripts](#4-build-in-scripts)
    * [Loadbalancer Build-In Scripts](#loadbalancer-build-in-scripts)
    * [Reverseproxy Build-In Scripts](#reverseproxy-build-in-scripts)
5. [Examples with docker-compose](#5-examples-with-docker-compose)
    * [Run with docker-compose as a local dev-server](#run-with-docker-compose-as-a-local-dev-server)

## 1. General Usage

### Self-Signed Certificates with local CA

Certification warnings suck! To change this (for your self-signed certificate), 
you should be your own local CA. All you need is a root-key (**myCA.key**) & 
root-certificate (**myCA.pem**). These two things should be placed on your **docker 
host and mounted to any docker container which uses self-signed certificates**. 
Additionally the root-certificate must be added as CA on all devices (browsers) 
which execute requests against your ssl-host(s). 

* create you private key:
```bash
$ openssl genrsa -out myCA.key 2048
```
* create your root-certificate
```bash
$ openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem
```

At the beginning of the command, the script asks for some certificate informations:

```bash
Country Name (2 letter code) [AU]:DE
State or Province Name (full name) [Some-State]:Saxony
Locality Name (eg, city) []:Leipzig
Organization Name (eg, company) [Internet Widgits Pty Ltd]:ProjektMOTOR GmbH
Organizational Unit Name (eg, section) []:
Common Name (e.g. server FQDN or YOUR name) []:
Email Address []:noreply@projektmotor.de
```

Congrats, now you are your own CA! :] Stop... you are your own CA, but nobody knows about it! :/
To change this, you should add the earlier generated certificate as CA to your browser.

* Chrome:
 * Settings > Manage certificates > Authorities > IMPORT
 * select you certificate file (myCA.pem)
 * select signing targets (e.g. websites)
 * double check the list of authorities if the certificate is imported as new authority

### Persistence

* mount a single path (i.e. vhost path)
    ```bash
    $ docker run -it --rm \
          -v /path/loadbalancer/conf/:/etc/apache2/conf-loadbalancer \
          -v /path/sites-available/:/etc/apache2/sites-available \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```
* mount a whole apache-config path
    ```bash
    $ docker run -it --rm \
          -v /path/apache2/:/etc/apache2 \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```

### Logging

In general it is a good idea to mount a host-folder to ```/var/log/apache2```. This makes your apache log-files persistent
and log debugging from the outside of the docker container quite easy. 

```bash
$ docker run -it --rm \
      -v .../logs/:/var/log/apache2 \
      --name acme-load-balancer-container \
      projektmotor/apache-load-balancer:latest
```

## 2. Load Balancer Mode

* create a local load balancer config file ```.../conf-loadbalancer/loadbalancer.conf```
    ```bash
    [acme-app]                            # starts config part (name has no further meaning)
    cluster=acme-cluster                  # name of load balancer cluster for acme-app
    uri=acme.de                           # the url your app should be available under
    ssl=true                              # use SSL for incoming connections
    ssl_self_signed=false                 # if true: use self signed certificate, if false: use letsencrypt
    reverse_proxy_address=0.0.0.0         # if behind reverse proxy OR another load balancer, set its ip here (otherwise REMOTE_ADDR & client ip logging doesn't work)
    nodes=[web1:443;web2:443;web3:443]    # comma separated list of worker nodes (HOST|IP:PORT)
    node_ssl=true                         # use ssl-connection for nodes
    ```
* run docker image
    ```bash
    $ docker run -it --rm \
          -v .../conf-loadbalancer/loadbalancer.conf/:/etc/apache2/conf-loadbalancer \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```
* vhost & proxy config is auto-generated inside the container during startup
    * **NOTICE**: if you change the ```loadbalancer.conf``` of a running container, you could regenerate the vhost- & proxy-config by running:
    ```bash
    $ apache-reload-cluster-conf.sh
    ```
* go to your browser & type https://acme.de

### Load Balancer with Self-Signed Certificate

* set ```ssl_self_signed=true``` in ```.../conf-loadbalancer/loadbalancer.conf```
* mount the root-certificate, root-key & and a folder to persist the certificates
    ```bash
    $ docker run -it --rm \
          -v .../conf-loadbalancer/loadbalancer.conf/:/etc/apache2/conf-loadbalancer \
          -v .../ssl_ca/:/etc/ssl_ca \
          -v .../myCA.key:/etc/myCA.key \
          -v .../myCA.pem:/etc/myCA.pem \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```

## 3. Reverse Proxy Mode

* run docker image
    ```bash
    $ docker run -it --rm \
          -v .../apache2/:/etc/apache2 \
          -v .../letsencrypt/:/etc/letsencrypt \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```
* add new vhost with build-in script: ```apache-init-reverseproxy-vhost.sh```
    ```bash
    $ docker exec -it acme-load-balancer-container apache-init-reverseproxy-vhost.sh
    ```
* the script asks for all necessary informations and creates the new vhost for you 

### Reverse Proxy with Self-Signed Certificate

* mount the root-certificate, root-key & and a folder to persist the certificates
    ```bash
    $ docker run -it --rm \
          -v .../apache2/:/etc/apache2 \
          -v .../ssl_ca/:/etc/ssl_ca \
          -v .../myCA.key:/etc/myCA.key \
          -v .../myCA.pem:/etc/myCA.pem \
          --name acme-load-balancer-container \
          projektmotor/apache-load-balancer:latest
    ```
* during execution of the build-in script ```apache-init-reverseproxy-vhost.sh``` type
    ```
    $ docker exec -it acme-load-balancer-container apache-init-reverseproxy-vhost.sh
    ...
    'Use self-signed certificate for incoming connections - from browser (only used when SSL for incoming connections is enabled; when N is used then certbot certificate is generated; shortcut: e) [y|N]: Y
    ...
    ```

## 4. Build-In Scripts

* reload apache config (```apache-reload.sh```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-reload.sh
  ```

### Loadbalancer Build-In Scripts

* add new VHOST (```apache-init-cluster-vhost```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-init-cluster-vhost.sh HOST-URI CLUSTER-NAME
    ```
    * HOST-URI: the url your app should be available under 
    * CLUSTER-NAME: a name of load balancer cluster for your app (free choice, but needed for cluster & node conf)
    * **NOTICE**: apache config has to be reloaded

* create new cluster (```apache-init-cluster.sh```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-init-cluster.sh CLUSTER-NAME
    ```
    * CLUSTER-NAME: the cluster name of your app (set in your vhost)

* add new worker node to existing cluster (```apache-add-cluster-node.sh```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-add-cluster-node.sh CLUSTER-NAME NODE
    ```
    * CLUSTER-NAME: the cluster name of your app (set in your vhost & cluster config)
    * NODE: a node config of format URI|IP[:PORT]
    * USE_SSL: use ssl for node-connection (https)
    * **NOTICE**: apache config has to be reloaded
    
    
### Reverseproxy Build-In Scripts

* add new VHOST (```apache-init-reverseproxy-vhost```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-init-reverseproxy-vhost.sh
    ```
    * this is an interactive and non-interactive command
        * all required parameters (domain, target ip, target port) will be 
          requested interactively
        * parameters can also be passed
          ```bash
          $ docker exec -it acme-load-balancer-container apache-init-reverseproxy-vhost.sh -d acme.de -i 157.138.29.201 -p 9600 -a n -m Y -s Y -l Y
          ```
    * optional: including SSL certificate creation
    * optional: use maintenance page

## 5. Examples with docker-compose

### Run with docker-compose as a local dev-server
* create config file ```/var/apps/reverse-proxy/docker-compose.yml``` 
    ```
    version: "3"
    services:
    
      loadbalancer:
        image: projektmotor/apache-load-balancer
        ports:
          - 80:80
          - 443:443
        volumes:
          - /var/apps/reverse-proxy/apache2/:/etc/apache2
          - /var/apps/reverse-proxy/letsencrypt/:/etc/letsencrypt
          - /var/apps/reverse-proxy/ssl_ca/:/etc/ssl_ca
          - /var/apps/reverse-proxy/myCA.key:/etc/myCA.key
          - /var/apps/reverse-proxy/myCA.pem:/etc/myCA.pem
        restart: always
        extra_hosts:
          - "dockerhost:$DOCKERHOST"
    ```
* create an executable file ```/var/apps/reverse-proxy/docker-start.sh``` as start script
    ```bash
    #!/bin/sh
    set -e
    
    export DOCKERHOST=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
    docker-compose -f docker-compose.yml up -d
    ```
    This one ensures that the env var ```DOCKERHOST``` always got your host ip which you can use in your reverse proxy vhost config.
* add vhosts to your local reverse proxy:
    * add in /etc/hosts
        ```
        127.0.0.1	acme
        127.0.0.1	acme-webpack
        127.0.0.1	acme-storybook
        ```
    * simple https secured project
        ```bash
        $ docker-compose exec loadbalancer apache-init-reverseproxy-vhost.sh -d acme -i dockerhost -p 9700 -a n -m n -s y -e y -l y -r n -w n -q y
        ```
    * webpack-dev-server with https
        ```bash
        $ docker-compose exec loadbalancer apache-init-reverseproxy-vhost.sh -d acme -i dockerhost -p 9704 -a n -m n -s y -e y -l y -r n -w y -q y
        ```
    * storybook with https
        ```bash
        $ docker-compose exec loadbalancer apache-init-reverseproxy-vhost.sh -d acme -i dockerhost -p 9705 -a n -m n -s y -e y -l n -r n -q y -w n
        ```
* Now you can start storybook and webpack-dev-server in your development container:  
    ```
    $ yarn start-storybook --config-dir storybook/ --port 9705
    ```   
    ```
    $ yarn encore dev-server --https --host 0.0.0.0 --port 9704 --disable-host-check  --public acme-webpack
    ```
    Ensure that ports 9700, 9704 and 9705 a forwarded in your development container. 
