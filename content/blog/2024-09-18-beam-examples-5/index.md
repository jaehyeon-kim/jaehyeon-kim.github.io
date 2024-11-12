---
title: Apache Beam Python Examples - Part 5 Call RPC Service in Batch using Stateless DoFn
date: 2024-09-18
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
  - gRPC
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: 
---

In the [previous post](/blog/2024-08-15-beam-examples-4), we developed an Apache Beam pipeline where the input data is augmented by a **Remote Procedure Call (RPC)** service. Each input element performs an RPC call and the output is enriched by the response. This is not an efficient way of accessing an external service provided that the service can accept more than one element. In this post, we discuss how to enhance the pipeline so that a single RPC call is made for a bundle of elements, which can save a significant amount time compared to making a call for each element.

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](#) (this post)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* [Part 7 Separate Droppable Data into Side Output](/blog/2024-10-24-beam-examples-7)
* [Part 8 Enhance Sport Activity Tracker with Runner Motivation](/blog/2024-11-21-beam-examples-8)
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

We develop an Apache Beam pipeline that accesses an external RPC service to augment input elements. In this version, it is configured so that a single RPC call is made for a bundle of elements.

### Shared Source

We have multiple pipelines that read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below. Note that, the Kafka read and write transforms have an argument called `deprecated_read`, which forces to use the legacy read when it is set to *True*. We will use the legacy read in this post to prevent a problem that is described in this [GitHub issue](https://github.com/apache/beam/issues/20979).

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
        deprecated_read: bool, # TO DO: remove as it applies only to ReadFromKafka
        label: str | None = None,
    ) -> None:
        super().__init__(label)
        self.boostrap_servers = bootstrap_servers
        self.topic = topic
        # TO DO: remove as it applies only to ReadFromKafka
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

According to the life cycle of a `DoFn` object, the `BatchRpcDoFn` is configured as follows.
- `setUp` - The RPC service is established because this method is commonly used to initialize transient resources that are needed during the processing.
- `start_bundle` - In a `DoFn` object, input elements are split into chunks called bundles, and this method is invoked when a new bundle arrives. We initialise an empty list to keep input elements in a bundle.
- `process` - Each input element in a bundle is appended into the elements list after being converted into a `WindowedValue` object.
- `finish_bundle` - A single RPC call is made to the `resolveBatch` method after unique input elements are converted into a `RequestList` object. It has two advantages. First, as requests with the same input tend to return the same output, making a call with unique elements can reduce request time. Secondly, calling to the `resolveBatch` method with multiple elements can save a significant amount of time compared to making a call for each element. Once a response is made, output elements are constructed by augmenting input elements with the response, and the output elements are returned as a list.
- `teardown` - The connection (channel) to the RPC service is closed.

```python
# chapter3/rpc_pardo_batch.py
import os
import argparse
import json
import re
import typing
import logging

import apache_beam as beam
from apache_beam.utils.windowed_value import WindowedValue
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from io_utils import ReadWordsFromKafka, WriteOutputsToKafka


def create_message(element: typing.Tuple[str, int]):
    msg = json.dumps({"word": element[0], "length": element[1]})
    print(msg)
    return element[0].encode("utf-8"), msg.encode("utf-8")


class BatchRpcDoFn(beam.DoFn):
    channel = None
    stub = None
    elements: typing.List[WindowedValue] = None
    hostname = "localhost"
    port = "50051"

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

    def start_bundle(self):
        self.elements = []

    def finish_bundle(self):
        import service_pb2

        unqiue_values = set([e.value for e in self.elements])
        request_list = service_pb2.RequestList()
        request_list.request.extend(
            [service_pb2.Request(input=e) for e in unqiue_values]
        )
        response = self.stub.resolveBatch(request_list)
        resolved = dict(zip(unqiue_values, [r.output for r in response.response]))

        return [
            WindowedValue(
                value=(e.value, resolved[e.value]),
                timestamp=e.timestamp,
                windows=e.windows,
            )
            for e in self.elements
        ]

    def process(
        self,
        element: str,
        timestamp=beam.DoFn.TimestampParam,
        win_param=beam.DoFn.WindowParam,
    ):
        self.elements.append(
            WindowedValue(value=element, timestamp=timestamp, windows=(win_param,))
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
            | "RequestRPC" >> beam.ParDo(BatchRpcDoFn())
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

We use a text file that keeps a random text (`input/lorem.txt`) for testing. Then, we add the lines into a test stream and apply the main transform. Finally, we compare the actual output with an expected output. The expected output is a list of tuples where each element is a word and its length.

```python
# chapter3/rpc_pardo_batch_test.py
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

from rpc_pardo_batch import BatchRpcDoFn
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


class RpcParDooBatchTest(unittest.TestCase):
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
                | "RequestRPC" >> beam.ParDo(BatchRpcDoFn())
            )

            EXPECTED_OUTPUT = compute_expected_output(lines)

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    unittest.main()
```

We can execute the pipeline test as shown below.

```bash
python chapter3/rpc_pardo_batch_test.py 
.
----------------------------------------------------------------------
Ran 1 test in 0.285s

OK
```

#### Pipeline Execution

Note that the Kafka bootstrap server is accessible on port *29092* outside the Docker network, and it can be accessed on *localhost:29092* from the Docker host machine and on *host.docker.internal:29092* from a Docker container that is launched with the host network. We use both types of the bootstrap server address - the former is used by the Kafka producer app and the latter by a Java IO expansion service, which is launched in a Docker container. Note further that, for the latter to work, we have to update the */etc/hosts* file by adding an entry for *host.docker.internal* as shown below. 

```bash
cat /etc/hosts | grep host.docker.internal
# 127.0.0.1       host.docker.internal
```

We need to send messages into the input Kafka topic before executing the pipeline. Input messages can be sent by executing the Kafka text producer - `python utils/faker_gen.py`. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about the Kafka producer.

![](input-messages.png#center)

When executing the pipeline, we specify only a single known argument that enables to use the legacy read (`--deprecated_read`) while accepting default values of the other known arguments (`bootstrap_servers`, `input_topic` ...). The remaining arguments are all pipeline arguments. Note that we deploy the pipeline on a local Flink cluster by specifying the flink master argument (`--flink_master=localhost:8081`). Alternatively, we can use an embedded Flink cluster if we exclude that argument.

```bash
## start the beam pipeline
## exclude --flink_master if using an embedded cluster
python chapter3/rpc_pardo_batch.py --deprecated_read \
    --job_name=rpc-pardo-batch --runner FlinkRunner --flink_master=localhost:8081 \
    --streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

On Flink UI, we see the pipeline only has a single task.

![](pipeline-dag.png#center)

On Kafka UI, we can check the output message is a dictionary of a word and its length.

![](output-messages.png#center)
