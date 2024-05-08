---
title: Apache Beam Local Development with Python - Part 5 Testing Pipelines
date: 2024-05-09
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
authors:
  - JaehyeonKim
images: []
description: We developed batch and streaming pipelines in Part 2 and Part 4. Often it is faster and simpler to identify and fix bugs on the pipeline code by performing local unit testing. Moreover, especially when it comes to creating a streaming pipeline, unit testing cases can facilitate development further by using TestStream as it allows us to advance watermarks or processing time according to different scenarios. In this post, we discuss how to perform unit testing of the batch and streaming pipelines that we developed earlier.
---

We developed batch and streaming pipelines in [Part 2](/blog/2024-04-04-beam-local-dev-2) and [Part 4](/blog/2024-05-02-beam-local-dev-4). Often it is faster and simpler to identify and fix bugs on the pipeline code by performing local unit testing. Moreover, especially when it comes to creating a streaming pipeline, unit testing cases can facilitate development further by using [TestStream](https://beam.apache.org/releases/pydoc/2.22.0/_modules/apache_beam/testing/test_stream.html) as it allows us to advance [watermarks](https://beam.apache.org/documentation/basics/#watermark) or processing time according to different scenarios. In this post, we discuss how to perform unit testing of the batch and streaming pipelines that we developed earlier.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](/blog/2024-03-28-beam-local-dev-1)
* [Part 2 Batch Pipelines](/blog/2024-04-04-beam-local-dev-2)
* [Part 3 Flink Runner](/blog/2024-04-18-beam-local-dev-3)
* [Part 4 Streaming Pipelines](/blog/2024-05-02-beam-local-dev-4)
* [Part 5 Testing Pipelines](#) (this post)

## Batch Pipeline Testing

### Pipeline Code

The pipeline begins with reading data from a folder named *inputs* and parses the Json lines. Then it creates a key-value pair where the key is the user ID (`id`) and the value is the file size bytes (`file_size_bytes`). After that, the records are grouped by the key and aggregated to obtain website visit count and traffic consumption distribution using a [ParDo](https://beam.apache.org/documentation/transforms/python/elementwise/pardo/) transform. Finally, the output records are written to a folder named *outputs* after being converted into dictionary.

```python
# section4/user_traffic.py
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

### Test Pipeline

As illustrated in the [Beam documentation](https://beam.apache.org/documentation/pipelines/test-your-pipeline/), we can use the following pattern to test a Beam pipeline.

- Create a *TestPipeline*.
- Create some static, known test input data.
- Use the *Create* transform to create a *PCollection* of your input data.
- Apply your transform to the input *PCollection* and save the resulting output *PCollection*.
- Use *PAssert* and its subclasses (or testing functions in Python) to verify that the output *PCollection* contains the elements that you expect.

We have three unit testing cases for this batch pipeline. The first two cases checks whether the input elements are parsed into the custom *EventLog* type as expected while the last case is used to test if the pipeline aggregates the elements by user correctly. In all cases, pipeline outputs are compared to expected outputs for verification.

```python
# section4/user_traffic_test.py
import sys
import unittest

import apache_beam as beam
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to

from user_traffic import EventLog, UserTraffic, parse_json, Aggregate


def main(out=sys.stderr, verbosity=2):
    loader = unittest.TestLoader()

    suite = loader.loadTestsFromModule(sys.modules[__name__])
    unittest.TextTestRunner(out, verbosity=verbosity).run(suite)


class ParseJsonTest(unittest.TestCase):
    def test_parse_json(self):
        with TestPipeline() as p:
            LINES = [
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:22.083", "event_ts": 1709232682083}',
                '{"ip": "105.100.237.193", "id": "5135574965990269004", "lat": 36.7323, "lng": 3.0875, "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_9 rv:2.0; wo-SN) AppleWebKit/531.18.2 (KHTML, like Gecko) Version/4.0.4 Safari/531.18.2", "age_bracket": "26-40", "opted_into_marketing": false, "http_request": "GET coniferophyta.html HTTP/1.0", "http_response": 200, "file_size_bytes": 427, "event_datetime": "2024-03-01T05:48:52.985", "event_ts": 1709232532985}',
            ]

            EXPECTED_OUTPUT = [
                EventLog(
                    ip="138.201.212.70",
                    id="462520009613048791",
                    lat=50.4779,
                    lng=12.3713,
                    user_agent="Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7",
                    age_bracket="18-25",
                    opted_into_marketing=False,
                    http_request="GET eucharya.html HTTP/1.0",
                    http_response=200,
                    file_size_bytes=207,
                    event_datetime="2024-03-01T05:51:22.083",
                    event_ts=1709232682083,
                ),
                EventLog(
                    ip="105.100.237.193",
                    id="5135574965990269004",
                    lat=36.7323,
                    lng=3.0875,
                    user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_9 rv:2.0; wo-SN) AppleWebKit/531.18.2 (KHTML, like Gecko) Version/4.0.4 Safari/531.18.2",
                    age_bracket="26-40",
                    opted_into_marketing=False,
                    http_request="GET coniferophyta.html HTTP/1.0",
                    http_response=200,
                    file_size_bytes=427,
                    event_datetime="2024-03-01T05:48:52.985",
                    event_ts=1709232532985,
                ),
            ]

            output = (
                p
                | beam.Create(LINES)
                | beam.Map(parse_json).with_output_types(EventLog)
            )

            assert_that(output, equal_to(EXPECTED_OUTPUT))

    def test_parse_null_lat_lng(self):
        with TestPipeline() as p:
            LINES = [
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": null, "lng": null, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:22.083", "event_ts": 1709232682083}',
            ]

            EXPECTED_OUTPUT = [
                EventLog(
                    ip="138.201.212.70",
                    id="462520009613048791",
                    lat=-1,
                    lng=-1,
                    user_agent="Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7",
                    age_bracket="18-25",
                    opted_into_marketing=False,
                    http_request="GET eucharya.html HTTP/1.0",
                    http_response=200,
                    file_size_bytes=207,
                    event_datetime="2024-03-01T05:51:22.083",
                    event_ts=1709232682083,
                ),
            ]

            output = (
                p
                | beam.Create(LINES)
                | beam.Map(parse_json).with_output_types(EventLog)
            )

            assert_that(output, equal_to(EXPECTED_OUTPUT))


class AggregateTest(unittest.TestCase):
    def test_aggregate(self):
        with TestPipeline() as p:
            LINES = [
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:22.083", "event_ts": 1709232682083}',
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET blastocladiomycota.html HTTP/1.0", "http_response": 200, "file_size_bytes": 446, "event_datetime": "2024-03-01T05:51:48.719", "event_ts": 1709232708719}',
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET home.html HTTP/1.0", "http_response": 200, "file_size_bytes": 318, "event_datetime": "2024-03-01T05:51:35.181", "event_ts": 1709232695181}',
            ]

            EXPECTED_OUTPUT = [
                UserTraffic(
                    id="462520009613048791",
                    page_views=3,
                    total_bytes=971,
                    max_bytes=446,
                    min_bytes=207,
                )
            ]

            output = (
                p
                | beam.Create(LINES)
                | beam.Map(parse_json).with_output_types(EventLog)
                | beam.Map(lambda e: (e.id, e.file_size_bytes))
                | beam.GroupByKey()
                | beam.ParDo(Aggregate()).with_output_types(UserTraffic)
            )

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    main(out=None)
```

We can perform unit testing of the batch pipeline simply by executing the test script.

```bash
$ python section4/user_traffic_test.py 
test_aggregate (__main__.AggregateTest) ... ok
test_parse_json (__main__.ParseJsonTest) ... ok
test_parse_null_lat_lng (__main__.ParseJsonTest) ... ok

----------------------------------------------------------------------
Ran 3 tests in 1.278s

OK
```

## Streaming Pipeline Testing

### Pipeline Code

It begins with reading and decoding messages from a Kafka topic named *website-visit*, followed by parsing the decoded Json string into a custom type named *EventLog*. After that, timestamp is re-assigned based on the *event_datetime* attribute and the element is converted into a key-value pair where user ID is taken as the key and 1 is given as the value. Finally, the tuple elements are aggregated in a fixed time window of 20 seconds and written to a Kafka topic named *traffic-agg*. Note that the output messages include two additional attributes (*window_start* and *window_end*) to clarify in which window they belong to.

```python
# section4/traffic_agg.py
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
        default="Flag to indicate whether to use a own local cluster",
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

### Test Pipeline

For testing the streaming pipeline, we use a [TestStream](https://beam.apache.org/releases/pydoc/2.22.0/_modules/apache_beam/testing/test_stream.html), which is used to generate events on an unbounded *PCollection* of elements. The stream has three elements of a single user with the following timestamp values. 

- *2024-03-01T05:51:22.083*
- *2024-03-01T05:51:32.083*
- *2024-03-01T05:51:52.083*

Therefore, if we aggregate the elements in a fixed time window of 20 seconds, we can expect the first two elements are grouped together while the last element is grouped on its own. The expected output can be created accordingly and compared to the pipeline output for verification.

```python
# section4/traffic_agg_test.py
import datetime
import sys
import unittest

import apache_beam as beam
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_stream import TestStream
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from traffic_agg import EventLog, parse_json, assign_timestamp


def main(out=sys.stderr, verbosity=2):
    loader = unittest.TestLoader()

    suite = loader.loadTestsFromModule(sys.modules[__name__])
    unittest.TextTestRunner(out, verbosity=verbosity).run(suite)


class TrafficWindowingTest(unittest.TestCase):
    def test_windowing_behaviour(self):
        options = PipelineOptions()
        options.view_as(StandardOptions).streaming = True
        with TestPipeline(options=options) as p:
            EVENTS = [
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:22.083", "event_ts": 1709232682083}',
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:32.083", "event_ts": 1709232682083}',
                '{"ip": "138.201.212.70", "id": "462520009613048791", "lat": 50.4779, "lng": 12.3713, "user_agent": "Mozilla/5.0 (iPod; U; CPU iPhone OS 3_1 like Mac OS X; ks-IN) AppleWebKit/532.30.7 (KHTML, like Gecko) Version/3.0.5 Mobile/8B115 Safari/6532.30.7", "age_bracket": "18-25", "opted_into_marketing": false, "http_request": "GET eucharya.html HTTP/1.0", "http_response": 200, "file_size_bytes": 207, "event_datetime": "2024-03-01T05:51:52.083", "event_ts": 1709232682083}',
            ]

            test_stream = (
                TestStream()
                .advance_watermark_to(0)
                .add_elements([EVENTS[0], EVENTS[1], EVENTS[2]])
                .advance_watermark_to_infinity()
            )

            output = (
                p
                | test_stream
                | beam.Map(parse_json).with_output_types(EventLog)
                | beam.Map(assign_timestamp)
                | beam.Map(lambda e: (e.id, 1))
                | beam.WindowInto(beam.window.FixedWindows(20))
                | beam.CombinePerKey(sum)
            )

            EXPECTED_OUTPUT = [("462520009613048791", 2), ("462520009613048791", 1)]

            assert_that(output, equal_to(EXPECTED_OUTPUT))


if __name__ == "__main__":
    main(out=None)
```

Similar to the previous testing, we can execute the test script for performing unit testing of the streaming pipeline.

```bash
$ python section4/traffic_agg_test.py 
test_windowing_behaviour (__main__.TrafficWindowingTest) ... ok

----------------------------------------------------------------------
Ran 1 test in 0.527s

OK
```

## Summary

In this series of posts, we discussed local development of Apache Beam pipelines using Python. In *Part 1*, a basic Beam pipeline was introduced, followed by demonstrating how to utilise Jupyter notebooks for interactive development. Several notebook examples were covered including [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) and [Beam DataFrames](https://beam.apache.org/documentation/dsls/dataframes/overview/). Batch pipelines were developed in *Part 2*, and we used pipelines from [GCP Python DataFlow Quest](https://github.com/GoogleCloudPlatform/training-data-analyst/tree/master/quests/dataflow_python) while modifying them to access local resources only. Each batch pipeline has two versions with/without SQL. In *Part 3*, we discussed how to set up local Flink and Kafka clusters for deploying streaming pipelines on the [Flink Runner](https://beam.apache.org/documentation/runners/flink/). A streaming pipeline with/without Beam SQL was built in *Part 4*, and this series concludes with illustrating unit testing of existing pipelines in this post.
