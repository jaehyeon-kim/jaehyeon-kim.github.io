---
title: API Development with R Part II
date: 2017-11-19
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - API development with R
categories:
  - Serverless
tags: 
  - R
  - Rserve
  - rApache
  - Plumber
authors:
  - JaehyeonKim
images: []
---
In [Part I](/blog/2017-11-18-api-development-with-r-1), it is discussed how to serve an R function with _plumber_, _Rserve_ and _rApache_. In this post, the APIs are deployed in a Docker container and, after showing example requests, their performance is compared. The [rocker/r-ver:3.4](https://hub.docker.com/r/rocker/r-ver/) is used as the base image and each of the APIs is added to it. For simplicity, the APIs are served by [Supervisor](http://supervisord.org/). For performance testing, [Locust](https://locust.io/) is used. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/r-api-demo).

## Deployment

As can be seen in the [Dockerfile](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/Dockerfile) below, _plumber_, _Rserve_ and _rApache_ are installed in order. _Plumber_ is an R package so that it can be installed by `install.packages()`. The latest versions of _Rserve_ and _rApache_ are built after installing their dependencies. Note, for _rApache_, the _Rook_ package is installed as well because the test function is served as a Rook application.

Then the source files are copied to `/home/docker/<api-name>`. _rApache_ requires extra configuration. First the Rook app ([rapache-app.R](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rapache/rapache-app.R)) and site configuration file ([rapache-site.conf](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rapache/rapache-site.conf)) are *symlink*ed to the necessary paths and the site is enabled.

Finaly _Suervisor_ is started with the [config file](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/api-supervisor.conf) that monitors/manages the APIs.

```docker
FROM rocker/r-ver:3.4
MAINTAINER Jaehyeon Kim <dottami@gmail.com>

RUN apt-get update && apt-get install -y wget supervisor

## Plumber
RUN R -e 'install.packages(c("plumber", "jsonlite"))'

## Rserve
RUN apt-get install -y libssl-dev
RUN wget http://www.rforge.net/Rserve/snapshot/Rserve_1.8-5.tar.gz \
    && R CMD INSTALL Rserve_1.8-5.tar.gz

## rApache
RUN apt-get install -y \
    libpcre3-dev liblzma-dev libbz2-dev libzip-dev libicu-dev
RUN apt-get install -y apache2 apache2-dev
RUN wget https://github.com/jeffreyhorner/rapache/archive/v1.2.8.tar.gz \
    && tar xvf v1.2.8.tar.gz \
    && cd rapache-1.2.8 && ./configure && make && make install

RUN R -e 'install.packages(c("Rook", "rjson"))'

RUN echo '/usr/local/lib/R/lib/' >> /etc/ld.so.conf.d/libR.conf \
    && ldconfig

## copy sources to /home/docker
RUN useradd docker && mkdir /home/docker \
	&& chown docker:docker /home/docker

RUN mkdir /home/docker/plumber /home/docker/rserve /home/docker/rapache
COPY ./src/plumber /home/docker/plumber/
COPY ./src/rserve /home/docker/rserve/
COPY ./src/rapache /home/docker/rapache/
COPY ./src/api-supervisor.conf /home/docker/api-supervisor.conf
RUN chmod -R 755 /home/docker

RUN ln -s /home/docker/rapache/rapache-site.conf \
    /etc/apache2/sites-available/rapache-site.conf \
    && ln -s /home/docker/rapache/rapache-app.R /var/www/rapache-app.R

## config rApache
RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf \
    && /bin/bash -c "source /etc/apache2/envvars" && mkdir -p /var/run/apache2 \
    && a2ensite rapache-site

CMD ["/usr/bin/supervisord", "-c", "/home/docker/api-supervisor.conf"]
```

### Plumber

As can be seen in [api-supervisor.conf](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/api-supervisor.conf), the _plumber_ API can be started at _port 9000_ as following. ([plumber-src.R](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/plumber/plumber-src.R) and [plumber-serve.R](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/plumber/plumber-serve.R) are discussed in [Part I](/blog/2017-11-18-API-Development-with-R-Part-I))

```bash
/usr/local/bin/Rscript /home/docker/plumber/plumber-serve.R
```

### Rserve

In order to utilize the built-in HTTP server of _Rserve_, `http.port` should be specified in [rserve.conf](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rserve/rserve.conf). Also it is necessary to set `daemon disable` to manage _Rserve_ by _Supervisor_.

```bash
http.port 8000
remote disable
auth disable
daemon disable
control disable
```

Then it is possible to start the _Rserve_ API at _port 8000_ as shown below. ([rserve-src.R](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rserve/rserve-src.R) is discussed in [Part I](/blog/2017-11-18-API-Development-with-R-Part-I).)

```bash
/usr/local/bin/R CMD Rserve --slave --RS-conf /home/docker/rserve/rserve.conf \
  --RS-source /home/docker/rserve/rserve-src.R
```

### rApache

The [site config file](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rapache/rapache-site.conf) of the _rApache_ API is shown below.

```bash
LoadModule R_module /usr/lib/apache2/modules/mod_R.so
<Location /test>
    SetHandler r-handler
    RFileEval /var/www/rapache-app.R:Rook::Server$call(test)
</Location>
```

It is possible to start the _rApache_ API at _port 80_ as following. ([rapache-app.R](https://github.com/jaehyeon-kim/r-api-demo/blob/master/api/src/rapache/rapache-app.R) is discussed in [Part I](/blog/2017-11-18-API-Development-with-R-Part-I).)

```bash
apache2ctl -DFOREGROUND
```

This Docker container can be built and run as following. Note the container's port 80 is mapped to the host's port 7000 to prevent a possible conflict.

```bash
## build
docker build -t=api ./api/.

## run
# rApache - 7000, Rserve - 8000, plumber - 9000
# all APIs managed by supervisor
docker run -d -p 7000:80 -p 8000:8000 -p 9000:9000 --name api api:latest
```

## Example Request

Example requests to the APIs and their responses are shown below. When a request includes both _n_ and _wait_ parameters, the APIs return 200 response as expected. Only the _Rserve_ API properly shows 400 response and the others need some modification.

```r
library(httr)
plumber200 <- POST(url = 'http://localhost:9000/test', encode = 'json',
                   body = list(n = 10, wait = 0.5))
unlist(c(api = 'plumber', status = status_code(plumber200),
         content = content(plumber200)))
```

```bash
##           api        status content.value 
##     "plumber"         "200"          "10"
```

```r
rapache200 <- POST(url = 'http://localhost:7000/test', encode = 'json',
                   body = list(n = 10, wait = 0.5))
unlist(c(api = 'rapache', status = status_code(rapache200),
         content = content(rapache200)))
```

```r
##           api        status content.value 
##     "rapache"         "200"          "10"
```

```r
rserve200 <- POST(url = 'http://localhost:8000/test', encode = 'json',
                  body = list(n = 10, wait = 0.5))
unlist(c(api = 'rserve', status = status_code(rserve200),
         content = content(rserve200)))
```

```r
##           api        status content.value 
##      "rserve"         "200"          "10"
```

```r
rserve400 <- POST(url = 'http://localhost:8000/test', encode = 'json',
                  body = list(wait = 0.5))
unlist(c(api = 'rserve', status = status_code(rserve400),
         content = content(rserve400)))
```

```r
##                     api                  status         content.message 
##                "rserve"                   "400" "Missing parameter - n"
```

## Performance Test

A way to examine performance of an API is to look into how effectively it can serve multiple concurrent requests. For this, [Locust](https://locust.io/), a Python based load testing tool, is used to simulate 1, 3 and 6 concurrent requests successively. 

The test [locust file](https://github.com/jaehyeon-kim/r-api-demo/blob/master/locustfile.py) is shown below.

```python
import json
from locust import HttpLocust, TaskSet, task

class TestTaskSet(TaskSet):

    @task
    def test(self):
        payload = {'n':10, 'wait': 0.5}
        headers = {'content-type': 'application/json'}
        self.client.post('/test', data=json.dumps(payload), headers=headers)
         
class MyLocust(HttpLocust):
    min_wait = 0
    max_wait = 0
    task_set = TestTaskSet
```

With this file, testing can be made as following (eg for 3 concurrent requests).

```bash
locust -f ./locustfile.py --host http://localhost:8000 --no-web -c 3 -r 3
```

When only 1 request is made successively, the average response time of the APIs is around 500ms. When there are multiple concurrent requests, however, the average response time of the _plumber_ API increases significantly. This is because R is single threaded and requests are _queued_ by _httpuv_. On the other hand, the average response time of the _Rserve_ API stays the same and this is because _Rserve_ handles concurrent requests by _forked_ processes. The performance of the _rApache_ API is in the middle. In practice, it is possible to boost the performance of the _rApache_ API by enabling [Prefork Multi-Processing Module](http://rapache.net/manual.html) although it will consume more memory.

![](response_time.png#center)

As expected, the _Rserve_ API handles considerably many requests per second. 

![](req_per_sec.png#center)

Note that the test function in this post is a bit unrealistic as it just waits before returning a value. In practice, R functions will consume more CPU and the average response time will tend to increase when multiple requests are made concurrently. Even in this case, the benefit of forking will persist.

This series investigate exposing R functions via an API. I hope you enjoy reading this series.
