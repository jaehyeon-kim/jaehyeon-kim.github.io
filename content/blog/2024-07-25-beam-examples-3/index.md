---
title: Apache Beam Python Examples - Part 3 Build Sport Activity Tracker with/without SQL
date: 2024-07-25
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
description: foo bar
---

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](#) (this post)
* Part 4 Call RPC Service for Data Augmentation
* Part 5 Call RPC Service in Batch using Stateless DoFn
* Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn
* Part 7 Separate Droppable Data into Side Output
* Part 8 Enhance Sport Activity Tracker with Runner Motivation
* Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Development Environment

The development environment requires an Apache Flink cluster, Apache Kafka cluster and [gRPC](https://grpc.io/) Server. For Flink, we can use either an embedded cluster or a local cluster while [Docker Compose](https://docs.docker.com/compose/) is used for the rest. See [Part 1](/blog/2024-07-04-beam-examples-1) for details about how to set up the development environment. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### Manage Environment

The Flink and Kafka clusters and gRPC server are managed by the following bash scripts.

- `./setup/start-flink-env.sh`
- `./setup/stop-flink-env.sh`

Those scripts accept four flags: `-f`, `-k` and `-g` to start/stop individual resources or `-a` to manage all of them. We can add multiple flags to start/stop multiple resources. Note that the scripts assume Flink 1.18.1 by default, and we can specify a specific Flink version if it is different from it e.g. `FLINK_VERSION=1.17.2 ./setup/start-flink-env.sh`.

Below shows how to start resources using the start-up script. We need to launch both the Flink and Kafka clusters if we deploy a Beam pipeline on a local Flink cluster. Otherwise, we can start the Kafka cluster only.

```bash
## start a local flink can kafka cluster
./setup/start-flink-env.sh -f -k
# start kafka...
# [+] Running 6/6
#  ⠿ Network app-network      Created                                     0.0s
#  ⠿ Volume "zookeeper_data"  Created                                     0.0s
#  ⠿ Volume "kafka_0_data"    Created                                     0.0s
#  ⠿ Container zookeeper      Started                                     0.3s
#  ⠿ Container kafka-0        Started                                     0.5s
#  ⠿ Container kafka-ui       Started                                     0.8s
# start flink 1.18.1...
# Starting cluster.
# Starting standalonesession daemon on host <hostname>.
# Starting taskexecutor daemon on host <hostname>.

## start a local kafka cluster only
./setup/start-flink-env.sh -k
# start kafka...
# [+] Running 6/6
#  ⠿ Network app-network      Created                                     0.0s
#  ⠿ Volume "zookeeper_data"  Created                                     0.0s
#  ⠿ Volume "kafka_0_data"    Created                                     0.0s
#  ⠿ Container zookeeper      Started                                     0.3s
#  ⠿ Container kafka-0        Started                                     0.5s
#  ⠿ Container kafka-ui       Started                                     0.8s
```

## Beam Pipelines

We develop two pipelines that calculate average word lengths. The former emits an output whenever an input text message is read while the latter returns outputs in a sliding time window.

### Shared Source

Both the pipelines read text messages from an input Kafka topic and write outputs to an output topic. Therefore, the data source and sink transforms are refactored into a utility module as shown below.

### Sport Tracker

```bash
python chapter2/sport_tracker.py --deprecated_read \
    --job_name=sport_tracker --runner FlinkRunner \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

![](sport-tracker-dag.png#center)

![](sport-tracker-output.png#center)

### Sport Tracker SQL

```bash
python chapter2/sport_tracker_sql.py --deprecated_read \
    --job_name=sport_tracker_sql --runner FlinkRunner \
	--streaming --environment_type=LOOPBACK --parallelism=3 --checkpointing_interval=10000
```

![](sport-tracker-sql-output.png#center)

