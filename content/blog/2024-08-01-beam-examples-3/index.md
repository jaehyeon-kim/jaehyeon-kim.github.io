---
title: Apache Beam Python Examples - Part 3 Build Sport Activity Tracker with/without SQL
date: 2024-08-01
draft: false
featured: false
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
description: 
---

In this post, we develop two Apache Beam pipelines that track sport activities of users and output their speed periodically. The first pipeline uses native transforms and [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) is used for the latter. While *Beam SQL* can be useful in some situations, its features in the Python SDK are not complete compared to the Java SDK. Therefore, we are not able to build the required tracking pipeline using it. We end up discussing potential improvements of *Beam SQL* so that it can be used for building competitive applications with the Python SDK.

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](#) (this post)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-18-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* Part 7 Separate Droppable Data into Side Output
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Development Environment

The development environment has an Apache Flink cluster and Apache Kafka cluster and [gRPC](https://grpc.io/) server - gRPC server will be used in later posts. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about how to set up the development environment. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### Manage Environment

The Flink and Kafka clusters and gRPC server are managed by the following bash scripts.

- `./setup/start-flink-env.sh`
- `./setup/stop-flink-env.sh`

Those scripts accept four flags: `-f`, `-k` and `-g` to start/stop individual resources or `-a` to manage all of them. We can add multiple flags to start/stop relevant resources. Note that the scripts assume Flink 1.18.1 by default, and we can specify a specific Flink version if it is different from it e.g. `FLINK_VERSION=1.17.2 ./setup/start-flink-env.sh`.

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

## Kafka Sport Activity Producer

A Kafka producer application is created to generate sport tracking activities of users. Those activities are tracked by user positions that have the following variables.

* *spot* - An integer value that indicates where a user locates. Although we may represent a user position using a geographic coordinate, we keep it as an integer for the sake of simplicity in this post.
* *timestamp* - A float value that shows the time in seconds since the Epoch when a user locates in the corresponding spot.

A configurable number of user tracks (`--num_tracks`, default 5) can be generated every two seconds by default (`--delay_seconds`). The producer sends the activity tracking records as a text by concatenating the user ID and position values with tab characters (`\t`).

```python
# utils/sport_tracker_gen.py
import time
import argparse
import random
import typing

from producer import TextProducer


class Position(typing.NamedTuple):
    spot: int
    timestamp: float

    @classmethod
    def create(cls, spot: int = random.randint(0, 100), timestamp: float = time.time()):
        return cls(spot=spot, timestamp=timestamp)


class TrackGenerator:
    def __init__(self, num_tracks: int, delay_seconds: int) -> None:
        self.num_tracks = num_tracks
        self.delay_seconds = delay_seconds
        self.positions = [
            Position.create(spot=random.randint(0, 110)) for _ in range(self.num_tracks)
        ]

    def update_positions(self):
        for ind, position in enumerate(self.positions):
            self.positions[ind] = self.move(
                start=position,
                delta=random.randint(-10, 10),
                duration=time.time() - position.timestamp,
            )

    def move(self, start: Position, delta: int, duration: float):
        spot, timestamp = tuple(start)
        return Position(spot=spot + delta, timestamp=timestamp + duration)

    def create_tracks(self):
        tracks = []
        for ind, position in enumerate(self.positions):
            track = f"user{ind}\t{position.spot}\t{position.timestamp}"
            print(track)
            tracks.append(track)
        return tracks


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__file__, description="Sport Data Generator")
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
        "--num_tracks",
        "-n",
        type=int,
        default=5,
        help="Number of tracks",
    )
    parser.add_argument(
        "--delay_seconds",
        "-d",
        type=float,
        default=2,
        help="The amount of time that a record should be delayed.",
    )
    args = parser.parse_args()

    producer = TextProducer(args.bootstrap_servers, args.topic_name)
    track_gen = TrackGenerator(args.num_tracks, args.delay_seconds)

    while True:
        tracks = track_gen.create_tracks()
        for track in tracks:
            producer.send_to_kafka(text=track)
        track_gen.update_positions()
        time.sleep(random.randint(0, args.delay_seconds))
```

The producer app sends the input messages using the following Kafka producer class.

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

We can execute the producer app after starting the Kafka cluster. Once executed, the activity tracking records are printed in the terminal.

```bash
python utils/sport_tracker_gen.py 
user0   97      1722127107.0654943
user1   56      1722127107.0654943
user2   55      1722127107.0654943
user3   55      1722127107.0654943
user4   95      1722127107.0654943
===========================
user0   88      1722127107.1854753
user1   49      1722127107.1854813
user2   55      1722127107.1854827
user3   61      1722127107.185484
user4   88      1722127107.1854854
===========================
...
```

Also, we can check the input messages using Kafka UI on *localhost:8080*.

![](input-messages.png#center)

## Beam Pipelines

We develop two Beam pipelines that track sport activities of users. The first pipeline uses native transforms and Beam SQL is used for the latter.

### Shared Source

Both the pipelines share the same sources, and they are refactored in a separate module.

* `Position` / `PositionCoder`
    - The input text messages are converted into a custom type (`Position`). Therefore, we need to create its type definition and register the instruction about how to encode/decode its value using a [coder](https://beam.apache.org/documentation/programming-guide/#data-encoding-and-type-safety) (`PositionCoder`). Note that, without registering the coder, the custom type cannot be processed by a portable runner. 
* `PreProcessInput`
    - This is a composite transform that converts an input text message into a tuple of user ID and position as well as assigns a timestamp value into an individual element.
* `ReadPositionsFromKafka`
    - It reads messages from a Kafka topic, and returns tuple elements of user ID and position. We need to specify the output type hint for a portable runner to recognise the output type correctly. Note that, the Kafka read and write methods has an argument called `deprecated_read`, which forces to use the legacy read when it is set to *True*. We will use the legacy read in this post to prevent a problem that is described in this [GitHub issue](https://github.com/apache/beam/issues/20979).
* `WriteMetricsToKafka`
    - It sends output messages to a Kafka topic. Each message is a tuple of user ID and speed. Note that the input type hint is necessary when the inputs are piped from a transform by *Beam SQL*.

```python
# chapter2/sport_tracker_utils.py
import re
import json
import random
import time
import typing

import apache_beam as beam
from apache_beam.io import kafka
from apache_beam import pvalue
from apache_beam.transforms.window import TimestampedValue
from apache_beam.utils.timestamp import Timestamp


class Position(typing.NamedTuple):
    spot: int
    timestamp: float

    def to_bytes(self):
        return json.dumps(self._asdict()).encode("utf-8")

    @classmethod
    def from_bytes(cls, encoded: bytes):
        d = json.loads(encoded.decode("utf-8"))
        return cls(**d)

    @classmethod
    def create(cls, spot: int = random.randint(0, 100), timestamp: float = time.time()):
        return cls(spot=spot, timestamp=timestamp)


class PositionCoder(beam.coders.Coder):
    def encode(self, value: Position):
        return value.to_bytes()

    def decode(self, encoded: bytes):
        return Position.from_bytes(encoded)

    def is_deterministic(self) -> bool:
        return True


beam.coders.registry.register_coder(Position, PositionCoder)


def add_timestamp(element: typing.Tuple[str, Position]):
    return TimestampedValue(element, Timestamp.of(element[1].timestamp))


def to_positions(input: str):
    workout, spot, timestamp = tuple(re.sub("\n", "", input).split("\t"))
    return workout, Position(spot=int(spot), timestamp=float(timestamp))


class PreProcessInput(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "ToPositions" >> beam.Map(to_positions)
            | "AddTS" >> beam.Map(add_timestamp)
        )


def decode_message(kafka_kv: tuple):
    print(kafka_kv)
    return kafka_kv[1].decode("utf-8")


@beam.typehints.with_output_types(typing.Tuple[str, Position])
class ReadPositionsFromKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topics: typing.List[str],
        group_id: str,
        deprecated_read: bool,
        verbose: bool = False,
        label: str | None = None,
    ):
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topics = topics
        self.group_id = group_id
        self.verbose = verbose
        self.expansion_service = None
        if deprecated_read:
            self.expansion_service = kafka.default_io_expansion_service(
                ["--experiments=use_deprecated_read"]
            )

    def expand(self, input: pvalue.PBegin):
        return (
            input
            | "ReadFromKafka"
            >> kafka.ReadFromKafka(
                consumer_config={
                    "bootstrap.servers": self.boostrap_servers,
                    "auto.offset.reset": "earliest",
                    # "enable.auto.commit": "true",
                    "group.id": self.group_id,
                },
                topics=self.topics,
                timestamp_policy=kafka.ReadFromKafka.create_time_policy,
                expansion_service=self.expansion_service,
            )
            | "DecodeMessage" >> beam.Map(decode_message)
            | "PreProcessInput" >> PreProcessInput()
        )


@beam.typehints.with_input_types(typing.Tuple[str, float])
class WriteMetricsToKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topic: str,
        deprecated_read: bool,
        label: str | None = None,
    ):
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topic = topic
        self.expansion_service = None
        if deprecated_read:
            self.expansion_service = kafka.default_io_expansion_service(
                ["--experiments=use_deprecated_read"]
            )

    def expand(self, pcoll: pvalue.PCollection):
        def create_message(element: typing.Tuple[str, float]):
            msg = json.dumps(dict(zip(["user", "speed"], element)))
            print(msg)
            return "".encode("utf-8"), msg.encode("utf-8")

        return (
            pcoll
            | "CreateMessage"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
            | "WriteToKafka"
            >> kafka.WriteToKafka(
                producer_config={"bootstrap.servers": self.boostrap_servers},
                topic=self.topic,
                expansion_service=self.expansion_service,
            )
        )
```

### Sport Tracker

The main transforms of this pipeline perform

1. `Windowing`: assigns input elements into a [global window](https://beam.apache.org/documentation/programming-guide/#windowing) with the following configuration.
    - Emits (or triggers) a window after a certain amount of processing time has passed since data was received with a delay of 3 seconds. (`trigger=AfterWatermark(early=AfterProcessingTime(3))`)
    - Disallows Late data (`allowed_lateness=0`)
    - Assigns the output timestamp from the latest input timestamp (`timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST`)
        - By default, the end of window timestamp is taken, but it is so distance future for the global window. Therefore, we take the latest timestamp of the input elements instead.
    - Configures `ACCUMULATING` as the window's accumulation mode (`accumulation_mode=AccumulationMode.ACCUMULATING`).
        - The trigger emits the results early but not multiple times. Therefore, which accumulation mode to choose doesn't give a different result in this transform. We can ignore this configuration.
2. `ComputeMetrics`: (1) groups by the input elements by key (*user ID*), (2) obtains the total distance and duration by looping through individual elements, (3) calculates the speed of a user, which is the distance divided by the duration, and, finally, (4) returns a metrics record, which is a tuple of user ID and speed.


```python
# chapter2/sport_tracker.py
import os
import argparse
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import GlobalWindows, TimestampCombiner
from apache_beam.transforms.trigger import (
    AfterWatermark,
    AccumulationMode,
    AfterProcessingTime,
)
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from sport_tracker_utils import (
    Position,
    ReadPositionsFromKafka,
    WriteMetricsToKafka,
)


def compute(element: typing.Tuple[str, typing.Iterable[Position]]):
    last: Position = None
    distance = 0
    duration = 0
    for p in sorted(element[1], key=lambda p: p.timestamp):
        if last is not None:
            distance += abs(p.spot - last.spot)
            duration += p.timestamp - last.timestamp
        last = p
    return element[0], distance / duration if duration > 0 else 0


class ComputeMetrics(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll | "GroupByKey" >> beam.GroupByKey() | "Compute" >> beam.Map(compute)
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
    parser.add_argument(
        "--deprecated_read",
        action="store_true",
        default="Whether to use a deprecated read. See https://github.com/apache/beam/issues/20979",
    )
    parser.set_defaults(deprecated_read=False)

    known_args, pipeline_args = parser.parse_known_args(argv)

    # # We use the save_main_session option because one or more DoFn's in this
    # # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    print(f"known args - {known_args}")
    print(f"pipeline options - {pipeline_options.display_data()}")

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | "ReadPositions"
            >> ReadPositionsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
                deprecated_read=known_args.deprecated_read,
            )
            | "Windowing"
            >> beam.WindowInto(
                GlobalWindows(),
                trigger=AfterWatermark(early=AfterProcessingTime(3)),
                allowed_lateness=0,
                timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST,
                accumulation_mode=AccumulationMode.ACCUMULATING,
            )
            | "ComputeMetrics" >> ComputeMetrics()
            | "WriteNotifications"
            >> WriteMetricsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic=known_args.output_topic,
                deprecated_read=known_args.deprecated_read,
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

We use test sport activities of two users that are stored in a file (`input/test-tracker-data.txt`). Then, we add them into a test stream and apply the same preprocessing and windowing transforms. Finally, we apply the metric computation transform and compare the outputs with the expected outputs where the expected speed values are calculated using the same logic.

```txt
# input/test-tracker-data.txt
user0	109	1713939465.7636628
user1	40	1713939465.7636628
user0	108	1713939465.8801599
user1	50	1713939465.8801658
user0	115	1713939467.8904564
user1	58	1713939467.8904696
...
```

```python
# chapter2/sport_tracker_test.py
import os
import re
import typing
import unittest

import apache_beam as beam
from apache_beam.coders import coders

from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.trigger import (
    AfterWatermark,
    AccumulationMode,
    AfterProcessingTime,
)
from apache_beam.transforms.window import GlobalWindows, TimestampCombiner
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from sport_tracker_utils import Position, PreProcessInput
from sport_tracker import ComputeMetrics


def read_file(filename: str, inputpath: str):
    with open(os.path.join(inputpath, filename), "r") as f:
        return f.readlines()


def compute_matrics(key: str, positions: typing.List[Position]):
    last: Position = None
    distance = 0
    duration = 0
    for p in sorted(positions, key=lambda p: p.timestamp):
        if last is not None:
            distance += abs(int(p.spot) - int(last.spot))
            duration += float(p.timestamp) - float(last.timestamp)
        last = p
    return key, distance / duration if duration > 0 else 0


def compute_expected_metrics(lines: list):
    ones, twos = [], []
    for line in lines:
        workout, spot, timestamp = tuple(re.sub("\n", "", line).split("\t"))
        position = Position(spot, timestamp)
        if workout == "user0":
            ones.append(position)
        else:
            twos.append(position)
    return [
        compute_matrics(key="user0", positions=ones),
        compute_matrics(key="user1", positions=twos),
    ]


class SportTrackerTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            PARENT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
            lines = read_file(
                "test-tracker-data.txt", os.path.join(PARENT_DIR, "inputs")
            )
            test_stream = TestStream(coder=coders.StrUtf8Coder()).with_output_types(str)
            for line in lines:
                test_stream.add_elements([line])
            test_stream.advance_watermark_to_infinity()

            output = (
                p
                | test_stream
                | "PreProcessInput" >> PreProcessInput()
                | "Windowing"
                >> beam.WindowInto(
                    GlobalWindows(),
                    trigger=AfterWatermark(early=AfterProcessingTime(3)),
                    allowed_lateness=0,
                    timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST,
                    accumulation_mode=AccumulationMode.ACCUMULATING,
                )
                | "ComputeMetrics" >> ComputeMetrics()
            )

            EXPECTED_OUTPUT = compute_expected_metrics(lines)

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter2/sport_tracker_test.py 
.
----------------------------------------------------------------------
Ran 1 test in 1.492s

OK
```

#### Pipeline Execution

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed on *localhost:29092* from the Docker host machine and on *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by a Kafka producer app that is discussed later and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

We specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter2/sport_tracker.py --deprecated_read \
    --job_name=sport_tracker --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Flink UI, we see the pipeline has two tasks. The first task is performed until windowing the input elements while the second task performs up to sending the metric records into the output topic.

![](sport-tracker-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of user ID and speed.

![](sport-tracker-output.png#center)

### Sport Tracker SQL

The main transforms of this pipeline perform

1. `Windowing`: assigns input elements into a [fixed time window](https://beam.apache.org/documentation/programming-guide/#windowing) of 5 seconds with the following configuration.
    - Disallows Late data (`allowed_lateness=0`)
2. `ComputeMetrics`: (1) converts the input elements into a new custom type (`Track`) so that the key (user ID) becomes present for grouping, (2) calculates the speed of a user where the distance and duration are obtained based on their max/min values only (!), and, finally, (3) returns a metrics record, which is a tuple of user ID and speed.

```python
# chapter2/sport_tracker_sql.py
import os
import argparse
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue, coders
from apache_beam.transforms.sql import SqlTransform
from apache_beam.transforms.window import FixedWindows
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from sport_tracker_utils import (
    Position,
    ReadPositionsFromKafka,
    WriteMetricsToKafka,
)


class Track(typing.NamedTuple):
    user: str
    spot: int
    timestamp: float


coders.registry.register_coder(Track, coders.RowCoder)


def to_track(element: typing.Tuple[str, Position]):
    return Track(element[0], element[1].spot, element[1].timestamp)


class ComputeMetrics(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "ToTrack" >> beam.Map(to_track).with_output_types(Track)
            | "Compute"
            >> SqlTransform(
                """
                WITH cte AS (
                    SELECT
                        `user`,
                        MIN(`spot`) - MAX(`spot`) AS distance,
                        MIN(`timestamp`) - MAX(`timestamp`) AS duration
                    FROM PCOLLECTION
                    GROUP BY `user`
                )
                SELECT 
                    `user`,
                    CASE WHEN duration = 0 THEN 0 ELSE distance / duration END AS speed
                FROM cte
                """
            )
            | "ToTuple"
            >> beam.Map(lambda e: tuple(e)).with_output_types(typing.Tuple[str, float])
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
    parser.add_argument(
        "--deprecated_read",
        action="store_true",
        default="Whether to use a deprecated read. See https://github.com/apache/beam/issues/20979",
    )
    parser.set_defaults(deprecated_read=False)

    known_args, pipeline_args = parser.parse_known_args(argv)

    # # We use the save_main_session option because one or more DoFn's in this
    # # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    print(f"known args - {known_args}")
    print(f"pipeline options - {pipeline_options.display_data()}")

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | "ReadPositions"
            >> ReadPositionsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
                deprecated_read=known_args.deprecated_read,
            )
            | "Windowing" >> beam.WindowInto(FixedWindows(5), allowed_lateness=0)
            | "ComputeMetrics" >> ComputeMetrics()
            | "WriteNotifications"
            >> WriteMetricsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic=known_args.output_topic,
                deprecated_read=known_args.deprecated_read,
            )
        )

        logging.getLogger().setLevel(logging.WARN)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

#### Pipeline Test

We have 8 test activity records of two users. Below shows those records after sorting by user ID and timestamp. Using the sorted records, we can easily obtain the expected outputs, which can be found in the last column.

![](sport-tracker-sql-test.png#center)

Note that the transform by Beam SQL cannot be tested by the streaming Python direct runner because it doesn't support cross-language pipelines. Therefore, we use the Flink runner for testing.

```python
# chapter2/sport_tracker_sql_test.py
import sys
import unittest

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.window import FixedWindows
from apache_beam.options.pipeline_options import PipelineOptions

from sport_tracker_utils import PreProcessInput
from sport_tracker_sql import ComputeMetrics


def main(out=sys.stderr, verbosity=2):
    loader = unittest.TestLoader()

    suite = loader.loadTestsFromModule(sys.modules[__name__])
    unittest.TextTestRunner(out, verbosity=verbosity).run(suite)


class SportTrackerTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        pipeline_opts = {"runner": "FlinkRunner", "parallelism": 1, "streaming": True}
        options = PipelineOptions([], **pipeline_opts)
        with TestPipeline(options=options) as p:
            lines = [
                "user0\t0\t0",
                "user1\t10\t2",
                "user0\t5\t4",
                "user1\t3\t3",
                "user0\t10\t6",
                "user1\t2\t7",
                "user0\t4\t9",
                "user1\t10\t9",
            ]
            test_stream = TestStream(coder=coders.StrUtf8Coder()).with_output_types(str)
            for line in lines:
                test_stream.add_elements([line])
            test_stream.advance_watermark_to_infinity()

            output = (
                p
                | test_stream
                | "PreProcessInput" >> PreProcessInput()
                | "Windowing" >> beam.WindowInto(FixedWindows(5), allowed_lateness=0)
                | "ComputeMetrics" >> ComputeMetrics()
            )

            assert_that(
                output,
                equal_to(
                    [("user0", 1.25), ("user1", 7.0), ("user0", 2.0), ("user1", 4.0)]
                ),
            )


if __name__ == "__main__":
    main(out=None)
```

The pipeline can be tested as shown below.

```bash
python chapter2/sport_tracker_sql_test.py 
ok

----------------------------------------------------------------------
Ran 1 test in 34.487s

OK
```

#### Pipeline Execution

Similar to the previous example, we use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments. Note that the transform by Beam SQL fails to run on a local Flink cluster. Therefore, an embedded Flink cluster is used without specifying the flink master argument.

```bash
## start the beam pipeline with an embedded flink cluster
python chapter2/sport_tracker_sql.py --deprecated_read \
    --job_name=sport_tracker_sql --runner FlinkRunner \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Kafka UI, we can check the output message is a dictionary of user ID and speed.

![](sport-tracker-sql-output.png#center)

## Potential Improvements of Beam SQL for Python SDK

As discussed earlier, the first pipeline uses native transforms, and it takes individual elements to calculate the distance and duration. On the other hand, the second pipeline approximates those values by their max/min values only. This kind of approximation is misleading and there are two options that we can overcome such a limitation.

- User defined function: The Java SDK supports [user defined functions](https://beam.apache.org/documentation/dsls/sql/extensions/user-defined-functions/) that accept a custom Java scalar or aggregation function. We can use a user defined aggregation function to mimics the first pipeline using Beam SQL, but it is not supported in the Python SDK at the moment.
- Beam SQL aggregation analytics functionality ([BEAM-9198](https://issues.apache.org/jira/browse/BEAM-9198)): This ticket aims to implement SQL window analytics functions, and we would be able to take individual elements by using the lead (or lag) function if supported.

I consider the usage of Beam SQL would be limited unless one or all of those features are supported in the Python SDK, although it supports interesting features such as [External Table](https://beam.apache.org/documentation/dsls/sql/extensions/create-external-table/) and [JOIN](https://beam.apache.org/documentation/dsls/sql/extensions/joins/).