---
title: Apache Beam Python Examples - Part 3 Build Sport Activity Tracker with/without SQL
date: 2024-08-01
draft: true
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
description: In this post, we develop two Apache Beam pipelines that track sport activities of users and output their speed periodically. The first pipeline uses native transforms and Beam SQL is used for the latter. While Beam SQL can be useful in some situations, its features in the Python SDK are not complete compared to the Java SDK. Therefore, we are not able to build the required tracking pipeline using it. We end up discussing potential improvements of Beam SQL.
---

In this post, we develop two Apache Beam pipelines that track sport activities of users and output their speed periodically. The first pipeline uses native transforms and [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) is used for the latter. While *Beam SQL* can be useful in some situations, its features in the Python SDK are not complete compared to the Java SDK. Therefore, we are not able to build the required tracking pipeline using it. We end up discussing potential improvements of *Beam SQL*.

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](#) (this post)
* Part 4 Call RPC Service for Data Augmentation
* Part 5 Call RPC Service in Batch using Stateless DoFn
* Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
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

It generates sport tracking activities of users, and those activities are tracked by user positions that have the following variables.

* *spot* - An integer value that indicates where a user locates. (We may represent a user position in two-dimensional space with his/her longitude and latitude. For the sake of simplicity, however, we keep it as an integer.)
* *timestamp* - A float value that shows the time in seconds since the Epoch when a user locates in the corresponding spot.

A configurable number of user tracks (`--num_tracks`, default 5) can be generated every two seconds by default (`--delay_seconds`). The producer sends the activity tracking records after concatenating the user ID and position values with tab characters (`\t`).

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

Once executed, the activity tracking records are printed in the terminal.

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

Also, we can check the input messages on `kafka-ui` (*localhost:8080*).

![](input-messages.png#center)

## Beam Pipelines

We develop two Beam pipelines that track sport activities of users. The first pipeline uses native transforms and Beam SQL is used for the latter.

### Shared Source

Both the pipelines share the same sources, and they are refactored in a utility module.

* `Position` / `PositionCoder`
    - The input text messages are converted into a custom type. Therefore, we need to create its type definition (`Position`) and register the instruction about how to encode/decode its value (`PositionCoder`). Note that the custom type is used in the output type hint of the `ReadPositionsFromKafka` transform. As the transform runs using the Java SDK, it fails to encode/decode the position values if we do  
* `PreProcessInput`
* `ReadPositionsFromKafka`
* `WriteMetricsToKafka`

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
                # impossible to allow late data using default timestamp policies
                # unless manually specifying timestamp by producer
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

#### Pipeline Execution

```bash
python chapter2/sport_tracker.py --deprecated_read \
    --job_name=sport_tracker --runner FlinkRunner \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

![](sport-tracker-dag.png#center)

![](sport-tracker-output.png#center)

### Sport Tracker SQL

[BEAM-9198](https://issues.apache.org/jira/browse/BEAM-9198)

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
from apache_beam.transforms.window import TimestampCombiner, FixedWindows
from apache_beam.transforms.trigger import AccumulationMode
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
            | "Windowing"
            >> beam.WindowInto(
                FixedWindows(5),
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

Streaming Python direct runner does not support cross-language pipelines.

![](sport-tracker-sql-test.png#center)

```python
# chapter2/sport_tracker_sql_test.py
import sys
import unittest

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.window import TimestampCombiner, FixedWindows
from apache_beam.transforms.trigger import AccumulationMode
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
                | "Windowing"
                >> beam.WindowInto(
                    FixedWindows(5),
                    allowed_lateness=0,
                    timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST,
                    accumulation_mode=AccumulationMode.ACCUMULATING,
                )
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

#### Pipeline Execution

```bash
python chapter2/sport_tracker_sql.py --deprecated_read \
    --job_name=sport_tracker_sql --runner FlinkRunner \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

![](sport-tracker-sql-output.png#center)

