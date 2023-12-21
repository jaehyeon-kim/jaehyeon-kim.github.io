---
title: Kafka Development on Kubernetes - Part 3 Kafka Connect
date: 2024-01-04
draft: true
featured: false
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
  - Kafka Connect
authors:
  - JaehyeonKim
images: []
description: Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. In this post, we discuss how to set up a data ingestion pipeline using Kafka connectors. Fake customer and order data is ingested into Kafka topics using the MSK Data Generator. Also, we use the Confluent S3 sink connector to save the messages of the topics into a S3 bucket. The Kafka Connect servers and individual connectors are deployed using the custom resources of Strimzi on Kubernetes.
---

[Kafka Connect](https://kafka.apache.org/documentation/#connect) is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka. In this post, we discuss how to set up a data ingestion pipeline using Kafka connectors. Fake customer and order data is ingested into Kafka topics using the [MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator). Also, we use the [Confluent S3](https://www.confluent.io/hub/confluentinc/kafka-connect-s3) sink connector to save the messages of the topics into a S3 bucket. The Kafka Connect servers and individual connectors are deployed using the custom resources of [Strimzi](https://strimzi.io/) on Kubernetes.

* [Part 1 Cluster Setup](/blog/2023-12-21-kafka-development-on-k8s-part-1)
* [Part 2 Producer and Consumer](/blog/2023-12-28-kafka-development-on-k8s-part-2)
* [Part 3 Kafka Connect](#) (this post)

## Kafka Connect

We create a Kafka Connect server using the Strimzi custom resource named *KafkaConnect*. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-on-k8s/part-03) of this post.

### Create Secrets

As discussed further below, a custom Docker image is built and pushed into an external Docker registry when we create a Kafka Connect server using Strimzi. Therefore, we need the registry secret to push the image. Also, as the sink connector needs permission to write files into a S3 bucket, AWS credentials should be added to the Connect server. Both the secret and credentials will be made available via Kubernetes [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) and those are created as shown below.

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

The Kafka Connect server is created using the Strimzi custom resource named *KafkaConnect*. When we create the custom resource, a Docker image is built, the image is pushed into an external Docker registry (*output.type: docker*), and it is pulled to deploy the Kafka Connect server instances. Therefore, in the *build* configuration, we need to indicate the location of an external Docker registry and registry secret (*pushSecret*). Note that the registry secret is referred from the Kubernetes Secret that is created earlier. Also, we can build connector sources together by specifying their types and URLs in *build.plugins*.

When it comes to the Connect server configuration, two server instances are configured to run (*replicas: 2*) and the same Kafka version (*2.8.1*) to the associating Kafka cluster is used. Also, the name and port of the service that exposes the Kafka internal listeners are used to specify the Kafka bootstrap server address. Moreover, AWS credentials are added to environment variables because the sink connector needs permission to write files to a S3 bucket.

```yaml
# manifests/kafka-connect.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: demo-connect
  annotations:
    strimzi.io/use-connector-resources: "true"
spec:
  version: 2.8.1
  replicas: 2
  bootstrapServers: demo-cluster-kafka-bootstrap:9092
  config:
    group.id: demo-connect
    offset.storage.topic: demo-connect-offsets
    config.storage.topic: demo-connect-configs
    status.storage.topic: demo-connect-status
    # -1 means it will use the default replication factor configured in the broker
    config.storage.replication.factor: -1
    offset.storage.replication.factor: -1
    status.storage.replication.factor: -1
    key.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter: org.apache.kafka.connect.json.JsonConverter
    key.converter.schemas.enable: false
    value.converter.schemas.enable: false
  externalConfiguration:
    env:
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: awscred
            key: AWS_ACCESS_KEY_ID
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: awscred
            key: AWS_SECRET_ACCESS_KEY
  build:
    output:
      type: docker
      image: jaehyeon/demo-connect:latest
      pushSecret: regcred
    # https://strimzi.io/docs/operators/0.27.1/using#plugins
    plugins:
      - name: confluentinc-kafka-connect-s3
        artifacts:
          - type: zip
            url: https://d1i4a15mxbxib1.cloudfront.net/api/plugins/confluentinc/kafka-connect-s3/versions/10.4.3/confluentinc-kafka-connect-s3-10.4.3.zip
      - name: msk-data-generator
        artifacts:
          - type: jar
            url: https://github.com/awslabs/amazon-msk-data-generator/releases/download/v0.4.0/msk-data-generator-0.4-jar-with-dependencies.jar
```

We assume that a Kafka cluster and management app are deployed on Minikube as discussed in [Part 1](/blog/2023-12-21-kafka-development-on-k8s-part-1). The Kafka Connect server can be created using the *kubernetes create* command as shown below.

```bash
kubectl create -f manifests/kafka-connect.yaml
```

Once the Connect image is built successfully, we can see that the image is pushed into the external Docker registry.

![](dockerhub.png#center)

Then the Connect server instances run by two Pods, and they are exposed by a service named *demo-connect-connect-api* on port 8083.

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

Both the source and sink connectors are created using the Strimzi custom resource named *KafkaConnector*.

### Source Connector

The connector class (*spec.class*) is set for the MSK Data Generator, and a single worker is allocated to it (*tasks.max*). Also, the key converter is set to the string converter as the keys of both topics are set to be primitive values (*genkp*) while the value converter is configured as the json converter. Finally, schemas are not enabled for both the key and value.

The remaining properties are specific to the source connector. Basically it sends messages to two topics (*customer* and *order*). They are linked by the *customer_id* attribute of the *order* topic where the value is from the key of the *customer* topic. This is useful for practicing stream processing e.g. for joining two streams.

```yaml
# manifests/kafka-connectors.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: order-source
  labels:
    strimzi.io/cluster: demo-connect
spec:
  class: com.amazonaws.mskdatagen.GeneratorSourceConnector
  tasksMax: 1
  config:
    ##
    key.converter: org.apache.kafka.connect.storage.StringConverter
    key.converter.schemas.enable: false
    value.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable: false
    ##
    genkp.customer.with: "#{Code.isbn10}"
    genv.customer.name.with: "#{Name.full_name}"
    genkp.order.with: "#{Internet.uuid}"
    genv.order.product_id.with: "#{number.number_between '101''109'}"
    genv.order.quantity.with: "#{number.number_between '1''5'}"
    genv.order.customer_id.matching: customer.key
    global.throttle.ms: 500
    global.history.records.max: 1000

...

```

### Sink Connector

The connector is configured to write files from both the topics (*order and customer*) into a S3 bucket (*s3.bucket.name*) where the file names are prefixed by the partition number (*DefaultPartitioner*). Also, it invokes file commits every 60 seconds (*rotate.schedule.interval.ms*) or the number of messages reach 100 (*flush.size*). Like the source connector, it overrides the converter-related properties.

```yaml
# manifests/kafka-connectors.yaml

...

apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: order-sink
  labels:
    strimzi.io/cluster: demo-connect
spec:
  class: io.confluent.connect.s3.S3SinkConnector
  tasksMax: 1
  config:
    ##
    key.converter: org.apache.kafka.connect.storage.StringConverter
    key.converter.schemas.enable: false
    value.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable: false
    ##
    storage.class: io.confluent.connect.s3.storage.S3Storage
    format.class: io.confluent.connect.s3.format.json.JsonFormat
    topics: order,customer
    s3.bucket.name: kafka-dev-on-k8s-ap-southeast-2
    s3.region: ap-southeast-2
    flush.size: 100
    rotate.schedule.interval.ms: 60000
    timezone: Australia/Sydney
    partitioner.class: io.confluent.connect.storage.partitioner.DefaultPartitioner
    errors.log.enable: true
```

### Deploy Connectors

The Kafka source and sink connectors can be created using the *kubernetes create* command as shown below. Once created, we can check their details by listing (or describing) the Strimzi custom resource (*KafkaConnector*). Below shows both the source and sink connectors are in ready status, which indicates they are running.

```bash
kubectl create -f manifests/kafka-connectors.yaml

kubectl get kafkaconnectors
# NAME           CLUSTER        CONNECTOR CLASS                                     MAX TASKS   READY
# order-sink     demo-connect   io.confluent.connect.s3.S3SinkConnector             1           True
# order-source   demo-connect   com.amazonaws.mskdatagen.GeneratorSourceConnector   1           True
```

We can also see the connector status on the Kafka management app (*kafka-ui*) as shown below.

![](connectors.png#center)

The sink connector writes messages of the two topics (*customer* and *order*), and topic names are used as S3 prefixes. 

![](s3-topics.png#center)

The files are generated by `<topic>+<partiton>+<start-offset>.json`. The sink connector's format class is set to *io.confluent.connect.s3.format.json.JsonFormat* so that it writes to Json files.

![](s3-files.png#center)

## Delete Resources

The Kubernetes resources and Minikube cluster can be removed by the *kubectl delete* and *minikube delete* commands respectively.

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

Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. In this post, we discussed how to set up a data ingestion pipeline using Kafka connectors. Fake customer and order data was ingested into Kafka topics using the MSK Data Generator. Also, we used the Confluent S3 sink connector to save the messages of the topics into a S3 bucket. The Kafka Connect servers and individual connectors were deployed using the custom resources of Strimzi on Kubernetes.
