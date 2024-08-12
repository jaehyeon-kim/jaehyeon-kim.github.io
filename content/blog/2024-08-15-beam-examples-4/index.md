---
title: Apache Beam Python Examples - Part 4 Call RPC Service for Data Augmentation
date: 2024-08-15
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
description: In this post, we develop two Apache Beam pipelines that track sport activities of users and output their speed periodically. The first pipeline uses native transforms and Beam SQL is used for the latter. While Beam SQL can be useful in some situations, its features in the Python SDK are not complete compared to the Java SDK. Therefore, we are not able to build the required tracking pipeline using it. We end up discussing potential improvements of Beam SQL so that it can be used for building competitive applications with the Python SDK.
---

In this post, we develop two Apache Beam pipelines that track sport activities of users and output their speed periodically. The first pipeline uses native transforms and [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) is used for the latter. While *Beam SQL* can be useful in some situations, its features in the Python SDK are not complete compared to the Java SDK. Therefore, we are not able to build the required tracking pipeline using it. We end up discussing potential improvements of *Beam SQL* so that it can be used for building competitive applications with the Python SDK.

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](#) (this post)
* Part 5 Call RPC Service in Batch using Stateless DoFn
* Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
* Part 7 Separate Droppable Data into Side Output
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Introduction to RPC Service

Two services are defined in the `.proto` file - `resolve` and `resolveBatch`. The former requests with a string and returns an integer while the latter requests with a list of the string requests and returns a list of the integer responses.

```proto
syntax = "proto3";

package chapter3;

message Request {
  string input = 1;
}

message Response {
  int32 output = 1;
}

message RequestList {
  repeated Request request = 1;
}

message ResponseList {
  repeated Response response = 1;
}

service RcpService {
  rpc resolve(Request) returns (Response);
  rpc resolveBatch(RequestList) returns (ResponseList);
}
```


```bash
cd chapter3
mkdir proto && touch proto/service.proto
## copy proto contents
## generate grpc client and server interfaces
python -m grpc_tools.protoc -I proto --python_out=. --grpc_python_out=. proto/service.proto
```

With the `.proto` service file, we can create 

Note that as we've already provided a version of the generated code in the proto directory, running this command regenerates the appropriate file rather than creates a new one. The generated code files are called `service_pb2.py` and `service_pb2_grpc.py` and contain:

- classes for the messages defined in `service.proto`
- classes for the service defined in `service.proto`
    - `RcpServiceStub`, which can be used by clients to invoke RcpService RPCs
    - `RcpServiceServicer`, which defines the interface for implementations of the RcpService service
- a function for the service defined in service.proto
    - `add_RcpServiceServicer_to_server`, which adds a RcpServiceServicer to a `grpc.Server`

```bash
tree -P "serv*|proto" -I "*pycache*"
.
├── proto
│   └── service.proto
├── server.py
├── server_client.py
├── service_pb2.py
├── service_pb2_grpc.py
├── service_test_mock.py
└── service_test_unit.py

1 directory, 7 files
```

![](rpc-demo.png#center)

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

### Beam Pipeline

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
# chapter3/rpc_pardo.py
import os
import argparse
import json
import re
import typing
import logging

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from io_utils import ReadWordsFromKafka, WriteOutputsToKafka


def create_message(element: typing.Tuple[str, int]):
    msg = json.dumps({"word": element[0], "length": element[1]})
    print(msg)
    return element[0].encode("utf-8"), msg.encode("utf-8")


class RpcDoFn(beam.DoFn):
    channel = None
    stub = None
    hostname = "localhost"
    port = "50051"

    def setup(self):
        import grpc
        import service_pb2_grpc

        self.channel: grpc.Channel = grpc.insecure_channel(
            f"{self.hostname}:{self.port}"
        )
        self.stub = service_pb2_grpc.RcpServiceStub(self.channel)

    def teardown(self):
        if self.channel is not None:
            self.channel.close()

    def process(self, element: str) -> typing.Iterator[typing.Tuple[str, int]]:
        import service_pb2

        request = service_pb2.Request(input=element)
        response = self.stub.resolve(request)
        yield element, response.output


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
            | "RequestRPC" >> beam.ParDo(RpcDoFn())
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
# chapter3/rpc_pardo_test.py
import os
import unittest
from concurrent import futures

import apache_beam as beam
from apache_beam.coders import coders
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

import grpc
import service_pb2_grpc
import server

from rpc_pardo import RpcDoFn
from io_utils import tokenize


def read_file(filename: str, inputpath: str):
    with open(os.path.join(inputpath, filename), "r") as f:
        return f.readlines()


def compute_expected_output(lines: list):
    output = []
    for line in lines:
        words = [(w, len(w)) for w in tokenize(line)]
        output = output + words
    return output


class RcpParDooTest(unittest.TestCase):
    server_class = server.RcpServiceServicer
    port = 50051

    def setUp(self):
        self.server = grpc.server(futures.ThreadPoolExecutor())
        service_pb2_grpc.add_RcpServiceServicer_to_server(
            self.server_class(), self.server
        )
        self.server.add_insecure_port(f"[::]:{self.port}")
        self.server.start()

    def tearDown(self):
        self.server.stop(None)

    def test_pipeline(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
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
                | "RequestRPC" >> beam.ParDo(RpcDoFn())
            )

            EXPECTED_OUTPUT = compute_expected_output(lines)

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter3/rpc_pardo_test.py 
.
----------------------------------------------------------------------
Ran 1 test in 0.373s

OK
```

#### Pipeline Execution

![](input-messages.png#center)

We specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter3/rpc_pardo.py --deprecated_read \
    --job_name=rpc-pardo --runner FlinkRunner --flink_master=localhost:8081 \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Flink UI, we see the pipeline has two tasks. The first task is performed until windowing the input elements while the second task performs up to sending the metric records into the output topic.

![](pipeline-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of user ID and speed.

![](output-messages.png#center)
