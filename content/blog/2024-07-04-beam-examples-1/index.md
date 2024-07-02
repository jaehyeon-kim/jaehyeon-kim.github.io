---
title: Apache Beam Python Examples - Part 1 Calculate K Most Frequent Words and Max Word Length
date: 2024-07-04
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Apache Beam Python Examples
categories:
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: In this series, we develop Apache Beam Python pipelines. The majority of them are from Building Big Data Pipelines with Apache Beam by Jan Lukavský. Mainly relying on the Java SDK, the book teaches fundamentals of Apache Beam using hands-on tasks, and we convert those tasks using the Python SDK. We focus on streaming pipelines, and they are deployed on a local (or embedded) Apache Flink cluster using the Apache Flink Runner. Beginning with setting up the development environment, we build two pipelines that obtain top K most frequent words and the word that has the longest word length in this post.
---

In this series, we develop [Apache Beam](https://beam.apache.org/) Python pipelines. The majority of them are from [Building Big Data Pipelines with Apache Beam by Jan Lukavský](https://www.packtpub.com/en-us/product/building-big-data-pipelines-with-apache-beam-9781800564930). Mainly relying on the Java SDK, the book teaches fundamentals of Apache Beam using hands-on tasks, and we convert those tasks using the Python SDK. We focus on streaming pipelines, and they are deployed on a local (or embedded) [Apache Flink](https://flink.apache.org/) cluster using the [Apache Flink Runner](https://beam.apache.org/documentation/runners/flink/). Beginning with setting up the development environment, we build two pipelines that obtain top K most frequent words and the word that has the longest word length in this post. 

* [Part 1 Calculate K Most Frequent Words and Max Word Length](#) (this post)
* Part 2 Calculate Average Word Length with/without Fixed Look back
* Part 3 Build Sport Activity Tracker with/without SQL
* Part 4 Call RPC Service for Data Augmentation
* Part 5 Call RPC Service in Batch using Stateless DoFn
* Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
* Part 7 Separate Droppable Data into Side Output
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Setup Development Environment

The development environment requires an Apache Flink cluster, Apache Kafka cluster and [gRPC](https://grpc.io/) Server. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### Flink Cluster

To set up a local Flink cluster, we should download a supported Flink release (e.g. 1.16.3, 1.17.2 or 1.18.1) - we use Flink 1.18.1 with Apache Beam 2.57.0 in this series. Once downloaded, we need to update the Flink configuration file, for example, to enable the Flink UI and to make the Flink binaries to be executable. The steps can be found below.

```bash
mkdir -p setup && cd setup
## 1. download flink binary and decompress in the same folder
FLINK_VERSION=1.18.1 # change flink version eg) 1.16.3, 1.17.2, 1.18.1 ...
wget https://dlcdn.apache.org/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz
tar -zxf flink-${FLINK_VERSION}-bin-scala_2.12.tgz
## 2. update flink configuration in eg) ./flink-${FLINK_VERSION}/conf/flink-conf.yaml
##  rest.port: 8081                    # uncommented
##  rest.address: localhost            # kept as is
##  rest.bind-address: 0.0.0.0         # changed from localhost
##  taskmanager.numberOfTaskSlots: 10  # updated from 1
## 3. make flink binaries to be executable
chmod -R +x flink-${FLINK_VERSION}/bin
```

### Kafka Cluster

A Kafka cluster with 1 broker and 1 Zookeeper node is used together with a Kafka management app (*kafka-ui*). The details of setting up the resources can be found in my *Kafka Development with Docker* series: [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1) and [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2).

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

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed via *localhost:29092* from the Docker host machine and *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by a Kafka producer app that is discussed later and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

### gRPC Server

We develop several pipelines that call an external RPC service for data enrichment in later posts. A gRPC server is required for those pipelines, and it is created using Docker Compose. The details of developing the underlying service will be discussed in Part 4.

```yaml
# setup/docker-compose-grpc.yml
version: "3.5"

services:
  grpc-server:
    build:
      context: .
    image: grpc-server
    container_name: grpc-server
    command: ["python", "/app/server.py"]
    ports:
      - 50051:50051
    networks:
      - appnet
    environment:
      PYTHONUNBUFFERED: "1"
      INSECURE_PORT: 0.0.0.0:50051
    volumes:
      - ../chapter3:/app

networks:
  appnet:
    name: grpc-network
```

### Manage Resources

The Flink and Kafka clusters and gRPC server are managed by bash scripts. Those scripts accept four flags: `-f`, `-k` and `-g` to start/stop individual resources or `-a` to manage all of them. We can add multiple flags to start/stop multiple resources. Note that the scripts assume Flink 1.18.1 by default, and we can specify a specific Flink version if it is different from it e.g. `FLINK_VERSION=1.17.2 ./setup/start-flink-env.sh`.

```bash
# setup/start-flink-env.sh
#!/usr/bin/env bash

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--kafka) start_kafka=true;;
        -f|--flink) start_flink=true;;
        -g|--grpc) start_grpc=true;;
        -a|--all) start_all=true;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ ! -z $start_all ] &&  [ $start_all = true ]; then
  start_kafka=true
  start_flink=true
  start_grpc=true
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#### start kafka cluster in docker
if [ ! -z $start_kafka ] &&  [ $start_kafka = true ]; then
  echo "start kafka..."
  docker-compose -f ${SCRIPT_DIR}/docker-compose.yml up -d
fi

#### start grpc server in docker
if [ ! -z $start_grpc ] &&  [ $start_grpc = true ]; then
  echo "start grpc server..."
  docker-compose -f ${SCRIPT_DIR}/docker-compose-grpc.yml up -d
fi

#### start local flink cluster
if [ ! -z $start_flink ] && [ $start_flink = true ]; then
  FLINK_VERSION=${FLINK_VERSION:-1.18.1}
  echo "start flink ${FLINK_VERSION}..."
  ${SCRIPT_DIR}/flink-${FLINK_VERSION}/bin/start-cluster.sh
fi
```

The teardown script stops applicable resources followed by removing all stopped containers. Comment out the container prune command if necessary (`docker container prune -f`).

```bash
# setup/stop-flink-env.sh
#!/usr/bin/env bash

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--kafka) stop_kafka=true;;
        -f|--flink) stop_flink=true;;
        -g|--grpc) stop_grpc=true;;
        -a|--all) stop_all=true;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ ! -z $stop_all ] && [ $stop_all = true ]; then
  stop_kafka=true
  stop_flink=true
  stop_grpc=true
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#### stop kafka cluster in docker
if [ ! -z $stop_kafka ] && [ $stop_kafka = true ]; then
  echo "stop kafka..."
  docker-compose -f ${SCRIPT_DIR}/docker-compose.yml down -v
fi

#### stop grpc server in docker
if [ ! -z $stop_grpc ] && [ $stop_grpc = true ]; then
  echo "stop grpc server..."
  docker-compose -f ${SCRIPT_DIR}/docker-compose-grpc.yml down
fi

#### stop local flink cluster
if [ ! -z $stop_flink ] && [ $stop_flink = true ]; then
  FLINK_VERSION=${FLINK_VERSION:-1.18.1}
  echo "stop flink ${FLINK_VERSION}..."
  ${SCRIPT_DIR}/flink-${FLINK_VERSION}/bin/stop-cluster.sh
fi

#### remove all stopped containers
docker container prune -f
```

Below shows how to start resources using the start-up script. We need to launch both the Flink and Kafka clusters if we deploy a Beam pipeline on a local Flink cluster. Otherwise, we can start the Kafka cluster only.

```bash
## start a local flink can kafka cluster
./setup/start-flink-env.sh -f -k
# start kafka...
# [+] Running 6/6
#  ⠿ Network app-network      Created                                     0.0s
#  ⠿ Volume "zookeeper_data"  Created                                     0.0s
#  ⠿ Volume "kafka_0_data"    Created                                     0.0s
#  ⠿ Container zookeeper      Started                                     0.3s
#  ⠿ Container kafka-0        Started                                     0.5s
#  ⠿ Container kafka-ui       Started                                     0.8s
# start flink 1.18.1...
# Starting cluster.
# Starting standalonesession daemon on host <hostname>.
# Starting taskexecutor daemon on host <hostname>.

## start a local kafka cluster only
./setup/start-flink-env.sh -k
# start kafka...
# [+] Running 6/6
#  ⠿ Network app-network      Created                                     0.0s
#  ⠿ Volume "zookeeper_data"  Created                                     0.0s
#  ⠿ Volume "kafka_0_data"    Created                                     0.0s
#  ⠿ Container zookeeper      Started                                     0.3s
#  ⠿ Container kafka-0        Started                                     0.5s
#  ⠿ Container kafka-ui       Started                                     0.8s
```

## Kafka Text Producer

We have two Kafka text producers as many pipelines read/process text messages from a Kafka topic. The first producer sends fake text from the [Faker](https://faker.readthedocs.io/en/master/) package. We can run the producer simply by executing the producer script.

```python
# utils/faker_gen.py
import time
import argparse

from faker import Faker
from producer import TextProducer

if __name__ == "__main__":
    parser = argparse.ArgumentParser(__file__, description="Fake Text Data Generator")
    parser.add_argument(
        "--bootstrap_servers",
        "-b",
        type=str,
        default="localhost:29092",
        help="Comma separated string of Kafka bootstrap addresses",
    )
    parser.add_argument(
        "--topic_name",
        "-t",
        type=str,
        default="input-topic",
        help="Kafka topic name",
    )
    parser.add_argument(
        "--delay_seconds",
        "-d",
        type=float,
        default=1,
        help="The amount of time that a record should be delayed.",
    )
    args = parser.parse_args()

    producer = TextProducer(args.bootstrap_servers, args.topic_name)
    fake = Faker()

    num_events = 0
    while True:
        num_events += 1
        text = fake.text()
        producer.send_to_kafka(text)
        if num_events % 10 == 0:
            print(f"{num_events} text sent. current - {text}")
        time.sleep(args.delay_seconds)
```

The second producer accepts user inputs, and it can be used for controlling text messages as well as message creation timestamps. The latter feature is useful for testing late arrival data. 

```python
# utils/interactive_gen.py
import re
import time
import argparse

from producer import TextProducer


def get_digit(shift: str, pattern: str = None):
    try:
        return int(re.sub(pattern, "", shift).strip())
    except (TypeError, ValueError):
        return 1


def get_ts_shift(shift: str):
    current = int(time.time() * 1000)
    multiplier = 1
    if shift.find("m") > 0:
        multiplier = 60 * 1000
        digit = get_digit(shift, r"m.+")
    elif shift.find("s") > 0:
        multiplier = 1000
        digit = get_digit(shift, r"s.+")
    else:
        digit = get_digit(shift)
    return {
        "current": current,
        "shift": int(digit) * multiplier,
        "shifted": current + int(digit) * multiplier,
    }


def parse_user_input(user_input: str):
    if len(user_input.split(";")) == 2:
        shift, text = tuple(user_input.split(";"))
        shift_info = get_ts_shift(shift)
        msg = " | ".join(
            [f"{k}: {v}" for k, v in {**{"text": text.strip()}, **shift_info}.items()]
        )
        print(f">> {msg}")
        return {"text": text.strip(), "timestamp_ms": shift_info["shifted"]}
    print(f">> text: {user_input}")
    return {"text": user_input}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        __file__, description="Interactive Text Data Generator"
    )
    parser.add_argument(
        "--bootstrap_servers",
        "-b",
        type=str,
        default="localhost:29092",
        help="Comma separated string of Kafka bootstrap addresses",
    )
    parser.add_argument(
        "--topic_name",
        "-t",
        type=str,
        default="input-topic",
        help="Kafka topic name",
    )
    args = parser.parse_args()

    producer = TextProducer(args.bootstrap_servers, args.topic_name)

    while True:
        user_input = input("ENTER TEXT: ")
        args = parse_user_input(user_input)
        producer.send_to_kafka(**args)
```

By default, the message creation timestamp is not shifted. We can do so by appending shift details (digit and scale) (e.g. `1 minute` or `10 sec`). Below shows some usage examples.

```bash
# python utils/interactive_gen.py
# ENTER TEXT: By default, message creation timestamp is not shifted!
# >> text: By default, message creation timestamp is not shifted!
# ENTER TEXT: -10 sec;Add time digit and scale to shift back. should be separated by semi-colon
# >> text: Add time digit and scale to shift back. should be separated by semi-colon | current: 1719891195495 | shift: -10000 | shifted: 1719891185495
# ENTER TEXT: -10s;We don't have to keep a blank.
# >> text: We don't have to keep a blank. | current: 1719891203698 | shift: 1000 | shifted: 1719891204698
# ENTER TEXT: 1 min;We can shift to the future but is it realistic?  
# >> text: We can shift to the future but is it realistic? | current: 1719891214039 | shift: 60000 | shifted: 1719891274039
```

Both the producer apps send text messages using the following Kafka producer class.

```python
# utils/producer.py
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
```

## Beam Pipelines

We develop two pipelines that obtain top K most frequent words and the word that has the longest word length.

### Shared Transforms

Both the pipelines read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below.

```python
# chapter3/word_process_utils.py
import re
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.io import kafka


def decode_message(kafka_kv: tuple):
    print(kafka_kv)
    return kafka_kv[1].decode("utf-8")


def tokenize(element: str):
    return re.findall(r"[A-Za-z\']+", element)


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
        )


class WriteProcessOutputsToKafka(beam.PTransform):
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

    def expand(self, pcoll: pvalue.PCollection):
        return pcoll | "WriteToKafka" >> kafka.WriteToKafka(
            producer_config={"bootstrap.servers": self.boostrap_servers},
            topic=self.topic,
            expansion_service=self.expansion_service,
        )
```

### Calculate the K most frequent words

The main transform of this pipeline (`CalculateTopKWords`) performs

1. `Windowing`: assigns input text messages into a [fixed time window](https://beam.apache.org/documentation/programming-guide/#windowing) of configurable length - 10 seconds by default
2. `Tokenize`: tokenizes (or converts) text into words
3. `CountPerWord`: counts occurrence of each word
4. `TopKWords`: selects top k words - 3 by default
5. `Flatten`: flattens a list of words into individual words

Also, it adds the window start and end timestamps when creating output messages (`CreateMessags`). 

```python
# chapter3/top_k_words.py
import os
import argparse
import json
import re
import typing
import logging

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import FixedWindows
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from word_process_utils import tokenize, ReadWordsFromKafka, WriteProcessOutputsToKafka


class CalculateTopKWords(beam.PTransform):
    def __init__(
        self, window_length: int, top_k: int, label: str | None = None
    ) -> None:
        self.window_length = window_length
        self.top_k = top_k
        super().__init__(label)

    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "Windowing" >> beam.WindowInto(FixedWindows(size=self.window_length))
            | "Tokenize" >> beam.FlatMap(tokenize)
            | "CountPerWord" >> beam.combiners.Count.PerElement()
            | "TopKWords"
            >> beam.combiners.Top.Of(self.top_k, lambda e: e[1]).without_defaults()
            | "Flatten" >> beam.FlatMap(lambda e: e)
        )


def create_message(element: typing.Tuple[str, str, str, int]):
    msg = json.dumps(dict(zip(["window_start", "window_end", "word", "freq"], element)))
    print(msg)
    return "".encode("utf-8"), msg.encode("utf-8")


class AddWindowTS(beam.DoFn):
    def process(self, top_k: typing.Tuple[str, int], win_param=beam.DoFn.WindowParam):
        yield (
            win_param.start.to_rfc3339(),
            win_param.end.to_rfc3339(),
            top_k[0],
            top_k[1],
        )


class CreateMessags(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "AddWindowTS" >> beam.ParDo(AddWindowTS())
            | "CreateMessages"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
        )


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--bootstrap_servers",
        default="host.docker.internal:29092",
        help="Kafka bootstrap server addresses",
    )
    parser.add_argument("--input_topic", default="input-topic", help="Input topic")
    parser.add_argument(
        "--output_topic",
        default=re.sub("_", "-", re.sub(".py$", "", os.path.basename(__file__))),
        help="Output topic",
    )
    parser.add_argument("--window_length", default="10", type=int, help="Window length")
    parser.add_argument("--top_k", default="3", type=int, help="Top k")

    known_args, pipeline_args = parser.parse_known_args(argv)
    print(f"known args - {known_args}")
    print(f"pipeline args - {pipeline_args}")

    # We use the save_main_session option because one or more DoFn's in this
    # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | "ReadInputsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
            )
            | "CalculateTopKWords"
            >> CalculateTopKWords(
                window_length=known_args.window_length,
                top_k=known_args.top_k,
            )
            | "CreateMessags" >> CreateMessags()
            | "WriteOutputsToKafka"
            >> WriteProcessOutputsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic=known_args.output_topic,
            )
        )

        logging.getLogger().setLevel(logging.WARN)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

#### Pipeline Test

As described in [this documentation](https://beam.apache.org/documentation/pipelines/test-your-pipeline/), we can test a Beam pipeline as following.

1. Create a `TestPipeline`.
2. Create some static, known test input data.
3. Create a `PCollection` of input data using the `Create` transform (if bounded source) or a `TestStream` (if unbounded source)
4. Apply the transform to the input `PCollection` and save the resulting output `PCollection`.
5. Use `PAssert` and its subclasses (or [testing utils](https://beam.apache.org/releases/pydoc/current/apache_beam.testing.util.html) in Python) to verify that the output `PCollection` contains the elements that you expect.

We configure the first three lines to be delivered in 2 seconds and the remaining two lines after 10 seconds. Therefore, the whole elements are split into two fixed time windows, given the window length of 10 seconds. We can check the top 3 words are *line*, *first* and *the* in the first window while *line*, *in* and *window* are the top 3 words in the second window. Then, we can create the expected output as a list of tuples of the word and number of occurrences and compare it with the pipeline output.

```python
# chapter3/top_k_words_test.py
import unittest

from apache_beam.coders import coders
from apache_beam.utils.timestamp import Timestamp
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.window import TimestampedValue
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from top_k_words import CalculateTopKWords


class TopKWordsTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            test_stream = (
                TestStream(coder=coders.StrUtf8Coder())
                .with_output_types(str)
                .add_elements(
                    [
                        TimestampedValue("This is the first line.", Timestamp.of(0)),
                        TimestampedValue(
                            "This is second line in the first window", Timestamp.of(1)
                        ),
                        TimestampedValue(
                            "Last line in the first window", Timestamp.of(2)
                        ),
                        TimestampedValue(
                            "This is another line, but in different window.",
                            Timestamp.of(10),
                        ),
                        TimestampedValue(
                            "Last line, in the same window as previous line.",
                            Timestamp.of(11),
                        ),
                    ]
                )
                .advance_watermark_to_infinity()
            )

            output = (
                p
                | test_stream
                | "CalculateTopKWords"
                >> CalculateTopKWords(
                    window_length=10,
                    top_k=3,
                )
            )

            EXPECTED_OUTPUT = [
                ("line", 3),
                ("first", 3),
                ("the", 3),
                ("line", 3),
                ("in", 2),
                ("window", 2),
            ]

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter2/top_k_words_test.py -v
test_windowing_behaviour (__main__.TopKWordsTest) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.354s

OK
```

#### Pipeline Execution

Below shows an example of executing the pipeline by specifying pipeline arguments only while accepting default values of the known arguments (*bootstrap_servers*, *input_topic* ...). Note that, by specifying the *flink_master* value to *localhost:8081*, it deployed the pipeline on a local Flink cluster. Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter2/top_k_words.py --job_name=top-k-words \
	--runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 \
	--checkpointing_interval=10000 --experiment=use_deprecated_read
```

On Flink UI, we see the pipeline polls messages and performs the main transform in multiple tasks while keeping Kafka offset commit as a separate task.

![](top-k-dag.png#center)

On Kafka UI, we can check the output messages include the frequent word details as well as window start/end timestamps.

![](top-k-output.png#center)

### Calculate the maximal word length

The main transform of this pipeline (`CalculateMaxWordLength`) performs

1. `Windowing`: assigns input text messages into a [global window](https://beam.apache.org/documentation/programming-guide/#windowing) and emits (or triggers) the result for every new input message with the following configuration
    - Disallows Late data (`allowed_lateness=0`)
    - Assigns the output timestamp from the latest input timestamp (`timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST`)
    - Keeps the previous elements that were already fired (`accumulation_mode=AccumulationMode.ACCUMULATING`) 
2. `Tokenize`: tokenizes (or converts) text into words
3. `GetLongestWord`: selects top 1 word that has the longest length
4. `Flatten`: flattens a list of words into a word

Also, the output timestamp is added when creating output messages (`CreateMessags`). 

```python
# chapter3/max_word_length_with_ts.py
import os
import argparse
import json
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import GlobalWindows, TimestampCombiner
from apache_beam.transforms.trigger import AfterCount, AccumulationMode, AfterWatermark
from apache_beam.transforms.util import Reify
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions


from word_process_utils import tokenize, ReadWordsFromKafka, WriteProcessOutputsToKafka


class CalculateMaxWordLength(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "Windowing"
            >> beam.WindowInto(
                GlobalWindows(),
                trigger=AfterWatermark(early=AfterCount(1)),
                allowed_lateness=0,
                timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST,
                accumulation_mode=AccumulationMode.ACCUMULATING,
            )
            | "Tokenize" >> beam.FlatMap(tokenize)
            | "GetLongestWord" >> beam.combiners.Top.Of(1, key=len).without_defaults()
            | "Flatten" >> beam.FlatMap(lambda e: e)
        )


def create_message(element: typing.Tuple[str, str]):
    msg = json.dumps(dict(zip(["created_at", "word"], element)))
    print(msg)
    return "".encode("utf-8"), msg.encode("utf-8")


class AddTS(beam.DoFn):
    def process(self, word: str, ts_param=beam.DoFn.TimestampParam):
        yield ts_param.to_rfc3339(), word


class CreateMessags(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "ReifyTimestamp" >> Reify.Timestamp()
            | "AddTimestamp" >> beam.ParDo(AddTS())
            | "CreateMessages"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
        )


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--bootstrap_servers",
        default="host.docker.internal:29092",
        help="Kafka bootstrap server addresses",
    )
    parser.add_argument("--input_topic", default="input-topic", help="Input topic")
    parser.add_argument(
        "--output_topic",
        default=re.sub("_", "-", re.sub(".py$", "", os.path.basename(__file__))),
        help="Output topic",
    )

    known_args, pipeline_args = parser.parse_known_args(argv)
    print(f"known args - {known_args}")
    print(f"pipeline args - {pipeline_args}")

    # We use the save_main_session option because one or more DoFn's in this
    # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | "ReadInputsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
            )
            | "CalculateMaxWordLength" >> CalculateMaxWordLength()
            | "CreateMessags" >> CreateMessags()
            | "WriteOutputsToKafka"
            >> WriteProcessOutputsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic=known_args.output_topic,
            )
        )

        logging.getLogger().setLevel(logging.WARN)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

#### Pipeline Test

The lengths of words increase for the first three elements (*a*, *bb*, *ccc*), and the output changes each time. The length of the fourth element (*d*) is smaller than the previous one, and the output remains the same. The last output is emitted as the watermark is advanced into the end of the global window. We can create the expected output as a list of `TestWindowedValue`s and compare it with the pipeline output.

```python
# chapter3/max_word_length_with_ts_test.py
import unittest

from apache_beam.coders import coders
from apache_beam.utils.timestamp import Timestamp
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to, TestWindowedValue
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.window import GlobalWindow, TimestampedValue
from apache_beam.transforms.util import Reify
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from max_word_length_with_ts import CalculateMaxWordLength


class MaxWordLengthTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            """
               We should put each element separately. The reason we do this is to ensure 
               that our trigger will be invoked in between each element. Because the trigger 
               invocation is optional, a runner might skip a particular firing. Putting each element 
               separately into addElements makes DirectRunner (our testing runner) invokes a trigger 
               for each input element.
            """
            test_stream = (
                TestStream(coder=coders.StrUtf8Coder())
                .with_output_types(str)
                .add_elements([TimestampedValue("a", Timestamp.of(0))])
                .add_elements([TimestampedValue("bb", Timestamp.of(10))])
                .add_elements([TimestampedValue("ccc", Timestamp.of(20))])
                .add_elements([TimestampedValue("d", Timestamp.of(30))])
                .advance_watermark_to_infinity()
            )

            output = (
                p
                | test_stream
                | "CalculateMaxWordLength" >> CalculateMaxWordLength()
                | "ReifyTimestamp" >> Reify.Timestamp()
            )

            EXPECTED_OUTPUT = [
                TestWindowedValue(
                    value="a", timestamp=Timestamp(0), windows=[GlobalWindow()]
                ),
                TestWindowedValue(
                    value="bb", timestamp=Timestamp(10), windows=[GlobalWindow()]
                ),
                TestWindowedValue(
                    value="ccc", timestamp=Timestamp(20), windows=[GlobalWindow()]
                ),
                TestWindowedValue(
                    value="ccc", timestamp=Timestamp(30), windows=[GlobalWindow()]
                ),
                TestWindowedValue(
                    value="ccc", timestamp=Timestamp(30), windows=[GlobalWindow()]
                ),
            ]

            assert_that(output, equal_to(EXPECTED_OUTPUT), reify_windows=True)


if __name__ == "__main__":
    unittest.main()
```

The pipeline can be tested as shown below.

```bash
python chapter2/max_word_length_test.py -v
test_windowing_behaviour (__main__.MaxWordLengthTest) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.446s

OK
```

#### Pipeline Execution

Similar to the previous example, we can execute the pipeline by specifying pipeline arguments only while accepting default values of the known arguments (*bootstrap_servers*, *input_topic* ...).

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter2/max_word_length_with_ts.py --job_name=max-word-len \
	--runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 \
	--checkpointing_interval=10000 --experiment=use_deprecated_read
```

Similar to the previous pipeline, on Flink UI, we see the pipeline polls messages and performs the main transform in multiple tasks while keeping Kafka offset commit as a separate task.

![](max-len-dag.png#center)

On Kafka UI, we can check the output messages include the longest word as well as its timestamp. Note that, as the input text message has multiple words, we can have multiple output messages that have the same timestamp - recall the accumulation mode is accumulating.

![](max-len-output.png#center)