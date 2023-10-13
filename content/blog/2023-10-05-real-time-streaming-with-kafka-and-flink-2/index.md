---
title: Real Time Streaming with Kafka and Flink - Introduction
date: 2023-10-05
draft: true
featured: true
comment: true
toc: false
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
  - Amazon MSK Connect
  - Amazon Managed Service for Apache Flink
  - Amazon Managed Flink
  - AWS Lambda
  - Amazon S3
  - Amazon DyanmoDB
  - Amazon Athena
  - AWS Glue
  - Amazon OpenSearch Service
  - Apache Kafka
  - Kafka Connect
  - Apache Flink
  - Pyflink
  - Apache Camel
  - OpenSearch
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
cevo: 33
docs: https://docs.google.com/document/d/1mX0VLCoGUEdGTSr3EKYkIgPl0KYtgRj1dY5pQ7svUuA
description: This series updates a real time analytics app based on Amazon Kinesis from an AWS workshop. Data is ingested from multiple sources into a Kafka cluster instead and Flink (Pyflink) apps are used extensively for data ingesting and processing. As an introduction, this post compares the original architecture with the new architecture, and the app will be implemented in subsequent posts.
---

**[This article](https://cevo.com.au/post/real-time-streaming-with-kafka-and-flink-intro/) was originally posted on Tech Insights of [Cevo Australia](https://cevo.com.au/).**

[Real Time Streaming with Amazon Kinesis](https://catalog.us-east-1.prod.workshops.aws/workshops/2300137e-f2ac-4eb9-a4ac-3d25026b235f/en-US) is an AWS workshop that helps users build a streaming analytics application on AWS. Incoming events are stored in a number of streams of the [Amazon Kinesis Data Streams](https://aws.amazon.com/kinesis/data-streams/) service, and various other AWS services and tools are used to process and analyse data. 

[Apache Kafka](https://kafka.apache.org/) is a popular distributed event store and stream processing platform, and it stores incoming events in topics. As part of learning real time streaming analytics on AWS, we can rebuild the analytics applications by replacing the Kinesis streams with Kafka topics. As an introduction, this post compares the workshop architecture with the updated architecture of this series. The labs of the updated architecture will be implemented in subsequent posts.

* [Introduction](#) (this post)
* Lab 1 Produce data to Kafka using Lambda
* Lab 2 Write data to Kafka from S3 using Flink
* Lab 3 Transform and write data to S3 from Kafka using Flink
* Lab 4 Clean, Aggregate, and Enrich Events with Flink
* Lab 5 Write data to DynamoDB using Kafka Connect
* Lab 6 Consume data from Kafka using Lambda

## Architecture Based-on Kafka and Flink

![](featured.png#center)


```json
{
	"id": "id3464573",
	"vendor_id": 5,
	"pickup_date": "2023-10-13T01:59:05.422",
	"dropoff_date": "2023-10-13T02:52:05.422",
	"passenger_count": 9,
	"pickup_longitude": "40.72935867",
	"pickup_latitude": "-73.97813416",
	"dropoff_longitude": "-73.91600037",
	"dropoff_latitude": "40.74634933",
	"store_and_fwd_flag": "Y",
	"gc_distance": 3,
	"trip_duration": 4731,
	"google_distance": 3,
	"google_duration": 4731
}
```