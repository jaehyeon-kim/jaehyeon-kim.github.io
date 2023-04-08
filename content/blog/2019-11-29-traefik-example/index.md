---
title: Dynamic Routing and Centralized Auth with Traefik, Python and R Example
date: 2019-11-29
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
  - Traefik
  - FastAPI
  - Rserve
  - R
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
---

[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) in [Kubernetes](https://kubernetes.io/) exposes HTTP and HTTPS routes from outside the cluster to services within the cluster. By setting rules, it routes requests to appropriate services (precisely requests are sent to individual [Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/) by [Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)). Rules can be set up dynamically and I find it's more efficient compared to traditional [reverse proxy](https://en.wikipedia.org/wiki/Reverse_proxy).

[Traefik](https://docs.traefik.io/v1.7/) is a modern HTTP reverse proxy and load balancer and it can be used as a _Kubernetes_ _Ingress Controller_. Moreover it supports other [providers](https://docs.traefik.io/providers/overview/), which are existing infrastructure components such as orchestrators, container engines, cloud providers, or key-value stores. To name a few, Docker, Kubernetes, AWS ECS, AWS DynamoDB and Consul are [supported providers](https://docs.traefik.io/v1.7/). With _Traefik_, it is possible to configure routing dynamically. Another interesting feature is [Forward Authentication](https://docs.traefik.io/v1.7/configuration/entrypoints/#forward-authentication) where authentication can be handled by an external service. In this post, it'll be demonstrated how _path-based_ routing can be set up by _Traefik with Docker_. Also a centralized authentication will be illustrated with the _Forward Authentication_ feature of _Traefik_.

## How Traefik works

Below shows an illustration of [internal architecture](https://docs.traefik.io/v1.7/basics/) of Traefik.


![](traefik-overview.png#center)


The [Traefik website](https://docs.traefik.io/v1.7/basics/) explains workflow of requests as following.

> * Incoming requests end on [entrypoints](https://docs.traefik.io/v1.7/basics/#entrypoints), as the name suggests, they are the network entry points into Traefik (listening port, SSL, traffic redirection...).
> * Traffic is then forwarded to a matching [frontend](https://docs.traefik.io/v1.7/basics/#frontends). A frontend defines routes from entrypoints to [backends](https://docs.traefik.io/v1.7/basics/#backends). Routes are created using requests fields (Host, Path, Headers...) and can match or not a request.
> * The frontend will then send the request to a backend. A backend can be composed by one or more [servers](https://docs.traefik.io/v1.7/basics/#servers), and by a load-balancing strategy.
> * Finally, the server will forward the request to the corresponding microservice in the private network.

In this example, a HTTP _entrypoint_ is setup on port 80. Requests through it are forwarded to 2 web services by the following _frontend_ rules.

* Host is `k8s-traefik.info` and path is `/pybackend`
* Host is `k8s-traefik.info` and path is `/rbackend`

As the paths of the rules suggest, requests to `/pybackend` are sent to a _backend_ service, created with [FastAPI](https://fastapi.tiangolo.com/features/). If the other rule is met, requests are sent to the [Rserve](https://www.rforge.net/Rserve/) _backend_ service. Note that only requests from authenticated users are fowarded to relevant _backends_ and it is configured in _frontend_ rules as well. Below shows how authentication is handled.


![](traefik-forward-auth.png#center)


## Traefik setup

Here is the traefik service defined in the compose file of this example - the full version can be found [here](https://github.com/jaehyeon-kim/k8s-traefik/blob/master/docker-compose.yaml).

```yaml
version: "3.7"
services:
  traefik:
    image: "traefik:v1.7.19"
    networks:
      - traefik-net
    command: >
      --docker
      --docker.domain=k8s-traefik.info
      --docker.exposedByDefault=false
      --docker.network=traefik-net
      --defaultentrypoints=http
      --entrypoints="Name:http Address::80"
      --api.dashboard
    ports:
      - 80:80
      - 8080:8080
    labels:
      - "traefik.frontend.rule=Host:k8s-traefik.info"
      - "traefik.port=8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
...
networks:
  traefik-net:
    name: traefik-network
```

In _commands_, the Docker provider is enabled (`--docker`) with a custom domain name (`k8s-traefik.info`). A dedicated network is created and it is used for this and the other services (`trafic-net`). A single HTTP _entrypoint_ is enabled as the default entrypoint. Finally monitoring dashboard is enabled (`--api.dashboard`). In _lables_, it is set to be served via the custom domain (hostname) - port 80 is for individual services while 8080 is for the monitoring UI.

It is necessary to have a custom hostname when setting up rules that include multiple hosts or enabling a HTTPS entrypoint. Although neither is discussed in this post, a custom domain (`k8s-traefik.info`), which is accessible only in local environment, is added - another post may come later. The location of _hosts_ file is

* Windows - `%WINDIR%\System32\drivers\etc\hosts` or `C:\Windows\System32\drivers\etc\hosts`
* Linux - `/etc/hosts`

And the following entry is added.

```bash
# using a virtual machine
<VM-IP-ADDRESS>    k8s-traefik.info
# or in the same machine
0.0.0.0            k8s-traefik.info
```

In order to show how routes are configured dynamically, only the Traefik service is started as following.

```bash
docker-compose up -d traefik
```

When visiting the monitoring UI via _http://k8s-traefik.info:8080/dashboard_, it's shown that no _frontend_ and _backend_ exists in the _docker_ provider tab.


![](traefik-providers-01.png#center)


## Services

The authentication service is just checking if there's an authorization header and the JWT value is _foobar_. If so, it returns 200 response so that requests can be forward to relevant backends. The source is shown below.

```python
import os
from typing import Dict, List
from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from starlette.requests import Request
from starlette.status import HTTP_401_UNAUTHORIZED

app = FastAPI(title="Forward Auth API", docs_url=None, redoc_url=None)

## authentication
class JWTBearer(HTTPBearer):
    def __init__(self, auto_error: bool = True):
        super().__init__(scheme_name="Novice JWT Bearer", auto_error=auto_error)

    async def __call__(self, request: Request) -> None:
        credentials: HTTPAuthorizationCredentials = await super().__call__(request)

        if credentials.credentials != "foobar":
            raise HTTPException(HTTP_401_UNAUTHORIZED, detail="Invalid Token")


## response models
class StatusResp(BaseModel):
    status: str


## service methods
@app.get("/auth", response_model=StatusResp, dependencies=[Depends(JWTBearer())])
async def forward_auth():
    return {"status": "ok"}
```

The service is defined in the compose file as following.

```yaml
...
  forward-auth:
    image: kapps/trafik-demo:pybackend
    networks:
      - traefik-net
    depends_on:
      - traefik
    command: >
      forward_auth:app
      --host=0.0.0.0
      --port=8000
      --reload
...
```

The Python service has 3 endpoints. The app's title and path value are returned when requests are made to `/` and `/{p}` - a variable path value. Those to `/admission` calls the Rserve service and relays results from it - see the Rseve service section for the request payload. Note that an authorization header is not necessary between services.

```python
import os
import httpx
from fastapi import FastAPI
from pydantic import BaseModel, Schema
from typing import Optional

APP_PREFIX = os.environ["APP_PREFIX"]

app = FastAPI(title="{0} API".format(APP_PREFIX), docs_url=None, redoc_url=None)

## response models
class NameResp(BaseModel):
    title: str


class PathResp(BaseModel):
    title: str
    path: str


class AdmissionReq(BaseModel):
    gre: int = Schema(None, ge=0, le=800)
    gpa: float = Schema(None, ge=0.0, le=4.0)
    rank: str = Schema(None)


class AdmissionResp(BaseModel):
    result: bool


## service methods
@app.get("/", response_model=NameResp)
async def whoami():
    return {"title": app.title}


@app.post("/admission")
async def admission(*, req: Optional[AdmissionReq]):
    host = os.getenv("RSERVE_HOST", "localhost")
    port = os.getenv("RSERVE_PORT", "8000")
    async with httpx.AsyncClient() as client:
        dat = req.json() if req else None
        r = await client.post("http://{0}:{1}/{2}".format(host, port, "admission"), data=dat)
        return r.json()


@app.get("/{p}", response_model=PathResp)
async def whichpath(p: str):
    print(p)
    return {"title": app.title, "path": p}
```

The Python service is configured with _lables_. Traefik is enabled and the same docker network is used. In _frontend_ rules, 

* requests are set to be forwarded if host is `k8s-traefik.info` and path is `/pybackend` - _PathPrefixStrip_ is to allow the path and its subpaths.
* authentication service is called and its address is _http://forward-auth:8080/auth_.
* authorization header is set to be copied to request - it's for adding a custom header to a request and _this label is mistakenly added_.

If the _frontend_ rules pass, requests are sent to _pybackend_ backend on port 8000.

```yaml
...
  pybackend:
    image: kapps/trafik-demo:pybackend
    networks:
      - traefik-net
    depends_on:
      - traefik
      - forward-auth
      - rbackend
    command: >
      main:app
      --host=0.0.0.0
      --port=8000
      --reload
    expose:
      - 8000
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-net"
      - "traefik.frontend.rule=Host:k8s-traefik.info;PathPrefixStrip:/pybackend"
      - "traefik.frontend.auth.forward.address=http://forward-auth:8000/auth"
      - "traefik.frontend.auth.forward.authResponseHeaders=Authorization"
      - "traefik.backend=pybackend"
      - "traefik.port=8000"
    environment:
      APP_PREFIX: "Python Backend"
      RSERVE_HOST: "rbackend"
      RSERVE_PORT: "8000"
...
```

### R Service

`whoami()` that returns the service name is executed when a request is made to the base path (`/`) - see [here](https://github.com/jaehyeon-kim/k8s-traefik/blob/master/rbackend/process-req.R#L47) for details. To `/admission`, an admission result of a graduate school is returned by fitting a simple logistic regression. The result is based on 3 fields - GRE (Graduate Record Exam scores), GPA (grade point average) and prestige of the undergraduate institution. It's from [UCLA Institute for Digital Research & Education](https://stats.idre.ucla.edu/r/dae/logit-regression/). If a field is missing, the mean or majority level is selected.

```r
DAT <- read.csv('./binary.csv')
DAT$rank <- factor(DAT$rank)

value_if_null <- function(v, DAT) {
  if (class(DAT[[v]]) == 'factor') {
    tt <- table(DAT[[v]])
    names(tt[tt==max(tt)])
  } else {
    mean(DAT[[v]])
  }
}

set_newdata <- function(args_called) {
  args_init <- list(gre=NULL, gpa=NULL, rank=NULL)
  newdata <- lapply(names(args_init), function(n) {
    if (is.null(args_called[[n]])) {
      args_init[[n]] <- value_if_null(n, DAT)
    } else {
      args_init[[n]] <- args_called[[n]]
    }
  })
  names(newdata) <- names(args_init)
  lapply(names(newdata), function(n) {
    flog.info(sprintf("%s - %s", n, newdata[[n]]))
  })
  newdata <- as.data.frame(newdata)
  newdata$rank <- factor(newdata$rank, levels = levels(DAT$rank))
  newdata
}

admission <- function(gre=NULL, gpa=NULL, rank=NULL, ...) {
  newdata <- set_newdata(args_called = as.list(sys.call()))
  logit <- glm(admit ~ gre + gpa + rank, data = DAT, family = "binomial")
  resp <- predict(logit, newdata=newdata, type="response")
  flog.info(sprintf("resp - %s", resp))
  list(result = resp > 0.5)
}

whoami <- function() {
    list(title=sprintf("%s API", Sys.getenv("APP_PREFIX", "RSERVE")))
}
```

The Rserve service is configured with _lables_ as well.

```yaml
...
  rbackend:
    image: kapps/trafik-demo:rbackend
    networks:
      - traefik-net
    depends_on:
      - traefik
      - forward-auth
    command: >
      --slave
      --RS-conf /home/app/rserve.conf
      --RS-source /home/app/rserve-src.R
    expose:
      - 8000
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-net"
      - "traefik.frontend.rule=Host:k8s-traefik.info;PathPrefixStrip:/rbackend"
      - "traefik.frontend.auth.forward.address=http://forward-auth:8000/auth"
      - "traefik.frontend.auth.forward.authResponseHeaders=Authorization"
      - "traefik.backend=rbackend"
      - "traefik.port=8000"
    environment:
      APP_PREFIX: "R Backend"
...
```

In order to check dynamic routes configuration, the Python service is started as following. Note that, as it depends on the authentication and Rserve service, these are started as well.

```bash
docker-compose up -d pybackend
```

Once those services are started, the frontends/backends of the Python and Rserve services appear in the monitoring UI.


![](traefik-providers-00.png#center)


Below shows some request examples.

```bash
#### Authentication failure responses from authentication server
http http://k8s-traefik.info/pybackend
# HTTP/1.1 403 Forbidden
# ...
# {
#     "detail": "Not authenticated"
# }

http http://k8s-traefik.info/pybackend "Authorization: Bearer foo"
# HTTP/1.1 401 Unauthorized
# ...
# {
#     "detail": "Invalid Token"
# }

#### Successful responses from Python service
http http://k8s-traefik.info/pybackend "Authorization: Bearer foobar"
# {
#     "title": "Python Backend API"
# }

http http://k8s-traefik.info/pybackend/foobar "Authorization: Bearer foobar"
# {
#     "path": "foobar",
#     "title": "Python Backend API"
# }

#### Succesesful responses from Rserve service
http http://k8s-traefik.info/rbackend "Authorization: Bearer foobar"
# {
#     "title": "R Backend API"
# }

#### Successful responses from requests to /admission
echo '{"gre": 600, "rank": "1"}' \
  | http POST http://k8s-traefik.info/rbackend/admission "Authorization: Bearer foobar"
# {
#     "result": true
# }

echo '{"gre": 600, "rank": "1"}' \
  | http POST http://k8s-traefik.info/pybackend/admission "Authorization: Bearer foobar"
# {
#     "result": true
# }
```

The _HEALTH_ tab of the monitoring UI shows some request metrics. After running the following for a while, the page is updated as shown below.

```bash
while true; do echo '{"gre": 600, "rank": "1"}' \
  | http POST http://k8s-traefik.info/pybackend/admission "Authorization: Bearer foobar"; sleep 1; done
```


![](traefik-health.png#center)
