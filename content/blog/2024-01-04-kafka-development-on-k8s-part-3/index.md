---
title: Kafka Development on Kubernetes - Part 3 Kafka Connect
date: 2024-01-04
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development on Kubernetes
categories:
  - Apache Kafka
tags: 
  - Apache Kafka
  - Kubernetes
  - Minikube
  - Strimzi
  - Python
  - Docker
authors:
  - JaehyeonKim
images: []
description: Foo Bar
---

* [Part 1 Cluster Setup](/blog/2023-12-21-kafka-development-on-k8s-part-1)
* [Part 2 Producer and Consumer](/blog/2023-12-28-kafka-development-on-k8s-part-2)
* [Part 3 Kafka Connect](#) (this post)

## Kafka Connect

### Create Secrets

```bash
# Log in to DockerHub if not done - docker login
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
```

```bash
kubectl create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: awscred
stringData:
  AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
EOF
```

### Deploy Connect Server

```bash
kubectl create -f manifests/kafka-connect.yaml
```

![](dockerhub.png#center)

```bash
kubectl get all -l strimzi.io/cluster=demo-connect
# NAME                                        READY   STATUS    RESTARTS   AGE
# pod/demo-connect-connect-559cd588b4-48lhd   1/1     Running   0          2m4s
# pod/demo-connect-connect-559cd588b4-wzqgs   1/1     Running   0          2m4s

# NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
# service/demo-connect-connect-api   ClusterIP   10.111.148.128   <none>        8083/TCP   2m4s

# NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/demo-connect-connect   2/2     2            2           2m4s

# NAME                                              DESIRED   CURRENT   READY   AGE
# replicaset.apps/demo-connect-connect-559cd588b4   2         2         2       2m4s
```

## Kafka Connectors 

### Source Connector

### Sink Connector

### Deploy Connectors

```bash
kubectl create -f manifests/kafka-connectors.yaml
kubectl get kafkaconnectors
# NAME           CLUSTER        CONNECTOR CLASS                                     MAX TASKS   READY
# order-sink     demo-connect   io.confluent.connect.s3.S3SinkConnector             1           True
# order-source   demo-connect   com.amazonaws.mskdatagen.GeneratorSourceConnector   1           True
```

![](connectors.png#center)

![](s3-topics.png#center)

![](s3-files.png#center)

## Delete Resources

```bash
## delete resources
kubectl delete -f manifests/kafka-connectors.yaml
kubectl delete -f manifests/kafka-connect.yaml
kubectl delete secret awscred
kubectl delete secret regcred
kubectl delete -f manifests/kafka-cluster.yaml
kubectl delete -f manifests/kafka-ui.yaml
kubectl delete -f manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## delete minikube
minikube delete
```

## Summary
