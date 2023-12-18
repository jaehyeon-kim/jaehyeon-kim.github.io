---
title: Kafka Development on Kubernetes - Part 1 Cluster Setup
date: 2023-12-21
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
  - Docker
authors:
  - JaehyeonKim
images: []
description: Foo Bar
---


* [Part 1 Cluster Setup](#) (this post)
* Part 2 Producer and Consumer
* Part 3 Kafka Connect

## Setup Kafka Cluster

### Deploy Strimzi Operator

```bash
## create minikube cluster
minikube start --cpus='max' --memory=10240 --addons=metrics-server --kubernetes-version=v1.24.7

## download and deploy strimzi oeprator
STRIMZI_VERSION="0.27.1"
DOWNLOAD_URL=https://github.com/strimzi/strimzi-kafka-operator/releases/download/$STRIMZI_VERSION/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
curl -L -o manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml ${DOWNLOAD_URL}

## deploy strimzi cluster operator
# change namespace from myproject to default
sed -i 's/namespace: .*/namespace: default/' manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
# deploy operator
kubectl create -f manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

# rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-entity-operator-delegation created
# customresourcedefinition.apiextensions.k8s.io/strimzipodsets.core.strimzi.io created
# clusterrole.rbac.authorization.k8s.io/strimzi-kafka-client created
# deployment.apps/strimzi-cluster-operator created
# customresourcedefinition.apiextensions.k8s.io/kafkarebalances.kafka.strimzi.io created
# clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-kafka-broker-delegation created
# configmap/strimzi-cluster-operator created
# rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator created
# customresourcedefinition.apiextensions.k8s.io/kafkamirrormakers.kafka.strimzi.io created
# clusterrole.rbac.authorization.k8s.io/strimzi-entity-operator created
# clusterrole.rbac.authorization.k8s.io/strimzi-kafka-broker created
# customresourcedefinition.apiextensions.k8s.io/kafkaconnects.kafka.strimzi.io created
# customresourcedefinition.apiextensions.k8s.io/kafkamirrormaker2s.kafka.strimzi.io created
# customresourcedefinition.apiextensions.k8s.io/kafkausers.kafka.strimzi.io created
# customresourcedefinition.apiextensions.k8s.io/kafkaconnectors.kafka.strimzi.io created
# customresourcedefinition.apiextensions.k8s.io/kafkas.kafka.strimzi.io created
# serviceaccount/strimzi-cluster-operator created
# customresourcedefinition.apiextensions.k8s.io/kafkatopics.kafka.strimzi.io created
# clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator created
# clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-global created
# clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-kafka-client-delegation created
# customresourcedefinition.apiextensions.k8s.io/kafkabridges.kafka.strimzi.io created
# clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-namespaced created
```

```bash
kubectl get deploy,rs,po
# NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/strimzi-cluster-operator   1/1     1            1           3m44s

# NAME                                                  DESIRED   CURRENT   READY   AGE
# replicaset.apps/strimzi-cluster-operator-7cc4b5759c   1         1         1       3m44s

# NAME                                            READY   STATUS    RESTARTS   AGE
# pod/strimzi-cluster-operator-7cc4b5759c-q45nv   1/1     Running   0          3m43s
```

### Deploy Kafka Cluster

```bash
kubectl create -f manifests/kafka-cluster.yaml
```

```bash
kubectl get all -l app.kubernetes.io/instance=demo-cluster
# NAME                           READY   STATUS    RESTARTS   AGE
# pod/demo-cluster-kafka-0       1/1     Running   0          67s
# pod/demo-cluster-kafka-1       1/1     Running   0          67s
# pod/demo-cluster-zookeeper-0   1/1     Running   0          109s

# NAME                                            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
# service/demo-cluster-kafka-bootstrap            ClusterIP   10.106.148.7     <none>        9091/TCP,9092/TCP            67s
# service/demo-cluster-kafka-brokers              ClusterIP   None             <none>        9090/TCP,9091/TCP,9092/TCP   67s
# service/demo-cluster-kafka-external-0           NodePort    10.109.118.191   <none>        29092:31733/TCP              67s
# service/demo-cluster-kafka-external-1           NodePort    10.105.36.159    <none>        29092:31342/TCP              67s
# service/demo-cluster-kafka-external-bootstrap   NodePort    10.97.88.48      <none>        29092:30247/TCP              67s
# service/demo-cluster-zookeeper-client           ClusterIP   10.97.131.183    <none>        2181/TCP                     109s
# service/demo-cluster-zookeeper-nodes            ClusterIP   None             <none>        2181/TCP,2888/TCP,3888/TCP   109s

# NAME                                      READY   AGE
# statefulset.apps/demo-cluster-kafka       2/2     67s
# statefulset.apps/demo-cluster-zookeeper   1/1     109s
```

### Deploy Kafka UI

```bash
kubectl create -f manifests/kafka-ui.yaml
```

```bash
kubectl get all -l app=kafka-ui
# NAME                            READY   STATUS    RESTARTS   AGE
# pod/kafka-ui-6d55c756b8-tznlp   1/1     Running   0          54s

# NAME               TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)          AGE
# service/kafka-ui   NodePort   10.99.20.37   <none>        8080:31119/TCP   54s

# NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/kafka-ui   1/1     1            1           54s

# NAME                                  DESIRED   CURRENT   READY   AGE
# replicaset.apps/kafka-ui-6d55c756b8   1         1         1       54s
```

```bash
minikube service kafka-ui --url
# http://127.0.0.1:38257
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

![](cluster.png#center)

## Produce and Consume Messages

### Produce Messages

```bash
kubectl run kafka-producer --image=quay.io/strimzi/kafka:0.27.1-kafka-2.8.1 --rm -it --restart=Never \
  -- bin/kafka-console-producer.sh --bootstrap-server demo-cluster-kafka-bootstrap:9092 --topic demo-topic

# >product: apples, quantity: 5
# >product: lemons, quantity: 7
```

### Consume Messages

```bash
kubectl run kafka-consumer --image=quay.io/strimzi/kafka:0.27.1-kafka-2.8.1 --rm -it --restart=Never \
  -- bin/kafka-console-consumer.sh --bootstrap-server demo-cluster-kafka-bootstrap:9092 --topic demo-topic --from-beginning

# product: apples, quantity: 5
# product: lemons, quantity: 7
```

![](messages.png#center)

## Delete Resources

```bash
## delete resources
kubectl delete -f manifests/kafka-cluster.yaml
kubectl delete -f manifests/kafka-ui.yaml
kubectl delete -f manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## delete minikube
minikube delete
```

## Summary