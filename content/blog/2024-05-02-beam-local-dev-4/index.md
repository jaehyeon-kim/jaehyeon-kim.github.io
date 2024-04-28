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
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - Python
authors:
  - JaehyeonKim
images: []
description: In this series, we discuss local development of Apache Beam pipelines using Python. A basic Beam pipeline was introduced in Part 1, followed by demonstrating how to utilise Jupyter notebooks, Beam SQL and Beam DataFrames. In this post, we discuss Batch pipelines that aggregate website visit log by user and time. The pipelines are developed with and without Beam SQL. Additionally, each pipeline is implemented on a Jupyter notebook for demonstration.
---

In this series, we discuss local development of [Apache Beam](https://beam.apache.org/) pipelines using Python. A basic Beam pipeline was introduced in [Part 1](/blog/2024-03-28-beam-local-dev-1), followed by demonstrating how to utilise Jupyter notebooks, [Beam SQL](https://beam.apache.org/documentation/dsls/sql/overview/) and [Beam DataFrames](https://beam.apache.org/documentation/dsls/dataframes/overview/). In this post, we discuss Batch pipelines that aggregate website visit log by user and time. The pipelines are developed with and without *Beam SQL*. Additionally, each pipeline is implemented on a Jupyter notebook for demonstration.

* [Part 1 Pipeline, Notebook, SQL and DataFrame](/blog/2024-03-28-beam-local-dev-1)
* [Part 2 Batch Pipelines](#) (this post)
* [Part 3 Flink Runner](/blog/2024-04-18-beam-local-dev-3)
* Part 4 Streaming Pipelines
* Part 5 Testing Pipelines

## Data Generation

We first need to generate website visit log data. As the second pipeline aggregates data by time, the max lag seconds (`--max_lag_seconds`) is set to 300 so that records are spread over 5 minutes period. See [Part 1](/blog/2024-03-28-beam-local-dev-1) for details about the data generation script and the source of this post can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-dev-env).

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

## Traffic Aggregation

### Pipeline Code

```python

```

### Start Flink/Kafka Clusters

### Generate Data

### Run Pipeline

## SQL Traffic Aggregation 

### Pipeline Code

### Start Flink/Kafka Clusters

### Generate Data

### Run Pipeline

```
$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}" | grep apache/beam_java11_sdk
46c51d89e966   apache/beam_java11_sdk:2.53.0   Up 7 seconds
2ad755fc66df   apache/beam_java11_sdk:2.53.0   Up 7 seconds
cf023d9bf39f   apache/beam_java11_sdk:2.53.0   Exited (1) 13 seconds ago
a549729318e3   apache/beam_java11_sdk:2.53.0   Exited (1) 38 seconds ago
95626f645252   apache/beam_java11_sdk:2.53.0   Exited (1) 57 seconds ago
38b56216e29a   apache/beam_java11_sdk:2.53.0   Exited (1) About a minute ago
3aee486b472f   apache/beam_java11_sdk:2.53.0   Exited (1) About a minute ago
```

## Summary

As part of discussing local development of *Apache Beam* pipelines using Python, we developed Batch pipelines that aggregate website visit log by user and time in this post. The pipelines were developed with and without *Beam SQL*. Additionally, each pipeline was implemented on a Jupyter notebook for demonstration.
