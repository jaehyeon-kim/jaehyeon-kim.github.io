---
title: Apache Beam Local Development with Python - Part 1 Pipeline, Notebook, SQL and DataFrame
date: 2024-01-18
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
description: The data build tool (dbt) is a popular data transformation tool for data warehouse development. Moreover, it can be used for data lakehouse development thanks to open table formats such as Apache Iceberg, Apache Hudi and Delta Lake. dbt supports key AWS analytics services and I wrote a series of posts that discuss how to utilise dbt with Redshift, Glue, EMR on EC2, EMR on EKS, and Athena. Those posts focus on platform integration, however, they do not show realistic ETL scenarios. In this series of posts, we discuss practical data warehouse/lakehouse examples including ETL orchestration with Apache Airflow. As a starting point, we develop a dbt project on PostgreSQL using fictional pizza shop data in this post.
---

[Apache Beam](https://beam.apache.org/) and [Apache Flink](https://flink.apache.org/) are popular tools for unified batch and stream data processing. I spent quite some time teaching myself PyFlink (Python API of Apache Flink) last year and found the Python API is rather limited compared to the Java API. This year I had a chance to learn data engineering on Google Compute Cloud (GCP) and become aware of the potential of Apache Beam for data streaming development in Python. Beam doesn't have its own processing engine and Beam pipelines are executed on a runner such as Apache Flink, Apache Spark, or Google Cloud Dataflow instead. Therefore Flink will still be quite important because the Flink Runner supports [a wide range of features](https://beam.apache.org/documentation/runners/capability-matrix/) both in batch and streaming context.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](#) (this post)
* Part 2 Batch Pipelines
* Part 3 Flink Runner
* Part 4 Streaming Pipelines
* Part 5 Testing Pipelines

## Apache Beam at a Glance

Apache Beam is an open source, unified model for defining both batch and streaming data-parallel processing pipelines. One of the novel features of Apache Beam is portability. Beam is portable on several layers:

- Beam's pipelines are portable between multiple runners (that is, a technology that executes the distributed computation described by a pipeline's author).
- Beam's data processing model is portable between various programming languages.
- Beam's data processing logic is portable between bounded and unbounded data.

By runner portability, we mean the possibility to run existing pipelines written in one of the supported programming languages (for instance, Java, Python, Go, Scala, or even SQL) against a data processing engine that can be chosen at runtime. A typical example of a runner would be Apache Flink, Apache Spark, or Google Cloud Dataflow.

When we say Beam's data processing model is portable between various programming languages, we mean it has the ability to provide support for multiple SDKs, regardless of the language or technology used by the runner. This way, we can code Beam pipelines in the Python language, and then run these against the Apache Flink Runner, written in Java.

Last but not least, the core of Apache Beam's model is designed so that it is portable between bounded and unbounded data. Bounded data is what was historically called batch processing, while unbounded data refers to real-time processing (that is, an application crunching live data as it arrives in the system and producing a low-latency output). This feature unifies batch and streaming data processing.

The unification of batch and streaming data processing is achieved by extending batch processing with the event time of each key-value pair and defining a sensible default window. Specifically batch data flow is extended to add streaming semantics by

- Assigning a fixed timestamp to all input key-value pairs.
- Assigning all input key-value pairs to the global window.
- Moving the watermark from –inf to +inf in one hop once all the data is processed.

Therefore Beam allows us to code a data pipeline as a streaming pipeline then run it in both a batch and streaming fashion.

## Prerequsites

```bash
$ java --version
openjdk 11.0.22 2024-01-16
OpenJDK Runtime Environment (build 11.0.22+7-post-Ubuntu-0ubuntu222.04.1)
OpenJDK 64-Bit Server VM (build 11.0.22+7-post-Ubuntu-0ubuntu222.04.1, mixed mode, sharing)

$ docker --version
Docker version 24.0.5, build 24.0.5-0ubuntu1~22.04.1

$ dot -V
dot - graphviz version 2.43.0 (0)

$ python --version
Python 3.10.12
```

### Data Generator

```python
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

```bash
$ python datagen/generate_data.py --source batch --num_users 20 --num_events 10000 --max_lag_seconds 60
...
$ head -n 3 inputs/4b1dba74-d970-4c67-a631-e0d7f52ad00e.out 
{"ip": "74.236.125.208", "id": "-5227372761963790049", "lat": 26.3587, "lng": -80.0831, "user_agent": "Mozilla/5.0 (Windows; U; Windows NT 5.1) AppleWebKit/534.23.4 (KHTML, like Gecko) Version/4.0.5 Safari/534.23.4", "age_bracket": "26-40", "opted_into_marketing": true, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 115, "event_datetime": "2024-03-25T04:26:55.473", "event_ts": 1711301215473}
{"ip": "75.153.216.235", "id": "5836835583895516006", "lat": 49.2302, "lng": -122.9952, "user_agent": "Mozilla/5.0 (Android 6.0.1; Mobile; rv:11.0) Gecko/11.0 Firefox/11.0", "age_bracket": "41-55", "opted_into_marketing": true, "http_request": "GET acanthocephala.html HTTP/1.0", "http_response": 200, "file_size_bytes": 358, "event_datetime": "2024-03-25T04:27:01.930", "event_ts": 1711301221930}
{"ip": "134.157.0.190", "id": "-5123638115214052647", "lat": 48.8534, "lng": 2.3488, "user_agent": "Mozilla/5.0 (X11; Linux i686) AppleWebKit/534.2 (KHTML, like Gecko) Chrome/23.0.825.0 Safari/534.2", "age_bracket": "55+", "opted_into_marketing": true, "http_request": "GET bacteria.html HTTP/1.0", "http_response": 200, "file_size_bytes": 402, "event_datetime": "2024-03-25T04:27:16.037", "event_ts": 1711301236037}
```

## Basic Pipeline

```python
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

$ head -n 3 outputs/1711341025220-00000-of-00001.out 
{'ip': '74.236.125.208', 'id': '-5227372761963790049', 'lat': 26.3587, 'lng': -80.0831, 'age_bracket': '26-40'}
{'ip': '75.153.216.235', 'id': '5836835583895516006', 'lat': 49.2302, 'lng': -122.9952, 'age_bracket': '41-55'}
{'ip': '134.157.0.190', 'id': '-5123638115214052647', 'lat': 48.8534, 'lng': 2.3488, 'age_bracket': '55+'}
```

`python section1/basic.py --runner FlinkRunner`

## Notebook

![](basic-01.png#center)

![](basic-02.png#center)

## SQL

![](sql-01.png#center)

![](sql-02.png#center)

![](sql-03.png#center)

## DataFrame

![](dataframe-01.png#center)

![](dataframe-02.png#center)

## Summary

The data build tool (dbt) is a popular data transformation tool. In this series, we discuss practical examples of data warehouse and lakehouse development where data transformation is performed by the data build tool (dbt) and ETL is managed by Apache Airflow. As a starting point, we developed a dbt project on PostgreSQL using fictional pizza shop data in this post. Two SCD type 2 dimension tables and a single transaction tables were modelled on a dbt project and impacts of record updates were discussed in detail.