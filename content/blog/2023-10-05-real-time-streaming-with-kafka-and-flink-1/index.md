---
title: Real Time Streaming with Kafka and Flink - Introduction
date: 2023-10-05
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Real Time Streaming with Kafka and Flink
categories:
  - Data Streaming
tags: 
  - AWS
  - Amazon MSK
  - Apache Flink
  - Apache Kafka
  - Pyflink
authors:
  - JaehyeonKim
images: []
cevo: 33
docs: https://docs.google.com/document/d/1mX0VLCoGUEdGTSr3EKYkIgPl0KYtgRj1dY5pQ7svUuA
description: This series updates a real time analytics app based on Amazon Kinesis from an AWS workshop. Data is ingested from multiple sources into a Kafka cluster instead and Flink (Pyflink) apps are used extensively for data ingesting and processing. As an introduction, this post compares the original architecture with the new architecture, and the app will be implemented in subsequent posts.
---

[Real Time Streaming with Amazon Kinesis](https://catalog.us-east-1.prod.workshops.aws/workshops/2300137e-f2ac-4eb9-a4ac-3d25026b235f/en-US) is an AWS workshop that helps users build a streaming analytics application on AWS. Incoming events are stored in a number of streams of the [Amazon Kinesis Data Streams](https://aws.amazon.com/kinesis/data-streams/) service, and various other AWS services and tools are used to process and analyse data. 

[Apache Kafka](https://kafka.apache.org/) is a popular distributed event store and stream processing platform, and it stores incoming events in topics. As part of learning real time streaming analytics on AWS, we can rebuild the analytics applications by replacing the Kinesis streams with Kafka topics. As an introduction, this post compares the workshop architecture with the updated architecture of this series. The labs of the updated architecture will be implemented in subsequent posts.

* [Introduction](#) (this post)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](/blog/2023-11-16-real-time-streaming-with-kafka-and-flink-4)
* [Lab 4 Clean, Aggregate, and Enrich Events with Flink](/blog/2023-11-23-real-time-streaming-with-kafka-and-flink-5)
* [Lab 5 Write data to DynamoDB using Kafka Connect](/blog/2023-11-30-real-time-streaming-with-kafka-and-flink-6)
* [Lab 6 Consume data from Kafka using Lambda](/blog/2023-12-14-real-time-streaming-with-kafka-and-flink-7)

[**Update 2023-11-06**] Initially I planned to deploy Pyflink applications on [Amazon Managed Service for Apache Flink](https://aws.amazon.com/managed-service-apache-flink/), but I changed the plan to use a local Flink cluster deployed on Docker. The main reasons are

1. It is not clear how to configure a Pyflink application for the managed service. For example, Apache Flink supports [pluggable file systems](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/deployment/filesystems/overview/) and the required dependency (eg *flink-s3-fs-hadoop-1.15.2.jar*) should be placed under the *plugins* folder. However, the sample Pyflink applications from [pyflink-getting-started](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) and [amazon-kinesis-data-analytics-blueprints](https://github.com/aws-samples/amazon-kinesis-data-analytics-blueprints/tree/main/apps/python-table-api/msk-serverless-to-s3-tableapi-python) either ignore the S3 jar file for deployment or package it together with other dependencies - *none of them uses the S3 jar file as a plugin*. I tried multiple different configurations, but all ended up with having an error whose code is *CodeError.InvalidApplicationCode*. I don't have such an issue when I deploy the app on a local Flink cluster and I haven't found a way to configure the app for the managed service as yet.
2. The Pyflink app for *Lab 4* requires the OpenSearch sink connector and the connector is available on *1.16.0+*. However, the latest Flink version of the managed service is still *1.15.2* and the sink connector is not available on it. Normally the latest version of the managed service is behind two minor versions of the official release, but it seems to take a little longer to catch up at the moment - the version 1.18.0 was released a while ago.

## Workshop Architecture

![](original.png#center)

* Lab 1 - Produce data to Kinesis Data Streams
  * We will go through a couple of ways to write data to a Kinesis Data Stream using [Amazon SDK](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/kinesis.html) and [Amazon Kinesis Producer Library](https://github.com/awslabs/amazon-kinesis-producer).
* Lab 2 - Write Data to a Kinesis Data Stream using Kinesis Data Analytics Studio Notebook
  * We will use Zeppelin Notebook to read *Taxi Ride* data from S3 and insert into Kinesis Stream.
* Lab 3 - Lambda with Kinesis Data Firehose
  * We will create a Kinesis stream and integrate with [Amazon Kinesis Data Firehose](https://aws.amazon.com/kinesis/data-firehose/) delivery stream to write to a S3 bucket. We will also create a Lambda function that transforms the incoming events and then sends the transformed data to the Firehose Delivery Stream. Finally, the data in S3 will be queried by [Amazon Athena](https://aws.amazon.com/athena/).
* Lab 4 - Clean, Aggregate, and Enrich Events with Kinesis Data Analytics
  * We will learn how to connect Kinesis Data Analytics Studio to your existing stream and clean, aggregate, and enrich the incoming events. The derived insights are finally persisted in [Amazon OpenSearch Service](https://aws.amazon.com/opensearch-service/), where they can be accessed and visualized using OpenSearch Dashboard.
* Lab 5 - Lambda Consumer for Kinesis Data Stream
  * We will use a Lambda consumer to consume data from the Kinesis Data Stream. As part of the lab we will create the Lambda function to process records from the Kinesis Data Stream.
* Lab 6 - Consuming with Amazon KCL
  * We will consume and process data with the [Kinesis Client Library (KCL)](https://docs.aws.amazon.com/streams/latest/dev/shared-throughput-kcl-consumers.html). The KCL takes care of many complex tasks associated with distributed processing and allows you to focus on the record processing logic.

## Architecture Based-on Kafka and Flink

![](featured.png#center)

* Lab 1 - Produce data to Kafka using Lambda
  * We will create Kafka producers using an EventBridge schedule rule and Lambda producer function. The schedule rule is set to run *every minute* and has a *configurable* number of targets where each of them invokes the producer function. The producer function sends messages to a Kafka cluster on [Amazon MSK](https://aws.amazon.com/msk/). In this way we are able to generate events using multiple Lambda functions according to the desired volume of events.
* Lab 2 - Write data to Kafka from S3 using Flink
  * We will develop a Pyflink application that reads *Taxi Ride* data from S3 and inserts into Kafka. As [Apache Flink](https://flink.apache.org/) supports both stream and batch processing, we are able to process static data without an issue. This kind of exercise can be useful for data enrichment that joins static data into stream events. 
* Lab 3 - Transform and write data to S3 from Kafka using Flink
  * We will write Kafka messages to a S3 bucket using a Pyflink application. Although Kafka Connect supports simple data transformations by the [single message transforms](https://kafka.apache.org/documentation.html#connect_transforms), they are quite limited compared to the scope that Apache Flink supports. Note that writing data to S3 allows us to build a data lake with real time data.
  * Alternatively we would be able to use the [managed data delivery](https://aws.amazon.com/blogs/aws/amazon-msk-introduces-managed-data-delivery-from-apache-kafka-to-your-data-lake/) of Amazon MSK, which loads data into Amazon S3 via Amazon Kinesis Data Firehose. This post sticks to a Pyflink application as it has potential to write data on open table formats such as Apache Iceberg and Apache Hudi.
* Lab 4 - Clean, Aggregate, and Enrich Events with Flink
  * We will learn how to connect a Pyflink application to the existing Kafka topics and clean, aggregate, and enrich the incoming events. The derived insights are finally persisted in [Amazon OpenSearch Service](https://aws.amazon.com/opensearch-service/), where they can be accessed and visualised using OpenSearch Dashboard. 
  * Note that the OpenSearch Flink connector is supported on Apache Flink version 1.16+ where the [latest supported version of Amazon Managed Flink](https://docs.aws.amazon.com/managed-flink/latest/java/earlier.html) is 1.15.2. Normally Amazon Managed Flink lags two minor versions behind and a newer version would be supported by the time when the lab is performed - The release of [Apache Flink version 1.18](https://cwiki.apache.org/confluence/display/FLINK/1.18+Release) is expected at the end of September 2023.
* Lab 5 - Write data to DynamoDB using Kafka Connect
  * We will learn how to write data into a DynamoDB table using [Kafka Connect](https://kafka.apache.org/documentation/#connect). *Kafka Connect* is a tool for scalably and reliably streaming data between Apache Kafka and other systems. [Apache Camel](https://camel.apache.org/manual/faq/what-is-camel.html) provides a number of open source [Kafka connectors](https://camel.apache.org/camel-kafka-connector) that can be used to integrate AWS services. 
* Lab 6 - Consume data from Kafka using Lambda
  * We will consume and process data with a Lambda function. Lambda internally polls for new messages from Kafka topics and then synchronously invokes the target Lambda function. Lambda reads the messages in batches and provides these to your function as an event payload.
