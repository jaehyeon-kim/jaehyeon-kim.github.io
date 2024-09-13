---
title: Apache Beam Python Examples - Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
date: 2024-10-09
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
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-25-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](#) (this post)
* Part 7 Separate Droppable Data into Side Output
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
./setup/start-flink-env.sh -f -k -g
# [+] Running 6/6
#  ⠿ Network app-network      Created                                                        0.0s
#  ⠿ Volume "kafka_0_data"    Created                                                        0.0s
#  ⠿ Volume "zookeeper_data"  Created                                                        0.0s
#  ⠿ Container zookeeper      Started                                                        0.5s
#  ⠿ Container kafka-0        Started                                                        0.7s
#  ⠿ Container kafka-ui       Started                                                        0.9s
# [+] Running 2/2
#  ⠿ Network grpc-network   Created                                                          0.0s
#  ⠿ Container grpc-server  Started                                                          0.4s
# start flink 1.18.1...
# Starting cluster.
# Starting standalonesession daemon on host <hostname>.
# Starting taskexecutor daemon on host <hostname>.

## start a local kafka cluster only
./setup/start-flink-env.sh -k -g
# [+] Running 6/6
#  ⠿ Network app-network      Created                                                        0.0s
#  ⠿ Volume "kafka_0_data"    Created                                                        0.0s
#  ⠿ Volume "zookeeper_data"  Created                                                        0.0s
#  ⠿ Container zookeeper      Started                                                        0.5s
#  ⠿ Container kafka-0        Started                                                        0.7s
#  ⠿ Container kafka-ui       Started                                                        0.9s
# [+] Running 2/2
#  ⠿ Network grpc-network   Created                                                          0.0s
#  ⠿ Container grpc-server  Started                                                          0.4s
```

## Remote Procedure Call (RPC) Service

The RPC service have two methods - `resolve` and `resolveBatch`. The former accepts a request with a string and returns an integer while the latter accepts a list of string requests and returns a list of integer responses. See [Part 4](/blog/2024-08-15-beam-examples-4) for details about how the RPC service is developed.

Overall, we have the following files for the gRPC server and client applications, and the `server.py` gets started when we execute the start-up script with the `-g` flag.

```bash
tree -P "serv*|proto" -I "*pycache*"
.
├── proto
│   └── service.proto
├── server.py
├── server_client.py
├── service_pb2.py
└── service_pb2_grpc.py

1 directory, 5 files
```

We can check the client and server applications as Python scripts. If we select 1, the next prompt requires to enter a word. Upon entering a word, it returns a tuple of the word and its length as an output. We can make an RPC request with a text if we select 2. Similar to the earlier call, it returns enriched outputs as multiple tuples.

![](rpc-demo.png#center)

## Beam Pipeline

We develop an Apache Beam pipeline that accesses an external RPC service to augment input elements. In this version, it is configured so that a single RPC call is made for multiple elements in batch. Using state and timers, it controls how many elements to process in a batch and how long to keep elements before flushing them.

### Shared Source

We have multiple pipelines that read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below. Note that, the Kafka read and write methods has an argument called `deprecated_read`, which forces to use the legacy read when it is set to *True*. We will use the legacy read in this post to prevent a problem that is described in this [GitHub issue](https://github.com/apache/beam/issues/20979).

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

In `BatchRpcDoFnStateful`, we use state and timers to control how many elements to process in a batch and how long to keep elements before flushing them.

**State**
- `BATCH_SIZE`
    - A varying integer value is kept in this state, and its value increases by one when a new element is added to a *batch*. It is used to determine whether to flush the elements in the batch for processing.
- `BATCH`
    - Input elements are kept in this state until being flushed.

**Timers**
- `FLUSH_TIMER`
    - This timer is triggered when it exceeds the maximum wait seconds. Without this timer, input elements may be held forever if the number of elements is less than the defined batch size. 
- `EOW_TIMER`
    - This timer is set up to ensure any existing elements are flushed at the end of the window.

In the `process` method, we set the flush and end of window timers if there is no element is a batch. Then, we add a new element to the batch and increase the batch size by one. Finally, the elements are flushed if the current batch size is greater than or equal to the defined batch size. In the `flush` method, it begins with collecting elements in the batch, followed by clearing up all state and timers. Then, a single RPC call is made to the `resolveBatch` method after unique input elements are converted into a `RequestList` object. Once a response is made, output elements are constructed by augmenting input elements with the response, and the output elements are returned as a list.

```python
# chapter3/rpc_pardo_stateful.py
import os
import argparse
import json
import re
import typing
import logging

import apache_beam as beam
from apache_beam.transforms.timeutil import TimeDomain
from apache_beam.transforms.userstate import (
    ReadModifyWriteStateSpec,
    BagStateSpec,
    TimerSpec,
    on_timer,
)
from apache_beam.transforms.window import GlobalWindow
from apache_beam.utils.windowed_value import WindowedValue
from apache_beam.utils.timestamp import Timestamp, Duration
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from io_utils import ReadWordsFromKafka, WriteOutputsToKafka


class ValueCoder(beam.coders.Coder):
    def encode(self, e: typing.Tuple[int, str]):
        """Encode to bytes with a trace that coder was used."""
        return f"x:{e[0]}:{e[1]}".encode("utf-8")

    def decode(self, b: bytes):
        s = b.decode("utf-8")
        assert s[0:2] == "x:"
        return tuple(s.split(":")[1:])

    def is_deterministic(self):
        return True


beam.coders.registry.register_coder(typing.Tuple[int, str], ValueCoder)


def create_message(element: typing.Tuple[str, int]):
    msg = json.dumps({"word": element[0], "length": element[1]})
    print(msg)
    return element[0].encode("utf-8"), msg.encode("utf-8")


def to_buckets(e: str):
    return (ord(e[0]) % 10, e)


class BatchRpcDoFnStateful(beam.DoFn):
    channel = None
    stub = None
    hostname = "localhost"
    port = "50051"

    BATCH_SIZE = ReadModifyWriteStateSpec("batch_size", beam.coders.VarIntCoder())
    BATCH = BagStateSpec(
        "batch",
        beam.coders.WindowedValueCoder(wrapped_value_coder=ValueCoder()),
    )
    FLUSH_TIMER = TimerSpec("flush_timer", TimeDomain.REAL_TIME)
    EOW_TIMER = TimerSpec("end_of_time", TimeDomain.WATERMARK)

    def __init__(self, batch_size: int, max_wait_secs: int):
        self.batch_size = batch_size
        self.max_wait_secs = max_wait_secs

    def setup(self):
        import grpc
        import service_pb2_grpc

        self.channel: grpc.Channel = grpc.insecure_channel(
            f"{self.hostname}:{self.port}"
        )
        self.stub = service_pb2_grpc.RpcServiceStub(self.channel)

    def teardown(self):
        if self.channel is not None:
            self.channel.close()

    def process(
        self,
        element: typing.Tuple[int, str],
        batch=beam.DoFn.StateParam(BATCH),
        batch_size=beam.DoFn.StateParam(BATCH_SIZE),
        flush_timer=beam.DoFn.TimerParam(FLUSH_TIMER),
        eow_timer=beam.DoFn.TimerParam(EOW_TIMER),
        timestamp=beam.DoFn.TimestampParam,
        win_param=beam.DoFn.WindowParam,
    ):
        current_size = batch_size.read() or 0
        if current_size == 0:
            flush_timer.set(Timestamp.now() + Duration(seconds=self.max_wait_secs))
            eow_timer.set(GlobalWindow().max_timestamp())
        current_size += 1
        batch_size.write(current_size)
        batch.add(
            WindowedValue(value=element, timestamp=timestamp, windows=(win_param,))
        )
        if current_size >= self.batch_size:
            return self.flush(batch, batch_size, flush_timer, eow_timer)

    @on_timer(FLUSH_TIMER)
    def on_flush_timer(
        self,
        batch=beam.DoFn.StateParam(BATCH),
        batch_size=beam.DoFn.StateParam(BATCH_SIZE),
        flush_timer=beam.DoFn.TimerParam(FLUSH_TIMER),
        eow_timer=beam.DoFn.TimerParam(EOW_TIMER),
    ):
        return self.flush(batch, batch_size, flush_timer, eow_timer)

    @on_timer(EOW_TIMER)
    def on_eow_timer(
        self,
        batch=beam.DoFn.StateParam(BATCH),
        batch_size=beam.DoFn.StateParam(BATCH_SIZE),
        flush_timer=beam.DoFn.TimerParam(FLUSH_TIMER),
        eow_timer=beam.DoFn.TimerParam(EOW_TIMER),
    ):
        return self.flush(batch, batch_size, flush_timer, eow_timer)

    def flush(
        self,
        batch=beam.DoFn.StateParam(BATCH),
        batch_size=beam.DoFn.StateParam(BATCH_SIZE),
        flush_timer=beam.DoFn.TimerParam(FLUSH_TIMER),
        eow_timer=beam.DoFn.TimerParam(EOW_TIMER),
    ):
        import service_pb2

        elements = list(batch.read())

        batch.clear()
        batch_size.clear()
        if flush_timer:
            flush_timer.clear()
        if eow_timer:
            eow_timer.clear()

        unqiue_values = set([e.value for e in elements])
        request_list = service_pb2.RequestList()
        request_list.request.extend(
            [service_pb2.Request(input=e[1]) for e in unqiue_values]
        )
        response = self.stub.resolveBatch(request_list)
        resolved = dict(
            zip([e[1] for e in unqiue_values], [r.output for r in response.response])
        )

        return [
            WindowedValue(
                value=(e.value[1], resolved[e.value[1]]),
                timestamp=e.timestamp,
                windows=e.windows,
            )
            for e in elements
        ]


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
        "--batch_size", type=int, default=10, help="Batch size to process"
    )
    parser.add_argument(
        "--max_wait_secs",
        type=int,
        default=4,
        help="Maximum wait seconds before processing",
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
            | "ToBuckets"
            >> beam.Map(to_buckets).with_output_types(typing.Tuple[int, str])
            | "RequestRPC"
            >> beam.ParDo(
                BatchRpcDoFnStateful(
                    batch_size=known_args.batch_size,
                    max_wait_secs=known_args.max_wait_secs,
                )
            )
            | "CreateMessags"
            >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
            | "WriteOutputsToKafka"
            >> WriteOutputsToKafka(
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

We use a text file that keeps a random text (`input/lorem.txt`) for testing. Then, we add the lines into a test stream and apply the main transform. Finally, we compare the actual output with an expected output. The expected output is a list of tuples where each element is a word and its length. Note that, I had an issue to run this test using the Python *DirectRunner*. Therefore, the *FlinkRunner* is used instead.

```python
# chapter3/rpc_pardo_stateful_test.py
import os
import unittest
import typing
from concurrent import futures

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.options.pipeline_options import PipelineOptions

import grpc
import service_pb2_grpc
import server

from rpc_pardo_stateful import to_buckets, BatchRpcDoFnStateful
from io_utils import tokenize


class MyItem(typing.NamedTuple):
    word: str
    length: int


beam.coders.registry.register_coder(MyItem, beam.coders.RowCoder)


def read_file(filename: str, inputpath: str):
    with open(os.path.join(inputpath, filename), "r") as f:
        return f.readlines()


def compute_expected_output(lines: list):
    output = []
    for line in lines:
        words = [(w, len(w)) for w in tokenize(line)]
        output = output + words
    return output


class RpcParDooStatefulTest(unittest.TestCase):
    server_class = server.RpcServiceServicer
    port = 50051

    def setUp(self):
        self.server = grpc.server(futures.ThreadPoolExecutor())
        service_pb2_grpc.add_RpcServiceServicer_to_server(
            self.server_class(), self.server
        )
        self.server.add_insecure_port(f"[::]:{self.port}")
        self.server.start()

    def tearDown(self):
        self.server.stop(None)

    def test_pipeline(self):
        pipeline_opts = {"runner": "FlinkRunner", "parallelism": 1, "streaming": True}
        options = PipelineOptions([], **pipeline_opts)
        with TestPipeline(options=options) as p:
            PARENT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
            lines = read_file("lorem.txt", os.path.join(PARENT_DIR, "inputs"))
            test_stream = TestStream(coder=coders.StrUtf8Coder()).with_output_types(str)
            for line in lines:
                test_stream.add_elements([line])
            test_stream.advance_watermark_to_infinity()

            output = (
                p
                | test_stream
                | "ExtractWords" >> beam.FlatMap(tokenize)
                | "ToBuckets"
                >> beam.Map(to_buckets).with_output_types(typing.Tuple[int, str])
                | "RequestRPC"
                >> beam.ParDo(BatchRpcDoFnStateful(batch_size=10, max_wait_secs=5))
            )

            EXPECTED_OUTPUT = compute_expected_output(lines)

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter3/rpc_pardo_stateful_test.py 
WARNING:root:Waiting for grpc channel to be ready at localhost:46459.
WARNING:root:Waiting for grpc channel to be ready at localhost:46459.
WARNING:root:Waiting for grpc channel to be ready at localhost:46459.
.
----------------------------------------------------------------------
Ran 1 test in 19.801s

OK
```

#### Pipeline Execution

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed on *localhost:29092* from the Docker host machine and on *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by a Kafka producer app that is discussed later and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

We need to send messages into the input Kafka topic before executing the pipeline. Input text message can be sent by executing a Kafka text producer - `python utils/faker_gen.py`.

![](input-messages.png#center)

When executing the pipeline, we specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter3/rpc_pardo_stateful.py --deprecated_read \
    --job_name=rpc-pardo-stateful --runner FlinkRunner --flink_master=localhost:8081 \
  --streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Flink UI, we see the pipeline only has a single task.

![](pipeline-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of a word and its length.

![](output-messages.png#center)
