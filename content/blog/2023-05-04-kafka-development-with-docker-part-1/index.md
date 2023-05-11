---
title: Kafka Development with Docker - Part 1 Kafka Cluster Setup
date: 2023-05-04
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development with Docker
categories:
  - Apache Kafka
tags: 
  - Apache Kafka
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Apache Kafka is one of the key technologies for modern data streaming architectures on AWS. Developing and testing Kafka-related applications can be easier using Docker and Docker Compose. In this series of posts, I will demonstrate reference implementations of those applications in Dockerized environments.
---

I'm teaching myself [modern data streaming architectures](https://docs.aws.amazon.com/whitepapers/latest/build-modern-data-streaming-analytics-architectures/build-modern-data-streaming-analytics-architectures.html) on AWS, and [Apache Kafka](https://kafka.apache.org/) is one of the key technologies, which can be used for messaging, activity tracking, stream processing and so on. While applications tend to be deployed to cloud, it can be much easier if we develop and test those with [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/) locally. As the series title indicates, I plan to publish articles that demonstrate Kafka and related tools in *Dockerized* environments. Although I covered some of them in previous posts, they are implemented differently in terms of the Kafka Docker image, the number of brokers, Docker volume mapping etc. It can be confusing, and one of the purposes of this series is to illustrate reference implementations that can be applied to future development projects. Also, I can extend my knowledge while preparing for this series. In fact Kafka security is one of the areas that I expect to learn further. Below shows a list of posts that I plan for now.

* [Part 1 Kafka Cluster Setup](#) (this post)
* Part 2 Kafka Management App
* Part 3 Kafka Connect without Schema Registry
* Part 4 Glue Schema Registry
* Part 5 Kafka Connect with Glue Schema Registry
* Part 6 SSL Encryption
* Part 7 SSL Authentication
* Part 8 SASL Authentication
* Part 9 Kafka Authorization
* (More topics related to MSK, MSK Connect...)

## Setup Kafka Cluster

We are going to create a Kafka cluster with 3 brokers and 1 Zookeeper node. Having multiple brokers are advantageous to test Kafka features. For example, the number of replication factor of a topic partition is limited to the number of brokers. Therefore, if we have multiple brokers, we can check what happens when the minimum in-sync replica configuration doesn't meet due to broker failure. We also need Zookeeper for metadata management - see [this article](https://www.conduktor.io/kafka/zookeeper-with-kafka/) for details about the role of Zookeeper. 

![](featured.png#center)

### Docker Compose File

There are popular docker images for Kafka development. Some of them are [confluentinc/cp-kafka](https://hub.docker.com/r/confluentinc/cp-kafka) from Confluent, [wurstmeister/kafka](https://hub.docker.com/r/wurstmeister/kafka) from wurstmeister, and [bitnami/kafka](https://hub.docker.com/r/bitnami/kafka) from Bitnami. I initially used the image from Confluent, but I was not sure how to select a specific version of Kafka - note the [recommended Kafka version of Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html#2.8.1) is 2.8.1. Also, the second image doesn't cover Kafka 3+ and it may be limited to use a newer version of Kafka in the future. In this regard, I chose the image from Bitnami.

The following Docker Compose file is used to create the Kafka cluster indicated earlier - it can also be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/blob/main/kafka-dev-with-docker/part-01/compose-kafka.yml) of this post. The resources created by the compose file is illustrated below.
- services
  - zookeeper
    - A Zookeeper node is created with minimal configuration. It allows anonymous login.
  - kafka-*[id]*
    - Each broker has a unique ID (*KAFKA_CFG_BROKER_ID*) and shares the same Zookeeper connect parameter (*KAFKA_CFG_ZOOKEEPER_CONNECT*). These are required to connect to the Zookeeper node.
    - Each has two listeners. The port 9092 is used within the same network and each has its own port (9093 to 9095), which can be used to connect from outside the network.
      - [**UPDATE 2023-05-09**] The external ports are updated from 29092 to 29094, which is because it is planned to use 9093 for SSL encryption.
    - Each can be accessed without authentication (*ALLOW_PLAINTEXT_LISTENER*). 
- networks
  - A network named *kafka-network* is created and used by all services. Having a custom network can be beneficial when services are launched by multiple Docker Compose files. This custom network can be referred by services in other compose files.
- volumes
  - Each service has its own volume that will be mapped to the container's data folder. We can check contents of the folder in the Docker volume path. More importantly data is preserved in the Docker volume unless it is deleted so that we don't have to recreate data every time the Kafka cluster gets started.
  - Docker volume mapping doesn't work as expected for me with WSL 2 and Docker Desktop. Therefore, I installed [Docker](https://docs.docker.com/engine/install/ubuntu/) and [Docker Compose](https://docs.docker.com.zh.xy2401.com/v17.12/compose/install/#install-compose) as Linux apps on WSL 2 and start the Docker daemon as `sudo service docker start`. Note I only need to run the command when the system (WSL 2) boots, and I haven't found a way to start it automatically.

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
      - "29092:29092"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-0:9092,EXTERNAL://localhost:29092
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
      - "29093:29093"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=1
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:29093
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-1:9092,EXTERNAL://localhost:29093
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
      - "29094:29094"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=2
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:29094
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka-2:9092,EXTERNAL://localhost:29094
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

### Start Containers

The Kafka cluster can be started by the `docker-compose up` command. As the compose file has a custom name (*compose-kafka.yml*), we need to specify the file name with the `-f` flag, and the `-d` flag makes the containers to run in the background. We can see that it creates the network, volumes and services in order.

```bash
$ cd kafka-dev-with-docker/part-01
$ docker-compose -f compose-kafka.yml up -d
# Creating network "kafka-network" with the default driver
# Creating volume "zookeeper_data" with local driver
# Creating volume "kafka_0_data" with local driver
# Creating volume "kafka_1_data" with local driver
# Creating volume "kafka_2_data" with local driver
# Creating zookeeper ... done
# Creating kafka-0   ... done
# Creating kafka-2   ... done
# Creating kafka-1   ... done
```

Once created, we can check the state of the containers with the `docker-compose ps` command.

```bash
$ docker-compose -f compose-kafka.yml ps
#   Name                 Command               State                                    Ports                                  
# -----------------------------------------------------------------------------------------------------------------------------
# kafka-0     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9093->9093/tcp,:::9093->9093/tcp                      
# kafka-1     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9094->9094/tcp,:::9094->9094/tcp                      
# kafka-2     /opt/bitnami/scripts/kafka ...   Up      9092/tcp, 0.0.0.0:9095->9095/tcp,:::9095->9095/tcp                      
# zookeeper   /opt/bitnami/scripts/zooke ...   Up      0.0.0.0:49153->2181/tcp,:::49153->2181/tcp, 2888/tcp, 3888/tcp, 8080/tcp
```

## Produce and Consume Messages

I will demonstrate how to produce and consume messages with Kafka command utilities after entering into one of the broker containers.

### Produce Messages

The command utilities locate in the `/opt/bitnami/kafka/bin/` directory. After moving to that directory, we can first create a topic with `kafka-topics.sh` by specifying the bootstrap server, topic name, number of partitions and replication factors - the last two are optional. Once the topic is created, we can produce messages with `kafka-console-producer.sh`, and it can be finished by pressing *Ctrl + C*.

```bash
$ docker exec -it kafka-0 bash
I have no name!@b04233b0bbba:/$ cd /opt/bitnami/kafka/bin/
## create topic
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-topics.sh \
  --bootstrap-server localhost:9092 --create \
  --topic orders --partitions 3 --replication-factor 3
# Created topic orders.

## produce messages
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic orders
>product: apples, quantity: 5
>product: lemons, quantity: 7
# press Ctrl + C to finish
```

### Consume Messages

We can use `kafka-console-consumer.sh` to consume messages. In this example, it polls messages from the beginning. Again we can finish it by pressing *Ctrl + C*.

```bash
$ docker exec -it kafka-0 bash
I have no name!@b04233b0bbba:/$ cd /opt/bitnami/kafka/bin/
## consume messages
I have no name!@b04233b0bbba:/opt/bitnami/kafka/bin$ ./kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic orders --from-beginning
product: apples, quantity: 5
product: lemons, quantity: 7
# press Ctrl + C to finish
```

### Note on Data Persistence

Sometimes we need to remove and recreate the Kafka containers, and it can be convenient if we can preserve data of the previous run. It is possible with the Docker volumes as data gets persisted in a later run as long as we keep using the same volumes. Note, by default, Docker Compose doesn't remove volumes, and they remain even if we run `docker-compose down`. Therefore, if we recreate the containers later, data is persisted in the volumes.

To give additional details, below shows the volumes created by the Docker Compose file and data of one of the brokers.  

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

...

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

If you want to remove everything including the volumes, add `-v` flag as shown below.

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

## Summary

In this post, we discussed how to set up a Kafka cluster with 3 brokers and a single Zookeeper node. A simple example of producing and consuming messages are illustrated. More reference implementations in relation to Kafka and related tools will be discussed in subsequent posts.