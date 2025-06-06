---
title: Apache Beam Local Development with Python - Part 4 Streaming Pipelines
date: 2024-05-02
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Apache Beam Local Development with Python
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
description: In Part 3, we discussed the portability layer of Apache Beam as it helps understand (1) how Python pipelines run on the Flink Runner and (2) how multiple SDKs can be used in a single pipeline, followed by demonstrating local Flink and Kafka cluster creation for developing streaming pipelines. In this post, we develop a streaming pipeline that aggregates page visits by user in a fixed time window of 20 seconds. Two versions of the pipeline are created with/without relying on Beam SQL.
---

In [Part 3](/blog/2024-04-18-beam-local-dev-3), we discussed the portability layer of [Apache Beam](https://beam.apache.org/) as it helps understand (1) how Python pipelines run on the [Flink Runner](https://beam.apache.org/documentation/runners/flink/) and (2) how multiple SDKs can be used in a single pipeline, followed by demonstrating local Flink and Kafka cluster creation for developing streaming pipelines. In this post, we build a streaming pipeline that aggregates page visits by user in a [fixed time window](https://beam.apache.org/documentation/programming-guide/#fixed-time-windows) of 20 seconds. Two versions of the pipeline are created with/without relying on [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/).

* [Part 1 Pipeline, Notebook, SQL and DataFrame](/blog/2024-03-28-beam-local-dev-1)
* [Part 2 Batch Pipelines](/blog/2024-04-04-beam-local-dev-2)
* [Part 3 Flink Runner](/blog/2024-04-18-beam-local-dev-3)
* [Part 4 Streaming Pipelines](#) (this post)
* [Part 5 Testing Pipelines](/blog/2024-05-09-beam-local-dev-5)

## Streaming Pipeline

The streaming pipeline we discuss in this post aggregates website visits by user ID in a [fixed time window](https://beam.apache.org/documentation/programming-guide/#fixed-time-windows) of 20 seconds. Two versions of the pipeline are created with/without relying on [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/), and they run on a Flink cluster at the end. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-dev-env).

### Traffic Aggregation

It begins with reading and decoding messages from a Kafka topic named *website-visit*, followed by parsing the decoded Json string into a custom type named *EventLog*. Note the [coder](https://beam.apache.org/documentation/programming-guide/#data-encoding-and-type-safety) for this custom type is registered, but it is not required because we don't have a cross-language transformation that deals with it. On the other hand, the coder has to be registered for the SQL version because it is used by the SQL transformation, which is performed using the Java SDK.

After that, timestamp is re-assigned based on the *event_datetime* attribute and the element is converted into a key-value pair where user ID is taken as the key and 1 is given as the value. By default, the Kafka reader assigns processing time (wall clock) as the element timestamp. If record timestamp is different from wall clock, we would have more relevant outcomes by re-assigning based on record timestamp.

The tuple elements are aggregated in a fixed time window of 20 seconds and written to a Kafka topic named *traffic-agg*. The output messages include two additional attributes (*window_start* and *window_end*) to clarify in which window they belong to.

```python
# section3/traffic_agg.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.io import kafka
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions


class EventLog(typing.NamedTuple):
    ip: str
    id: str
    lat: float
    lng: float
    user_agent: str
    age_bracket: str
    opted_into_marketing: bool
    http_request: str
    http_response: int
    file_size_bytes: int
    event_datetime: str
    event_ts: int


beam.coders.registry.register_coder(EventLog, beam.coders.RowCoder)


def decode_message(kafka_kv: tuple):
    return kafka_kv[1].decode("utf-8")


def create_message(element: dict):
    key = {"event_id": element["id"], "window_start": element["window_start"]}
    print(element)
    return json.dumps(key).encode("utf-8"), json.dumps(element).encode("utf-8")


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


def assign_timestamp(element: EventLog):
    ts = datetime.datetime.strptime(
        element.event_datetime, "%Y-%m-%dT%H:%M:%S.%f"
    ).timestamp()
    return beam.window.TimestampedValue(element, ts)


class AddWindowTS(beam.DoFn):
    def process(self, element: tuple, window=beam.DoFn.WindowParam):
        window_start = window.start.to_utc_datetime().isoformat(timespec="seconds")
        window_end = window.end.to_utc_datetime().isoformat(timespec="seconds")
        output = {
            "id": element[0],
            "window_start": window_start,
            "window_end": window_end,
            "page_views": element[1],
        }
        yield output


def run():
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--runner", default="FlinkRunner", help="Specify Apache Beam Runner"
    )
    parser.add_argument(
        "--use_own",
        action="store_true",
        default="Flag to indicate whether to use an own local cluster",
    )
    opts = parser.parse_args()

    pipeline_opts = {
        "runner": opts.runner,
        "job_name": "traffic-agg",
        "environment_type": "LOOPBACK",
        "streaming": True,
        "parallelism": 3,
        "experiments": [
            "use_deprecated_read"
        ],  ## https://github.com/apache/beam/issues/20979
        "checkpointing_interval": "60000",
    }
    if opts.use_own is True:
        pipeline_opts = {**pipeline_opts, **{"flink_master": "localhost:8081"}}
    print(pipeline_opts)
    options = PipelineOptions([], **pipeline_opts)
    # Required, else it will complain that when importing worker functions
    options.view_as(SetupOptions).save_main_session = True

    p = beam.Pipeline(options=options)
    (
        p
        | "Read from Kafka"
        >> kafka.ReadFromKafka(
            consumer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                ),
                "auto.offset.reset": "earliest",
                # "enable.auto.commit": "true",
                "group.id": "traffic-agg",
            },
            topics=["website-visit"],
        )
        | "Decode messages" >> beam.Map(decode_message)
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Assign timestamp" >> beam.Map(assign_timestamp)
        | "Form key value pair" >> beam.Map(lambda e: (e.id, 1))
        | "Tumble window per minute" >> beam.WindowInto(beam.window.FixedWindows(20))
        | "Sum by key" >> beam.CombinePerKey(sum)
        | "Add window timestamp" >> beam.ParDo(AddWindowTS())
        | "Create messages"
        >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
        | "Write to Kafka"
        >> kafka.WriteToKafka(
            producer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                )
            },
            topic="traffic-agg",
        )
    )

    logging.getLogger().setLevel(logging.INFO)
    logging.info("Building pipeline ...")

    p.run().wait_until_finish()


if __name__ == "__main__":
    run()
```

### SQL Traffic Aggregation 

The main difference of this version is that multiple transformations are performed by a single SQL transformation. Specifically it aggregates the number of page views by user in a fixed time window of 20 seconds. The SQL transformation performed in a separate Docker container using the Java SDK and thus the output type has to be specified before it. Otherwise, an error is thrown because the Java SDK doesn't know how to encode/decode the elements.

```python
# section3/traffic_agg_sql.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.io import kafka
from apache_beam.transforms.sql import SqlTransform
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions


class EventLog(typing.NamedTuple):
    ip: str
    id: str
    lat: float
    lng: float
    user_agent: str
    age_bracket: str
    opted_into_marketing: bool
    http_request: str
    http_response: int
    file_size_bytes: int
    event_datetime: str
    event_ts: int


beam.coders.registry.register_coder(EventLog, beam.coders.RowCoder)


def decode_message(kafka_kv: tuple):
    return kafka_kv[1].decode("utf-8")


def create_message(element: dict):
    key = {"event_id": element["event_id"], "window_start": element["window_start"]}
    print(element)
    return json.dumps(key).encode("utf-8"), json.dumps(element).encode("utf-8")


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


def format_timestamp(element: EventLog):
    event_ts = datetime.datetime.fromisoformat(element.event_datetime)
    temp_dict = element._asdict()
    temp_dict["event_datetime"] = datetime.datetime.strftime(
        event_ts, "%Y-%m-%d %H:%M:%S"
    )
    return EventLog(**temp_dict)


def run():
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "--runner", default="FlinkRunner", help="Specify Apache Beam Runner"
    )
    parser.add_argument(
        "--use_own",
        action="store_true",
        default="Flag to indicate whether to use an own local cluster",
    )
    opts = parser.parse_args()

    options = PipelineOptions()
    pipeline_opts = {
        "runner": opts.runner,
        "job_name": "traffic-agg-sql",
        "environment_type": "LOOPBACK",
        "streaming": True,
        "parallelism": 3,
        "experiments": [
            "use_deprecated_read"
        ],  ## https://github.com/apache/beam/issues/20979
        "checkpointing_interval": "60000",
    }
    if opts.use_own is True:
        pipeline_opts = {**pipeline_opts, **{"flink_master": "localhost:8081"}}
    print(pipeline_opts)
    options = PipelineOptions([], **pipeline_opts)
    # Required, else it will complain that when importing worker functions
    options.view_as(SetupOptions).save_main_session = True

    query = """
    WITH cte AS (
        SELECT
            id, 
            CAST(event_datetime AS TIMESTAMP) AS ts
        FROM PCOLLECTION
    )
    SELECT
        id AS event_id,
        CAST(TUMBLE_START(ts, INTERVAL '20' SECOND) AS VARCHAR) AS window_start,
        CAST(TUMBLE_END(ts, INTERVAL '20' SECOND) AS VARCHAR) AS window_end,
        COUNT(*) AS page_view
    FROM cte
    GROUP BY
        TUMBLE(ts, INTERVAL '20' SECOND), id
    """

    p = beam.Pipeline(options=options)
    (
        p
        | "Read from Kafka"
        >> kafka.ReadFromKafka(
            consumer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                ),
                "auto.offset.reset": "earliest",
                # "enable.auto.commit": "true",
                "group.id": "traffic-agg-sql",
            },
            topics=["website-visit"],
        )
        | "Decode messages" >> beam.Map(decode_message)
        | "Parse elements" >> beam.Map(parse_json)
        | "Format timestamp" >> beam.Map(format_timestamp).with_output_types(EventLog)
        | "Count per minute" >> SqlTransform(query)
        | "To dictionary" >> beam.Map(lambda e: e._asdict())
        | "Create messages"
        >> beam.Map(create_message).with_output_types(typing.Tuple[bytes, bytes])
        | "Write to Kafka"
        >> kafka.WriteToKafka(
            producer_config={
                "bootstrap.servers": os.getenv(
                    "BOOTSTRAP_SERVERS",
                    "host.docker.internal:29092",
                )
            },
            topic="traffic-agg-sql",
        )
    )

    logging.getLogger().setLevel(logging.INFO)
    logging.info("Building pipeline ...")

    p.run().wait_until_finish()


if __name__ == "__main__":
    run()
```

## Run Pipeline

We can use local Flink and Kafka clusters as discussed in [Part 3](/blog/2024-04-18-beam-local-dev-3). The Flink cluster is optional as Beam runs a pipeline on an embedded Flink cluster if we do not specify a cluster URL.

### Start Flink/Kafka Clusters

As shown later, I have an issue to run the SQL version of the pipeline on a local cluster, and it has to be deployed on an embedded cluster instead. With the *-a* option, we can deploy local Flink and Kafka clusters, and they are used for the pipeline without SQL while only a local Kafka cluster is launched for the SQL version with the *-k* option.

```bash
# start both flink and kafka cluster for traffic aggregation
$ ./setup/start-flink-env.sh -a

# start only kafka cluster for sql traffic aggregation
$ ./setup/start-flink-env.sh -k
```

### Data Generation

For streaming data generation, we can use the website visit log generator that was introduced in [Part 1](/blog/2024-03-28-beam-local-dev-1). We can execute the script while specifying the *source* argument to *streaming*. Below shows an example of generating Kafka messages for the streaming pipeline.

```bash
$ python datagen/generate_data.py --source streaming --num_users 5 --delay_seconds 0.5
...
10 events created so far...
{'ip': '151.21.93.137', 'id': '2142139324490406578', 'lat': 45.5253, 'lng': 9.333, 'user_agent': 'Mozilla/5.0 (iPad; CPU iPad OS 14_2_1 like Mac OS X) AppleWebKit/536.0 (KHTML, like Gecko) FxiOS/16.3w0588.0 Mobile/66I206 Safari/536.0', 'age_bracket': '26-40', 'opted_into_marketing': True, 'http_request': 'GET amoebozoa.html HTTP/1.0', 'http_response': 200, 'file_size_bytes': 453, 'event_datetime': '2024-04-28T23:12:50.484', 'event_ts': 1714309970484}
20 events created so far...
{'ip': '146.13.4.138', 'id': '5642783739616136718', 'lat': 39.0437, 'lng': -77.4875, 'user_agent': 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_7_5 rv:4.0; bg-BG) AppleWebKit/532.16.6 (KHTML, like Gecko) Version/4.0.5 Safari/532.16.6', 'age_bracket': '41-55', 'opted_into_marketing': False, 'http_request': 'GET archaea.html HTTP/1.0', 'http_response': 200, 'file_size_bytes': 207, 'event_datetime': '2024-04-28T23:12:55.526', 'event_ts': 1714309975526}
30 events created so far...
{'ip': '36.255.131.188', 'id': '676397447776623774', 'lat': 31.2222, 'lng': 121.4581, 'user_agent': 'Mozilla/5.0 (compatible; MSIE 7.0; Windows 98; Win 9x 4.90; Trident/4.0)', 'age_bracket': '26-40', 'opted_into_marketing': False, 'http_request': 'GET fungi.html HTTP/1.0', 'http_response': 200, 'file_size_bytes': 440, 'event_datetime': '2024-04-28T23:13:00.564', 'event_ts': 1714309980564}
```

### Execute Pipeline Script

#### Traffic Aggregation

The traffic aggregation pipeline can be executed using the local Flink cluster by specifying the *use_own* argument.

```bash
$ python section3/traffic_agg.py --use_own
```

After a while, we can check both the input and output topics in the *Topics* section of *kafka-ui*. It can be accessed on *localhost:8080*.

![](kafka-topics.png#center)

We can use the Flink web UI to monitor the pipeline as a Flink job. When we click the *traffic-agg* job in the *Running Jobs* section, we see 4 operations are linked in the *Overview* tab. The first two operations are polling and reading Kafka source description. All the transformations up to windowing the keyed elements are performed in the third operation, and the elements are aggregated and written to the Kafka output topic in the last operation.

![](flink-job.png#center)

#### SQL Traffic Aggregation

I see the following error when I execute the SQL version of the pipeline with the *use_own* option. It seems that the Java SDK container for SQL transformation fails to download its expansion service and does not complete initialisation steps - see [Part 3](/blog/2024-04-18-beam-local-dev-3) for details about how multiple SDKs can be used in a single pipeline. Therefore, the Flink job fails to access the SDK container, and it keeps recreate a new container.

![](flink-job-sql.png#center)

We can see lots of containers are stopped and get recreated.

```bash
$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}" | grep apache/beam_java11_sdk
46c51d89e966   apache/beam_java11_sdk:2.53.0   Up 7 seconds
2ad755fc66df   apache/beam_java11_sdk:2.53.0   Up 7 seconds
cf023d9bf39f   apache/beam_java11_sdk:2.53.0   Exited (1) 13 seconds ago
a549729318e3   apache/beam_java11_sdk:2.53.0   Exited (1) 38 seconds ago
95626f645252   apache/beam_java11_sdk:2.53.0   Exited (1) 57 seconds ago
38b56216e29a   apache/beam_java11_sdk:2.53.0   Exited (1) About a minute ago
3aee486b472f   apache/beam_java11_sdk:2.53.0   Exited (1) About a minute ago
```

Instead, we can run the pipeline on an embedded Flink cluster without adding the *use_own* option. Note that we need to stop the existing clusters, start only a Kafka cluster with the *-k* option and re-generate data before executing this pipeline script.

```bash
$ python section3/traffic_agg_sql.py
```

Similar to the earlier version, we can check the input and output topics on *localhost:8080* as well.

![](kafka-topics-sql.png#center)

## Summary

In this post, we developed a streaming pipeline that aggregates website visits by user in a fixed time window of 20 seconds. Two versions of the pipeline were created with/without relying on Beam SQL. The first version that doesn't rely on SQL was deployed on a local Flink cluster, and how it is deployed as a Flink job is checked on the Flink web UI. The second version, however, had an issue to deploy on a local Flink cluster, and it was deployed on an embedded Flink cluster.
