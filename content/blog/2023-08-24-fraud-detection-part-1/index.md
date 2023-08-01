---
title: Kafka and DynamoDB for Real Time Fraud Detection - Part 1 Local Development
date: 2023-08-14
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka and DynamoDB for Real Time Fraud Detection
categories:
  - Data Engineering
tags:
  - Apache Flink
  - Apache Kafka
  - Kafka Connect
  - Amazon DynamoDB
  - Python
  - Docker
  - Docker Compose
  - Fraud Detection
authors:
  - JaehyeonKim
images: []
cevo: 29
description: The suite of Apache Camel Kafka connectors and the Kinesis Kafka connector from the AWS Labs can be effective for building data ingestion pipelines that integrate AWS services. In this post, I will illustrate how to develop the Camel DynamoDB sink connector using Docker. Fake order data will be generated using the MSK Data Generator source connector, and the sink connector will be configured to consume the topic messages to ingest them into a DynamoDB table.
---

[Apache Flink](https://flink.apache.org/) is an open-source, unified stream-processing and batch-processing framework. Its core is a distributed streaming data-flow engine that you can use to run real-time stream processing on high-throughput data sources. Currently, it is widely used to build applications for fraud/anomaly detection, rule-based alerting, business process monitoring, and continuous ETL to name a few.

On AWS, we can deploy a Flink application via [Amazon Kinesis Data Analytics (KDA)](https://aws.amazon.com/kinesis/data-analytics/), [Amazon EMR](https://aws.amazon.com/emr/) and [Amazon EKS](https://aws.amazon.com/eks/). Among those, KDA is the easiest option as it provides the underlying infrastructure for your Apache Flink applications.

There are a number of AWS workshops and blog posts that we can learn Flink development on AWS and one of those is [AWS Kafka and DynamoDB for real time fraud detection](https://catalog.us-east-1.prod.workshops.aws/workshops/ad026e95-37fd-4605-a327-b585a53b1300/en-US). While this workshop targets a Flink application via KDA, it would have been easier if it illustrated local development before moving into deployment. In this series of posts, we will implement the fraud detection application of the workshop. In part 1, the app will be developed locally using Docker, and it will be deployed via KDA in part 2.

* [Part 1 Local Development](#) (this post)
* Part 2 Deployment via KDA

## Architecture

There are two Python applications that send transaction and flagged account records into the corresponding topics - the transaction app sends records indefinitely in a loop. Both the topics are consumed by a Flink application, and it filters the transactions from the flagged accounts followed by sending them into an output topic. Finally, the flagged transaction records are sent into a DynamoDB table by the Camel DynamoDB sink connector.

![](featured.png#center)

## Kafka Services

A Kafka cluster with a single broker and zookeeper node is used in this post. The broker has two listeners and the port 9092 and 29092 are used for internal and external communication respectively. The default number of partitions is set to 2. Details about Kafka cluster setup can be found in [this post](https://jaehyeon.me/blog/2023-05-04-kafka-development-with-docker-part-1/).



```yaml
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
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=2
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-connect:
    image: bitnami/kafka:2.8.1
    container_name: connect
    command: >
      /opt/bitnami/kafka/bin/connect-distributed.sh
      /opt/bitnami/kafka/config/connect-distributed.properties
    ports:
      - "8083:8083"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
    volumes:
      - "./configs/connect-distributed.properties:/opt/bitnami/kafka/config/connect-distributed.properties"
      - "./connectors/camel-aws-ddb-sink-kafka-connector:/opt/connectors/camel-aws-ddb-sink-kafka-connector"
    depends_on:
      - zookeeper
      - kafka-0
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP: kafka-0:9092
    depends_on:
      - zookeeper
      - kafka-0
      - kafka-connect

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
```