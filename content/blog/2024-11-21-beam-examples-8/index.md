---
title: Apache Beam Python Examples - Part 8 Enhance Sport Activity Tracker with Runner Motivation
date: 2024-11-21
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
  - Data Streaming
tags: 
  - Apache Beam
  - Apache Flink
  - Apache Kafka
  - Python
authors:
  - JaehyeonKim
images: []
description: 
---

In [Part 3](/blog/2024-08-01-beam-examples-3), we developed a Beam pipeline that tracks sport activities of users and outputs their speeds periodically. While reporting such values is useful for users on its own, we can provide more engaging information to users if we have a pipeline that reports pacing of their activities over periods. For example, we can send a message to encourage a user to work harder if he/she has a performance goal and is underperforming for some periods. In this post, we develop a new pipeline that tracks user activities and reports pacing details by comparing short term metrics to their long term counterparts.

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-18-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* [Part 7 Separate Droppable Data into Side Output](/blog/2024-10-24-beam-examples-7)
* [Part 8 Enhance Sport Activity Tracker with Runner Motivation](#) (this post)
* [Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn](/blog/2024-12-05-beam-examples-9)
* [Part 10 Develop Streaming File Reader using Splittable DoFn](/blog/2024-12-19-beam-examples-10)

## Development Environment

The development environment has an Apache Flink cluster, Apache Kafka cluster and [gRPC](https://grpc.io/) server. The gRPC server was used in Part 4 to 6. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about how to set up the development environment. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

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
user0   78      1731565423.0311885
user1   13      1731565423.0311885
user2   108     1731565423.0311885
user3   64      1731565423.0311885
user4   92      1731565423.0311885
===========================
user0   87      1731565423.1549027
user1   22      1731565423.154912
user2   116     1731565423.1549146
user3   67      1731565423.1549163
user4   99      1731565423.1549182
===========================
...
```

Also, we can check the input messages using Kafka UI on *localhost:8080*.

![](input-messages.png#center)

## Beam Pipeline

We develop a new pipeline that tracks user activities and reports pacing details by comparing short term metrics to their long term counterparts.

### Shared Source

* `Position` / `PositionCoder`
    - The input text messages are converted into a custom type (`Position`). Therefore, we need to create its type definition and register the instruction about how to encode/decode its value using a [coder](https://beam.apache.org/documentation/programming-guide/#data-encoding-and-type-safety) (`PositionCoder`). Note that, without registering the coder, the custom type cannot be processed by a portable runner. 
* `ComputeBoxedMetrics`
    - This composite transform begins with placing activity tracking elements into a global window and pushes them into the `ToMetricFn` *DoFn*.
* `ToMetricFn`
    - This is a stateful *DoFn* that buffers the tracking elements and flushes them periodically. Once flushed, it computes a metric record recursively and returns a tuple of the key (user ID) and metric together with the associating timestamp. The timestamp of the output tuple is taken from the first element's timestamp.
* `Metric`
    - This is a custom data type that keeps user activity metrics.
* `MeanPaceCombineFn`
    - This *CombineFn* accumulates user activity metrics and computes an average speed.
* `ReadPositionsFromKafka`
    - It reads messages from a Kafka topic, and returns tuple elements of user ID and position. We need to specify the output type hint for a portable runner to recognise the output type correctly. Note that, the Kafka read and write transforms have an argument called `deprecated_read`, which forces to use the legacy read when it is set to *True*. We will use the legacy read in this post to prevent a problem that is described in this [GitHub issue](https://github.com/apache/beam/issues/20979).
* `PreProcessInput`
    - This is a composite transform that converts an input text message into a tuple of user ID and position as well as assigns a timestamp value into an individual element.
* `WriteNotificationsToKafka`
    - It sends output messages to a Kafka topic. Each message is a tuple of track (user ID) and notification.

```python
# chapter4/sport_tracker_utils.py
import re
import json
import random
import time
import typing
import logging

import apache_beam as beam
from apache_beam.io import kafka
from apache_beam import pvalue
from apache_beam.transforms.util import Reify
from apache_beam.transforms.window import GlobalWindows, TimestampedValue
from apache_beam.transforms.timeutil import TimeDomain
from apache_beam.transforms.userstate import (
    ReadModifyWriteStateSpec,
    BagStateSpec,
    TimerSpec,
    on_timer,
)
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


class Metric(typing.NamedTuple):
    distance: float
    duration: int

    def to_bytes(self):
        return json.dumps(self._asdict()).encode("utf-8")

    @classmethod
    def from_bytes(cls, encoded: bytes):
        d = json.loads(encoded.decode("utf-8"))
        return cls(**d)


class ToMetricFn(beam.DoFn):
    MIN_TIMESTAMP = ReadModifyWriteStateSpec("min_timestamp", beam.coders.FloatCoder())
    BUFFER = BagStateSpec("buffer", PositionCoder())
    FLUSH_TIMER = TimerSpec("flush", TimeDomain.WATERMARK)

    def __init__(self, verbose: bool = False):
        self.verbose = verbose

    def process(
        self,
        element: typing.Tuple[str, Position],
        timestamp=beam.DoFn.TimestampParam,
        buffer=beam.DoFn.StateParam(BUFFER),
        min_timestamp=beam.DoFn.StateParam(MIN_TIMESTAMP),
        flush_timer=beam.DoFn.TimerParam(FLUSH_TIMER),
    ):
        min_ts: Timestamp = min_timestamp.read()
        if min_ts is None:
            if self.verbose and element[0] == "user0":
                logging.info(
                    f"ToMetricFn set flush timer for {element[0]} at {timestamp}"
                )
            min_timestamp.write(timestamp)
            flush_timer.set(timestamp)
        buffer.add(element[1])

    @on_timer(FLUSH_TIMER)
    def flush(
        self,
        key=beam.DoFn.KeyParam,
        buffer=beam.DoFn.StateParam(BUFFER),
        min_timestamp=beam.DoFn.StateParam(MIN_TIMESTAMP),
    ):
        items: typing.List[Position] = []
        for item in buffer.read():
            items.append(item)
            if self.verbose and key == "user0":
                logging.info(
                    f"ToMetricFn flush track {key}, ts {item.timestamp}, num items {len(items)}"
                )

        items = list(sorted(items, key=lambda p: p.timestamp))
        outputs = list(self.flush_metrics(items, key))

        buffer.clear()
        buffer.add(items[-1])
        min_timestamp.clear()
        return outputs

    def flush_metrics(self, items: typing.List[Position], key: str):
        i = 1
        while i < len(items):
            last = items[i - 1]
            next = items[i]
            distance = abs(next.spot - last.spot)
            duration = next.timestamp - last.timestamp
            if duration > 0:
                yield TimestampedValue(
                    (key, Metric(distance, duration)),
                    Timestamp.of(last.timestamp),
                )
            i += 1


@beam.typehints.with_input_types(typing.Tuple[str, Position])
class ComputeBoxedMetrics(beam.PTransform):
    def __init__(self, verbose: bool = False, label: str | None = None):
        super().__init__(label)
        self.verbose = verbose

    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | beam.WindowInto(GlobalWindows())
            | beam.ParDo(ToMetricFn(verbose=self.verbose))
        )


class MeanPaceCombineFn(beam.CombineFn):
    def create_accumulator(self):
        return Metric(0, 0)

    def add_input(self, mutable_accumulator: Metric, element: Metric):
        return Metric(*tuple(map(sum, zip(mutable_accumulator, element))))

    def merge_accumulators(self, accumulators: typing.List[Metric]):
        return Metric(*tuple(map(sum, zip(*accumulators))))

    def extract_output(self, accumulator: Metric):
        if accumulator.duration == 0:
            return float("NaN")
        return accumulator.distance / accumulator.duration

    def get_accumulator_coder(self):
        return beam.coders.registry.get_coder(Metric)


class PreProcessInput(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        def add_timestamp(element: typing.Tuple[str, Position]):
            return TimestampedValue(element, Timestamp.of(element[1].timestamp))

        def to_positions(input: str):
            workout, spot, timestamp = tuple(re.sub("\n", "", input).split("\t"))
            return workout, Position(spot=int(spot), timestamp=float(timestamp))

        return (
            pcoll
            | "ToPositions" >> beam.Map(to_positions)
            | "AddTS" >> beam.Map(add_timestamp)
        )


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
        def decode_message(kafka_kv: tuple):
            if self.verbose:
                print(kafka_kv)
            return kafka_kv[1].decode("utf-8")

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
            )
            | "DecodeMsg" >> beam.Map(decode_message)
            | "PreProcessInput" >> PreProcessInput()
        )


class WriteNotificationsToKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topic: str,
        label: str | None = None,
    ):
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topic = topic

    def expand(self, pcoll: pvalue.PCollection):
        def create_message(element: tuple):
            msg = json.dumps({"track": element[0], "notification": element[1]})
            print(msg)
            return element[0].encode("utf-8"), msg.encode("utf-8")

        return (
            pcoll
            | "CreateMessage"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
            | "WriteToKafka"
            >> kafka.WriteToKafka(
                producer_config={"bootstrap.servers": self.boostrap_servers},
                topic=self.topic,
            )
        )
```

### Pipeline Source

The main transform is performed by `SportTrackerMotivation`. It begins with producing metrics using the `ComputeBoxedMetrics` transform. Then, those metrics are averaged *within* a short period (default to 20 seconds) as well as *across* a long period (default to 100 seconds). A fixed window is applied to obtain short averages while computing long averages involves more steps as illustrated below.

1. A sliding window is applied where the size and period are the long and short periods respectively. 
2. The average in each of the sliding windows is computed. 
3. The long averages are re-windowed to a fixed window that has the same size to the short averages.
    - It makes the long averages are placed in comparable windows to the short averages.

After both the short and long averages are obtained, they are joined by the `CoGroupByKey` transform followed by generating pacing details of user activities. Note that we can also join the short/long averages using a side input - see [this link](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-pipelines/chapter4/sport_tracker_motivation_side_inputs.py) for details.

The pipeline can be better illustrated with an example. Let say we have three positions of a user, and two metric records can be obtained recursively by comparing a position and its previous one. The short averages are computed with the metrics that belong to `[20, 40)` and `[60, 80)` windows. On the other hand, the long averages are obtained across multiple windows by including all metrics that fall in `[Long Avg Window Start, Window End)`. Note that, as the long averages are re-windowed, joining is based on `[Window Start, Window End)`. We end up having two matching windows and the notification values are obtained by comparing the short and long averages.

![](breakdown.png#center)

```python
# chapter4/sport_tracker_motivation_co_gbk.py
import os
import argparse
import re
import typing
import logging

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import FixedWindows, SlidingWindows
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from sport_tracker_utils import (
    ReadPositionsFromKafka,
    WriteNotificationsToKafka,
    ComputeBoxedMetrics,
    MeanPaceCombineFn,
)


class SportTrackerMotivation(beam.PTransform):
    def __init__(
        self,
        short_duration: int,
        long_duration: int,
        verbose: bool = False,
        label: str | None = None,
    ):
        super().__init__(label)
        self.short_duration = short_duration
        self.long_duration = long_duration
        self.verbose = verbose

    def expand(self, pcoll: pvalue.PCollection):
        def as_motivations(
            element: typing.Tuple[
                str, typing.Tuple[typing.Iterable[float], typing.Iterable[float]]
            ],
        ):
            shorts, longs = element[1]
            short_avg = next(iter(shorts), None)
            long_avg = next(iter(longs), None)
            if long_avg in [None, 0] or short_avg in [None, 0]:
                status = None
            else:
                diff = short_avg / long_avg
                if diff < 0.9:
                    status = "underperforming"
                elif diff < 1.1:
                    status = "pacing"
                else:
                    status = "outperforming"
            if self.verbose and element[0] == "user0":
                logging.info(
                    f"SportTrackerMotivation track {element[0]}, short average {short_avg}, long average {long_avg}, status - {status}"
                )
            if status is None:
                return []
            return [(element[0], status)]

        boxed = pcoll | "ComputeMetrics" >> ComputeBoxedMetrics(verbose=self.verbose)
        short_average = (
            boxed
            | "ShortWindow" >> beam.WindowInto(FixedWindows(self.short_duration))
            | "ShortAverage" >> beam.CombinePerKey(MeanPaceCombineFn())
        )
        long_average = (
            boxed
            | "LongWindow"
            >> beam.WindowInto(SlidingWindows(self.long_duration, self.short_duration))
            | "LongAverage" >> beam.CombinePerKey(MeanPaceCombineFn())
            | "MatchToShortWindow" >> beam.WindowInto(FixedWindows(self.short_duration))
        )
        return (
            (short_average, long_average)
            | beam.CoGroupByKey()
            | beam.FlatMap(as_motivations)
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
    parser.add_argument("--short_duration", default=20, type=int, help="Input topic")
    parser.add_argument("--long_duration", default=100, type=int, help="Input topic")
    parser.add_argument(
        "--verbose", action="store_true", default="Whether to enable log messages"
    )
    parser.set_defaults(verbose=False)
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
            | "SportsTrackerMotivation"
            >> SportTrackerMotivation(
                short_duration=known_args.short_duration,
                long_duration=known_args.long_duration,
                verbose=known_args.verbose,
            )
            | "WriteNotifications"
            >> WriteNotificationsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic=known_args.output_topic,
            )
        )

        logging.getLogger().setLevel(logging.INFO)
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

We have two test cases assuming bounded and unbounded scenarios. Each includes sport activities of two users, and we can obtain the expected outputs with the reasoning illustrated earlier.

```python
# chapter4/sport_tracker_motivation_co_gbk_test.py
import typing
import unittest
from itertools import chain

from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.utils.timestamp import Timestamp
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from sport_tracker_utils import Position
from sport_tracker_motivation_co_gbk import SportTrackerMotivation


class SportTrackerMotivationTest(unittest.TestCase):
    def test_pipeline_bounded(self):
        options = PipelineOptions()
        with TestPipeline(options=options) as p:
            # now = time.time()
            now = 0
            user0s = [
                ("user0", Position.create(spot=0, timestamp=now + 30)),
                ("user0", Position.create(spot=25, timestamp=now + 60)),
                ("user0", Position.create(spot=22, timestamp=now + 75)),
            ]
            user1s = [
                ("user1", Position.create(spot=0, timestamp=now + 30)),
                ("user1", Position.create(spot=-20, timestamp=now + 60)),
                ("user1", Position.create(spot=80, timestamp=now + 75)),
            ]
            inputs = chain(*zip(user0s, user1s))

            test_stream = TestStream()
            for input in inputs:
                test_stream.add_elements([input], event_timestamp=input[1].timestamp)
            test_stream.advance_watermark_to_infinity()

            output = (
                p
                | test_stream.with_output_types(typing.Tuple[str, Position])
                | SportTrackerMotivation(short_duration=20, long_duration=100)
            )

            EXPECTED_OUTPUT = [
                ("user0", "pacing"),
                ("user1", "pacing"),
                ("user0", "underperforming"),
                ("user1", "outperforming"),
            ]

            assert_that(output, equal_to(EXPECTED_OUTPUT))

    def test_pipeline_unbounded(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            # now = time.time()
            now = 0
            user0s = [
                ("user0", Position.create(spot=0, timestamp=now + 30)),
                ("user0", Position.create(spot=25, timestamp=now + 60)),
                ("user0", Position.create(spot=22, timestamp=now + 75)),
            ]
            user1s = [
                ("user1", Position.create(spot=0, timestamp=now + 30)),
                ("user1", Position.create(spot=-20, timestamp=now + 60)),
                ("user1", Position.create(spot=80, timestamp=now + 75)),
            ]
            inputs = chain(*zip(user0s, user1s))
            watermarks = [now + 5, now + 10, now + 15, now + 20, now + 29, now + 30]

            test_stream = TestStream()
            test_stream.advance_watermark_to(Timestamp.of(now))
            for input in inputs:
                test_stream.add_elements([input], event_timestamp=input[1].timestamp)
                if watermarks:
                    test_stream.advance_watermark_to(Timestamp.of(watermarks.pop(0)))
            test_stream.advance_watermark_to_infinity()

            output = (
                p
                | test_stream.with_output_types(typing.Tuple[str, Position])
                | SportTrackerMotivation(short_duration=30, long_duration=90)
            )

            EXPECTED_OUTPUT = [
                ("user0", "pacing"),
                ("user1", "pacing"),
                ("user0", "underperforming"),
                ("user1", "outperforming"),
            ]

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter4/sport_tracker_motivation_co_gbk_test.py 
..
----------------------------------------------------------------------
Ran 2 tests in 1.032s

OK
```

#### Pipeline Execution

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed on *localhost:29092* from the Docker host machine and on *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by the Kafka producer app and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

We need to send messages into the input Kafka topic before executing the pipeline. Input messages can be sent by executing the Kafka text producer - `python utils/sport_tracker_gen.py`.

When executing the pipeline, we specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
## add --verbose to check detailed log messages
python chapter4/sport_tracker_motivation_co_gbk.py --deprecated_read \
	--job_name=sport-tracker-motivation --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Flink UI, we see the pipeline has multiple tasks. Notably the tasks that compute the short and long averages are split and executed in parallel, and the outcomes are combined subsequently. 

![](pipeline-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of track (user ID) and notification.

![](output-messages.png#center)
