---
title: Kafka Connect for AWS Services Integration - Part 1 Introduction
date: 2023-05-03
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Connect for AWS Services Integration
categories:
  - Apache Kafka
tags: 
  - AWS
  - Apache Kafka
  - Kafka Connect
authors:
  - JaehyeonKim
images: []
cevo: 28
description: Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It can be used to build real-time data pipeline on AWS effectively. In this post, I will introduce available Kafka connectors mainly for AWS services integration. Also, developing and deploying some of them will be covered in later posts.
---

**[This article](https://cevo.com.au/post/kafka-connect-for-aws-part-1/) was originally posted on Tech Insights of [Cevo Australia](https://cevo.com.au/).**

[Amazon Kinesis Data Streams](https://aws.amazon.com/kinesis/data-streams/) and [Amazon Managed Streaming for Apache Kafka (MSK)](https://aws.amazon.com/msk/) are two managed streaming services offered by AWS. Many resources on the web indicate Kinesis Data Streams is better when it comes to integrating with AWS services. However, it is not necessarily the case with the help of Kafka Connect. According to the documentation of [Apache Kafka](https://kafka.apache.org/documentation/#connect), *Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka*. Kafka Connect supports two types of connectors - source and sink. Source connectors are used to ingest messages from external systems into Kafka topics while messages are ingested into external systems form Kafka topics with sink connectors. In this post, I will introduce available Kafka connectors mainly for AWS services integration. Also, developing and deploying some of them will be covered in later posts.

* [Part 1 Introduction](#) (this post)
* [Part 2 Develop Camel DynamoDB Sink Connector](/blog/2023-06-04-kafka-connect-for-aws-part-2)
* [Part 3 Deploy Camel DynamoDB Sink Connector](/blog/2023-07-03-kafka-connect-for-aws-part-3)
* [Part 4 Develop Aiven OpenSearch Sink Connector](/blog/2023-10-23-kafka-connect-for-aws-part-4)
* Part 5 Deploy Aiven OpenSearch Sink Connector

## Amazon

As far as I've searched, there are two GitHub repositories by AWS. The [Kinesis Kafka Connector](https://github.com/awslabs/kinesis-kafka-connector) includes sink connectors for Kinesis Data Streams and Kinesis Data Firehose. Also, recently AWS released a Kafka connector for Amazon Personalize and the project repository can be found [here](https://github.com/aws/personalize-kafka-connector). The available connectors are summarised below.

|Service|Source|Sink|
|:------|:-----:|:---:|
|[Kinesis](https://github.com/awslabs/kinesis-kafka-connector)||✔|
|[Kinesis - Firehose](https://github.com/awslabs/kinesis-kafka-connector)||✔|
|[Personalize](https://github.com/aws/personalize-kafka-connector)||✔|
|[EventBridge](https://github.com/awslabs/eventbridge-kafka-connector)||✔|

Note that, if we use the sink connector for Kinesis Data Firehose, we can build data pipelines to the [AWS services that are supported by it](https://docs.aws.amazon.com/firehose/latest/dev/create-name.html), which covers S3, Redshift and OpenSearch mainly. 

There is one more source connector by AWS Labs to be noted, although it doesn't support integration with a specific AWS service. The [Amazon MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator) is a translation of the [Voluble connector](https://github.com/MichaelDrogalis/voluble), and it can be used to generate test or fake data and ingest into a Kafka topic.

## Confluent Hub

[Confluent](https://www.confluent.io/) is a leading provider of Apache Kafka and related services. It manages the [Confluent Hub](https://www.confluent.io/hub/) where we can discover (and/or submit) Kafka connectors for various integration use cases. Although it keeps a wide range of connectors, only less than 10 connectors can be used to integrate with AWS services reliably at the time of writing this post. Moreover, all of them except for the S3 sink connector are licensed under *Commercial (Standard)*, which requires purchase of Confluent Platform subscription. Or it can only be used on a single broker cluster or evaluated for 30 days otherwise. Therefore, practically most of them cannot be used unless you have a subscription for the Confluent Platform.

|Service|Source|Sink|Licence|
|:------|:-----:|:---:|:------:|
|[S3](https://www.confluent.io/hub/confluentinc/kafka-connect-s3)||✔|Free|
|[S3](https://www.confluent.io/hub/confluentinc/kafka-connect-s3-source)|✔||Commercial (Standard)|
|[Redshift](https://www.confluent.io/hub/confluentinc/kafka-connect-aws-redshift)||✔|Commercial (Standard)|
|[SQS](https://www.confluent.io/hub/confluentinc/kafka-connect-sqs)|✔||Commercial (Standard)|
|[Kinesis](https://www.confluent.io/hub/confluentinc/kafka-connect-kinesis)|✔||Commercial (Standard)|
|[DynamoDB](https://www.confluent.io/hub/confluentinc/kafka-connect-aws-dynamodb)||✔|Commercial (Standard)|
|[CloudWatch Metrics](https://www.confluent.io/hub/confluentinc/kafka-connect-aws-cloudwatch-metrics)||✔|Commercial (Standard)|
|[Lambda](https://www.confluent.io/hub/confluentinc/kafka-connect-aws-lambda/)||✔|Commercial (Standard)|
|[CloudWatch Logs](https://www.confluent.io/hub/confluentinc/kafka-connect-aws-cloudwatch-logs)|✔||Commercial (Standard)|

## Camel Kafka Connector

[Apache Camel](https://camel.apache.org/manual/faq/what-is-camel.html) is a versatile open-source integration framework based on known [Enterprise Integration Patterns](https://camel.apache.org/components/3.20.x/eips/enterprise-integration-patterns.html). It supports [Camel Kafka connectors](https://camel.apache.org/camel-kafka-connector/3.18.x/index.html), which allows you to use all [Camel components](https://camel.apache.org/components/3.20.x/index.html) as Kafka Connect connectors. The latest LTS version is *3.18.x (LTS)*, and it is supported until July 2023. Note that it works with Apache Kafka at version 2.8.0 as a dependency. In spite of the compatibility requirement, the connectors are using the Kafka Client which often is [compatible with different broker versions](https://github.com/apache/camel-kafka-connector/issues/1525), especially when the two versions are closer. Therefore, we can use them with a different Kafka version e.g. [2.8.1, which is recommended by Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html).

At the time of writing this post, there are 23 source and sink connectors that target specific AWS services - see the summary table below. Moreover, there are connectors targeting popular RDBMS, which cover MariaDB, MySQL, Oracle, PostgreSQL and MS SQL Server. Together with the [Debezium connectors](https://debezium.io/), we can build effective data pipelines on Amazon RDS as well. Overall Camel connectors can be quite beneficial when building real-time data pipelines on AWS. 

|Service|Source|Sink|
|:------|:-----:|:---:|
|[S3](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-sink-kafka-sink-connector.html)||✔|
|[S3](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-source-kafka-source-connector.html)|✔||
|[S3 - Streaming Upload](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-streaming-upload-sink-kafka-sink-connector.html)||✔|
|[Redshift](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-redshift-sink-kafka-sink-connector.html)||✔|
|[Redshift](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-redshift-source-kafka-source-connector.html)|✔||
|[SQS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-sink-kafka-sink-connector.html)||✔|
|[SQS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-source-kafka-source-connector.html)|✔||
|[SQS - FIFO](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-fifo-sink-kafka-sink-connector.html)||✔|
|[SQS - Batch](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-batch-sink-kafka-sink-connector.html)||✔|
|[Kinesis](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-kinesis-sink-kafka-sink-connector.html)||✔|
|[Kinesis](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-kinesis-source-kafka-source-connector.html)|✔||
|[Kinesis - Firehose](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-kinesis-firehose-sink-kafka-sink-connector.html)||✔|
|[DynamoDB](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html)||✔|
|[DynamoDB - Streams](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-streams-source-kafka-source-connector.html)|✔||
|[CloudWatch Metrics](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-cloudwatch-sink-kafka-sink-connector.html)||✔|
|[Lambda](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-lambda-sink-kafka-sink-connector.html)||✔|
|[EC2](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ec2-sink-kafka-sink-connector.html)||✔|
|[EventBridge](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-eventbridge-sink-kafka-sink-connector.html)||✔|
|[Secrets Manager](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-secrets-manager-sink-kafka-sink-connector.html)||✔|
|[SES](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ses-sink-kafka-sink-connector.html)||✔|
|[SNS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sns-sink-kafka-sink-connector.html)||✔|
|[SNS - FIFO](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sns-fifo-sink-kafka-sink-connector.html)||✔|
|[IAM](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws2-iam-kafka-sink-connector.html)||✔|
|[KMS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws2-kms-kafka-sink-connector.html)||✔|

## Other Providers

Two other vendors ([Aiven](https://aiven.io/) and [Lenses](https://lenses.io/)) provide Kafka connectors that target AWS services, and those are related to S3 and OpenSearch - see below. I find the OpenSearch sink connector from Aiven would be worth a close look.

|Service|Source|Sink|Provider|
|:------|:-----:|:---:|:---:|
|[S3](https://docs.aiven.io/docs/products/kafka/kafka-connect/howto/s3-sink-connector-aiven)||✔|Aiven|
|[OpenSearch](https://docs.aiven.io/docs/products/kafka/kafka-connect/howto/opensearch-sink)||✔|Aiven|
|[S3](https://docs.lenses.io/5.1/connectors/sinks/s3sinkconnector/)||✔|Lenses|
|[S3](https://docs.lenses.io/5.1/connectors/sources/s3sourceconnector/)|✔||Lenses|

## Summary

Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It can be used to build real-time data pipelines on AWS effectively. We have discussed a range of Kafka connectors both from Amazon and 3rd-party projects. We will showcase some of them in later posts.
