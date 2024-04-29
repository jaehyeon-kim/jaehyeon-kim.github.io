---
title: Apache Beam Local Development with Python - Part 3 Flink Runner
date: 2024-04-18
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Apache Beam Local Development with Python
categories:
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - Python
  - Jupyter Notebook
authors:
  - JaehyeonKim
images: []
description: Beam pipelines are portable between batch and streaming semantics but not every Runner is equally capable. The Apache Flink Runner supports Python, and it has good features that allow us to develop streaming pipelines effectively. We first discuss the portability layer of Apache Beam as it helps understand (1) how a pipeline developed by the Python SDK can be executed in the Flink Runner that only understands Java JAR and (2) how multiple SDKs can be used in a single pipeline. Then we move on to how to manage local Flink and Kafka clusters using bash scripts. Finally, we end up illustrating a simple streaming pipeline, which reads and writes website visit logs from and to Kafka topics.
---

In this series, we discuss local development of [Apache Beam](https://beam.apache.org/) pipelines using Python. In the previous posts, we mainly talked about Batch pipelines with/without Beam SQL. Beam pipelines are portable between batch and streaming semantics, and we will discuss streaming pipeline development in this and the next posts. While there are multiple Beam Runners, not every Runner supports Python or some Runners have too limited features in streaming semantics - see [Beam Capability Matrix](https://beam.apache.org/documentation/runners/capability-matrix/) for details. So far, the Apache Flink and Google Cloud Dataflow Runners are the best options, and we will use the [Flink Runner](https://beam.apache.org/documentation/runners/flink/) in this series. This post begins with demonstrating the *portability layer* of Apache Beam as it helps understand (1) how a pipeline developed by the Python SDK can be executed in the Flink Runner that only understands Java JAR and (2) how multiple SDKs can be used in a single pipeline. Then we discuss how to start up/tear down local Flink and Kafka clusters using bash scripts. Finally, we end up demonstrating a simple streaming pipeline, which reads and writes website visit logs from and to Kafka topics.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](/blog/2024-03-28-beam-local-dev-1)
* [Part 2 Batch Pipelines](/blog/2024-04-04-beam-local-dev-2)
* [Part 3 Flink Runner](#) (this post)
* [Part 4 Streaming Pipelines](/blog/2024-05-02-beam-local-dev-4)
* Part 5 Testing Pipelines

## Portability Layer

Apache Beam Pipelines are portable on several layers between (1) Beam Runners, (2) batch/streaming semantics and (3) programming languages.

The portability between programming languages are achieved by the portability layer, and it has two components - Apache Beam components and Runner components. Essentially the Beam Runners (Apache Flink, Apache Spark, Google Cloud Datafolow ...) don't have to understand a Beam SDK but are able to execute pipelines built by it regardless.

![](beam-portability-layer.png#center)

Each Runner typically has a coordinator that needs to receive a job submission and creates tasks for worker nodes according to the submission. For example, the coordinator of the Flink Runner is the Flink JobManager, and it receives a Java JAR file for job execution along with the Directed Acyclic Graph (DAG) of transforms, serialized user code and so on.

Then there are two problems to solve.

1. How can a non-Java SDK converts a Beam pipeline into a Java JAR that the Flink Runner understands?
2. How can the Runner's worker nodes execute non-Java user code?

These problems are tackled down by (1) portable pipeline representation, (2) Job Service, and (3) SDK harness.

### Portable pipeline representation

A non-Java SDK converts a Beam pipeline into a portable representation, which mainly includes the Directed Acyclic Graph (DAG) of transforms and serialized user-defined functions (UDFs)/user code - eg beam.Map(...). Protocol buffers are used for this representation, and it is submitted to Job Service once created.

### Job Service

This component receives a portable representation of a pipeline and converts it into a format that a Runner can understand. Note that, when it creates a job, it replaces calls to UDFs with calls to the SDK harness process in which the UDFs are actually executed for the Runner. Also, it instructs the Runner coordinator to create a SDK harness process for each worker.

### SDK harness

As mentioned, calls to UDFs on a Runner worker are delegated to calls in the SDK harness process, and the UDFs are executed using the same SDK that they are created. Note that communication between the Runner worker and the SDK harness process is made by gRPC - an HTTP/2 based protocol that relies on protocol buffers as its serialization mechanism. The harness is specific to SDK and, for the Python SDK, there are multiple options.

- DOCKER (default): User code is executed within a container started on each worker node.
- PROCESS: User code is executed by processes that are automatically started by the runner on each worker node.
- EXTERNAL: User code is dispatched to an external service.
- LOOPBACK: User code is executed within the same process that submitted the pipeline and is useful for local testing.

### Cross-language Pipelines

The portability layer can be extended to cross-language pipelines where transforms are mixed from multiple SDKs. A typical example is the Kafka Connector I/O for the Python SDK where the *ReadFromKafka* and *WriteToKafka* transforms are made by the Java SDK. Also, the SQL transform (*SqlTransform*) of Beam SQL is performed by the Java SDK.

Here the challenge is how to make a non-Java SDK to be able to serialize data for a Java SDK so that its portable pipeline representation can be created! This challenge is handled by the expansion service. Simply put, when a source SDK wants to submit a pipeline to a Runner, it creates its portable pipeline representation. During this process, if it sees an external (cross-language) transform, it sends a request to the expansion service, asking it to expand the transform into a portable representation. Then, the expansion service creates/returns the portable representation, and it is inserted into the complete pipeline representation. For the Python SDK, the expansion service gets started automatically, or we can customize it, for example, to change the SDK harness from DOCKER to PROCESS.

![](expansion-service.png#center)

Note this section is based on [Building Big Data Pipelines with Apache Beam by Jan Lukavský](https://www.packtpub.com/product/building-big-data-pipelines-with-apache-beam/9781800564930) and you can check more details in the book!

## Manage Streaming Environment

The streaming development environment requires local Apache Flink and Apache Kafka clusters. Initially I was going to create a Flink cluster on Docker, but I had an issue that the Kafka Connect I/O fails to resolve Kafka bootstrap addresses. Specifically, for the Kafka I/O, a docker container is launched by the Flink TaskManager with the host network (`--network host`) - remind that the default SDK harness option is DOCKER. Then the SDK harness container looks for Kafka bootstrap addresses in its host, which is the Flink TaskManager container, not the Docker host machine. Therefore, the address resolution fails because the Kafka cluster doesn't run there. It would work with other SDH harness options, but I thought it requires too much setup for local development. On the other hand, the issue no longer applies if we launch a Flink cluster locally, and we will use this approach instead. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-dev-env).

### Flink Cluster

The latest supported version of Apache Flink is 1.16 as of writing this post, and we can download and unpack it in a dedicated folder named *setup* as shown below. Note that some scripts in the *bin* folder should be executable, and their permission is changed at the end.

```bash
$ mkdir setup && cd setup
$ wget https://dlcdn.apache.org/flink/flink-1.16.3/flink-1.16.3-bin-scala_2.12.tgz
$ tar -zxf flink-1.16.3-bin-scala_2.12.tgz
$ chmod -R +x flink-1.16.3/bin/
```

Next, Flink configuration is updated so that the Flink UI is accessible and the number of tasks slots is increased to 10.

```yaml
# setup/flink-1.16.3/config/flink-conf.yaml
 rest.port: 8081                    # uncommented
 rest.address: localhost            # kept as is
 rest.bind-address: 0.0.0.0         # changed from localhost
 taskmanager.numberOfTaskSlots: 10  # updated from 1
```

### Kafka Cluster

A Kafka cluster with 1 broker and 1 Zookeeper node is used for this post together with a Kafka management app (*kafka-ui*). The details of setting up the resources can be found in my *Kafka Development with Docker* series.

- [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
- [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)

Those resources are deployed using Docker Compose with the following configuration file.

```yaml
# setup/docker-compose.yml
version: "3.5"

services:
  zookeeper:
    image: bitnami/zookeeper:3.5
    container_name: zookeeper
    expose:
      - 2181
    networks:
      - appnet
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
    volumes:
      - zookeeper_data:/bitnami/zookeeper
  kafka-0:
    image: bitnami/kafka:2.8.1
    container_name: kafka-0
    expose:
      - 9092
    ports:
      - "29092:29092"
    networks:
      - appnet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=3
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=1
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-ui:
    image: provectuslabs/kafka-ui:v0.7.1
    container_name: kafka-ui
    ports:
      - "8080:8080"
    networks:
      - appnet
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
    depends_on:
      - zookeeper
      - kafka-0

networks:
  appnet:
    name: app-network

volumes:
  zookeeper_data:
    driver: local
    name: zookeeper_data
  kafka_0_data:
    driver: local
    name: kafka_0_data
```

Note that the bootstrap server is exposed on port *29092*, and it can be accessed via *localhost:29092* from the Docker host machine and *host.docker.internal:29092* from a Docker container that is launched with the host network. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below.

```bash
$ cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

### Manage Flink/Kafka Clusters

The Flink and Kafka clusters are managed by bash scripts. They accept three arguments: *-k* or *-f* to launch a Kafka or Flink cluster individually or *-a* to launch both of them. Below shows the startup script, and it creates a Kafka cluster on Docker followed by starting a Flink cluster if conditions are met.

```bash
# setup/start-flink-env.sh
#!/usr/bin/env bash

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--kafka) start_kafka=true;;
        -f|--flink) start_flink=true;;
        -a|--all) start_all=true;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ ! -z $start_all ] &&  [ $start_all = true ]; then
  start_kafka=true
  start_flink=true
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#### start kafka cluster on docker
if [ ! -z $start_kafka ] &&  [ $start_kafka = true ]; then
  docker-compose -f ${SCRIPT_DIR}/docker-compose.yml up -d
fi

#### start local flink cluster
if [ ! -z $start_flink ] && [ $start_flink = true ]; then
  ${SCRIPT_DIR}/flink-1.16.3/bin/start-cluster.sh
fi
```

The teardown script is structured to stop/remove the Kafka-related containers and Docker volumes, stop the Flink cluster and remove unused containers. The last pruning is for cleaning up containers that are created by Java SDK harness processes.

```bash
# setup/stop-flink-env.sh
#!/usr/bin/env bash

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--kafka) stop_kafka=true;;
        -f|--flink) stop_flink=true;;
        -a|--all) stop_all=true;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ ! -z $stop_all ] && [ $stop_all = true ]; then
  stop_kafka=true
  stop_flink=true
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#### stop kafka cluster in docker
if [ ! -z $stop_kafka ] && [ $stop_kafka = true ]; then
    docker-compose -f ${SCRIPT_DIR}/docker-compose.yml down -v
fi

#### stop local flink cluster
if [ ! -z $stop_flink ] && [ $stop_flink = true ]; then
    ${SCRIPT_DIR}/flink-1.16.3/bin/stop-cluster.sh
fi

#### remove all stopped containers
docker container prune -f
```

## Steaming Pipeline

The streaming pipeline is really simple in this post that it just (1) reads/decodes messages from an input Kafka topic named *website-visit*, (2) parses the elements into a pre-defined type of *EventLog* and (3) encodes/sends them into an output Kafka topic named *website-out*.

The pipeline has a number of notable options as shown below. Those that are specific to the Flink Runner are marked in bold, and they can be checked further in the [Flink Runner document](https://beam.apache.org/documentation/runners/flink/).

- *runner* - The name of the Beam Runner, default to *FlinkRunner*.
- *job_name* - The pipeline job name that can be checked eg on the Flink UI.
- *environment_type* - The [SDK harness](https://beam.apache.org/documentation/runtime/sdk-harness-config/) environment type. *LOOPBACK* is selected for development, so that user code is executed within the same process that submitted the pipeline.
- *streaming* - The flag whether to enforce streaming mode or not.
- **parallelism** - The degree of parallelism to be used when distributing operations onto workers.
- *experiments* > *use_deprecated_read* - Use the depreciated read mode for the Kafka IO to work. See [BEAM-11998](https://issues.apache.org/jira/browse/BEAM-11998) for details.
- **checkpointing_interval** - The interval in milliseconds at which to trigger checkpoints of the running pipeline.
- **flink_master** - The address of the Flink Master where the pipeline should be executed. It is automatically set as *localhost:8081* if the *use_own* argument is included. Otherwise, the pipeline runs with an embedded Flink cluster. 

```python
# section3/kafka_io.py
import os
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.io import kafka
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions


class EventLog(typing.NamedTuple):
    ip: str
    id: str
    lat: float
    lng: float
    user_agent: str
    age_bracket: str
    opted_into_marketing: bool
    http_request: str
    http_response: int
    file_size_bytes: int
    event_datetime: str
    event_ts: int


beam.coders.registry.register_coder(EventLog, beam.coders.RowCoder)


def decode_message(kafka_kv: tuple):
    return kafka_kv[1].decode("utf-8")


def create_message(element: EventLog):
    key = {"event_id": element.id, "event_ts": element.event_ts}
    value = element._asdict()
    print(key)
    return json.dumps(key).encode("utf-8"), json.dumps(value).encode("utf-8")


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


def run():
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--runner", default="FlinkRunner", help="Specify Apache Beam Runner"
    )
    parser.add_argument(
        "--use_own",
        action="store_true",
        default="Flag to indicate whether to use an own local cluster",
    )
    opts = parser.parse_args()

    pipeline_opts = {
        "runner": opts.runner,
        "job_name": "kafka-io",
        "environment_type": "LOOPBACK",
        "streaming": True,
        "parallelism": 3,
        "experiments": [
            "use_deprecated_read"
        ],  ## https://github.com/apache/beam/issues/20979
        "checkpointing_interval": "60000",
    }
    if opts.use_own is True:
        pipeline_opts = {**pipeline_opts, **{"flink_master": "localhost:8081"}}
    print(pipeline_opts)
    options = PipelineOptions([], **pipeline_opts)
    # Required, else it will complain that when importing worker functions
    options.view_as(SetupOptions).save_main_session = True

    p = beam.Pipeline(options=options)
    (
        p
        | "Read from Kafka"
        >> kafka.ReadFromKafka(
            consumer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                ),
                "auto.offset.reset": "earliest",
                # "enable.auto.commit": "true",
                "group.id": "kafka-io",
            },
            topics=["website-visit"],
        )
        | "Decode messages" >> beam.Map(decode_message)
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Create messages"
        >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
        | "Write to Kafka"
        >> kafka.WriteToKafka(
            producer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                )
            },
            topic="website-out",
        )
    )

    logging.getLogger().setLevel(logging.INFO)
    logging.info("Building pipeline ...")

    p.run().wait_until_finish()


if __name__ == "__main__":
    run()
```

### Start Flink/Kafka Clusters

To run the pipeline, we need to launch a Kafka cluster and optionally a Flink cluster. They can be created using the startup script with the *-a* or *-k* option. We create both the clusters for the example pipeline of this post.

```bash
# start both flink and kafka cluster
$ ./setup/start-flink-env.sh -a

# start only kafka cluster
# ./setup/start-flink-env.sh -k
```

Once the clusters are launched, we can check the Kafka resources on *localhost:8080*.

![](kafka-ui.png#center)

And the Flink web UI is accessible on *localhost:8081*.

![](flink-ui.png#center)

### Generate Data

For streaming data generation, we can use the website visit log generator that was introduced in [Part 1](/blog/2024-03-28-beam-local-dev-1). We can execute the script while specifying the *source* argument to *streaming*. Below shows an example of generating Kafka messages for the streaming pipeline.

```bash
$ python datagen/generate_data.py --source streaming --num_users 5 --delay_seconds 0.5
# 10 events created so far...
# {'ip': '126.1.20.79', 'id': '-2901668335848977108', 'lat': 35.6895, 'lng': 139.6917, 'user_agent': 'Mozilla/5.0 (Windows; U; Windows NT 5.1) AppleWebKit/533.44.1 (KHTML, like Gecko) Version/4.0.2 Safari/533.44.1', 'age_bracket': '26-40', 'opted_into_marketing': True, 'http_request': 'GET chromista.html HTTP/1.0', 'http_response': 200, 'file_size_bytes': 316, 'event_datetime': '2024-04-14T21:51:33.042', 'event_ts': 1713095493042}
# 20 events created so far...
# {'ip': '126.1.20.79', 'id': '-2901668335848977108', 'lat': 35.6895, 'lng': 139.6917, 'user_agent': 'Mozilla/5.0 (Windows; U; Windows NT 5.1) AppleWebKit/533.44.1 (KHTML, like Gecko) Version/4.0.2 Safari/533.44.1', 'age_bracket': '26-40', 'opted_into_marketing': True, 'http_request': 'GET archaea.html HTTP/1.0', 'http_response': 200, 'file_size_bytes': 119, 'event_datetime': '2024-04-14T21:51:38.090', 'event_ts': 1713095498090}
# ...
```

### Run Pipeline

The streaming pipeline can be executed as shown below. As mentioned, we use the local Flink cluster by specifying the *use_own* argument.

```bash
$ python section3/kafka_io.py --use_own
```

After a while, we can check both the input and output topics in the *Topics* section of *kafka-ui*.

![](kafka-topics.png#center)

We can use the Flink web UI to monitor the pipeline as a Flink job. When we click the *kafka-io* job in the *Running Jobs* section, we see 3 operations are linked in the *Overview* tab. The first two operations are polling and reading Kafka source description while the actual pipeline runs in the last operation.

![](flink-job.png#center)

Note that, although the main pipeline's SDK harness is set to *LOOPBACK*, the Kafka I/O runs on the Java SDK, and it associates with its own SDK harness, which defaults to *DOCKER*. We can check the Kafka I/O's SDK harness process is launched in a container as following.

```bash
$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Command}}\t{{.Status}}"
CONTAINER ID   IMAGE                           COMMAND                  STATUS
3cd5a628a970   apache/beam_java11_sdk:2.53.0   "/opt/apache/beam/bo…"   Up 4 minutes
```

### Stop Flink/Kafka Clusters

After we stop the pipeline and data generation scripts, we can tear down the Flink and Kafka clusters using the bash script that was explained earlier with *-a* or *-k* arguments.

```bash
# stop both flink and kafka cluster
$ ./setup/stop-flink-env.sh -a

# stop only kafka cluster
# ./setup/stop-flink-env.sh -k
```

## Summary

The Apache Flink Runner supports Python, and it has good features that allow us to develop streaming pipelines effectively. We first discussed the *portability layer* of Apache Beam as it helps understand (1) how a pipeline developed by the Python SDK can be executed in the Flink Runner that only understands Java JAR and (2) how multiple SDKs can be used in a single pipeline. Then we moved on to how to manage local Flink and Kafka clusters using bash scripts. Finally, we ended up illustrating a simple streaming pipeline, which reads and writes website visit logs from and to Kafka topics.
