---
title: Building Apache Flink Applications in Python
date: 2023-10-19
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Kafka Development with Docker
categories:
  - Data Streaming
tags: 
  - Apache Kafka
  - Apache Flink
  - Pyflink
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
description: Building Apache Flink Applications in Java by Confluent is a course to introduce Apache Flink through a series of hands-on exercises. Utilising the Flink DataStream API,  the course develops three Flink applications from ingesting source data into calculating usage statistics. As part of learning the Flink DataStream API in Pyflink, I converted the Java apps into Python equivalent while performing the course exercises in Pyflink. This post summarises the progress of the conversion and shows the final output.
---

[Building Apache Flink Applications in Java](https://developer.confluent.io/courses/flink-java/overview/) is a course to introduce [Apache Flink](https://flink.apache.org/) through a series of hands-on exercises, and it is provided by [Confluent](https://www.confluent.io/). Utilising the [Flink DataStream API](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/datastream/overview/), the course develops three Flink applications that populate multiple source data sets, collect them into a standardised data set, and aggregate it to produce usage statistics. As part of learning the Flink DataStream API in Pyflink, I converted the Java apps into Python equivalent while performing the course exercises in Pyflink. This post summarises the progress of the conversion and shows the final output.

## Architecture

There are two airlines (*SkyOne* and *Sunset*) and they have their own flight data in different schemas. While the course ingests the source data into corresponding topics using a Flink application that makes use of the [DataGen DataStream Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/datastream/datagen/), we use a [Kafka producer application](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s05_data_gen.py) here because the DataGen connector is not available for python.

The [flight importer job](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s16_merge.py) reads the messages from the source topics, standardises them into the flight data schema, and pushed into another Kafka topic, called *flightdata*. It is developed using Pyflink.

The [usage statistics calculator](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s20_manage_state.py) sources the *flightdata* topic and calculates usage statistics over a one-minute window, which is grouped by email address. Moreover, while accessing the global state, it produces cumulative usage statistics, which carries information from one window to the next. It is developed using Pyflink as well.

![](featured.png#center)

## Course Contents

Below describes course contents. ✅ and ☑️ indicate exercises and course materials respectively. The lesson 3 covers how to set up Kafka and Flink clusters using Docker Compose. The Kafka producer app is created as the lesson 5 exercise. The final versions of the flight importer job and usage statistics calculator can be found as exercises of the lesson 16 and 20 respectively.

1. Apache Flink with Java - An Introduction
2. Datastream Programming
3. ✅ How to Start Flink and Get Setup (Exercise)
   - Built Kafka and Flink clusters using Docker
   - Bitnami images are used for the Kafka cluster - see [this page](https://jaehyeon.me/blog/2023-05-04-kafka-development-with-docker-part-1/) for details.
   - A custom Docker image (_building-pyflink-apps:1.17.1_) is created to install Python and the Pyflink package as well as to save dependent Jar files
     - See the [Dockerfile](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/Dockerfile), and it can be built by `docker build -t=building-pyflink-apps:1.17.1 .`
   - See the [docker-compose.yml](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/docker-compose.yml) and the clusters can be started by `docker-compose up -d`
4. ☑️ The Flink Job Lifecycle
   - A minimal example of executing a Pyflink app is added.
   - **See course content(s) below**
     - [s04_intro.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s04_intro.py)
5. ✅ Running a Flink Job (Exercise)
   - Pyflink doesn't have the DataGen DataStream connector. Used a Kafka producer instead to create topics and send messages.
     - 4 topics are created (_skyone_, _sunset_, _flightdata_ and _userstatistics_) and messages are sent to the first two topics.
   - **See course content(s) below**
     - [s05_data_gen.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s05_data_gen.py)
       - Topics are created by a flag argument so add it if it is the first time running it. i.e. `python src/s05_data_gen.py --create`. Basically it deletes the topics if exits and creates them.
6. Anatomy of a Stream
7. Flink Data Sources
8. ✅ Creating a Flink Data Source (Exercise)
   - It reads from the _skyone_ topic and prints the values. The values are deserialized as string in this exercise.
   - This and all the other Pyflink applications can be executed locally or run in the Flink cluster. See the script for details.
   - **See course content(s) below**
     - [s08_create_source.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s08_create_source.py)
9. Serializers & Deserializers
10. ✅ Deserializing Messages in Flink (Exercise)
    - The _skyone_ message values are deserialized as Json string and they are returned as the [named Row type](https://nightlies.apache.org/flink/flink-docs-master/api/python/reference/pyflink.common/api/pyflink.common.typeinfo.Types.ROW_NAMED.html#pyflink.common.typeinfo.Types.ROW_NAMED). As the Flink type is not convenient for processing, it is converted into a Python object, specifically [Data Classes](https://docs.python.org/3/library/dataclasses.html).
    - **See course content(s) below**
      - [s10_deserialization.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s10_deserialization.py)
11. ☑️ Transforming Data in Flink
    - _Map_, _FlatMap_, _Filter_ and _Reduce_ transformations are illustrated using built-in operators and process functions.
    - **See course content(s) below**
      - [s11_transformation.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s11_transformation.py)
      - [s11_process_function.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s11_process_function.py)
12. ✅ Flink Data Transformations (Exercise)
    - The source data is transformed into the flight data. Later data from _skyone_ and _sunset_ will be converted into this schema for merging them.
    - The transformation is performed in a function called _define_workflow_ for being tested. This function will be updated gradually.
    - **See course content(s) below**
      - [s12_transformation.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s12_transformation.py)
      - [test_s12_transformation.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/test_s12_transformation.py)
        - Expected to run testing scripts individually eg) `pytest src/test_s12_transformation.py -svv`
13. Flink Data Sinks
14. ✅ Creating a Flink Data Sink (Exercise)
    - The converted data from _skyone_ will be pushed into a Kafka topic (_flightdata_).
    - Note that, as the Python Data Classes cannot be serialized, records are converted into the named Row type before being sent.
    - **See course content(s) below**
      - [s14_sink.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s14_sink.py)
15. ☑️ Creating Branching Data Streams in Flink
    - Various branching methods are illustrated, which covers _Union_, _CoProcessFunction_, _CoMapFunction_, _CoFlatMapFunction_, and _Side Outputs_.
    - **See course content(s) below**
      - [s15_branching.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s15_branching.py)
16. ✅ Merging Flink Data Streams (Exercise)
    - Records from the _skyone_ and _sunset_ topics are merged and sent into the _flightdata_ topic after being converted into the flight data.
    - **See course content(s) below**
      - [s16_merge.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s16_merge.py)
      - [test_s16_merge.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/test_s16_merge.py)
17. Windowing and Watermarks in Flink
18. ✅ Aggregating Flink Data using Windowing (Exercise)
    - Usage statistics (total flight duration and number of flights) are calculated by email address, and they are sent into the _userstatistics_ topic.
    - Note the transformation is _stateless_ in a sense that aggregation is entirely within a one-minute tumbling window.
    - **See course content(s) below**
      - [s18_aggregation.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s18_aggregation.py)
      - [test_s18_aggregation.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/test_s18_aggregation.py)
19. Working with Keyed State in Flink
20. ✅ Managing State in Flink (Exercise)
    - The transformation gets _stateful_ so that usage statistics are continuously updated by accessing the state values.
    - The _reduce_ function includes a window function that allows you to access the global state. The window function takes the responsibility to keep updating the global state and to return updated values.
    - **See course content(s) below**
      - [s20_manage_state.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/s20_manage_state.py)
      - [test_s20_manage_state.py](https://github.com/jaehyeon-kim/flink-demos/tree/master/building-pyflink-apps/src/test_s20_manage_state.py)
21. Closing Remarks

## Start Applications

After creating the Kafka and Flink clusters using Docker Compose, we need to start the Python producer in one terminal. Then we can submit the other Pyflink applications in another terminal.

```bash
#### build docker image for Pyflink
docker build -t=building-pyflink-apps:1.17.1 .

#### create kafka and flink clusters and kafka-ui
docker-compose up -d

#### start kafka producer in one terminal
python -m venv venv
source venv/bin/activate
# upgrade pip (optional)
pip install pip --upgrade
# install required packages
pip install -r requirements-dev.txt
## start with --create flag to create topics before sending messages
python src/s05_data_gen.py --create

#### submit pyflink apps in another terminal
## flight importer
docker exec jobmanager /opt/flink/bin/flink run \
    --python /tmp/src/s16_merge.py \
    --pyFiles file:///tmp/src/models.py,file:///tmp/src/utils.py \
    -d

## usage calculator
docker exec jobmanager /opt/flink/bin/flink run \
    --python /tmp/src/s20_manage_state.py \
    --pyFiles file:///tmp/src/models.py,file:///tmp/src/utils.py \
    -d
```

We can check the Pyflink jobs are running on the Flink Dashboard via *localhost:8081*.

![](flink-jobs.png#center)

Also, we can check the Kafka topics on *kafka-ui* via *localhost:8080*.

![](kafka-topics.png#center)

## Unit Testing

Four lessons have unit testing cases, and they are expected to run separately by specifying a testing script. For example, below shows running unit testing cases of the final usage statistics calculator job.

![](unit-testing.png#center)