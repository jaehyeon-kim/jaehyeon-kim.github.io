---
title: Cronicle Multi Server Setup
date: 2019-07-19
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Engineering
tags: 
  - Cronicle
  - Docker
  - Nginx
authors:
  - JaehyeonKim
images: []
---

Accroding to the [project GitHub repository](https://github.com/jhuckaby/Cronicle), 

> Cronicle is a multi-server task scheduler and runner, with a web based front-end UI. It handles both scheduled, repeating and on-demand jobs, targeting any number of slave servers, with real-time stats and live log viewer.

By default, Cronicle is configured to launch a single master server - task scheduling is controlled by the master server. For high availability, it is important that another server takes the role of master when the existing master server fails.

In this post, multi-server configuration of Cronicle will be demonstrated with Docker and Nginx as load balancer. Specifically a single master and backup server will be set up and they will be served behind a load balancer - backup server is a slave server that can take the role of master when the master is not avaialble. 

The source of this post can be found [here](https://github.com/jaehyeon-kim/play-cronicle).

## Cronicle Docker Image

There isn't an official Docker image for Cronicle. I just installed it from _python:3.6_ image. The docker file can be found as following.

```docker
FROM python:3.6

ARG CRONICLE_VERSION=v0.8.28
ENV CRONICLE_VERSION=${CRONICLE_VERSION}

# Node
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get install -y nodejs \
    && curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update && apt-get install -y yarn

# Cronicle
RUN curl -s "https://raw.githubusercontent.com/jhuckaby/Cronicle/${CRONICLE_VERSION}/bin/install.js" | node \
    && cd /opt/cronicle \
    && npm install aws-sdk

EXPOSE 3012
EXPOSE 3014

ENTRYPOINT ["/docker-entrypoint.sh"]
```

As Cronicle is written in Node.js, it should be installed as well. _aws-sdk_ is not required strictly but it is added to test S3 integration later. Port 3012 is the default web port of Cronicle and 3014 is used for server auto-discovery via UDP broadcast - it may not be required.

_docker-entrypoint.sh_ is used to start a Cronicle server. For master, one more step is necessary, which is initializing the storage system. An environment variable (_IS_MASTER_) will be used to control storage initialization.

```sh
#!/bin/bash

set -e

if [ "$IS_MASTER" = "0" ]
then
  echo "Running SLAVE server"
else 
  echo "Running MASTER server"
  /opt/cronicle/bin/control.sh setup
fi

/opt/cronicle/bin/control.sh start

while true; 
do 
  sleep 30; 
  /opt/cronicle/bin/control.sh status
done
```

A custom docker image, *cronicle-base*, is built using as following.

```sh
docker build -t=cronicle-base .
```

## Load Balancer

Nginx is used as a load balancer. The [config file](https://github.com/jaehyeon-kim/play-cronicle/blob/master/loadbalancer/nginx.conf) can be found as following. It listens port 8080 and passes a request to _cronicle1:3012_ or _cronicle2:3012_.

```sh
events { worker_connections 1024; }
 
http {
    upstream cronicles {
        server cronicle1:3012;
        server cronicle2:3012;
    }
 
    server {
        listen 8080;
 
        location / {
            proxy_pass         http://cronicles;
            proxy_set_header   Host $host;
        }
    }
}
```

In order for Cronicle servers to be served behind the load balancer, the following changes are made (complete config file can be found [here](https://github.com/jaehyeon-kim/play-cronicle/blob/master/sample_conf/config.json)).

```json
{
	"base_app_url": "http://loadbalancer:8080",

    ...
	
	"web_direct_connect": true,

    ...	
}
```

First, [**base_app_url**](https://github.com/jhuckaby/Cronicle#base_app_url) should be changed to the load balancer URL instead of an individual server's URL. Secondly [**web_direct_connect**](https://github.com/jhuckaby/Cronicle#web_direct_connect) should be changed to _true_. According to the project repository,

> If you set this parameter (web_direct_connect) to true, then the Cronicle web application will connect directly to your individual Cronicle servers. This is more for multi-server configurations, especially when running behind a load balancer with multiple backup servers. The Web UI must always connect to the master server, so if you have multiple backup servers, it needs a direct connection.

## Launch Servers

Docke Compose is used to launch 2 Cronicle servers (master and backup) and a load balancer. The service _cronicle1_ is for the master while _cronicle2_ is for the backup server. Note that both servers should have the same configuration file (_config.json_). Also, as the backup server will take the role of master, it should have access to the same data - _./backend/cronicle/data_ is mapped to both the servers. (Cronicle supports S3 or Couchbase as well.)

```yaml
version: '3.2'

services:
  loadbalancer:
    container_name: loadbalancer
    hostname: loadbalancer
    image: nginx    
    volumes:
      - ./loadbalancer/nginx.conf:/etc/nginx/nginx.conf
    tty: true
    links:
      - cronicle1
    ports:
      - 8080:8080
  cronicle1:
    container_name: cronicle1
    hostname: cronicle1
    image: cronicle-base
    #restart: always
    volumes:
      - ./sample_conf/config.json:/opt/cronicle/conf/config.json
      - ./sample_conf/emails:/opt/cronicle/conf/emails
      - ./docker-entrypoint.sh:/docker-entrypoint.sh
      - ./backend/cronicle/data:/opt/cronicle/data
    entrypoint: /docker-entrypoint.sh
    environment:
      IS_MASTER: "1"
  cronicle2:
    container_name: cronicle2
    hostname: cronicle2
    image: cronicle-base
    #restart: always
    volumes:
      - ./sample_conf/config.json:/opt/cronicle/conf/config.json
      - ./sample_conf/emails:/opt/cronicle/conf/emails
      - ./docker-entrypoint.sh:/docker-entrypoint.sh
      - ./backend/cronicle/data:/opt/cronicle/data
    entrypoint: /docker-entrypoint.sh
    environment:
      IS_MASTER: "0"
```

It can be started as following.

```sh
docker-compose up -d
```

## Add Backup Server

Once started, Cronicle web app will be accessible at *http://localhost:8080* and it's possible to log in as the admin user - username and password are all _admin_.

In `Admin > Servers`, it's possible to see that the 2 Cronicle servers are shown. The master server is recognized as expected but the backup server (cronicle2) is not yet added.

![](add-server-01.png#center)

By default, 2 server groups (All Servers and Master Group) are created and the backup server should be added to the Master Group. To do so, the _Hostname Match_ regular expression is modified as following: `^(cronicle[1-2])$`. 

![](add-server-02.png#center)

Then it can be shown that the backup server is recognized correctly.

![](add-server-03.png#center)

## Create Event

A test event is created in order to show that an event that's created in the original master can be available in the backup server when it takes the role of master.

![](create-event-01.png#center)

Cronicle has a web UI so that it is easy to manage/monitor scheduled events. It also has management API that many jobs can be performed programmatically. Here an event that runs a simple shell script is created.

![](create-event-02.png#center)

![](create-event-03.png#center)

Once created, it is listed in `Schedule` tab.

![](create-event-04.png#center)

## Backup Becomes Master

As mentioned earlier, the backup server will take the role of master when the master becomes unavailable. In order to see this, I removed the master server as following.

```js
docker-compose rm -f cronicle1
```

After a while, it's possible to see that the backup server becomes master.

![](remove-master-01.png#center)

It can also be checked in `Admin > Activity Log`.

![](remove-master-02.png#center)

In `Schedule`, the test event can be found.

![](remove-master-03.png#center)
