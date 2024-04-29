---
title: Apache Beam Local Development with Python - Part 2 Batch Pipelines
date: 2024-04-04
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
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - Python
  - Jupyter Notebook
authors:
  - JaehyeonKim
images: []
description: In this series, we discuss local development of Apache Beam pipelines using Python. A basic Beam pipeline was introduced in Part 1, followed by demonstrating how to utilise Jupyter notebooks, Beam SQL and Beam DataFrames. In this post, we discuss Batch pipelines that aggregate website visit log by user and time. The pipelines are developed with and without Beam SQL. Additionally, each pipeline is implemented on a Jupyter notebook for demonstration.
---

In this series, we discuss local development of [Apache Beam](https://beam.apache.org/) pipelines using Python. A basic Beam pipeline was introduced in [Part 1](/blog/2024-03-28-beam-local-dev-1), followed by demonstrating how to utilise Jupyter notebooks, [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) and [Beam DataFrames](https://beam.apache.org/documentation/dsls/dataframes/overview/). In this post, we discuss Batch pipelines that aggregate website visit log by user and time. The pipelines are developed with and without *Beam SQL*. Additionally, each pipeline is implemented on a Jupyter notebook for demonstration.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](/blog/2024-03-28-beam-local-dev-1)
* [Part 2 Batch Pipelines](#) (this post)
* [Part 3 Flink Runner](/blog/2024-04-18-beam-local-dev-3)
* [Part 4 Streaming Pipelines](/blog/2024-05-02-beam-local-dev-4)
* Part 5 Testing Pipelines

## Data Generation

We first need to generate website visit log data. As the second pipeline aggregates data by time, the max lag seconds (`--max_lag_seconds`) is set to 300 so that records are spread over 5 minutes period. See [Part 1](/blog/2024-03-28-beam-local-dev-1) for details about the data generation script and the source of this post can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-dev-env).

```bash
$ python datagen/generate_data.py --source batch --num_users 20 --num_events 10000 --max_lag_seconds 300
...
$ head -n 3 inputs/d919cc9e-dade-44be-872e-86598a4d0e47.out 
{"ip": "81.112.193.168", "id": "-7450326752843155888", "lat": 41.8919, "lng": 12.5113, "user_agent": "Opera/8.29.(Windows CE; hi-IN) Presto/2.9.160 Version/10.00", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 131, "event_datetime": "2024-04-02T04:30:18.999", "event_ts": 1711992618999}
{"ip": "204.14.50.181", "id": "3385356383147784679", "lat": 47.7918, "lng": -122.2243, "user_agent": "Opera/9.77.(Windows NT 5.01; ber-DZ) Presto/2.9.166 Version/12.00", "age_bracket": "55+", "opted_into_marketing": true, "http_request": "GET coniferophyta.html HTTP/1.0", "http_response": 200, "file_size_bytes": 229, "event_datetime": "2024-04-02T04:28:13.144", "event_ts": 1711992493144}
{"ip": "11.32.249.163", "id": "8764514706569354597", "lat": 37.2242, "lng": -95.7083, "user_agent": "Opera/8.45.(Windows NT 4.0; xh-ZA) Presto/2.9.177 Version/10.00", "age_bracket": "26-40", "opted_into_marketing": false, "http_request": "GET protozoa.html HTTP/1.0", "http_response": 200, "file_size_bytes": 373, "event_datetime": "2024-04-02T04:30:12.612", "event_ts": 1711992612612}
```

## User Traffic

This pipeline basically calculates the number of website visits and distribution of traffic consumption by user. 

### Beam Pipeline

The pipeline begins with reading data from a folder named *inputs* and parses the Json lines. Then it creates a key value pair where the key is the user ID (`id`) and the value is the file size bytes (`file_size_bytes`). After that, the records are grouped by the key and aggregated to obtain website visit count and traffic consumption distribution per user using a [ParDo](https://beam.apache.org/documentation/transforms/python/elementwise/pardo/) transform. Finally, the output records are written to a folder named *outputs* after being converted into dictionary.

Note that custom types are created for the input and output elements using [element schema](https://beam.apache.org/documentation/programming-guide/#element-schema) (*EventLog* and *UserTraffic*), and transformations become more expressive using them. Also, the custom types are [registered to the coder registry](https://beam.apache.org/documentation/programming-guide/#specifying-coders) so that they are encoded/decoded appropriately - see the transformations that specify the output types via `with_output_types`.

[**Update 2024-04-30**]
Note the coders for the custom types are registered, but it is not required because we don't have a cross-language transformation that deals with them.

```python
# section2/user_traffic.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import StandardOptions


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


class UserTraffic(typing.NamedTuple):
    id: str
    page_views: int
    total_bytes: int
    max_bytes: int
    min_bytes: int


beam.coders.registry.register_coder(EventLog, beam.coders.RowCoder)
beam.coders.registry.register_coder(UserTraffic, beam.coders.RowCoder)


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


class Aggregate(beam.DoFn):
    def process(self, element: typing.Tuple[str, typing.Iterable[int]]):
        key, values = element
        yield UserTraffic(
            id=key,
            page_views=len(values),
            total_bytes=sum(values),
            max_bytes=max(values),
            min_bytes=min(values),
        )


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
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Form key value pair" >> beam.Map(lambda e: (e.id, e.file_size_bytes))
        | "Group by key" >> beam.GroupByKey()
        | "Aggregate by id" >> beam.ParDo(Aggregate()).with_output_types(UserTraffic)
        | "To dict" >> beam.Map(lambda e: e._asdict())
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

Once we execute the pipeline, we can check the output records by reading the output file. By default, the pipeline runs via the [Direct Runner](https://beam.apache.org/documentation/runners/direct/).

```bash
$ python section2/user_traffic.py
...
$ cat outputs/1712032400886-00000-of-00001.out 
{'id': '-7450326752843155888', 'page_views': 466, 'total_bytes': 139811, 'max_bytes': 498, 'min_bytes': 100}
{'id': '3385356383147784679', 'page_views': 471, 'total_bytes': 142846, 'max_bytes': 499, 'min_bytes': 103}
{'id': '8764514706569354597', 'page_views': 498, 'total_bytes': 152005, 'max_bytes': 499, 'min_bytes': 101}
{'id': '1097462159655745840', 'page_views': 483, 'total_bytes': 145655, 'max_bytes': 499, 'min_bytes': 101}
{'id': '5107076440238203196', 'page_views': 520, 'total_bytes': 155475, 'max_bytes': 499, 'min_bytes': 100}
{'id': '3817299155409964875', 'page_views': 515, 'total_bytes': 155516, 'max_bytes': 498, 'min_bytes': 100}
{'id': '4396740364429657096', 'page_views': 534, 'total_bytes': 159351, 'max_bytes': 499, 'min_bytes': 101}
{'id': '323358690592146285', 'page_views': 503, 'total_bytes': 150204, 'max_bytes': 497, 'min_bytes': 100}
{'id': '-297761604717604766', 'page_views': 519, 'total_bytes': 157246, 'max_bytes': 499, 'min_bytes': 103}
{'id': '-8832654768096800604', 'page_views': 489, 'total_bytes': 145166, 'max_bytes': 499, 'min_bytes': 100}
{'id': '-7508437511513814045', 'page_views': 492, 'total_bytes': 146561, 'max_bytes': 499, 'min_bytes': 100}
{'id': '-4225319382884577471', 'page_views': 518, 'total_bytes': 158242, 'max_bytes': 499, 'min_bytes': 101}
{'id': '-6246779037351548961', 'page_views': 432, 'total_bytes': 127013, 'max_bytes': 499, 'min_bytes': 101}
{'id': '7514213899672341122', 'page_views': 515, 'total_bytes': 154753, 'max_bytes': 498, 'min_bytes': 100}
{'id': '8063196327933870504', 'page_views': 526, 'total_bytes': 159395, 'max_bytes': 499, 'min_bytes': 101}
{'id': '4927182384805166657', 'page_views': 501, 'total_bytes': 151023, 'max_bytes': 498, 'min_bytes': 100}
{'id': '134630243715938340', 'page_views': 506, 'total_bytes': 153509, 'max_bytes': 498, 'min_bytes': 101}
{'id': '-5889211929143180249', 'page_views': 491, 'total_bytes': 146755, 'max_bytes': 499, 'min_bytes': 100}
{'id': '3809491485105813594', 'page_views': 518, 'total_bytes': 155992, 'max_bytes': 499, 'min_bytes': 100}
{'id': '4086706052291208999', 'page_views': 503, 'total_bytes': 154038, 'max_bytes': 499, 'min_bytes': 100}
```

We can run the pipeline using a different runner e.g. by specifying the [Flink Runner](https://beam.apache.org/documentation/runners/flink/) in the *runner* argument. Interestingly it completes the pipeline by multiple tasks.

```bash
$ python section2/user_traffic.py --runner FlinkRunner
...
$ ls outputs/ | grep 1712032503940
1712032503940-00000-of-00005.out
1712032503940-00003-of-00005.out
1712032503940-00002-of-00005.out
1712032503940-00004-of-00005.out
1712032503940-00001-of-00005.out
```

### Beam SQL

The pipeline that calculates user statistic can also be developed using [*SqlTransform*](https://beam.apache.org/releases/pydoc/current/apache_beam.transforms.sql.html), which translates a SQL query into [PTransforms](https://beam.apache.org/documentation/basics/#ptransform). The following pipeline creates the same output to the previous pipeline.

```python
# section2/user_traffic_sql.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.transforms.sql import SqlTransform
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import StandardOptions


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


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


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

    query = """
    SELECT
        id,
        COUNT(*) AS page_views,
        SUM(file_size_bytes) AS total_bytes,
        MAX(file_size_bytes) AS max_bytes,
        MIN(file_size_bytes) AS min_bytes
    FROM PCOLLECTION
    GROUP BY id
    """

    p = beam.Pipeline(options=options)
    (
        p
        | "Read from files"
        >> beam.io.ReadFromText(
            file_pattern=os.path.join(PARENT_DIR, opts.inputs, "*.out")
        )
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Aggregate by user" >> SqlTransform(query)
        | "To Dict" >> beam.Map(lambda e: e._asdict())
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

When we execute the pipeline script, we see that a Docker container is launched and actual transformations are performed within it via the Java SDK. The container exits when the pipeline completes.

```bash
$ python section2/user_traffic_sql.py
...

$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}"
CONTAINER ID   IMAGE                           STATUS
c7d7bad6b1e9   apache/beam_java11_sdk:2.53.0   Exited (137) 5 minutes ago

$ cat outputs/1712032675637-00000-of-00001.out 
{'id': '-297761604717604766', 'page_views': 519, 'total_bytes': 157246, 'max_bytes': 499, 'min_bytes': 103}
{'id': '3817299155409964875', 'page_views': 515, 'total_bytes': 155516, 'max_bytes': 498, 'min_bytes': 100}
{'id': '-8832654768096800604', 'page_views': 489, 'total_bytes': 145166, 'max_bytes': 499, 'min_bytes': 100}
{'id': '4086706052291208999', 'page_views': 503, 'total_bytes': 154038, 'max_bytes': 499, 'min_bytes': 100}
{'id': '3809491485105813594', 'page_views': 518, 'total_bytes': 155992, 'max_bytes': 499, 'min_bytes': 100}
{'id': '323358690592146285', 'page_views': 503, 'total_bytes': 150204, 'max_bytes': 497, 'min_bytes': 100}
{'id': '1097462159655745840', 'page_views': 483, 'total_bytes': 145655, 'max_bytes': 499, 'min_bytes': 101}
{'id': '-7508437511513814045', 'page_views': 492, 'total_bytes': 146561, 'max_bytes': 499, 'min_bytes': 100}
{'id': '7514213899672341122', 'page_views': 515, 'total_bytes': 154753, 'max_bytes': 498, 'min_bytes': 100}
{'id': '8764514706569354597', 'page_views': 498, 'total_bytes': 152005, 'max_bytes': 499, 'min_bytes': 101}
{'id': '5107076440238203196', 'page_views': 520, 'total_bytes': 155475, 'max_bytes': 499, 'min_bytes': 100}
{'id': '134630243715938340', 'page_views': 506, 'total_bytes': 153509, 'max_bytes': 498, 'min_bytes': 101}
{'id': '-6246779037351548961', 'page_views': 432, 'total_bytes': 127013, 'max_bytes': 499, 'min_bytes': 101}
{'id': '-7450326752843155888', 'page_views': 466, 'total_bytes': 139811, 'max_bytes': 498, 'min_bytes': 100}
{'id': '4927182384805166657', 'page_views': 501, 'total_bytes': 151023, 'max_bytes': 498, 'min_bytes': 100}
{'id': '-5889211929143180249', 'page_views': 491, 'total_bytes': 146755, 'max_bytes': 499, 'min_bytes': 100}
{'id': '8063196327933870504', 'page_views': 526, 'total_bytes': 159395, 'max_bytes': 499, 'min_bytes': 101}
{'id': '3385356383147784679', 'page_views': 471, 'total_bytes': 142846, 'max_bytes': 499, 'min_bytes': 103}
{'id': '4396740364429657096', 'page_views': 534, 'total_bytes': 159351, 'max_bytes': 499, 'min_bytes': 101}
{'id': '-4225319382884577471', 'page_views': 518, 'total_bytes': 158242, 'max_bytes': 499, 'min_bytes': 101}
```

When we develop a pipeline, [Interactive Beam](https://github.com/apache/beam/tree/master/sdks/python/apache_beam/runners/interactive) on a Jupyter notebook can be convenient. The user traffic pipelines are implemented using notebooks, and they can be found in [section2/user_traffic.ipynb](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section2/user_traffic.ipynb) and [section2/user_traffic_sql.ipynb](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section2/user_traffic_sql.ipynb) respectively. We can start a Jupyter server while enabling Jupyter Lab and ignoring authentication as shown below. Once started, it can be accessed on *http://localhost:8888*.

```bash
$ JUPYTER_ENABLE_LAB=yes jupyter lab --ServerApp.token='' --ServerApp.password=''
```

![](user_traffic.png#center)

## Minute Traffic

This pipeline aggregates the number of website visits in fixed time windows over 60 seconds. 

### Beam Pipeline

As the user traffic pipeline, it begins with reading data from a folder named *inputs* and parses the Json lines. Then it adds timestamp to elements by parsing the *event_datetime* attribute, defines fixed time windows over 60 seconds, and counts the number of records within the windows. Finally, it writes the aggregated records into a folder named *outputs* after adding *window_start* and *window_end* timestamp attributes.

[**Update 2024-04-30**]
Note the coder for the custom type is registered, but it is not required because we don't have a cross-language transformation that deals with it.

```python
# section2/minute_traffic.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.transforms.combiners import CountCombineFn
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import StandardOptions


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


def parse_json(element: str):
    row = json.loads(element)
    # lat/lng sometimes empty string
    if not row["lat"] or not row["lng"]:
        row = {**row, **{"lat": -1, "lng": -1}}
    return EventLog(**row)


def add_timestamp(element: EventLog):
    ts = datetime.datetime.strptime(
        element.event_datetime, "%Y-%m-%dT%H:%M:%S.%f"
    ).timestamp()
    return beam.window.TimestampedValue(element, ts)


class AddWindowTS(beam.DoFn):
    def process(self, element: int, window=beam.DoFn.WindowParam):
        window_start = window.start.to_utc_datetime().isoformat(timespec="seconds")
        window_end = window.end.to_utc_datetime().isoformat(timespec="seconds")
        output = {
            "window_start": window_start,
            "window_end": window_end,
            "page_views": element,
        }
        yield output


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
            file_pattern=os.path.join(os.path.join(PARENT_DIR, "inputs", "*.out"))
        )
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Add event timestamp" >> beam.Map(add_timestamp)
        | "Tumble window per minute" >> beam.WindowInto(beam.window.FixedWindows(60))
        | "Count per minute"
        >> beam.CombineGlobally(CountCombineFn()).without_defaults()
        | "Add window timestamp" >> beam.ParDo(AddWindowTS())
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

As mentioned earlier, we set the max lag seconds (`--max_lag_seconds`) to 300 so that records are spread over 5 minutes period. Therefore, we can see that website visit counts are found in multiple time windows.

```bash
$ python section2/minute_traffic.py
...
$ cat outputs/1712033031226-00000-of-00001.out 
{'window_start': '2024-04-01T17:30:00', 'window_end': '2024-04-01T17:31:00', 'page_views': 1963}
{'window_start': '2024-04-01T17:28:00', 'window_end': '2024-04-01T17:29:00', 'page_views': 2023}
{'window_start': '2024-04-01T17:27:00', 'window_end': '2024-04-01T17:28:00', 'page_views': 1899}
{'window_start': '2024-04-01T17:29:00', 'window_end': '2024-04-01T17:30:00', 'page_views': 2050}
{'window_start': '2024-04-01T17:31:00', 'window_end': '2024-04-01T17:32:00', 'page_views': 1970}
{'window_start': '2024-04-01T17:32:00', 'window_end': '2024-04-01T17:33:00', 'page_views': 95}
```

### Beam SQL

The traffic by fixed time window can also be obtained using *SqlTransform*. As mentioned in Part 1, *Beam SQL* supports two dialects - [Calcite SQL](https://calcite.apache.org/) and [ZetaSQL](https://github.com/google/zetasql). The following pipeline creates output files using both the dialects.

```python
# section2/minute_traffic_sql.py
import os
import datetime
import argparse
import json
import logging
import typing

import apache_beam as beam
from apache_beam.transforms.sql import SqlTransform
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import StandardOptions


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

    calcite_query = """
    WITH cte AS (
        SELECT CAST(event_datetime AS TIMESTAMP) AS ts
        FROM PCOLLECTION
    )
    SELECT
        CAST(TUMBLE_START(ts, INTERVAL '1' MINUTE) AS VARCHAR) AS window_start,
        CAST(TUMBLE_END(ts, INTERVAL '1' MINUTE) AS VARCHAR) AS window_end,
        COUNT(*) AS page_view
    FROM cte
    GROUP BY
        TUMBLE(ts, INTERVAL '1' MINUTE)
    """

    zeta_query = """
    SELECT
        STRING(window_start) AS start_time,
        STRING(window_end) AS end_time,
        COUNT(*) AS page_views
    FROM
        TUMBLE(
            (SELECT TIMESTAMP(event_datetime) AS ts FROM PCOLLECTION),
            DESCRIPTOR(ts),
            'INTERVAL 1 MINUTE')
    GROUP BY
        window_start, window_end
    """

    p = beam.Pipeline(options=options)
    transformed = (
        p
        | "Read from files"
        >> beam.io.ReadFromText(
            file_pattern=os.path.join(os.path.join(PARENT_DIR, "inputs", "*.out"))
        )
        | "Parse elements" >> beam.Map(parse_json).with_output_types(EventLog)
        | "Format timestamp" >> beam.Map(format_timestamp).with_output_types(EventLog)
    )

    ## calcite sql output
    (
        transformed
        | "Count per minute via Caltice" >> SqlTransform(calcite_query)
        | "To Dict via Caltice" >> beam.Map(lambda e: e._asdict())
        | "Write to file via Caltice"
        >> beam.io.WriteToText(
            file_path_prefix=os.path.join(
                PARENT_DIR,
                "outputs",
                f"{int(datetime.datetime.now().timestamp() * 1000)}-calcite",
            ),
            file_name_suffix=".out",
        )
    )

    ## zeta sql output
    (
        transformed
        | "Count per minute via Zeta" >> SqlTransform(zeta_query, dialect="zetasql")
        | "To Dict via Zeta" >> beam.Map(lambda e: e._asdict())
        | "Write to file via Zeta"
        >> beam.io.WriteToText(
            file_path_prefix=os.path.join(
                PARENT_DIR,
                "outputs",
                f"{int(datetime.datetime.now().timestamp() * 1000)}-zeta",
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

As expected, both the SQL dialects produce the same output.

```bash
$ python section2/minute_traffic_sql.py
...
$ cat outputs/1712033090583-calcite-00000-of-00001.out 
{'window_start': '2024-04-02 04:32:00', 'window_end': '2024-04-02 04:33:00', 'page_view': 95}
{'window_start': '2024-04-02 04:28:00', 'window_end': '2024-04-02 04:29:00', 'page_view': 2023}
{'window_start': '2024-04-02 04:30:00', 'window_end': '2024-04-02 04:31:00', 'page_view': 1963}
{'window_start': '2024-04-02 04:29:00', 'window_end': '2024-04-02 04:30:00', 'page_view': 2050}
{'window_start': '2024-04-02 04:27:00', 'window_end': '2024-04-02 04:28:00', 'page_view': 1899}
{'window_start': '2024-04-02 04:31:00', 'window_end': '2024-04-02 04:32:00', 'page_view': 1970}

$ cat outputs/1712033101760-zeta-00000-of-00001.out 
{'start_time': '2024-04-02 04:30:00+00', 'end_time': '2024-04-02 04:31:00+00', 'page_views': 1963}
{'start_time': '2024-04-02 04:29:00+00', 'end_time': '2024-04-02 04:30:00+00', 'page_views': 2050}
{'start_time': '2024-04-02 04:31:00+00', 'end_time': '2024-04-02 04:32:00+00', 'page_views': 1970}
{'start_time': '2024-04-02 04:32:00+00', 'end_time': '2024-04-02 04:33:00+00', 'page_views': 95}
{'start_time': '2024-04-02 04:28:00+00', 'end_time': '2024-04-02 04:29:00+00', 'page_views': 2023}
{'start_time': '2024-04-02 04:27:00+00', 'end_time': '2024-04-02 04:28:00+00', 'page_views': 1899}
```

Jupyter notebooks are created for the minute traffic pipelines, and they can be found in [section2/minute_traffic.ipynb](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section2/minute_traffic.ipynb) and [section2/minute_traffic_sql.ipynb](https://github.com/jaehyeon-kim/beam-demos/blob/master/beam-dev-env/section2/minute_traffic_sql.ipynb) respectively.

![](minute_traffic.png#center)

## Summary

As part of discussing local development of *Apache Beam* pipelines using Python, we developed Batch pipelines that aggregate website visit log by user and time in this post. The pipelines were developed with and without *Beam SQL*. Additionally, each pipeline was implemented on a Jupyter notebook for demonstration.
