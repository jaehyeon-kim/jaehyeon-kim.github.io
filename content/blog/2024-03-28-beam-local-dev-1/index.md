---
title: Apache Beam Local Development with Python - Part 1 Pipeline, Notebook, SQL and DataFrame
date: 2024-03-28
draft: false
featured: true
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
description: Apache Beam and Apache Flink are open-source frameworks for parallel, distributed data processing at scale. Flink has DataStream and Table/SQL APIs and the former has more capacity to develop sophisticated data streaming applications. The DataStream API of PyFlink, Flink’s Python API, however, is not as complete as its Java counterpart, and it doesn’t provide enough capability to extend when there are missing features in Python. On the other hand, Apache Beam supports more possibility to extend and/or customise its features. In this series of posts, we discuss local development of Apache Beam pipelines using Python. In Part 1, a basic Beam pipeline is introduced, followed by demonstrating how to utilise Jupyter notebooks for interactive development. It also covers Beam SQL and Beam DataFrames examples on notebooks. In subsequent posts, we will discuss batch and streaming pipeline development and concludes with illustrating unit testing of existing pipelines.
---

[Apache Beam](https://beam.apache.org/) and [Apache Flink](https://flink.apache.org/) are open-source frameworks for parallel, distributed data processing at scale. Flink has DataStream and Table/SQL APIs and the former has more capacity to develop sophisticated data streaming applications. The DataStream API of PyFlink, Flink's Python API, however, is not as complete as its Java counterpart, and it doesn't provide enough capability to extend when there are missing features in Python. Recently I had a chance to look through Apache Beam and found it supports more possibility to extend and/or customise its features.

In this series of posts, we discuss local development of Apache Beam pipelines using Python. In *Part 1*, a basic Beam pipeline is introduced, followed by demonstrating how to utilise Jupyter notebooks for interactive development. Several notebook examples are covered including [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) and [Beam DataFrames](https://beam.apache.org/documentation/dsls/dataframes/overview/). Batch pipelines will be developed in *Part 2*, and we use pipelines from [GCP Python DataFlow Quest](https://github.com/GoogleCloudPlatform/training-data-analyst/tree/master/quests/dataflow_python) while modifying them to access local resources only. Each batch pipeline has two versions with/without SQL. Beam doesn't have its own processing engine and Beam pipelines are executed on a runner such as Apache Flink, Apache Spark, or Google Cloud Dataflow instead. We will use the [Flink Runner](https://beam.apache.org/documentation/runners/flink/) for deploying streaming pipelines as it supports [a wide range of features](https://beam.apache.org/documentation/runners/capability-matrix/) especially in streaming context. In *Part 3*, we will discuss how to set up a local Flink cluster as well as a local Kafka cluster for data source and sink. A streaming pipeline with/without Beam SQL will be built in *Part 4*, and this series concludes with illustrating unit testing of existing pipelines in *Part 5*.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](#) (this post)
* [Part 2 Batch Pipelines](/blog/2024-04-04-beam-local-dev-2)
* [Part 3 Flink Runner](/blog/2024-04-18-beam-local-dev-3)
* [Part 4 Streaming Pipelines](/blog/2024-05-02-beam-local-dev-4)
* [Part 5 Testing Pipelines](/blog/2024-05-09-beam-local-dev-5)

## Prerequisites

We need to install Java, Docker and GraphViz.
- [Java 11](https://nightlies.apache.org/flink/flink-docs-stable/docs/try-flink/local_installation/) to launch a local Flink cluster
- [Docker](https://www.docker.com/) for Kafka connection/executing Beam SQL as well as deploying a Kafka cluster
- [GraphViz](https://www.graphviz.org/about/) to visualize pipeline DAGs

```bash
$ java --version
openjdk 11.0.22 2024-01-16
OpenJDK Runtime Environment (build 11.0.22+7-post-Ubuntu-0ubuntu220.04.1)
OpenJDK 64-Bit Server VM (build 11.0.22+7-post-Ubuntu-0ubuntu220.04.1, mixed mode, sharing)

$ docker --version
Docker version 24.0.6, build ed223bc

$ dot -V
dot - graphviz version 2.43.0 (0)
```

Also, I use Python 3.10.13 and Beam 2.53.0 - supported Python versions are 3.8, 3.9, 3.10, 3.11. The following list shows key dependent packages.

- apache-beam[gcp,aws,azure,test,docs,interactive]==2.53.0
- jupyterlab==4.1.2
- kafka-python
- faker
- geocoder

The source of this post can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-dev-env).

### Data Generator

Website visit log is used as source data for both batch and streaming data pipelines. It begins with creating a configurable number of users and simulates their website visit history. When the source argument is *batch*, it writes the records into a folder named *inputs* while those are sent to a Kafka topic named *website-visit* if the source is *streaming* - we will talk further about streaming source generation in *Part 3*. Below shows how to execute the script for batch and streaming sources respectively.

```bash
# Batch example:
python datagen/generate_data.py --source batch --num_users 20 --num_events 10000 --max_lag_seconds 60

# Streaming example:
python datagen/generate_data.py --source streaming --num_users 5 --delay_seconds 0.5
```

```python
# datagen/generate_data.py
import os
import json
import uuid
import argparse
import datetime
import time
import math
from faker import Faker
import geocoder
import random
from kafka import KafkaProducer


class EventGenerator:
    def __init__(
        self,
        source: str,
        num_users: int,
        num_events: int,
        max_lag_seconds: int,
        delay_seconds: float,
        bootstrap_servers: list,
        topic_name: str,
        file_name: str = str(uuid.uuid4()),
    ):
        self.source = source
        self.num_users = num_users
        self.num_events = num_events
        self.max_lag_seconds = max_lag_seconds
        self.delay_seconds = delay_seconds
        self.bootstrap_servers = bootstrap_servers
        self.topic_name = topic_name
        self.file_name = file_name
        self.user_pool = self.create_user_pool()
        if self.source == "streaming":
            self.kafka_producer = self.create_producer()

    def create_user_pool(self):
        """
        Returns a list of user instances given the max number of users.
        Each user instances is a dictionary that has the following attributes:
            ip, id, lat, lng, user_agent, age_bracket, opted_into_marketing
        """
        init_fields = [
            "ip",
            "id",
            "lat",
            "lng",
            "user_agent",
            "age_bracket",
            "opted_into_marketing",
        ]
        user_pool = []
        for _ in range(self.num_users):
            user_pool.append(dict(zip(init_fields, self.set_initial_values())))
        return user_pool

    def create_producer(self):
        """
        Returns a KafkaProducer instance
        """
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda v: json.dumps(v).encode("utf-8"),
        )

    def set_initial_values(self, faker=Faker()):
        """
        Returns initial user attribute values using Faker
        """
        ip = faker.ipv4()
        lookup = geocoder.ip(ip)
        try:
            lat, lng = lookup.latlng
        except Exception:
            lat, lng = "", ""
        id = str(hash(f"{ip}{lat}{lng}"))
        user_agent = random.choice(
            [
                faker.firefox,
                faker.chrome,
                faker.safari,
                faker.internet_explorer,
                faker.opera,
            ]
        )()
        age_bracket = random.choice(["18-25", "26-40", "41-55", "55+"])
        opted_into_marketing = random.choice([True, False])
        return ip, id, lat, lng, user_agent, age_bracket, opted_into_marketing

    def set_req_info(self):
        """
        Returns a tuple of HTTP request information - http_request, http_response, file_size_bytes
        """
        uri = random.choice(
            [
                "home.html",
                "archea.html",
                "archaea.html",
                "bacteria.html",
                "eucharya.html",
                "protozoa.html",
                "amoebozoa.html",
                "chromista.html",
                "cryptista.html",
                "plantae.html",
                "coniferophyta.html",
                "fungi.html",
                "blastocladiomycota.html",
                "animalia.html",
                "acanthocephala.html",
            ]
        )
        file_size_bytes = random.choice(range(100, 500))
        http_request = f"{random.choice(['GET'])} {uri} HTTP/1.0"
        http_response = random.choice([200])
        return http_request, http_response, file_size_bytes

    def append_to_file(self, event: dict):
        """
        Appends a website visit event record into an event output file.
        """
        parent_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
        with open(
            os.path.join(parent_dir, "inputs", f"{self.file_name}.out"), "a"
        ) as fp:
            fp.write(f"{json.dumps(event)}\n")

    def send_to_kafka(self, event: dict):
        """
        Sends a website visit event record into a Kafka topic.
        """
        try:
            self.kafka_producer.send(
                self.topic_name,
                key={"event_id": event["id"], "event_ts": event["event_ts"]},
                value=event,
            )
            self.kafka_producer.flush()
        except Exception as e:
            raise RuntimeError("fails to send a message") from e

    def generate_events(self):
        """
        Generate webstie visit events as per the max number events.
        Events are either saved to an output file (batch) or sent to a Kafka topic (streaming).
        """
        num_events = 0
        while True:
            num_events += 1
            if num_events > self.num_events:
                break
            event_ts = datetime.datetime.utcnow() + datetime.timedelta(
                seconds=random.uniform(0, self.max_lag_seconds)
            )
            req_info = dict(
                zip(
                    ["http_request", "http_response", "file_size_bytes"],
                    self.set_req_info(),
                )
            )
            event = {
                **random.choice(self.user_pool),
                **req_info,
                **{
                    "event_datetime": event_ts.isoformat(timespec="milliseconds"),
                    "event_ts": int(event_ts.timestamp() * 1000),
                },
            }
            divide_by = 100 if self.source == "batch" else 10
            if num_events % divide_by == 0:
                print(f"{num_events} events created so far...")
                print(event)
            if self.source == "batch":
                self.append_to_file(event)
            else:
                self.send_to_kafka(event)
                time.sleep(self.delay_seconds or 0)


if __name__ == "__main__":
    """
    Batch example:
        python datagen/generate_data.py --source batch --num_users 20 --num_events 10000 --max_lag_seconds 60
    Streaming example:
        python datagen/generate_data.py --source streaming --num_users 5 --delay_seconds 0.5
    """
    parser = argparse.ArgumentParser(__file__, description="Web Server Data Generator")
    parser.add_argument(
        "--source",
        "-s",
        type=str,
        default="batch",
        choices=["batch", "streaming"],
        help="The data source - batch or streaming",
    )
    parser.add_argument(
        "--num_users",
        "-u",
        type=int,
        default=50,
        help="The number of users to create",
    )
    parser.add_argument(
        "--num_events",
        "-e",
        type=int,
        default=math.inf,
        help="The number of events to create.",
    )
    parser.add_argument(
        "--max_lag_seconds",
        "-l",
        type=int,
        default=0,
        help="The maximum seconds that a record can be lagged.",
    )
    parser.add_argument(
        "--delay_seconds",
        "-d",
        type=float,
        default=None,
        help="The amount of time that a record should be delayed. Only applicable to streaming.",
    )

    args = parser.parse_args()
    source = args.source
    num_users = args.num_users
    num_events = args.num_events
    max_lag_seconds = args.max_lag_seconds
    delay_seconds = args.delay_seconds

    gen = EventGenerator(
        source,
        num_users,
        num_events,
        max_lag_seconds,
        delay_seconds,
        os.getenv("BOOTSTRAP_SERVERS", "localhost:29092"),
        os.getenv("TOPIC_NAME", "website-visit"),
    )
    gen.generate_events()
```

Once we execute the script for generating batch pipeline data, we see a new file is created in the *inputs* folder as shown below.

```bash
$ python datagen/generate_data.py --source batch --num_users 20 --num_events 10000 --max_lag_seconds 60
...
$ head -n 3 inputs/4b1dba74-d970-4c67-a631-e0d7f52ad00e.out 
{"ip": "74.236.125.208", "id": "-5227372761963790049", "lat": 26.3587, "lng": -80.0831, "user_agent": "Mozilla/5.0 (Windows; U; Windows NT 5.1) AppleWebKit/534.23.4 (KHTML, like Gecko) Version/4.0.5 Safari/534.23.4", "age_bracket": "26-40", "opted_into_marketing": true, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 115, "event_datetime": "2024-03-25T04:26:55.473", "event_ts": 1711301215473}
{"ip": "75.153.216.235", "id": "5836835583895516006", "lat": 49.2302, "lng": -122.9952, "user_agent": "Mozilla/5.0 (Android 6.0.1; Mobile; rv:11.0) Gecko/11.0 Firefox/11.0", "age_bracket": "41-55", "opted_into_marketing": true, "http_request": "GET acanthocephala.html HTTP/1.0", "http_response": 200, "file_size_bytes": 358, "event_datetime": "2024-03-25T04:27:01.930", "event_ts": 1711301221930}
{"ip": "134.157.0.190", "id": "-5123638115214052647", "lat": 48.8534, "lng": 2.3488, "user_agent": "Mozilla/5.0 (X11; Linux i686) AppleWebKit/534.2 (KHTML, like Gecko) Chrome/23.0.825.0 Safari/534.2", "age_bracket": "55+", "opted_into_marketing": true, "http_request": "GET bacteria.html HTTP/1.0", "http_response": 200, "file_size_bytes": 402, "event_datetime": "2024-03-25T04:27:16.037", "event_ts": 1711301236037}
```

## Basic Pipeline

Below shows a basic Beam pipeline. It (1) reads one or more files that match a file name pattern, (2) parses lines of Json string into Python dictionaries, (3) filters records where *opted_into_marketing* is TRUE, (4) selects a subset of attributes and finally (5) writes the updated records into a folder named outputs. It uses the [Direct Runner](https://beam.apache.org/documentation/runners/direct/) by default, and we can also try a different runner by specifying the *runner* name (eg `python section1/basic.py --runner FlinkRunner`).

```python
# section1/basic.py
import os
import datetime
import argparse
import json
import logging

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import StandardOptions


def run():
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--inputs",
        default="inputs",
        help="Specify folder name that event records are saved",
    )
    parser.add_argument(
        "--runner", default="DirectRunner", help="Specify Apache Beam Runner"
    )
    opts = parser.parse_args()
    PARENT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

    options = PipelineOptions()
    options.view_as(StandardOptions).runner = opts.runner

    p = beam.Pipeline(options=options)
    (
        p
        | "Read from files"
        >> beam.io.ReadFromText(
            file_pattern=os.path.join(PARENT_DIR, opts.inputs, "*.out")
        )
        | "Parse Json" >> beam.Map(lambda line: json.loads(line))
        | "Filter status" >> beam.Filter(lambda d: d["opted_into_marketing"] is True)
        | "Select columns"
        >> beam.Map(
            lambda d: {
                k: v
                for k, v in d.items()
                if k in ["ip", "id", "lat", "lng", "age_bracket"]
            }
        )
        | "Write to file"
        >> beam.io.WriteToText(
            file_path_prefix=os.path.join(
                PARENT_DIR,
                "outputs",
                f"{int(datetime.datetime.now().timestamp() * 1000)}",
            ),
            file_name_suffix=".out",
        )
    )

    logging.getLogger().setLevel(logging.INFO)
    logging.info("Building pipeline ...")

    p.run().wait_until_finish()


if __name__ == "__main__":
    run()
```

Once executed, we can check the output records in the *outputs* folder.

```bash
$ python section1/basic.py 
INFO:root:Building pipeline ...
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function annotate_downstream_side_inputs at 0x7f1d24906050> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function fix_side_input_pcoll_coders at 0x7f1d24906170> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function pack_combiners at 0x7f1d24906680> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function lift_combiners at 0x7f1d24906710> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function expand_sdf at 0x7f1d249068c0> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function expand_gbk at 0x7f1d24906950> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function sink_flattens at 0x7f1d24906a70> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function greedily_fuse at 0x7f1d24906b00> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function read_to_impulse at 0x7f1d24906b90> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function impulse_to_input at 0x7f1d24906c20> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function sort_stages at 0x7f1d24906e60> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function add_impulse_to_dangling_transforms at 0x7f1d24906f80> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function setup_timer_mapping at 0x7f1d24906dd0> ====================
INFO:apache_beam.runners.portability.fn_api_runner.translations:==================== <function populate_data_channel_coders at 0x7f1d24906ef0> ====================
INFO:apache_beam.runners.worker.statecache:Creating state cache with size 104857600
INFO:apache_beam.runners.portability.fn_api_runner.worker_handlers:Created Worker handler <apache_beam.runners.portability.fn_api_runner.worker_handlers.EmbeddedWorkerHandler object at 0x7f1d2c548550> for environment ref_Environment_default_environment_1 (beam:env:embedded_python:v1, b'')
INFO:apache_beam.io.filebasedsink:Starting finalize_write threads with num_shards: 1 (skipped: 0), batches: 1, num_threads: 1
INFO:apache_beam.io.filebasedsink:Renamed 1 shards in 0.01 seconds.
```

```bash
$ head -n 3 outputs/1711341025220-00000-of-00001.out 
{'ip': '74.236.125.208', 'id': '-5227372761963790049', 'lat': 26.3587, 'lng': -80.0831, 'age_bracket': '26-40'}
{'ip': '75.153.216.235', 'id': '5836835583895516006', 'lat': 49.2302, 'lng': -122.9952, 'age_bracket': '41-55'}
{'ip': '134.157.0.190', 'id': '-5123638115214052647', 'lat': 48.8534, 'lng': 2.3488, 'age_bracket': '55+'}
```

## Interactive Beam

[Interactive Beam](https://github.com/apache/beam/tree/master/sdks/python/apache_beam/runners/interactive) is aimed at integrating Apache Beam with [Jupyter notebook](http://jupyter.org/) to make pipeline prototyping and data exploration much faster and easier. It provides nice features such as graphical representation of pipeline DAGs and [PCollection](https://beam.apache.org/documentation/basics/#pcollection) elements, fetching PCollections as pandas DataFrame and faster execution/re-execution of pipelines.

We can start a Jupyter server while enabling Jupyter Lab and ignoring authentication as shown below. Once started, it can be accessed on *http://localhost:8888*.

```bash
$ JUPYTER_ENABLE_LAB=yes jupyter lab --ServerApp.token='' --ServerApp.password=''
```

The basic pipeline is recreated in [*section1/basic.ipynb*](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section1/basic.ipynb). The *InteractiveRunner* is used for the pipeline and, by default, the Python Direct Runner is taken as the underlying runner. When we run the first two cells, we can show the output records in a data table.

![](basic-01.png#center)

The pipeline DAG can be visualized using the *show_graph* method as shown below. It helps identify or share how a pipeline is executed more effectively.

![](basic-02.png#center)

## Beam SQL

[Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) allows a Beam user (currently only available in Beam Java and Python) to query bounded and unbounded [PCollections](https://beam.apache.org/documentation/basics/#pcollection) with SQL statements. An SQL query is translated to a [PTransform](https://beam.apache.org/documentation/basics/#ptransform), and it can be particularly useful for joining multiple PCollections.

In [*section1/sql.ipynb*](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section1/sql.ipynb), we first create a PCollection of 3 elements that can be used as source data.

![](sql-01.png#center)

Beam SQL is executed as an IPython extension, and it should be loaded before being used. The magic function requires *query*, and we can optionally specify the output name (*OUTPUT_NAME*) and runner (*RUNNER*).

![](sql-02.png#center)

After the extension is loaded, we execute a SQL query, optionally specifying the output PCollection name (*filtered*). We can use the existing PCollection named *items* as the source.

There are several notes about Beam SQL on a notebook.

1. The SQL query is executed in a separate Docker container and data is processed via the Java SDK.
2. Currently it only supports the Direct Runner and Dataflow Runner.
3. The output PCollection is accessible in the entire notebook, and we can use it in another cell.
4. While Beam SQL supports both [Calcite SQL](https://calcite.apache.org/) and [ZetaSQL](https://github.com/google/zetasql), the magic function doesn't allow us to select which dialect to choose. Only the default Calcite SQL will be used on a notebook.

![](sql-03.png#center)

## Beam DataFrames

The Apache Beam Python SDK provides a [DataFrame API](https://beam.apache.org/documentation/dsls/dataframes/overview/) for working with pandas-like DataFrame objects. This feature lets you convert a PCollection to a DataFrame and then interact with the DataFrame using the standard methods available on the pandas DataFrame API.

In [*section1/dataframe.ipynb*](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section1/dataframe.ipynb), we also create a PCollection of 3 elements as the Beam SQL example.

![](dataframe-01.png#center)

Subsequently we convert the source PCollection into a pandas DataFrame using the *to_dataframe* method, process data via pandas API and return to PCollection using the *to_pcollection* method.

![](dataframe-02.png#center)

## Summary

Apache Beam and Apache Flink are open-source frameworks for parallel, distributed data processing at scale. While PyFlink, Flink's Python API, is limited to build sophisticated data streaming applications, Apache Beam's Python SDK has potential as it supports more capacity to extend and/or customise its features. In this series of posts, we discuss local development of Apache Beam pipelines using Python. In Part 1, a basic Beam pipeline was introduced, followed by demonstrating how to utilise Jupyter notebooks for interactive development. We also covered Beam SQL and Beam DataFrames examples on notebooks.