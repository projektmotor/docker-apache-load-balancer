# APACHE2 Load Balancer

## Use Cases

* as reverse proxy to serve multiple (docker-) web apps on a single host
* as load balancer between multiple worker nodes
* as a combination of the first two things

## How to use

### Getting started

* create a local load balancer config file ```/path/loadbalancer.conf```
    ```bash
    [acme-app]                  # starts config part (name has no further meaning)
    uri=acme.de                 # the url your app should be available under
    cluster=acme-cluster        # name of load balancer cluster for acme-app
    nodes=[web1:80,web2:80]              # comma separated list of worker nodes (HOST|IP:PORT)
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
    * **NOTICE**: apache config has to be reloaded
    
    
#### Reverseproxy Build-In Scripts

* add new VHOST (```apache-init-reverseproxy-vhost```)
    ```bash
    $ docker exec -it acme-load-balancer-container apache-init-reverseproxy-vhost.sh
    ```
    * this is a interactive command, all required parameters (domain, target ip, target port) will be 
    requested interactively
    * optional: including SSL certificate creation

oMo
