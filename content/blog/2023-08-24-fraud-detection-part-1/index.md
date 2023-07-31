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
