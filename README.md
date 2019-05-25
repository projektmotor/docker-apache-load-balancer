# APACHE2 Load Balancer

[![Build Status](https://travis-ci.org/projektmotor/docker-apache-load-balancer.svg?branch=master)](https://travis-ci.org/projektmotor/docker-apache-load-balancer) 

## Use Cases

* as reverse proxy to serve multiple (docker-) web apps on a single host
* as load balancer between multiple worker nodes
* as a combination of the first two things

What else:

* using as reverse-proxy / load balancer in a development env, including local https with local CA

## How to use

### Getting started

* create a local load balancer config file ```/path/loadbalancer.conf```
    ```bash
    [acme-app]                  # starts config part (name has no further meaning)
    uri=acme.de                 # the url your app should be available under
    cluster=acme-cluster        # name of load balancer cluster for acme-app
    nodes=[web1:443,web2:443]              # comma separated list of worker nodes (HOST|IP:PORT)
    node_ssl=true              # use ssl-connection for nodes
    ```
* build image
    ```bash
    $ docker build -t acme-load-balancer -v /path/loadbalancer/conf/:/etc/apache2/conf-loadbalancer .
    ```
* run the image
    ```bash
    $ docker run -it --rm --name acme-load-balancer-container acme-load-balancer
    ```

### Persistence

* use a volume to achieve persistence of your apache config
    * mount a single path (i.e. vhost path)
        ```bash
        $ docker build \
              -t acme-load-balancer \
              -v /path/loadbalancer/conf/:/etc/apache2/conf-loadbalancer \
              -v /path/sites-available/:/etc/apache2/sites-available \
              .
        ```
    * mount a whole apache-config path
        ```bash
        $ docker build \
              -t acme-load-balancer \
              -v /path/apache2/:/etc/apache2 \
              .
        ```

### Self-Signed SSL with local CA

#### Prepare Docker Host

To be you own local CA a root-key & root-certificate is needed. These two things should
be placed on your docker host. Additionally the root-certificate must be added as CA on
all devices (browsers) which execute requests against your ssl-host(s). 

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

Congrats, you are your own CA! :] Stop... you are your own CA, but nobody knows about it! :/
To change this, you should add the earlier generated certificate as CA to your browser.

* Chrome:
    * Settings > Manage certificates > Authorities > IMPORT
    * select you certificate file (myCA.pem)
    * select signing targets (e.g. websites)
    * double check the list of authorities if the certificate is imported as new authority

#### Create VHost with certificate signed by the local CA

What you should do now, differs from your use case.

##### Load Balancer which is configured by "loadbalancer.conf"

Dude, this one is truly simple. Just change the ssl-parameter from ```false``` to ```true```

```bash
[acme-devel]
uri=acme.devel
ssl=true                            # ssl for your load balancer vhost
cluster=acme-devel-cluster
nodes=[web1:80;web2:80;web3:80]
node_ssl=true                       # ssl for node-connections 
```

##### Revers Proxy which is created by the build-in script

Using a self-signed certificate in reverse proxy env is not yet done. There are no 
impediments, its just a matter of time ;]

### Build-In Scripts

* reload apache config (```apache-reload.sh```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-reload.sh
  ```

#### Loadbalancer Build-In Scripts

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
    
    
#### Reverseproxy Build-In Scripts

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
