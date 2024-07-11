---
title: Apache Beam Python Examples - Part 2 Calculate Average Word Length with/without Fixed Look back
date: 2024-07-18
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
description: foo bar
---

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](#) (this post)
* Part 3 Build Sport Activity Tracker with/without SQL
* Part 4 Call RPC Service for Data Augmentation
* Part 5 Call RPC Service in Batch using Stateless DoFn
* Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
* Part 7 Separate Droppable Data into Side Output
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Development Environment

The development environment requires an Apache Flink cluster, Apache Kafka cluster and [gRPC](https://grpc.io/) Server. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about how to set up the development environment. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### Manage Environment

The Flink and Kafka clusters and gRPC server are managed by the following bash scripts.

- `./setup/start-flink-env.sh`
- `./setup/stop-flink-env.sh`

Those scripts accept four flags: `-f`, `-k` and `-g` to start/stop individual resources or `-a` to manage all of them. We can add multiple flags to start/stop multiple resources. Note that the scripts assume Flink 1.18.1 by default, and we can specify a specific Flink version if it is different from it e.g. `FLINK_VERSION=1.17.2 ./setup/start-flink-env.sh`.

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

## Beam Pipelines

We develop two pipelines that calculate average word lengths. The former emits an output whenever an input text message is read while the latter returns outputs in a sliding time window.

### Shared Transforms

Both the pipelines read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below.

```python
# chapter2/word_process_utils.py
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
        )


class WriteProcessOutputsToKafka(beam.PTransform):
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

### Calculate Average Word Length

The main transform of this pipeline (`CalculateAverageWordLength`) performs

1. `Windowing`: assigns input text messages into a [global window](https://beam.apache.org/documentation/programming-guide/#windowing) and emits (or triggers) the result for every new input message with the following configuration
    - Disallows Late data (`allowed_lateness=0`)
    - Assigns the output timestamp from the latest input timestamp (`timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST`)
    - Keeps the previous elements that were already fired (`accumulation_mode=AccumulationMode.ACCUMULATING`) 
2. `Tokenize`: tokenizes (or converts) text into words
3. `GetAvgWordLength`: calculates the average word lengths by combining all words using a custom combine function (`AverageFn`)
    - Using an accumulator, `AverageFn` obtains the average word length by dividing the sum of lengths with the number of words. 

Also, the output timestamp is added when creating output messages (`CreateMessags`). 

```python
# chapter2/average_word_length.py
import os
import json
import argparse
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import GlobalWindows, TimestampCombiner
from apache_beam.transforms.trigger import AfterCount, AccumulationMode, Repeatedly
from apache_beam.transforms.util import Reify
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from word_process_utils import tokenize, ReadWordsFromKafka, WriteProcessOutputsToKafka


class AvgAccum(typing.NamedTuple):
    length: int
    count: int


beam.coders.registry.register_coder(AvgAccum, beam.coders.RowCoder)


class AverageFn(beam.CombineFn):
    def create_accumulator(self):
        return AvgAccum(length=0, count=0)

    def add_input(self, mutable_accumulator: AvgAccum, element: str):
        length, count = tuple(mutable_accumulator)
        return AvgAccum(length=length + len(element), count=count + 1)

    def merge_accumulators(self, accumulators: typing.List[AvgAccum]):
        lengths, counts = zip(*accumulators)
        return AvgAccum(length=sum(lengths), count=sum(counts))

    def extract_output(self, accumulator: AvgAccum):
        length, count = tuple(accumulator)
        return length / count if count else float("NaN")

    def get_accumulator_coder(self):
        return beam.coders.registry.get_coder(AvgAccum)


class CalculateAverageWordLength(beam.PTransform):
    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "Windowing"
            >> beam.WindowInto(
                GlobalWindows(),
                trigger=Repeatedly(AfterCount(1)),
                allowed_lateness=0,
                timestamp_combiner=TimestampCombiner.OUTPUT_AT_LATEST,
                accumulation_mode=AccumulationMode.ACCUMULATING,
                # closing behaviour - EMIT_ALWAYS, on_time_behavior - FIRE_ALWAYS
            )
            | "Tokenize" >> beam.FlatMap(tokenize)
            | "GetAvgWordLength"
            >> beam.CombineGlobally(
                AverageFn()
            ).without_defaults()  # DAG gets complicated if with_default()
        )


def create_message(element: typing.Tuple[str, float]):
    msg = json.dumps(dict(zip(["created_at", "avg_len"], element)))
    print(msg)
    return "".encode("utf-8"), msg.encode("utf-8")


class AddTS(beam.DoFn):
    def process(self, avg_len: float, ts_param=beam.DoFn.TimestampParam):
        yield ts_param.to_rfc3339(), avg_len


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
            | "ReadInputsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
                deprecated_read=known_args.deprecated_read,
            )
            | "CalculateAverageWordLength" >> CalculateAverageWordLength()
            | "CreateMessags" >> CreateMessags()
            | "WriteOutputsToKafka"
            >> WriteProcessOutputsToKafka(
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

```python
# chapter2/average_word_length_test.py
import unittest

from apache_beam.coders import coders
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from average_word_length import CalculateAverageWordLength


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
                .add_elements(["a"])
                .add_elements(["bb"])
                .add_elements(["ccc"])
                .advance_watermark_to_infinity()
            )

            output = (
                p
                | test_stream
                | "CalculateMaxWordLength" >> CalculateAverageWordLength()
            )

            EXPECTED_OUTPUT = [1.0, 1.5, 2.0]

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter2/average_word_length_test.py -v
test_windowing_behaviour (__main__.MaxWordLengthTest) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.343s

OK
```

#### Pipeline Execution

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter2/average_word_length.py --deprecated_read \
         --job_name=avg-word-length --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

![](avg-word-len-dag.png#center)

![](avg-word-len-output.png#center)

### Calculate Average Word Length with Fixed Lookback

![](avg-lookback.png#center)

```python
# chapter2/sliding_window_word_length.py
import os
import json
import argparse
import re
import logging
import typing

import apache_beam as beam
from apache_beam import pvalue
from apache_beam.transforms.window import SlidingWindows
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from word_process_utils import tokenize, ReadWordsFromKafka, WriteProcessOutputsToKafka


class AvgAccum(typing.NamedTuple):
    length: int
    count: int


beam.coders.registry.register_coder(AvgAccum, beam.coders.RowCoder)


class AverageFn(beam.CombineFn):
    def create_accumulator(self):
        return AvgAccum(length=0, count=0)

    def add_input(self, mutable_accumulator: AvgAccum, element: str):
        length, count = tuple(mutable_accumulator)
        return AvgAccum(length=length + len(element), count=count + 1)

    def merge_accumulators(self, accumulators: typing.List[AvgAccum]):
        lengths, counts = zip(*accumulators)
        return AvgAccum(length=sum(lengths), count=sum(counts))

    def extract_output(self, accumulator: AvgAccum):
        length, count = tuple(accumulator)
        return length / count if count else float("NaN")

    def get_accumulator_coder(self):
        return beam.coders.registry.get_coder(AvgAccum)


class CalculateAverageWordLength(beam.PTransform):
    def __init__(self, size: int, period: int, label: str | None = None) -> None:
        super().__init__(label)
        self.size = size
        self.period = period

    def expand(self, pcoll: pvalue.PCollection):
        return (
            pcoll
            | "Windowing"
            >> beam.WindowInto(SlidingWindows(size=self.size, period=self.period))
            | "Tokenize" >> beam.FlatMap(tokenize)
            | "GetAvgWordLength" >> beam.CombineGlobally(AverageFn()).without_defaults()
        )


def create_message(element: typing.Tuple[str, str, float]):
    msg = json.dumps(dict(zip(["window_start", "window_end", "avg_len"], element)))
    print(msg)
    return "".encode("utf-8"), msg.encode("utf-8")


class AddWindowTS(beam.DoFn):
    def process(self, avg_len: float, win_param=beam.DoFn.WindowParam):
        yield (
            win_param.start.to_rfc3339(),
            win_param.end.to_rfc3339(),
            avg_len,
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
    parser.add_argument("--size", type=int, default=10, help="Window size")
    parser.add_argument("--period", type=int, default=2, help="Window period")
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
            | "ReadInputsFromKafka"
            >> ReadWordsFromKafka(
                bootstrap_servers=known_args.bootstrap_servers,
                topics=[known_args.input_topic],
                group_id=f"{known_args.output_topic}-group",
                deprecated_read=known_args.deprecated_read,
            )
            | "CalculateAverageWordLength"
            >> CalculateAverageWordLength(
                size=known_args.size, period=known_args.period
            )
            | "CreateMessags" >> CreateMessags()
            | "WriteOutputsToKafka"
            >> WriteProcessOutputsToKafka(
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

```python
# chapter2/sliding_window_word_length_test.py
import datetime
import unittest

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.utils.timestamp import Timestamp
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.transforms.window import TimestampedValue
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from sliding_window_word_length import CalculateAverageWordLength, AddWindowTS


def create_dt(index: int):
    return datetime.datetime.fromtimestamp(index, tz=datetime.timezone.utc).replace(
        tzinfo=None
    )


def to_rfc3339(dt: datetime.datetime):
    return f'{dt.isoformat(sep="T", timespec="seconds")}Z'


class SlidingWindowWordLengthTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            now = 8  # window start becomes datetime.datetime(1970, 1, 1, 0, 0) if 8, not 0??
            test_stream = (
                TestStream(coder=coders.StrUtf8Coder())
                .with_output_types(str)
                .add_elements([TimestampedValue("a", Timestamp.of(now + 0))])
                .add_elements([TimestampedValue("bb", Timestamp.of(now + 1.99))])
                .add_elements([TimestampedValue("ccc", Timestamp.of(now + 5))])
                .add_elements([TimestampedValue("dddd", Timestamp.of(now + 10))])
                .advance_watermark_to_infinity()
            )

            output = (
                p
                | test_stream
                | "CalculateAverageWordLength"
                >> CalculateAverageWordLength(size=10, period=2)
                | "AddWindowTS" >> beam.ParDo(AddWindowTS())
            )

            EXPECTED_VALUES = [1.5, 1.5, 2.0, 2.0, 2.0, 3.5, 3.5, 4.0, 4.0, 4.0]
            EXPECTED_OUTPUT = [
                (
                    to_rfc3339(create_dt(i * 2)),
                    to_rfc3339(create_dt(i * 2) + datetime.timedelta(seconds=10)),
                    EXPECTED_VALUES[i],
                )
                for i in range(len(EXPECTED_VALUES))
            ]

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

The pipeline can be tested as shown below.

```bash
python chapter2/sliding_window_word_length_test.py -v
test_windowing_behaviour (__main__.SlidingWindowWordLengthTest) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.358s

OK
```

#### Pipeline Execution

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter2/sliding_window_word_length.py --deprecated_read\
         --job_name=slinding-word-length --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000

```

![](avg-lookback-dag.png#center)

![](avg-lookback-output.png#center)
