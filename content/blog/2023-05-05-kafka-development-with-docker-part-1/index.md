---
title: Kafka Development with Docker - Part 1 Kafka Cluster
date: 2023-05-05
draft: true
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development with Docker
categories:
  - Data Engineering
tags: 
  - Apache Kafka
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Apache Kafka is one of the key technologies for modern data streaming architectures on AWS. Developing and testing Kafka-related applications can be easier using Docker and Docker Compose. In this series of posts, I will demonstrate reference implementations of those applications in Dockerized environments.
---

I'm teaching myself [modern data streaming architectures](https://docs.aws.amazon.com/whitepapers/latest/build-modern-data-streaming-analytics-architectures/build-modern-data-streaming-analytics-architectures.html) on AWS, and [Apache Kafka](https://kafka.apache.org/) is one of the key technologies, which can be used for messaging, activity tracking, stream processing and so on. While applications tend to be deployed to cloud, it can be much easier if we develop and test those with [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/) locally. As the series title indicates, I plan to publish articles that demonstrate Kafka and related tools in *Dockerized* environments. The purpose of this series is in two folds. Firstly, although I covered related topics in previous posts, they are implemented in slightly different settings in terms of the Kafka version, the number of brokers etc. Therefore, I consider it is good to keep reference implementations in this series, which can be applied to future development projects. Also, while preparing for this series, I can extend my knowledge, for example, on Kafka security. Below shows the list of posts that I plan for now.

* [Part 1 Kafka Cluster](#) (this post)
* Part 2 Kafka Management UI
* Part 3 Kafka Connect without Schema Registry
* Part 4 Glue Schema Registry
* Part 5 Kafka Connect with Glue Schema Registry
* Part 6 SSL Encryption
* Part 7 SSL Authentication
* Part 8 SASL Authentication
* Part 9 Kafka Authorization
* (MSK related topics)


```yaml
# /kafka-dev-with-docker/part-01/compose-kafka.yml
version: "3.5"

services:
  zookeeper:
    image: bitnami/zookeeper:3.5
    container_name: zookeeper
    ports:
      - "2181"
    networks:
      - kafkanet
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
    volumes:
      - zookeeper_data:/bitnami/zookeeper
  kafka-0:
    image: bitnami/kafka:2.8.1
    container_name: kafka-0
    expose:
      - 9092
    ports:
      - "9093:9093"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-0:9092,EXTERNAL://localhost:9093
      - KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-1:
    image: bitnami/kafka:2.8.1
    container_name: kafka-1
    expose:
      - 9092
    ports:
      - "9094:9094"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=1
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:9094
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-1:9092,EXTERNAL://localhost:9094
      - KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT
    volumes:
      - kafka_1_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-2:
    image: bitnami/kafka:2.8.1
    container_name: kafka-2
    expose:
      - 9092
    ports:
      - "9095:9095"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=2
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:9095
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-2:9092,EXTERNAL://localhost:9095
      - KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT
    volumes:
      - kafka_2_data:/bitnami/kafka
    depends_on:
      - zookeeper

networks:
  kafkanet:
    name: kafka-network

volumes:
  zookeeper_data:
    driver: local
    name: zookeeper_data
  kafka_0_data:
    driver: local
    name: kafka_0_data
  kafka_1_data:
    driver: local
    name: kafka_1_data
  kafka_2_data:
    driver: local
    name: kafka_2_data
```

```bash
$ cd kafka-dev-with-docker/part-01
$ docker-compose -f compose-kafka.yml up -d
Creating network "kafka-network" with the default driver
Creating volume "zookeeper_data" with local driver
Creating volume "kafka_0_data" with local driver
Creating volume "kafka_1_data" with local driver
Creating volume "kafka_2_data" with local driver
Creating zookeeper ... done
Creating kafka-0   ... done
Creating kafka-2   ... done
Creating kafka-1   ... done
$ docker-compose -f compose-kafka.yml ps
#   Name                 Command               State                                    Ports                                  
# -----------------------------------------------------------------------------------------------------------------------------
# kafka-0     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9093->9093/tcp,:::9093->9093/tcp                      
# kafka-1     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9094->9094/tcp,:::9094->9094/tcp                      
# kafka-2     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9095->9095/tcp,:::9095->9095/tcp                      
# zookeeper   /opt/bitnami/scripts/zooke ...   Up      0.0.0.0:49153->2181/tcp,:::49153->2181/tcp, 2888/tcp, 3888/tcp, 8080/tcp
```

```bash
$ docker volume ls | grep data$
# local     kafka_0_data
# local     kafka_1_data
# local     kafka_2_data
# local     zookeeper_data
$ sudo ls -l /var/lib/docker/volumes/kafka_0_data/_data/data
# total 96
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-0
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-12
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-15
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-18
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-21
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-24
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-27
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-3
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-30
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-33
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-36
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-39
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-42
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-45
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-48
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 __consumer_offsets-6
# drwxr-xr-x 2 hadoop root 4096 May  3 07:58 __consumer_offsets-9
# -rw-r--r-- 1 hadoop root    0 May  3 07:52 cleaner-offset-checkpoint
# -rw-r--r-- 1 hadoop root    4 May  3 07:59 log-start-offset-checkpoint
# -rw-r--r-- 1 hadoop root   88 May  3 07:52 meta.properties
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 orders-0
# drwxr-xr-x 2 hadoop root 4096 May  3 07:57 orders-1
# drwxr-xr-x 2 hadoop root 4096 May  3 07:59 orders-2
# -rw-r--r-- 1 hadoop root  442 May  3 07:59 recovery-point-offset-checkpoint
# -rw-r--r-- 1 hadoop root  442 May  3 07:59 replication-offset-checkpoint
```

```bash
$ docker exec -it kafka-0 bash
I have no name!@b04233b0bbba:/$ cd /opt/bitnami/kafka/bin/
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-topics.sh \
  --bootstrap-server localhost:9092 --create \
  --topic orders --partitions 3 --replication-factor 3
# Created topic orders.
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic orders
>product: apples, quantity: 5
>product: lemons, quantity: 7
# press Ctrl + C to finish
```

```bash
$ docker exec -it kafka-0 bash
I have no name!@b04233b0bbba:/$ cd /opt/bitnami/kafka/bin/
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning
product: apples, quantity: 5
product: lemons, quantity: 7
# press Ctrl + C to finish
```

```bash
$ docker-compose -f compose-kafka.yml down -v
# Stopping kafka-1   ... done
# Stopping kafka-0   ... done
# Stopping kafka-2   ... done
# Stopping zookeeper ... done
# Removing kafka-1   ... done
# Removing kafka-0   ... done
# Removing kafka-2   ... done
# Removing zookeeper ... done
# Removing network kafka-network
# Removing volume zookeeper_data
# Removing volume kafka_0_data
# Removing volume kafka_1_data
# Removing volume kafka_2_data
```