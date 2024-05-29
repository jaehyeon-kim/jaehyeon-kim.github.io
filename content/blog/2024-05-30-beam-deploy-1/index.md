---
title: Deploy Python Streaming Processing App on Kubernetes - Part 1 PyFlink Applicatin
date: 2024-05-30
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Deploy Python Streaming Processing App on Kubernetes
categories:
  - Data Streaming
tags: 
  - Apache Flink
  - Apache Kafka
  - Kubernetes
  - Python
  - Docker
authors:
  - JaehyeonKim
images: []
description: Flink Kubernetes Operator acts as a control plane to manage the complete deployment lifecycle of Apache Flink applications. With the operator, we can simplify deployment and management of Python stream processing applications, and we discuss how to deploy a PyFlink application and Python Apache Beam pipeline on the Flink Runner on Kubernetes in this series. In Part 1, we first deploy a Kafka cluster on minikube as the source and sink of the PyFlink application are Kafka topics. Then, the application source is packaged in a custom Docker image and deployed on the minikube cluster using the Flink Kubernetes Operator. Finally, the output of the application is checked by sending messages to the input Kafka topic using a Python producer application.
---

[Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/concepts/overview/) acts as a control plane to manage the complete deployment lifecycle of Apache Flink applications. With the operator, we can simplify deployment and management of Python stream processing applications, and we discuss how to deploy a PyFlink application and Python Apache Beam pipeline on the [Flink Runner](https://beam.apache.org/documentation/runners/flink/) on Kubernetes in this series.

In Part 1, we first deploy a Kafka cluster on [minikube](https://minikube.sigs.k8s.io/docs/) as the source and sink of the PyFlink application are Kafka topics. Then, the application source is packaged in a custom Docker image and deployed on the minikube cluster using the Flink Kubernetes Operator. Finally, the output of the application is checked by sending messages to the input Kafka topic using a Python producer application.

* [Part 1 PyFlink Applicatin](#) (this post)
* Part 2 Beam Pipeline on Flink Runner

## Setup Kafka Cluster

As the source and sink of the stream processing application are Kafka topics, a Kafka cluster is deployed using the [Strimzi Operator](https://strimzi.io/) on a [minikube](https://minikube.sigs.k8s.io/docs/) cluster. We install Strimzi version 0.39.0 and Kubernetes version 1.25.3. Once the [minikube CLI](https://minikube.sigs.k8s.io/docs/start/) and [Docker](https://www.docker.com/) are installed, a minikube cluster can be created by specifying the desired Kubernetes version.

```bash
minikube start --cpus='max' --memory=20480 --addons=metrics-server --kubernetes-version=v1.25.3
```

### Deploy Strimzi Operator

The [**project repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-deploy) keeps manifest files that can be used to deploy the *Strimzi Operator*, Kafka cluster and Kafka management app. If you want to download a different version of the operator, you can download the relevant manifest file by specifying the desired version. By default, the manifest file assumes that the resources are deployed in the *myproject* namespace. As we deploy them in the *default* namespace, however, we need to change the resource namespace using [sed](https://www.gnu.org/software/sed/manual/sed.html) accordingly. The operator can be deployed using `kubectl create`.

```bash
## download and deploy strimzi oeprator
STRIMZI_VERSION="0.39.0"

## (optional) if downloading a different version
DOWNLOAD_URL=https://github.com/strimzi/strimzi-kafka-operator/releases/download/$STRIMZI_VERSION/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
curl -L -o kafka/manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml ${DOWNLOAD_URL}
# update namespace from myproject to default
sed -i 's/namespace: .*/namespace: default/' kafka/manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## deploy strimzi cluster operator
kubectl create -f kafka/manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
```

We can check the Strimzi Operator runs as a [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

```bash
kubectl get deploy,rs,po
# NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/strimzi-cluster-operator   1/1     1            1           2m50s

# NAME                                                 DESIRED   CURRENT   READY   AGE
# replicaset.apps/strimzi-cluster-operator-8d6d4795c   1         1         1       2m50s

# NAME                                           READY   STATUS    RESTARTS   AGE
# pod/strimzi-cluster-operator-8d6d4795c-94t8c   1/1     Running   0          2m49s
```

### Deploy Kafka Cluster

We deploy a Kafka cluster with a single broker and Zookeeper node. It has both internal and external listeners on port 9092 and 29092 respectively. Note that the external listener will be used to access the Kafka cluster outside the minikube cluster. Also, the cluster is configured to allow automatic creation of topics (*auto.create.topics.enable: "true"*) and the default number of partition is set to 3 (*num.partitions: 3*).

```yaml
# kafka/manifests/kafka-cluster.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: demo-cluster
spec:
  kafka:
    version: 3.5.2
    replicas: 1
    resources:
      requests:
        memory: 256Mi
        cpu: 250m
      limits:
        memory: 512Mi
        cpu: 500m
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
      inter.broker.protocol.version: "3.5"
      auto.create.topics.enable: "true"
      num.partitions: 3
  zookeeper:
    replicas: 1
    resources:
      requests:
        memory: 256Mi
        cpu: 250m
      limits:
        memory: 512Mi
        cpu: 500m
    storage:
      type: persistent-claim
      size: 10Gi
      deleteClaim: true
```

The Kafka cluster can be deployed using `kubectl create`.

```bash
kubectl create -f kafka/manifests/kafka-cluster.yaml
```

The Kafka and Zookeeper nodes are managed by the [*StrimziPodSet*](https://strimzi.io/docs/operators/latest/configuring.html#type-StrimziPodSet-reference) custom resource. It also creates multiple [services](https://kubernetes.io/docs/concepts/services-networking/service/), and we use the following services in this series.

- communication within the Kubernetes cluster
  - *demo-cluster-kafka-bootstrap* - to access Kafka brokers from the client and management apps
  - *demo-cluster-zookeeper-client* - to access Zookeeper node from the management app
- communication from the host
  - *demo-cluster-kafka-external-bootstrap* - to access Kafka brokers from the producer app

```bash
kubectl get all -l app.kubernetes.io/instance=demo-cluster
# NAME                           READY   STATUS    RESTARTS   AGE
# pod/demo-cluster-kafka-0       1/1     Running   0          94s
# pod/demo-cluster-zookeeper-0   1/1     Running   0          117s

# NAME                                            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                               AGE
# service/demo-cluster-kafka-bootstrap            ClusterIP   10.111.140.173   <none>        9091/TCP,9092/TCP                     94s
# service/demo-cluster-kafka-brokers              ClusterIP   None             <none>        9090/TCP,9091/TCP,8443/TCP,9092/TCP   94s
# service/demo-cluster-kafka-external-0           NodePort    10.104.111.213   <none>        29092:30663/TCP                       94s
# service/demo-cluster-kafka-external-bootstrap   NodePort    10.104.149.213   <none>        29092:31966/TCP                       94s
# service/demo-cluster-zookeeper-client           ClusterIP   10.98.115.75     <none>        2181/TCP                              118s
# service/demo-cluster-zookeeper-nodes            ClusterIP   None             <none>        2181/TCP,2888/TCP,3888/TCP            118s
```

### Deploy Kafka UI

[UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme) is a free and open-source Kafka management application, and it is deployed as a Kubernetes Deployment. The Deployment is configured to have a single instance, and the Kafka cluster access details are specified as environment variables.

```yaml
# kafka/manifests/kafka-ui.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: kafka-ui
  name: kafka-ui
spec:
  type: ClusterIP
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
          resources:
            requests:
              memory: 256Mi
              cpu: 250m
            limits:
              memory: 512Mi
              cpu: 500m
```

The Kafka management app (*kafka-ui*) can be deployed using `kubectl create`.

```bash
kubectl create -f kafka/manifests/kafka-ui.yaml

kubectl get all -l app=kafka-ui
# NAME                            READY   STATUS    RESTARTS   AGE
# pod/kafka-ui-65dbbc98dc-zl5gv   1/1     Running   0          35s

# NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# service/kafka-ui   ClusterIP   10.109.14.33   <none>        8080/TCP   36s

# NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/kafka-ui   1/1     1            1           35s

# NAME                                  DESIRED   CURRENT   READY   AGE
# replicaset.apps/kafka-ui-65dbbc98dc   1         1         1       35s
```

We can use `kubectl port-forward` to connect to the *kafka-ui* server running in a Kubernetes cluster.

```bash
kubectl port-forward svc/kafka-ui 8080
```

![](kafka-ui.png#center)

## Develop Stream Processing App

A streaming processing application is developed using PyFlink and it is packaged in a custom Docker image for deployment.

### PyFlink Code

The application begins with reading text messages from a Kafka topic named *input-topic*, followed by extracting words by splitting the messages. Next, as we are going to calculate the average lengths of all words, all of them are added to a Tumbling window of 5 seconds - we use a processing time window for simplicity. After that, it calculates the average length of words in a window. Note that, as we are going to include the window start and end timestamps, the *ProcessAllWindowFunction* is used instead of the *AggregateFunction*. Finally, the output reocrds are sent into a Kafka topic named *output-topic-flink*.

```python
# flink/word_len.py
import os
import re
import json
import datetime
import logging
import typing

from pyflink.common import WatermarkStrategy
from pyflink.datastream import (
    DataStream,
    StreamExecutionEnvironment,
    RuntimeExecutionMode,
)
from pyflink.common.typeinfo import Types
from pyflink.datastream.functions import ProcessAllWindowFunction
from pyflink.datastream.window import TumblingProcessingTimeWindows, Time, TimeWindow
from pyflink.datastream.connectors.kafka import (
    KafkaSource,
    KafkaOffsetsInitializer,
    KafkaSink,
    KafkaRecordSerializationSchema,
    DeliveryGuarantee,
)
from pyflink.common.serialization import SimpleStringSchema


def tokenize(element: str):
    for word in re.findall(r"[A-Za-z\']+", element):
        yield word


def create_message(element: typing.Tuple[str, str, float]):
    return json.dumps(dict(zip(["window_start", "window_end", "avg_len"], element)))


class AverageWindowFunction(ProcessAllWindowFunction):
    def process(
        self, context: ProcessAllWindowFunction.Context, elements: typing.Iterable[str]
    ) -> typing.Iterable[typing.Tuple[str, str, float]]:
        window: TimeWindow = context.window()
        window_start = datetime.datetime.fromtimestamp(window.start // 1000).isoformat(
            timespec="seconds"
        )
        window_end = datetime.datetime.fromtimestamp(window.end // 1000).isoformat(
            timespec="seconds"
        )
        length, count = 0, 0
        for e in elements:
            length += len(e)
            count += 1
        result = window_start, window_end, length / count if count else float("NaN")
        logging.info(f"AverageWindowFunction: result - {result}")
        yield result


def define_workflow(source_system: DataStream):
    return (
        source_system.flat_map(tokenize)
        .window_all(TumblingProcessingTimeWindows.of(Time.seconds(5)))
        .process(AverageWindowFunction())
    )


if __name__ == "__main__":
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_runtime_mode(RuntimeExecutionMode.STREAMING)
    env.enable_checkpointing(5000)
    env.set_parallelism(3)

    input_source = (
        KafkaSource.builder()
        .set_bootstrap_servers(os.getenv("BOOTSTRAP_SERVERS", "localhost:29092"))
        .set_topics(os.getenv("INPUT_TOPIC", "input-topic"))
        .set_group_id(os.getenv("GROUP_ID", "flink-word-len"))
        .set_starting_offsets(KafkaOffsetsInitializer.latest())
        .set_value_only_deserializer(SimpleStringSchema())
        .build()
    )

    input_stream = env.from_source(
        input_source, WatermarkStrategy.no_watermarks(), "input_source"
    )

    output_sink = (
        KafkaSink.builder()
        .set_bootstrap_servers(os.getenv("BOOTSTRAP_SERVERS", "localhost:29092"))
        .set_record_serializer(
            KafkaRecordSerializationSchema.builder()
            .set_topic(os.getenv("OUTPUT_TOPIC", "output-topic-flink"))
            .set_value_serialization_schema(SimpleStringSchema())
            .build()
        )
        .set_delivery_guarantee(DeliveryGuarantee.AT_LEAST_ONCE)
        .build()
    )

    define_workflow(input_stream).map(
        create_message, output_type=Types.STRING()
    ).sink_to(output_sink).name("output_sink")

    env.execute("avg-word-length-flink")
```

### Build Docker Image

A custom Docker image named *flink-python-example:1.17* is created for deployment. Based on the official *flink:1.17* image, it downloads dependnent Jar files, installs Python and the apache-flink package, and adds the application source.

```Dockerfile
# flink/Dockerfile
FROM flink:1.17

ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION:-3.10.13}
ARG FLINK_VERSION
ENV FLINK_VERSION=${FLINK_VERSION:-1.17.2}

## download connector libs
RUN wget -P /opt/flink/lib/ https://repo.maven.apache.org/maven2/org/apache/kafka/kafka-clients/3.2.3/kafka-clients-3.2.3.jar \
  && wget -P /opt/flink/lib/ https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/$FLINK_VERSION/flink-sql-connector-kafka-$FLINK_VERSION.jar

## install python
RUN apt-get update -y && \
  apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev libffi-dev liblzma-dev && \
  wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
  tar -xvf Python-${PYTHON_VERSION}.tgz && \
  cd Python-${PYTHON_VERSION} && \
  ./configure --without-tests --enable-shared && \
  make -j6 && \
  make install && \
  ldconfig /usr/local/lib && \
  cd .. && rm -f Python-${PYTHON_VERSION}.tgz && rm -rf Python-${PYTHON_VERSION} && \
  ln -s /usr/local/bin/python3 /usr/local/bin/python && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

## install pip packages
RUN pip3 install apache-flink==${FLINK_VERSION}

## add python script
USER flink
RUN mkdir /opt/flink/usrlib
ADD word_len.py /opt/flink/usrlib/word_len.py
```

As the custom image should be accessible in the minikube cluster, we should point the terminal's docker-cli to the minikube's Docker engine. Then, the image can be built as usual using `docker build`.

```bash
# point the docker-cli to the minikube's Docker engine
eval $(minikube docker-env)
# build image
docker build -t flink-python-example:1.17 flink/
```

## Deploy Stream Processing App

The Pyflink application is be deployed as a single job of a Flink cluster using the Flink Kubernetes Operator. Then, we check the output of the application by sending text messages to the input Kafka topic.

### Deploy Flink Kubernetes Operator

We first need to install the [certificate manager](https://github.com/cert-manager/cert-manager) on the minikube cluster to enable adding the webhook component. Then, the operator can be installed using a Helm chart, and the version 1.8.0 is installed in the post.

```bash
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
helm repo add flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-1.8.0/
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator
# NAME: flink-kubernetes-operator
# LAST DEPLOYED: Wed May 29 05:05:08 2024
# NAMESPACE: default
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None

helm list
# NAME                            NAMESPACE       REVISION        UPDATED                                         STATUS          CHART                           APP VERSION
# flink-kubernetes-operator       default         1               2024-05-29 05:05:08.241071054 +1000 AEST        deployed        flink-kubernetes-operator-1.8.0 1.8.0
```

### Deploy PyFlink App

The PyFlink app is deployed as a single job of a Flink cluster using the *FlinkDeployment* custom resource. In the manifest file, we configure common properties such as the Docker image, Flink version, cluster configuration and pod template. These properties are applied to the Flink job manager and task manager where only the replica and resource are specified additionally. Finally, the PyFlink app is added as a job where the main *PythonDriver* entry class requires the paths of the Python executable and application source script. See this page for details about the [*FlinkDeployment*](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-release-1.8/docs/custom-resource/overview/) resource.

```yaml
# flink/word_len.yml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: flink-word-len
spec:
  image: flink-python-example:1.17
  imagePullPolicy: Never
  flinkVersion: v1_17
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "5"
  serviceAccount: flink
  podTemplate:
    spec:
      containers:
        - name: flink-main-container
          env:
            - name: BOOTSTRAP_SERVERS
              value: demo-cluster-kafka-bootstrap:9092
            - name: INPUT_TOPIC
              value: input-topic
            - name: GROUP_ID
              value: flink-word-len
            - name: OUTPUT_TOPIC
              value: output-topic-flink
          volumeMounts:
            - mountPath: /opt/flink/log
              name: flink-logs
            - mountPath: /tmp/flink-artifact-staging
              name: flink-staging
      volumes:
        - name: flink-logs
          emptyDir: {}
        - name: flink-staging
          emptyDir: {}
  jobManager:
    resource:
      memory: "2048m"
      cpu: 1
  taskManager:
    replicas: 2
    resource:
      memory: "2048m"
      cpu: 1
  job:
    jarURI: local:///opt/flink/opt/flink-python-1.17.2.jar
    entryClass: "org.apache.flink.client.python.PythonDriver"
    args:
      [
        "-pyclientexec",
        "/usr/local/bin/python3",
        "-py",
        "/opt/flink/usrlib/word_len.py",
      ]
    parallelism: 3
    upgradeMode: stateless
```

Before we deploy the PyFlink app, make sure the input topic is created. We can create it using *kafka-ui* easily.

![](topic-create.png#center)

The app can be deployed using `kubectl create`, and it creates the Flink job manager, task manager and associated services.

```bash
kubectl create -f flink/word_len.yml
# flinkdeployment.flink.apache.org/flink-word-len created

kubectl get all -l app=flink-word-len
# NAME                                  READY   STATUS    RESTARTS   AGE
# pod/flink-word-len-854cf856d8-w8cjf   1/1     Running   0          78s
# pod/flink-word-len-taskmanager-1-1    1/1     Running   0          66s

# NAME                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
# service/flink-word-len        ClusterIP   None            <none>        6123/TCP,6124/TCP   78s
# service/flink-word-len-rest   ClusterIP   10.107.62.132   <none>        8081/TCP            78s

# NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/flink-word-len   1/1     1            1           78s

# NAME                                        DESIRED   CURRENT   READY   AGE
# replicaset.apps/flink-word-len-854cf856d8   1         1         1       78s
```

The Flink web UI can be accessed using `kubectl port-forward` on port 8081. In the job graph, we see there are two tasks where the first task is performed until tokenizing input messages and the second one is up to sending the average word length records to the output topic.

```bash
kubectl port-forward svc/flink-word-len-rest 8081
```

![](flink-ui.png#center)

### Kafka Producer

A simple Python Kafka producer is created to check the output of the application. The producer app sends random text from the [Faker](https://faker.readthedocs.io/en/master/) package to the input Kafka topic every 1 second by default.

```python
# kafka/client/producer.py
import os
import time

from faker import Faker
from kafka import KafkaProducer


class TextProducer:
    def __init__(self, bootstrap_servers: list, topic_name: str) -> None:
        self.bootstrap_servers = bootstrap_servers
        self.topic_name = topic_name
        self.kafka_producer = self.create_producer()

    def create_producer(self):
        """
        Returns a KafkaProducer instance
        """
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            value_serializer=lambda v: v.encode("utf-8"),
        )

    def send_to_kafka(self, text: str, timestamp_ms: int = None):
        """
        Sends text to a Kafka topic.
        """
        try:
            args = {"topic": self.topic_name, "value": text}
            if timestamp_ms is not None:
                args = {**args, **{"timestamp_ms": timestamp_ms}}
            self.kafka_producer.send(**args)
            self.kafka_producer.flush()
        except Exception as e:
            raise RuntimeError("fails to send a message") from e


if __name__ == "__main__":
    producer = TextProducer(
        os.getenv("BOOTSTRAP_SERVERS", "localhost:29092"),
        os.getenv("TOPIC_NAME", "input-topic"),
    )
    fake = Faker()

    num_events = 0
    while True:
        num_events += 1
        text = fake.text()
        producer.send_to_kafka(text)
        if num_events % 5 == 0:
            print(f"<<<<<{num_events} text sent... current>>>>\n{text}")
        time.sleep(int(os.getenv("DELAY_SECONDS", "1")))
```

The Kafka bootstrap server can be exposed on port 29092 using `kubectl port-forward` and the producer app can be started by executing the Python script.

```bash
kubectl port-forward svc/demo-cluster-kafka-external-bootstrap 29092

python kafka/client/producer.py
```

We can see the output topic (*output-topic-flink*) is created on *kafka-ui*.

![](kafka-topics.png#center)

Also, we can check the output messages are created as expected in the *Topics* tab. 

![](output-topic-messages.png#center)

## Delete Resources

The Kubernetes resources and minikube cluster can be deleted as shown below.

```bash
## delete flink operator and related resoruces
kubectl delete flinkdeployment/flink-word-len
helm uninstall flink-kubernetes-operator
kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml

## delete kafka cluster and related resources
STRIMZI_VERSION="0.39.0"
kubectl delete -f kafka/manifests/kafka-cluster.yaml
kubectl delete -f kafka/manifests/kafka-ui.yaml
kubectl delete -f kafka/manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## delete minikube
minikube delete
```

## Summary

Flink Kubernetes Operator acts as a control plane to manage the complete deployment lifecycle of Apache Flink applications. With the operator, we can simplify deployment and management of Python stream processing applications on Kubernetes. In this post, we discussed how to deploy a PyFlink application on Kubernetes. We first deployed a Kafka cluster on minikube as the source and sink of the PyFlink application are Kafka topics. Then, the application source is packaged in a custom Docker image and deployed on the minikube cluster using the Flink Kubernetes Operator. Finally, the output of the application is checked by sending messages to the input Kafka topic using a Python producer application.