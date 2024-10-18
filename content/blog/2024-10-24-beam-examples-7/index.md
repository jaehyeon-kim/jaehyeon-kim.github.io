---
title: Apache Beam Python Examples - Part 7 Separate Droppable Data into Side Output
date: 2024-10-24
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
  - gRPC
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: 
---

In the [previous post](/blog/2024-09-25-beam-examples-5), we developed an Apache Beam pipeline where the input data is augmented by an **Remote Procedure Call (RPC)** service. It is developed so that a single RPC call is made for a bundle of elements. The bundle size, however, is determined by the runner, we may encounter an issue e.g. if an RPC service becomes quite slower if a large number of elements are included in a single request. We can improve the pipeline using stateful `DoFn` where the number elements to process and maximum wait seconds can be controlled. Note that, although the stateful `DoFn` used in this post solves the data aumentation task well, in practice, we should use the built-in transforms such as [BatchElements](https://beam.apache.org/documentation/transforms/python/aggregation/batchelements/) and [GroupIntoBatches](https://beam.apache.org/documentation/transforms/python/aggregation/groupintobatches/) whenever possible. 

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-18-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* [Part 7 Separate Droppable Data into Side Output](#) (this post)
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Development Environment

The development environment has an Apache Flink cluster, Apache Kafka cluster and [gRPC](https://grpc.io/) server. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about how to set up the development environment. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### Manage Environment

The Flink and Kafka clusters and gRPC server are managed by the following bash scripts.

- `./setup/start-flink-env.sh`
- `./setup/stop-flink-env.sh`

Those scripts accept four flags: `-f`, `-k` and `-g` to start/stop individual resources or `-a` to manage all of them. We can add multiple flags to start/stop relevant resources. Note that the scripts assume Flink 1.18.1 by default, and we can specify a specific Flink version if it is different from it e.g. `FLINK_VERSION=1.17.2 ./setup/start-flink-env.sh`.

Below shows how to start resources using the start-up script. We need to launch both the Flink/Kafka clusters and gRPC server if we deploy a Beam pipeline on a local Flink cluster. Otherwise, we can start the Kafka cluster and gRPC server only.

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

## Kafka Producer

```python
# utils/faker_shifted_gen.py
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
        "--max_shift_seconds",
        "-m",
        type=float,
        default=15,
        help="The maximum amount of time that a message create stamp is shifted back.",
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
    Faker.seed(1237)

    num_events = 0
    while True:
        num_events += 1
        text = fake.text(max_nb_chars=10)
        current = int(time.time())
        shift = fake.random_element(range(args.max_shift_seconds))
        shifted = current - shift
        producer.send_to_kafka(text=text, timestamp_ms=shifted * 1000)
        print(
            f"text - {text}, ts - {current}, shift - {shift} secs - shifted ts {shifted}"
        )
        time.sleep(args.delay_seconds)
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

```bash
python utils/faker_shifted_gen.py 
text - Church., ts - 1729223414, shift - 6 secs - shifted ts 1729223408
text - For., ts - 1729223415, shift - 3 secs - shifted ts 1729223412
text - Have., ts - 1729223416, shift - 9 secs - shifted ts 1729223407
text - Health., ts - 1729223417, shift - 6 secs - shifted ts 1729223411
text - Join., ts - 1729223418, shift - 2 secs - shifted ts 1729223416
text - Nice., ts - 1729223419, shift - 11 secs - shifted ts 1729223408
text - Us., ts - 1729223420, shift - 8 secs - shifted ts 1729223412
text - Friend., ts - 1729223421, shift - 4 secs - shifted ts 1729223417
text - Executive., ts - 1729223422, shift - 2 secs - shifted ts 1729223420
text - Memory., ts - 1729223423, shift - 6 secs - shifted ts 1729223417
text - Charge., ts - 1729223424, shift - 0 secs - shifted ts 1729223424
text - Season., ts - 1729223425, shift - 3 secs - shifted ts 1729223422
text - Several., ts - 1729223426, shift - 14 secs - shifted ts 1729223412
text - Not say., ts - 1729223427, shift - 2 secs - shifted ts 1729223425
text - City eat., ts - 1729223428, shift - 3 secs - shifted ts 1729223425
text - Character., ts - 1729223429, shift - 8 secs - shifted ts 1729223421
text - Finally., ts - 1729223430, shift - 4 secs - shifted ts 1729223426
text - Letter., ts - 1729223431, shift - 1 secs - shifted ts 1729223430
text - Case., ts - 1729223432, shift - 8 secs - shifted ts 1729223424
text - Word., ts - 1729223433, shift - 6 secs - shifted ts 1729223427
```

## Beam Pipeline

to be updated

### Shared Source

We have multiple pipelines that read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below. Note that, the Kafka read and write methods has an argument called `deprecated_read`, which forces to use the legacy read when it is set to *True*. We will use the legacy read in this post to prevent a problem that is described in this [GitHub issue](https://github.com/apache/beam/issues/20979).

`timestamp_policy=kafka.ReadFromKafka.create_time_policy`

```python
# chapter3/io_utils.py
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
        deprecated_read: bool,
        verbose: bool = False,
        label: str | None = None,
    ) -> None:
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
            | "ExtractWords" >> beam.FlatMap(tokenize)
        )


class WriteOutputsToKafka(beam.PTransform):
    def __init__(
        self,
        bootstrap_servers: str,
        topic: str,
        deprecated_read: bool,
        label: str | None = None,
    ) -> None:
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topic = topic
        self.expansion_service = None
        if deprecated_read:
            self.expansion_service = kafka.default_io_expansion_service(
                ["--experiments=use_deprecated_read"]
            )

    def expand(self, pcoll: pvalue.PCollection):
        return pcoll | "WriteToKafka" >> kafka.WriteToKafka(
            producer_config={"bootstrap.servers": self.boostrap_servers},
            topic=self.topic,
            expansion_service=self.expansion_service,
        )
```

### Pipeline Source

to be updated!

```python
# chapter3/droppable_data_filter.py
import os
import argparse
import json
import re
import typing
import logging

import apache_beam as beam
from apache_beam import pvalue, Windowing
from apache_beam.transforms.trigger import AccumulationMode
from apache_beam.transforms.timeutil import TimeDomain
from apache_beam.transforms.userstate import (
    ReadModifyWriteStateSpec,
    TimerSpec,
    on_timer,
)
from apache_beam.transforms.window import (
    GlobalWindows,
    BoundedWindow,
    FixedWindows,
)
from apache_beam.transforms.util import Reify
from apache_beam.utils.timestamp import Timestamp
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from io_utils import ReadWordsFromKafka, WriteOutputsToKafka

MAIN_OUTPUT = "main_output"
DROPPABLE_OUTPUT = "droppable_output"


def create_message(
    element: typing.Union[typing.Tuple[Timestamp, Timestamp, str], str], is_main: bool
):
    if is_main:
        msg = json.dumps(
            {
                "start": element[0].seconds(),
                "end": element[1].seconds(),
                "word": element[2],
            }
        )
        key = element[2]
    else:
        msg = element
        key = msg
    logging.info(f"{'main' if is_main else 'droppable'} message - {msg}")
    return key.encode("utf-8"), msg.encode("utf-8")


class SplitDroppable(beam.PTransform):
    def expand(self, pcoll):
        windowing: Windowing = pcoll.windowing
        assert windowing.windowfn != GlobalWindows

        def to_kv(
            element: typing.Tuple[str, Timestamp, BoundedWindow],
        ) -> typing.Tuple[str, str]:
            value, timestamp, window = element
            return str(window), value

        outputs: pvalue.DoOutputsTuple = (
            pcoll
            | Reify.Window()
            | beam.Map(to_kv)
            | beam.WindowInto(GlobalWindows())
            | beam.ParDo(SplitDroppableDataFn(windowing=windowing))
            .with_outputs(DROPPABLE_OUTPUT, main=MAIN_OUTPUT)
            .with_input_types(typing.Tuple[str, str])
        )

        pcolls = {}
        pcolls[MAIN_OUTPUT] = outputs[MAIN_OUTPUT]
        pcolls[DROPPABLE_OUTPUT] = outputs[DROPPABLE_OUTPUT]

        return pcolls | Rewindow(windowing=windowing)


class SplitDroppableDataFn(beam.DoFn):
    TOO_LATE = ReadModifyWriteStateSpec("too_late", beam.coders.BooleanCoder())
    WINDOW_GC_TIMER = TimerSpec("window_gc_timer", TimeDomain.WATERMARK)

    def __init__(self, windowing: Windowing):
        self.windowing = windowing

    def process(
        self,
        element: typing.Tuple[str, str],
        too_late=beam.DoFn.StateParam(TOO_LATE),
        window_gc_timer=beam.DoFn.TimerParam(WINDOW_GC_TIMER),
    ):
        max_ts = self.get_max_ts(element[0])
        allowed_lateness_sec = self.windowing.allowed_lateness.micros // 1000000
        too_late_for_window = too_late.read() or False
        logging.info(f"string (value) - {element[1]}, window (key) {element[0]}")
        if too_late_for_window is False:
            timer_val = max_ts + allowed_lateness_sec
            logging.info(f"set up eow timer at {timer_val}")
            window_gc_timer.set(timer_val)
        if too_late_for_window is True:
            yield pvalue.TaggedOutput(DROPPABLE_OUTPUT, element[1])
        else:
            yield element[1]

    @on_timer(WINDOW_GC_TIMER)
    def on_window_gc_timer(self, too_late=beam.DoFn.StateParam(TOO_LATE)):
        too_late.write(True)

    @staticmethod
    def get_max_ts(window_str: str):
        """Extract the maximum timestamp of a window string eg) '[0.001, 600.001)'"""
        bounds = re.findall(r"[\d]+[.\d]+", window_str)
        assert len(bounds) == 2
        return float(bounds[1])


class Rewindow(beam.PTransform):
    def __init__(self, label: str | None = None, windowing: Windowing = None):
        super().__init__(label)
        self.windowing = windowing

    def expand(self, pcolls):
        window_fn = self.windowing.windowfn
        allowed_lateness = self.windowing.allowed_lateness
        # closing_behavior = self.windowing.closing_behavior # emit always
        # on_time_behavior = self.windowing.on_time_behavior # fire always
        timestamp_combiner = self.windowing.timestamp_combiner
        trigger_fn = self.windowing.triggerfn
        accumulation_mode = (
            AccumulationMode.DISCARDING
            if self.windowing.accumulation_mode == 1
            else AccumulationMode.ACCUMULATING
        )
        main_output = pcolls[MAIN_OUTPUT] | "MainWindowInto" >> beam.WindowInto(
            windowfn=window_fn,
            trigger=trigger_fn,
            accumulation_mode=accumulation_mode,
            timestamp_combiner=timestamp_combiner,
            allowed_lateness=allowed_lateness,
        )
        return {
            "main_output": main_output,
            "droppable_output": pcolls[DROPPABLE_OUTPUT],
        }


class AddWindowTS(beam.DoFn):
    def process(self, element: str, win_param=beam.DoFn.WindowParam):
        yield (win_param.start, win_param.end, element)


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--bootstrap_servers",
        default="host.docker.internal:29092",
        help="Kafka bootstrap server addresses",
    )
    parser.add_argument("--input_topic", default="input-topic", help="Input topic")
    parser.add_argument("--window_length", default=5, type=int, help="Input topic")
    parser.add_argument("--allowed_lateness", default=2, type=int, help="Input topic")
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
        outputs = (
            p
            | "ReadInputsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
                deprecated_read=known_args.deprecated_read,
            )
            | "Windowing"
            >> beam.WindowInto(
                FixedWindows(known_args.window_length),
                allowed_lateness=known_args.allowed_lateness,
                accumulation_mode=AccumulationMode.DISCARDING,
            )
            | "SpiltDroppable" >> SplitDroppable()
        )

        (
            outputs[MAIN_OUTPUT]
            | "AddWindowTimestamp" >> beam.ParDo(AddWindowTS())
            | "CreateMainMessage"
            >> beam.Map(create_message, is_main=True).with_output_types(
                typing.Tuple[bytes, bytes]
            )
            | "WriteToMainTopic"
            >> WriteOutputsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic="output-normal-topic",
                deprecated_read=known_args.deprecated_read,
            )
        )

        (
            outputs[DROPPABLE_OUTPUT]
            | "CreateDroppableMessage"
            >> beam.Map(create_message, is_main=False).with_output_types(
                typing.Tuple[bytes, bytes]
            )
            | "WriteToDroppableTopic"
            >> WriteOutputsToKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topic="output-droppable-topic",
                deprecated_read=known_args.deprecated_read,
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

to be updated

```python
# chapter3/droppable_data_filter_test.py
import unittest

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.transforms.window import IntervalWindow
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to, equal_to_per_window
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.trigger import AccumulationMode
from apache_beam.transforms.window import FixedWindows, TimestampedValue
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions
from apache_beam.utils.timestamp import Timestamp

from io_utils import tokenize
from droppable_data_filter import (
    SplitDroppable,
    MAIN_OUTPUT,
    DROPPABLE_OUTPUT,
)


class DroppableDataFilterTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        now = 0
        # now = int(time.time())
        with TestPipeline(options=options) as p:
            test_stream = (
                TestStream(coder=coders.StrUtf8Coder())
                .with_output_types(str)
                .advance_watermark_to(Timestamp(seconds=now))
                .add_elements(
                    [TimestampedValue("a", Timestamp(seconds=now + 3))]
                )  # fine, before watermark - on time
                .advance_watermark_to(Timestamp(seconds=now + 6.999))
                .add_elements(
                    [TimestampedValue("b", Timestamp(seconds=now + 4))]
                )  # late, but within allowed lateness
                .advance_watermark_to(Timestamp(seconds=now + 7))
                .add_elements([TimestampedValue("c", now)])  # droppable
                .advance_watermark_to_infinity()
            )

            outputs = (
                p
                | test_stream
                | "ExtractWords" >> beam.FlatMap(tokenize)
                | "Windowing"
                >> beam.WindowInto(
                    FixedWindows(5),
                    allowed_lateness=2,
                    accumulation_mode=AccumulationMode.DISCARDING,
                )
                | "SpiltDroppable" >> SplitDroppable()
            )

            main_expected = {
                IntervalWindow(Timestamp(seconds=now), Timestamp(seconds=now + 5)): [
                    "a",
                    "b",
                ],
            }

            assert_that(
                outputs[MAIN_OUTPUT],
                equal_to_per_window(main_expected),
                reify_windows=True,
                label="assert_main",
            )

            assert_that(
                outputs[DROPPABLE_OUTPUT], equal_to(["c"]), label="assert_droppable"
            )


class DroppableDataFilterTestFail(unittest.TestCase):
    @unittest.expectedFailure
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        now = 0
        # now = int(time.time())
        with TestPipeline(options=options) as p:
            test_stream = (
                TestStream(coder=coders.StrUtf8Coder())
                .with_output_types(str)
                .advance_watermark_to(Timestamp(seconds=now + 7.5))
                .add_elements(
                    [TimestampedValue("c", now)]
                )  # should be dropped but not!
                .advance_watermark_to_infinity()
            )

            outputs = (
                p
                | test_stream
                | "Extract words" >> beam.FlatMap(tokenize)
                | "Windowing"
                >> beam.WindowInto(
                    FixedWindows(5),
                    allowed_lateness=2,
                    accumulation_mode=AccumulationMode.DISCARDING,
                )
                | "SpiltDroppable" >> SplitDroppable()
            )

            assert_that(
                outputs[DROPPABLE_OUTPUT], equal_to(["c"]), label="assert_droppable"
            )


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter3/droppable_data_filter_test.py 
...
----------------------------------------------------------------------
Ran 2 tests in 0.979s

OK (expected failures=1)
```

#### Pipeline Execution

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed on *localhost:29092* from the Docker host machine and on *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by a Kafka producer app that is discussed later and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

We need to send messages into the input Kafka topic before executing the pipeline. Input text message can be sent by executing a Kafka text producer - `python utils/faker_shifted_gen.py`.

![](input-messages.png#center)

When executing the pipeline, we specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter3/droppable_data_filter.py --deprecated_read \
	--job_name=droppable-data-filter --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

to be updated

![](pipeline-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of a word and its length.

![](all-topics.png#center)
