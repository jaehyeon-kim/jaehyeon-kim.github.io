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

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is a popular data transformation tool for data warehouse development. Moreover, it can be used for [data lakehouse](https://www.databricks.com/glossary/data-lakehouse) development thanks to open table formats such as Apache Iceberg, Apache Hudi and Delta Lake. *dbt* supports key AWS analytics services and I wrote a series of posts that discuss how to utilise *dbt* with [Redshift](/blog/2022-09-28-dbt-on-aws-part-1-redshift), [Glue](/blog/2022-10-09-dbt-on-aws-part-2-glue), [EMR on EC2](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2), [EMR on EKS](/blog/2022-11-01-dbt-on-aws-part-4-emr-eks), and [Athena](/blog/2023-04-12-integrate-glue-schema-registry). Those posts focus on platform integration, however, they do not show realistic ETL scenarios. 

In this series of posts, we discuss practical data warehouse/lakehouse examples including ETL orchestration with Apache Airflow. As a starting point, we develop a *dbt* project on PostgreSQL using fictional pizza shop data in this post.


* [Part 1 Pipeline, Notebook, SQL and DataFrame](#) (this post)
* Part 2 Batch Pipelines
* Part 3 Flink Runner
* Part 4 Streaming Pipelines
* Part 5 Testing Pipelines

## Data Generator

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

    if opts.runner != "FlinkRunner":
        p.run()
    else:
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

$ head outputs/1711309448421-00000-of-00001.out 
{'ip': '30.28.43.179', 'id': '6601570356503437554', 'lat': 37.2242, 'lng': -95.7083, 'age_bracket': '55+'}
{'ip': '217.161.130.218', 'id': '-4587808562569740150', 'lat': 51.4015, 'lng': -1.3247, 'age_bracket': '41-55'}
{'ip': '170.70.126.46', 'id': '976443204308231857', 'lat': 19.4285, 'lng': -99.1277, 'age_bracket': '55+'}
{'ip': '97.36.82.86', 'id': '6551080344843772016', 'lat': 39.0437, 'lng': -77.4875, 'age_bracket': '18-25'}
{'ip': '60.118.97.251', 'id': '2488414394279316006', 'lat': 35.65, 'lng': 139.7333, 'age_bracket': '41-55'}
{'ip': '97.36.82.86', 'id': '6551080344843772016', 'lat': 39.0437, 'lng': -77.4875, 'age_bracket': '18-25'}
{'ip': '30.28.43.179', 'id': '6601570356503437554', 'lat': 37.2242, 'lng': -95.7083, 'age_bracket': '55+'}
{'ip': '217.146.147.145', 'id': '-9100325337763240340', 'lat': 52.5244, 'lng': 13.4105, 'age_bracket': '41-55'}
{'ip': '12.76.144.217', 'id': '1329647496255812603', 'lat': 34.0522, 'lng': -118.2437, 'age_bracket': '18-25'}
{'ip': '168.181.34.94', 'id': '1659503249510730712', 'lat': -29.7175, 'lng': -52.4258, 'age_bracket': '41-55'}
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