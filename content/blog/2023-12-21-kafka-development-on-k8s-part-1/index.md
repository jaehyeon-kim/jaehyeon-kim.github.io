---
title: Kafka Development on Kubernetes - Part 1 Cluster Setup
date: 2023-12-21
draft: false
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
description: Apache Kafka is one of the key technologies for implementing data streaming architectures. Strimzi provides a way to run an Apache Kafka cluster and related resources on Kubernetes in various deployment configurations. In this series of posts, we will discuss how to create a Kafka cluster, to develop Kafka client applications in Python and to build a data pipeline using Kafka connectors on Kubernetes.
---

[Apache Kafka](https://kafka.apache.org/) is one of the key technologies for implementing data streaming architectures. [Strimzi](https://strimzi.io/) provides a way to run an Apache Kafka cluster and related resources on Kubernetes in various deployment configurations. In this series of posts, we will discuss how to create a Kafka cluster, to develop Kafka client applications in Python and to build a data pipeline using Kafka connectors on Kubernetes.

* [Part 1 Cluster Setup](#) (this post)
* Part 2 Producer and Consumer
* Part 3 Kafka Connect

## Setup Kafka Cluster

The Kafka cluster is deployed using the [Strimzi Operator](https://strimzi.io/) on a [Minikube](https://minikube.sigs.k8s.io/docs/) cluster. We install Strimzi version 0.27.1 and Kubernetes version 1.24.7 as we use Kafka version 2.8.1 - see [this page](https://strimzi.io/downloads/) for details about Kafka version compatibility. Once the [Minikube CLI](https://minikube.sigs.k8s.io/docs/start/) and [Docker](https://www.docker.com/) are installed, a Minikube cluster can be created by specifying the desired Kubernetes version as shown below.

```bash
minikube start --cpus='max' --memory=10240 --addons=metrics-server --kubernetes-version=v1.24.7
```

### Deploy Strimzi Operator

The project repository keeps manifest files that can be used to deploy the Strimzi Operator and related resources. We can download the relevant manifest file by specifying the desired version. By default, the manifest file assumes the resources are deployed in the *myproject* namespace. As we deploy them in the *default* namespace, however, we need to change the resource namespace accordingly using [sed](https://www.gnu.org/software/sed/manual/sed.html). The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-on-k8s/part-01) of this post.

The resources that are associated with the Strimzi Operator can be deployed using the *kubectl create* command. Note that over 20 resources are deployed from the manifest file including Kafka-related [custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/). Among those, we use the *Kafka*, *KafkaConnect* and *KafkaConnector* custom resources in this series.

```bash
## download and update strimzi oeprator manifest
STRIMZI_VERSION="0.27.1"
DOWNLOAD_URL=https://github.com/strimzi/strimzi-kafka-operator/releases/download/$STRIMZI_VERSION/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
curl -L -o manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml ${DOWNLOAD_URL}
# update namespace from myproject to default
sed -i 's/namespace: .*/namespace: default/' manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## deploy strimzi cluster operator
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

We can check the Strimzi Operator runs as a [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

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

We deploy a Kafka cluster with two brokers and one Zookeeper node. It has both internal and external listeners on port 9092 and 29092 respectively. Note that the external listener is configured as the *nodeport* type so that the associating service can be accessed from the host machine. Also, the cluster is configured to allow automatic creation of topics (*auto.create.topics.enable: "true"*) and the default number of partition is set to 3 (*num.partitions: 3*).

```yaml
# manifests/kafka-cluster.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: demo-cluster
spec:
  kafka:
    replicas: 2
    version: 2.8.1
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: external
        port: 29092
        type: nodeport
        tls: false
    storage:
      type: jbod
      volumes:
        - id: 0
          type: persistent-claim
          size: 20Gi
          deleteClaim: true
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
      inter.broker.protocol.version: 2.8
      auto.create.topics.enable: "true"
      num.partitions: 3
  zookeeper:
    replicas: 1
    storage:
      type: persistent-claim
      size: 10Gi
      deleteClaim: true
```

The Kafka cluster can be deployed using the *kubectl create* command as shown below.

```bash
kubectl create -f manifests/kafka-cluster.yaml
```

The Kafka and Zookeeper nodes are deployed as [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) as it provides guarantees about the ordering and uniqueness of the associating [Pods](https://kubernetes.io/docs/concepts/workloads/pods/). It also creates multiple [services](https://kubernetes.io/docs/concepts/services-networking/service/), and we use the following services in this series.

- communication within Kubernetes cluster
  - *demo-cluster-kafka-bootstrap* - to access Kafka brokers from the client and management apps
  - *demo-cluster-zookeeper-client* - to access Zookeeper node from the management app
- communication from host
  - *demo-cluster-kafka-external-bootstrap* - to access Kafka brokers from the client apps

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

[UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme) is a free and open-source Kafka management application, and it is deployed as a Kubernetes Deployment. The Deployment is configured to have a single instance, and the Kafka cluster access details are specified as environment variables. The app is associated by a service of the *NodePort* type for external access.

```yaml
# manifests/kafka-ui.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: kafka-ui
  name: kafka-ui
spec:
  type: NodePort
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: kafka-ui
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: kafka-ui
  name: kafka-ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
        - image: provectuslabs/kafka-ui:v0.7.1
          name: kafka-ui-container
          ports:
            - containerPort: 8080
          env:
            - name: KAFKA_CLUSTERS_0_NAME
              value: demo-cluster
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: demo-cluster-kafka-bootstrap:9092
            - name: KAFKA_CLUSTERS_0_ZOOKEEPER
              value: demo-cluster-zookeeper-client:2181
          resources: {}
```

The Kafka management app (*kafka-ui*) can be deployed using the *kubectl create* command as shown below.

```bash
kubectl create -f manifests/kafka-ui.yaml

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

We can use the [*minikube service*](https://minikube.sigs.k8s.io/docs/handbook/accessing/) command to obtain the Kubernetes URL for the *kafka-ui* service in the host's local cluster.

```bash
minikube service kafka-ui --url
# http://127.0.0.1:38257
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

![](cluster.png#center)

## Produce and Consume Messages

We can produce and consume messages with Kafka command utilities by creating two Pods in separate terminals. The Pods start the producer (*kafka-console-producer.sh*) and consumer (*kafka-console-consumer.sh*) scripts respectively while specifying necessary arguments such as the bootstrap server address and topic name. We can see that the records created by the producer are appended in the consumer terminal.

```bash
kubectl run kafka-producer --image=quay.io/strimzi/kafka:0.27.1-kafka-2.8.1 --rm -it --restart=Never \
  -- bin/kafka-console-producer.sh --bootstrap-server demo-cluster-kafka-bootstrap:9092 --topic demo-topic

# >product: apples, quantity: 5
# >product: lemons, quantity: 7
```

```bash
kubectl run kafka-consumer --image=quay.io/strimzi/kafka:0.27.1-kafka-2.8.1 --rm -it --restart=Never \
  -- bin/kafka-console-consumer.sh --bootstrap-server demo-cluster-kafka-bootstrap:9092 --topic demo-topic --from-beginning

# product: apples, quantity: 5
# product: lemons, quantity: 7
```

We can also check the messages in the management app as shown below.

![](messages.png#center)

## Delete Resources

The Kubernetes resources and Minikube cluster can be removed by the *kubectl delete* and *minikube delete* commands respectively.

```bash
## delete resources
kubectl delete -f manifests/kafka-cluster.yaml
kubectl delete -f manifests/kafka-ui.yaml
kubectl delete -f manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## delete minikube
minikube delete
```

## Summary

Apache Kafka is one of the key technologies for implementing data streaming architectures. Strimzi provides a way to run an Apache Kafka cluster and related resources on Kubernetes in various deployment configurations. In this post, we discussed how to deploy a Kafka cluster on a Minikube cluster using the Strimzi Operator. Also, it is demonstrated how to produce and consume messages using the Kafka command line utilities.
