---
title: Deploy Python Stream Processing App on Kubernetes - Part 2 Beam Pipeline on Flink Runner
date: 2024-06-06
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Deploy Python Stream Processing App on Kubernetes
categories:
  - Data Streaming
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - Apache Kafka
  - Kubernetes
  - Minikube
  - Python
  - Docker
authors:
  - JaehyeonKim
images: []
# description: In this post, we develop an Apache Beam pipeline using the Python SDK and deploy it on an Apache Flink cluster via the Apache Flink Runner. Same as Part I, we deploy a Kafka cluster using the Strimzi Operator on a minikube cluster as the pipeline uses Apache Kafka topics for its data source and sink. Then, we develop the pipeline as a Python package and add the package to a custom Docker image so that Python user code can be executed externally. For deployment, we create a Flink session cluster via the Flink Kubernetes Operator, and deploy the pipeline using a Kubernetes job. Finally, we check the output of the application by sending messages to the input Kafka topic using a Python producer application.
---

In this post, we develop an [Apache Beam](https://beam.apache.org/) pipeline using the [Python SDK](https://beam.apache.org/documentation/sdks/python/) and deploy it on an [Apache Flink](https://flink.apache.org/) cluster via the [Apache Flink Runner](https://beam.apache.org/documentation/runners/flink/). Same as [Part I](/blog/2024-05-30-beam-deploy-1), we deploy a Kafka cluster using the [Strimzi Operator](https://strimzi.io/) on a [minikube](https://minikube.sigs.k8s.io/docs/) cluster as the pipeline uses [Apache Kafka](https://kafka.apache.org/) topics for its data source and sink. Then, we develop the pipeline as a Python package and add the package to a custom Docker image so that Python user code can be executed externally. For deployment, we create a Flink session cluster via the [Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/), and deploy the pipeline using a Kubernetes job. Finally, we check the output of the application by sending messages to the input Kafka topic using a Python producer application.

<!--more-->

* [Part 1 PyFlink Application](/blog/2024-05-30-beam-deploy-1)
* [Part 2 Beam Pipeline on Flink Runner](#) (this post)

## Resources to run a Python Beam pipeline on Flink

We develop an Apache Beam pipeline using the Python SDK and deploy it on an [Apache Flink](https://flink.apache.org/) cluster via the [Apache Flink Runner](https://beam.apache.org/documentation/runners/flink/). While the Flink cluster is created by the [Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/), we need two components (**Job Service** and [**SDK Harness**](https://beam.apache.org/documentation/runtime/sdk-harness-config/)) to run the pipeline on the *Flink Runner*. Roughly speaking, the former converts details about a Python pipeline into a format that the Flink runner can understand while the Python user code is executed by the latter - see [this post](/blog/2024-04-18-beam-local-dev-3) for more details. Note that the Python SDK provides convenience wrappers to manage those components, and it can be utilised by specifying *FlinkRunner* in the pipeline option (i.e. `--runner=FlinkRunner`). We let the *Job Service* be managed automatically while relying on our own *SDK Harness* as a sidecar container for simplicity. Also, we need the **Java IO Expansion Service** as an extra because the pipeline uses [Apache Kafka](https://kafka.apache.org/) topics for its data source and sink, and the *Kafka Connector I/O* is developed in Java. Simply put, the expansion service is used to serialise data for the Java SDK.

## Setup Kafka Cluster

Same as [Part I](/blog/2024-05-30-beam-deploy-1), we deploy a Kafka cluster using the [Strimzi Operator](https://strimzi.io/) on a [minikube](https://minikube.sigs.k8s.io/docs/) cluster. Also, we create [UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme) to facilitate development. See [Part I](/blog/2024-05-30-beam-deploy-1) for details about how to create them. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-deploy).

When a Kafka cluster is created successfully, we can see the following resources.

```bash
kubectl get po,strimzipodsets.core.strimzi.io,svc -l app.kubernetes.io/instance=demo-cluster
NAME                           READY   STATUS    RESTARTS   AGE
pod/demo-cluster-kafka-0       1/1     Running   0          4m16s
pod/demo-cluster-zookeeper-0   1/1     Running   0          4m44s

NAME                                                   PODS   READY PODS   CURRENT PODS   AGE
strimzipodset.core.strimzi.io/demo-cluster-kafka       1      1            1              4m17s
strimzipodset.core.strimzi.io/demo-cluster-zookeeper   1      1            1              4m45s

NAME                                            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                               AGE
service/demo-cluster-kafka-bootstrap            ClusterIP   10.100.17.151    <none>        9091/TCP,9092/TCP                     4m17s
service/demo-cluster-kafka-brokers              ClusterIP   None             <none>        9090/TCP,9091/TCP,8443/TCP,9092/TCP   4m17s
service/demo-cluster-kafka-external-0           NodePort    10.104.252.159   <none>        29092:30867/TCP                       4m17s
service/demo-cluster-kafka-external-bootstrap   NodePort    10.98.229.176    <none>        29092:31488/TCP                       4m17s
service/demo-cluster-zookeeper-client           ClusterIP   10.109.80.70     <none>        2181/TCP                              4m46s
service/demo-cluster-zookeeper-nodes            ClusterIP   None             <none>        2181/TCP,2888/TCP,3888/TCP            4m46s
```

The Kafka management app (*kafka-ui*) is deployed as a Kubernetes [*deployment*](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) and exposed by a single [service](https://kubernetes.io/docs/concepts/services-networking/service/).

```bash
kubectl get all -l app=kafka-ui
NAME                            READY   STATUS    RESTARTS   AGE
pod/kafka-ui-65dbbc98dc-xjnvh   1/1     Running   0          10m

NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/kafka-ui   ClusterIP   10.106.116.129   <none>        8080/TCP   10m

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kafka-ui   1/1     1            1           10m

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/kafka-ui-65dbbc98dc   1         1         1       10m
```

We can use `kubectl port-forward` to connect to the *kafka-ui* server running in the minikube cluster on port 8080.

```bash
kubectl port-forward svc/kafka-ui 8080
```

![](kafka-ui.png#center)

## Develop Stream Processing App

We develop an Apache Beam pipeline as a Python package and add it to a custom Docker image, which is used to execute Python user code (*SDK Harness*). We also build another custom Docker image, which adds the Java SDK of Apache Beam to the official Flink base image. This image is used for deploying a Flink cluster as well as for executing Java user code of the *Kafka Connector I/O*.


### Beam Pipeline Code

The application begins with reading text messages from an input Kafka topic, followed by extracting words by splitting the messages (*ReadWordsFromKafka*). Next, the elements (words) are added to a fixed time window of 5 seconds and their average length is calculated (*CalculateAvgWordLen*). Finally, we include the window start/end timestamps and send the updated element to an output Kafka topic (*WriteWordLenToKafka*).

Note that we create a custom *Java IO Expansion Service* (`get_expansion_service`) and add it to the *ReadFromKafka* and *WriteToKafka* transforms of the *Kafka Connector I/O*. Although the *Kafka I/O* provides a function to create that service, it did not work for me (or I do not understand how to make use of it yet). Instead, I ended up creating a custom service as illustrated in [Building Big Data Pipelines with Apache Beam by Jan Lukavský](https://www.packtpub.com/product/building-big-data-pipelines-with-apache-beam/9781800564930). Note further that the expansion service Jar file (*beam-sdks-java-io-expansion-service.jar*) should exist in the Kubernetes [*job*](https://kubernetes.io/docs/concepts/workloads/controllers/job/) that executes the pipeline while the Java SDK (*/opt/apache/beam/boot*) should exist in the runner worker.

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

The pipeline script is added to a Python package under a folder named *word_len*, and a simple module named *run* is created as it should be executed as a module (i.e. `python -m ...`). (I had an error if I execute the pipeline as a script.) Note that this way of packaging is for demonstration only and see [this document](https://beam.apache.org/documentation/sdks/python-pipeline-dependencies/) for a recommended way of packaging a pipeline. 

```python
# beam/word_len/run.py
from . import *

run()
```

Overall, the pipeline package is structured as shown below.

```bash
tree beam/word_len

beam/word_len
├── __init__.py
├── run.py
└── word_len.py
```

### Build Docker Images

As mentioned earlier, we build a custom Docker image (*beam-python-example:1.16*) that is used for deploying a Flink cluster as well as for executing Java user code of the *Kafka Connector I/O*.

```Dockerfile
# beam/Dockerfile
FROM flink:1.16

COPY --from=apache/beam_java11_sdk:2.56.0 /opt/apache/beam/ /opt/apache/beam/
```

We also build another custom Docker image (*beam-python-harness:2.56.0*) to run Python user code (*SDK Harness*). From the Python SDK Docker image, it first installs JDK Development Kit (JDK) and downloads the *Java IO Expansion Service* Jar file. Then, Beam pipeline packages are copied to the */app* folder, and it ends up adding the app folder into the *PYTHONPATH* environment variable, which makes the packages to be searchable.

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

As the custom images should be accessible in the minikube cluster, we should point the terminal's docker-cli to the minikube's Docker engine. Then, the images can be built as usual using `docker build`.

```bash
eval $(minikube docker-env)
docker build -t beam-python-example:1.16 beam/
docker build -t beam-python-harness:2.56.0 -f beam/Dockerfile-python-harness beam/
```

## Deploy Stream Processing App

The Beam pipeline is executed on a [Flink session cluster](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/custom-resource/overview/#session-cluster-deployments), which is deployed via the Flink Kubernetes Operator. Note that the [application deployment mode](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/custom-resource/overview/#application-deployments) where the Beam pipeline is deployed as a Flink job doesn't seem to work (or I don't understand how to do so yet) due to either job submission timeout error or failing to upload the job artifact. After the pipeline is deployed, we check the output of the application by sending text messages to the input Kafka topic.

### Deploy Flink Kubernetes Operator

We first need to install the [certificate manager](https://github.com/cert-manager/cert-manager) on the minikube cluster to enable adding the webhook component. Then, the operator can be installed using a Helm chart, and the version 1.8.0 is installed in the post.

```bash
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
helm repo add flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-1.8.0/
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator
# NAME: flink-kubernetes-operator
# LAST DEPLOYED: Mon Jun 03 21:37:45 2024
# NAMESPACE: default
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None

helm list
# NAME                            NAMESPACE       REVISION        UPDATED                                         STATUS          CHART                           APP VERSION
# flink-kubernetes-operator       default         1               2024-06-03 21:37:45.579302452 +1000 AEST        deployed        flink-kubernetes-operator-1.8.0 1.8.0
```

### Deploy Beam Pipeline

First, we create a Flink session cluster. In the manifest file, we configure common properties such as the Docker image, Flink version, cluster configuration and pod template. These properties are applied to the Flink job manager and task manager, and only the replica and resource are specified additionally to them. Note that we add a sidecar container to the task manager and this *SDK Harness* container is configured to execute Python user code - see the job configuration below.

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

The pipeline is deployed using a Kubernetes job, and the custom *SDK Harness* image is used to execute the pipeline as a module. The first two arguments are application specific arguments and the rest are arguments for pipeline options. The pipeline arguments are self-explanatory, or you can check available options in the [pipeline options source](https://github.com/apache/beam/blob/master/sdks/python/apache_beam/options/pipeline_options.py) and [Flink Runner document](https://beam.apache.org/documentation/runners/flink/). Note that, to execute Python user code in the sidecar container, we set the environment type to *EXTERNAL* and environment config to *localhost:50000*.
 
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
            - "--parallelism=3"
            - "--flink_submit_uber_jar"
            - "--environment_type=EXTERNAL"
            - "--environment_config=localhost:50000"
            - "--checkpointing_interval=10000"
      restartPolicy: Never
```

The session cluster and job can be deployed using `kubectl create`, and the former creates the *FlinkDeployment* custom resource, which manages the job manager deployment, task manager pod and associated services. When we check the log of the job's pod, we see that it starts the *Job Service* after downloading the Jar file, uploads the pipeline artifact, submit the pipeline as a Flink job and continuously monitors the job status.

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
# INFO:apache_beam.runners.portability.abstract_job_service:Artifact server started on port 43287
# DEBUG:apache_beam.runners.portability.abstract_job_service:Prepared job 'job' as 'job-edc1c2f1-80ef-48b7-af14-7e6fc86f338a'
# INFO:apache_beam.runners.portability.abstract_job_service:Running job 'job-edc1c2f1-80ef-48b7-af14-7e6fc86f338a'
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "POST /v1/jars/upload HTTP/1.1" 200 148
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "POST /v1/jars/e1984c45-d8bc-4aa1-9b66-369a23826921_beam.jar/run HTTP/1.1" 200 44
# INFO:apache_beam.runners.portability.flink_uber_jar_job_server:Started Flink job as a403cb2f92fecee65b8fd7cc8ac6e68a
# INFO:apache_beam.runners.portability.portable_runner:Job state changed to STOPPED
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/a403cb2f92fecee65b8fd7cc8ac6e68a/execution-result HTTP/1.1" 200 31
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/a403cb2f92fecee65b8fd7cc8ac6e68a/execution-result HTTP/1.1" 200 31
# INFO:apache_beam.runners.portability.portable_runner:Job state changed to RUNNING
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): word-len-cluster-rest:8081
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/a403cb2f92fecee65b8fd7cc8ac6e68a/execution-result HTTP/1.1" 200 31
# DEBUG:urllib3.connectionpool:http://word-len-cluster-rest:8081 "GET /v1/jobs/a403cb2f92fecee65b8fd7cc8ac6e68a/execution-result HTTP/1.1" 200 31
# ...
```

After deployment is complete, we can see the following Flink session cluster and job related resources.

```bash
kubectl get all -l app=word-len-cluster
# NAME                                    READY   STATUS    RESTARTS   AGE
# pod/word-len-cluster-7c98f6f868-d4hbx   1/1     Running   0          5m32s
# pod/word-len-cluster-taskmanager-1-1    2/2     Running   0          4m3s

# NAME                            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
# service/word-len-cluster        ClusterIP   None           <none>        6123/TCP,6124/TCP   5m32s
# service/word-len-cluster-rest   ClusterIP   10.104.23.28   <none>        8081/TCP            5m32s

# NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/word-len-cluster   1/1     1            1           5m32s

# NAME                                          DESIRED   CURRENT   READY   AGE
# replicaset.apps/word-len-cluster-7c98f6f868   1         1         1       5m32s

kubectl get all -l app=word-len-job
# NAME                     READY   STATUS    RESTARTS   AGE
# pod/word-len-job-24r6q   1/1     Running   0          5m24s

# NAME                     COMPLETIONS   DURATION   AGE
# job.batch/word-len-job   0/1           5m24s      5m24s
```

The Flink web UI can be accessed using `kubectl port-forward` on port 8081. In the job graph, we see there are two tasks where the first task is performed until adding word elements into a fixed time window and the second one is up to sending the average word length records to the output topic.

```bash
kubectl port-forward svc/flink-word-len-rest 8081
```

![](flink-ui.png#center)

The *Kafka I/O* automatically creates a topic if it doesn't exist, and we can see the input topic is created on *kafka-ui*.

![](kafka-topics-1.png#center)

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

![](kafka-topics-2.png#center)

Also, we can check the output messages are created as expected in the *Topics* tab. 

![](output-topic-messages.png#center)

## Delete Resources

The Kubernetes resources and minikube cluster can be deleted as shown below.

```bash
## delete flink operator and related resoruces
kubectl delete -f beam/word_len_cluster.yml
kubectl delete -f beam/word_len_job.yml
helm uninstall flink-kubernetes-operator
helm repo remove flink-operator-repo
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

In this series, we discuss how to deploy Python stream processing applications on Kubernetes, and we developed a PyFlink application in the previous post. In this post, we developed an Apache Beam pipeline using the Python SDK and deployed it on an Apache Flink cluster via the Apache Flink Runner. Same as the previous post, we deployed a Kafka cluster using the Strimzi Operator on a minikube cluster as the pipeline uses Apache Kafka topics for its data source and sink. Then, we developed the pipeline as a Python package and added the package to a custom Docker image so that Python user code can be executed externally. For deployment, we created a Flink session cluster via the Flink Kubernetes Operator, and deployed the pipeline using a Kubernetes job. Finally, we checked the output of the application by sending messages to the input Kafka topic using a Python producer application.
