---
title: Kafka Connectors for AWS Integration
date: 2023-05-03
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - 
categories:
  - Data Engineering
tags: 
  - AWS
  - Amazon MSK
  - Amazon MSK Connect
  - Apache Kafka
  - Kafka Connect
authors:
  - JaehyeonKim
images: []
# cevo: 26
description: ...
---

According to the documentation of [Apache Kafka](https://kafka.apache.org/documentation/#connect), *Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka*. 

- [Confluent Hub](https://www.confluent.io/hub/)
- [Camel Kafka Connector](https://camel.apache.org/camel-kafka-connector/3.18.x/index.html), 
- avien, 
- lenses
- firehose?
- https://github.com/awslabs/amazon-msk-data-generator
- https://github.com/awslabs/kinesis-kafka-connector
- https://github.com/aws/personalize-kafka-connector


|Service|Source|Sink|License|
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


|Service|Source|Sink|
|:------|:-----:|:---:|
|[S3](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-sink-kafka-sink-connector.html)||✔|
|[S3](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-source-kafka-source-connector.html)|✔||
|[S3 - Streaming Upload](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-s3-streaming-upload-sink-kafka-sink-connector.html)||✔|
|[Redshift](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-redshift-sink-kafka-sink-connector.html)||✔|
|[Redshift](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-redshift-source-kafka-source-connector.html)|✔||
|[SQS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-sink-kafka-sink-connector.html)||✔|
|[SQS](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-source-kafka-source-connector.html)|✔||
|[SQS - FIFO Sink](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-fifo-sink-kafka-sink-connector.html)||✔|
|[SQS - Batch Sink](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-sqs-batch-sink-kafka-sink-connector.html)||✔|
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