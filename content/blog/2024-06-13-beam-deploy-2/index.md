---
title: Deploy Python Streaming Processing App on Kubernetes - Part 2 Beam Pipeline on Flink Runner
date: 2024-06-13
draft: true
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
  - Apache Beam
  - Apache Flink
  - Apache Kafka
  - Kubernetes
  - Python
  - Docker
authors:
  - JaehyeonKim
images: []
description: to be updated 
---

* [Part 1 PyFlink Applicatin](/blog/2024-06-06-beam-deploy-1)
* [Part 2 Beam Pipeline on Flink Runner](#) (this post)

## Deploy Kafka Cluster

The Kafka cluster is deployed using the [Strimzi Operator](https://strimzi.io/) on a [Minikube](https://minikube.sigs.k8s.io/docs/) cluster. We install Strimzi version 0.39.0 and Kubernetes version 1.25.3. Once the [Minikube CLI](https://minikube.sigs.k8s.io/docs/start/) and [Docker](https://www.docker.com/) are installed, a Minikube cluster can be created by specifying the desired Kubernetes version as shown below.

The Kafka management app (*kafka-ui*) can be deployed using the *kubectl create* command as shown below.

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

We can use the [*minikube service*](https://minikube.sigs.k8s.io/docs/handbook/accessing/) command to obtain the Kubernetes URL for the *kafka-ui* service.

```bash
kubectl port-forward svc/kafka-ui 8080
```

![](kafka-ui.png#center)

## Develop Stream Processing App

### Beam Pipeline Code

```python
# beam/word_len/word_len.py
import json
import argparse
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.io import kafka
from apache_beam.transforms.window import FixedWindows
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from apache_beam.transforms.external import JavaJarExpansionService


def get_expansion_service(
    jar="/opt/apache/beam/jars/beam-sdks-java-io-expansion-service.jar", args=None
):
    if args == None:
        args = [
            "--defaultEnvironmentType=PROCESS",
            '--defaultEnvironmentConfig={"command": "/opt/apache/beam/boot"}',
            "--experiments=use_deprecated_read",
        ]
    return JavaJarExpansionService(jar, ["{{PORT}}"] + args)


class WordAccum(typing.NamedTuple):
    length: int
    count: int


beam.coders.registry.register_coder(WordAccum, beam.coders.RowCoder)


def decode_message(kafka_kv: tuple, verbose: bool = False):
    if verbose:
        print(kafka_kv)
    return kafka_kv[1].decode("utf-8")


def tokenize(element: str):
    return re.findall(r"[A-Za-z\']+", element)


def create_message(element: typing.Tuple[str, str, float]):
    msg = json.dumps(dict(zip(["window_start", "window_end", "avg_len"], element)))
    print(msg)
    return "".encode("utf-8"), msg.encode("utf-8")


class AverageFn(beam.CombineFn):
    def create_accumulator(self):
        return WordAccum(length=0, count=0)

    def add_input(self, mutable_accumulator: WordAccum, element: str):
        length, count = tuple(mutable_accumulator)
        return WordAccum(length=length + len(element), count=count + 1)

    def merge_accumulators(self, accumulators: typing.List[WordAccum]):
        lengths, counts = zip(*accumulators)
        return WordAccum(length=sum(lengths), count=sum(counts))

    def extract_output(self, accumulator: WordAccum):
        length, count = tuple(accumulator)
        return length / count if count else float("NaN")

    def get_accumulator_coder(self):
        return beam.coders.registry.get_coder(WordAccum)


class AddWindowTS(beam.DoFn):
    def process(self, avg_len: float, win_param=beam.DoFn.WindowParam):
        yield (
            win_param.start.to_rfc3339(),
            win_param.end.to_rfc3339(),
            avg_len,
        )


class ReadWordsFromKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topics: typing.List[str],
        group_id: str,
        verbose: bool = False,
        expansion_service: typing.Any = None,
        label: str | None = None,
    ) -> None:
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topics = topics
        self.group_id = group_id
        self.verbose = verbose
        self.expansion_service = expansion_service

    def expand(self, input: pvalue.PBegin):
        return (
            input
            | "ReadFromKafka"
            >> kafka.ReadFromKafka(
                consumer_config={
                    "bootstrap.servers": self.boostrap_servers,
                    "auto.offset.reset": "latest",
                    # "enable.auto.commit": "true",
                    "group.id": self.group_id,
                },
                topics=self.topics,
                timestamp_policy=kafka.ReadFromKafka.create_time_policy,
                commit_offset_in_finalize=True,
                expansion_service=self.expansion_service,
            )
            | "DecodeMessage" >> beam.Map(decode_message)
            | "Tokenize" >> beam.FlatMap(tokenize)
        )


class CalculateAvgWordLen(beam.PTransform):
    def expand(self, input: pvalue.PCollection):
        return (
            input
            | "Windowing" >> beam.WindowInto(FixedWindows(size=5))
            | "GetAvgWordLength" >> beam.CombineGlobally(AverageFn()).without_defaults()
        )


class WriteWordLenToKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topic: str,
        expansion_service: typing.Any = None,
        label: str | None = None,
    ) -> None:
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topic = topic
        self.expansion_service = expansion_service

    def expand(self, input: pvalue.PCollection):
        return (
            input
            | "AddWindowTS" >> beam.ParDo(AddWindowTS())
            | "CreateMessages"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
            | "WriteToKafka"
            >> kafka.WriteToKafka(
                producer_config={"bootstrap.servers": self.boostrap_servers},
                topic=self.topic,
                expansion_service=self.expansion_service,
            )
        )


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--deploy",
        dest="deploy",
        action="store_true",
        default="Flag to indicate whether to deploy to a cluster",
    )
    parser.add_argument(
        "--bootstrap_servers",
        dest="bootstrap",
        default="host.docker.internal:29092",
        help="Kafka bootstrap server addresses",
    )
    parser.add_argument(
        "--input_topic",
        dest="input",
        default="input-topic",
        help="Kafka input topic name",
    )
    parser.add_argument(
        "--output_topic",
        dest="output",
        default="output-topic-beam",
        help="Kafka output topic name",
    )
    parser.add_argument(
        "--group_id",
        dest="group",
        default="beam-word-len",
        help="Kafka output group ID",
    )

    known_args, pipeline_args = parser.parse_known_args(argv)

    print(known_args)
    print(pipeline_args)

    # We use the save_main_session option because one or more DoFn's in this
    # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session

    expansion_service = None
    if known_args.deploy is True:
        expansion_service = get_expansion_service()

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | "ReadWordsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap,
                topics=[known_args.input],
                group_id=known_args.group,
                expansion_service=expansion_service,
            )
            | "CalculateAvgWordLen" >> CalculateAvgWordLen()
            | "WriteWordLenToKafka"
            >> WriteWordLenToKafka(
                bootstrap_servers=known_args.bootstrap,
                topic=known_args.output,
                expansion_service=expansion_service,
            )
        )

        logging.getLogger().setLevel(logging.DEBUG)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```


```python
# beam/word_len/run.py
from . import *

run()
```

### Build Docker Images

```Dockerfile
# beam/Dockerfile
FROM flink:1.16

COPY --from=apache/beam_java11_sdk:2.56.0 /opt/apache/beam/ /opt/apache/beam/
```

```Dockerfile
# beam/Dockerfile-python-harness
FROM apache/beam_python3.10_sdk:2.56.0

ARG BEAM_VERSION
ENV BEAM_VERSION=${BEAM_VERSION:-2.56.0}
ENV REPO_BASE_URL=https://repo1.maven.org/maven2/org/apache/beam

RUN apt-get update && apt-get install -y default-jdk

RUN mkdir -p /opt/apache/beam/jars \
  && wget ${REPO_BASE_URL}/beam-sdks-java-io-expansion-service/${BEAM_VERSION}/beam-sdks-java-io-expansion-service-${BEAM_VERSION}.jar \
          --progress=bar:force:noscroll -O /opt/apache/beam/jars/beam-sdks-java-io-expansion-service.jar

COPY word_len /app/word_len
COPY word_count /app/word_count

ENV PYTHONPATH="$PYTHONPATH:/app"
```

```bash
eval $(minikube docker-env)
docker build -t beam-python-example:1.16 beam/
docker build -t beam-python-harness:2.56.0 beam/ -f beam/Dockerfile-python-harness beam/
```

## Deploy Stream Processing App

### Deploy Flink Kubernetes Operator

```bash
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
helm repo add flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-1.8.0/
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator
# NAME: flink-kubernetes-operator
# LAST DEPLOYED: Wed May 29 05:48:07 2024
# NAMESPACE: default
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None

helm list
# NAME                            NAMESPACE       REVISION        UPDATED                                         STATUS          CHART                           APP VERSION
# flink-kubernetes-operator       default         1               2024-05-29 05:48:07.957068852 +1000 AEST        deployed        flink-kubernetes-operator-1.8.0 1.8.0
```

### Deploy Beam Pipeline

```yaml
# beam/word_len_cluster.yml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: word-len-cluster
spec:
  image: beam-python-example:1.16
  imagePullPolicy: Never
  flinkVersion: v1_16
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "10"
  serviceAccount: flink
  podTemplate:
    spec:
      containers:
        - name: flink-main-container
          volumeMounts:
            - mountPath: /opt/flink/log
              name: flink-logs
      volumes:
        - name: flink-logs
          emptyDir: {}
  jobManager:
    resource:
      memory: "2048Mi"
      cpu: 2
  taskManager:
    replicas: 1
    resource:
      memory: "2048Mi"
      cpu: 2
    podTemplate:
      spec:
        containers:
          - name: python-harness
            image: beam-python-harness:2.56.0
            args: ["-worker_pool"]
            ports:
              - containerPort: 50000
                name: harness-port
```

```yaml
# beam/word_len_job.yml
apiVersion: batch/v1
kind: Job
metadata:
  name: word-len-job
spec:
  template:
    metadata:
      labels:
        app: word-len-job
    spec:
      containers:
        - name: beam-word-len-job
          image: beam-python-harness:2.56.0
          command: ["python"]
          args:
            - "-m"
            - "word_len.run"
            - "--deploy"
            - "--bootstrap_servers=demo-cluster-kafka-bootstrap:9092"
            - "--runner=FlinkRunner"
            - "--flink_master=word-len-cluster-rest:8081"
            - "--job_name=beam-word-len"
            - "--streaming"
            - "--flink_submit_uber_jar"
            - "--environment_type=EXTERNAL"
            - "--environment_config=localhost:50000"
            - "--checkpointing_interval=10000"
      restartPolicy: Never
```

```bash
kubectl create -f beam/word_len_cluster.yml
# flinkdeployment.flink.apache.org/word-len-cluster created
kubectl create -f beam/word_len_job.yml
# job.batch/word-len-job created

kubectl logs word-len-job-p5rph -f
# WARNING:apache_beam.options.pipeline_options:Unknown pipeline options received: --checkpointing_interval=10000. Ignore if flags are used for internal purposes.
# WARNING:apache_beam.options.pipeline_options:Unknown pipeline options received: --checkpointing_interval=10000. Ignore if flags are used for internal purposes.
# INFO:root:Building pipeline ...
# INFO:apache_beam.runners.portability.flink_runner:Adding HTTP protocol scheme to flink_master parameter: http://word-len-cluster-rest:8081
# WARNING:apache_beam.options.pipeline_options:Unknown pipeline options received: --checkpointing_interval=10000. Ignore if flags are used for internal purposes.
# DEBUG:apache_beam.runners.portability.abstract_job_service:Got Prepare request.
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/config HTTP/1.1" 200 240
# INFO:apache_beam.utils.subprocess_server:Downloading job server jar from https://repo.maven.apache.org/maven2/org/apache/beam/beam-runners-flink-1.16-job-server/2.56.0/beam-runners-flink-1.16-job-server-2.56.0.jar
# INFO:apache_beam.runners.portability.abstract_job_service:Artifact server started on port 36741
# DEBUG:apache_beam.runners.portability.abstract_job_service:Prepared job 'job' as 'job-03f5b32d-ea18-4d62-946f-c29a1a38a1e9'
# INFO:apache_beam.runners.portability.abstract_job_service:Running job 'job-03f5b32d-ea18-4d62-946f-c29a1a38a1e9'
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "POST /v1/jars/upload HTTP/1.1" 200 148
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "POST /v1/jars/b2754da8-844d-4236-bf84-dde39d27861c_beam.jar/run HTTP/1.1" 200 44
# INFO:apache_beam.runners.portability.flink_uber_jar_job_server:Started Flink job as 6e6033f9e987e7a1da7acec706c2d3d5
# INFO:apache_beam.runners.portability.portable_runner:Job state changed to STOPPED
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/6e6033f9e987e7a1da7acec706c2d3d5/execution-result HTTP/1.1" 200 31
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/6e6033f9e987e7a1da7acec706c2d3d5/execution-result HTTP/1.1" 200 31
# INFO:apache_beam.runners.portability.portable_runner:Job state changed to RUNNING
# ...
```

```bash
kubectl port-forward svc/flink-word-len-rest 8081
```

![](flink-ui.png#center)

![](kafka-topics-1.png#center)

### Kafka Producer

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

```bash
kubectl port-forward svc/demo-cluster-kafka-external-bootstrap 29092

python kafka/client/producer.py
```

![](kafka-topics-2.png#center)

![](output-topic-messages.png#center)

## Delete Resources

```bash
kubectl delete -f beam/word_len_cluster.yml
kubectl delete -f beam/word_len_job.yml
helm uninstall flink-kubernetes-operator
kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml

STRIMZI_VERSION="0.39.0"
kubectl delete -f kafka/manifests/kafka-cluster.yaml
kubectl delete -f kafka/manifests/kafka-ui.yaml
kubectl delete -f kafka/manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml
```

## Summary

Apache Beam and Apache Flink are open-source frameworks for parallel, distributed data processing at scale. While PyFlink, Flink's Python API, is limited to build sophisticated data streaming applications, Apache Beam's Python SDK has potential as it supports more capacity to extend and/or customise its features. In this series of posts, we discuss local development of Apache Beam pipelines using Python. In Part 1, a basic Beam pipeline was introduced, followed by demonstrating how to utilise Jupyter notebooks for interactive development. We also covered Beam SQL and Beam DataFrames examples on notebooks.