---
title: Real Time Streaming with Kafka and Flink - Lab 5 Write data to DynamoDB using Kafka Connect
date: 2023-11-30
draft: false
featured: false
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
  - Amazon MSK Connect
  - Amazon DynamoDB
  - Apache Kafka
  - Kafka Connect
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka. In this lab, we will discuss how to create a data pipeline that ingests data from a Kafka topic into a DynamoDB table using the Camel DynamoDB sink connector.
---

[Kafka Connect](https://kafka.apache.org/documentation/#connect) is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka. In this lab, we will discuss how to create a data pipeline that ingests data from a Kafka topic into a DynamoDB table using the [Camel DynamoDB sink connector](https://camel.apache.org/camel-kafka-connector/3.20.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html).

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](#) (this post)
* [Lab 4 Clean, Aggregate, and Enrich Events with Flink](/blog/2023-11-23-real-time-streaming-with-kafka-and-flink-5)
* [Lab 5 Write data to DynamoDB using Kafka Connect](#) (this post)
* Lab 6 Consume data from Kafka using Lambda

## Architecture

Fake taxi ride data is sent to a Kafka topic by the Kafka producer application that is discussed in [Lab 1](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2). The messages of the topic are written into a DynamoDB table by a Kafka sink connector, which is deployed on [Amazon MSK Connect](https://aws.amazon.com/msk/features/msk-connect/).

![](featured.png#center)

## Infrastructure

The AWS infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post. See this [earlier post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details about how to create the resources. The key resources cover a VPC, VPN server, MSK cluster and Python Lambda producer app.

### MSK Connect

For this lab, a Kafka sink connector and DynamoDB table are created additionally, and their details are illustrated below.

#### Download Connector Source

Before we deploy the sink connector, its source should be downloaded into the *infra/connectors* path. From there, the source can be saved into a S3 bucket followed by being used to create a custom plugin. The connector source has multiple Jar files, and they should be compressed as the zip format. The archive file can be created by executing the *download.sh* file.

```bash
# download.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

SRC_PATH=${SCRIPT_DIR}/infra/connectors
rm -rf ${SRC_PATH} && mkdir -p ${SRC_PATH}

## Download camel dynamodb sink connector
echo "download camel dynamodb sink connector..."
DOWNLOAD_URL=https://repo.maven.apache.org/maven2/org/apache/camel/kafkaconnector/camel-aws-ddb-sink-kafka-connector/3.20.3/camel-aws-ddb-sink-kafka-connector-3.20.3-package.tar.gz

# decompress and zip contents to create custom plugin of msk connect later
curl -o ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz ${DOWNLOAD_URL} \
  && tar -xvzf ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz -C ${SRC_PATH} \
  && cd ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector \
  && zip -r camel-aws-ddb-sink-kafka-connector.zip . \
  && mv camel-aws-ddb-sink-kafka-connector.zip ${SRC_PATH} \
  && rm ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz
```

Below shows the sink connector source. As mentioned, the zip file will be used to create a custom plugin. Note that the unarchived connect source is kept because we can use it on a local Kafka Connect server deployed on Docker.

```bash
$ tree infra/connectors -P 'camel-aws-ddb-sink-kafka-connector*' -I 'docs'
infra/connectors
├── camel-aws-ddb-sink-kafka-connector
│   └── camel-aws-ddb-sink-kafka-connector-3.20.3.jar
└── camel-aws-ddb-sink-kafka-connector.zip
```

#### DynamoDB Sink Connector

The connector is configured to write messages from the *taxi-rides* topic into a DynamoDB table. It requires to specify the table name, AWS region, operation, write capacity and whether to use the [default credential provider](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) - see the [documentation](https://camel.apache.org/camel-kafka-connector/3.20.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) for details. Note that, if you don't use the default credential provider, you have to specify the *access key id* and *secret access key*. Note also that the [*camel.sink.unmarshal* option](https://github.com/apache/camel-kafka-connector/blob/camel-kafka-connector-3.20.3/connectors/camel-aws-ddb-sink-kafka-connector/src/main/resources/kamelets/aws-ddb-sink.kamelet.yaml#L123) is to convert data from the internal *java.util.HashMap* into the required *java.io.InputStream*. Without this configuration, the [connector fails](https://github.com/apache/camel-kafka-connector/issues/1532) with the *org.apache.camel.NoTypeConversionAvailableException* error.

```terraform
# infra/msk-connect.tf
resource "aws_mskconnect_connector" "taxi_rides_sink" {
  count = local.connect.to_create ? 1 : 0

  name = "${local.name}-taxi-rides-sink"

  kafkaconnect_version = "2.7.1"

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = {
    # connector configuration
    "connector.class"                = "org.apache.camel.kafkaconnector.awsddbsink.CamelAwsddbsinkSinkConnector",
    "tasks.max"                      = "1",
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable"   = false,
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable" = false,
    # camel ddb sink configuration
    "topics"                                                   = "taxi-rides",
    "camel.kamelet.aws-ddb-sink.table"                         = aws_dynamodb_table.taxi_rides.id,
    "camel.kamelet.aws-ddb-sink.region"                        = local.region,
    "camel.kamelet.aws-ddb-sink.operation"                     = "PutItem",
    "camel.kamelet.aws-ddb-sink.writeCapacity"                 = 1,
    "camel.kamelet.aws-ddb-sink.useDefaultCredentialsProvider" = true,
    "camel.sink.unmarshal"                                     = "jackson"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam

      vpc {
        security_groups = [aws_security_group.msk.id]
        subnets         = module.vpc.private_subnets
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.camel_ddb_sink[0].arn
      revision = aws_mskconnect_custom_plugin.camel_ddb_sink[0].latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.camel_ddb_sink[0].name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.default_bucket.id
        prefix  = "logs/msk/connect/taxi-rides-sink"
      }
    }
  }

  service_execution_role_arn = aws_iam_role.kafka_connector_role[0].arn
}

resource "aws_mskconnect_custom_plugin" "camel_ddb_sink" {
  count = local.connect.to_create ? 1 : 0

  name         = "${local.name}-camel-ddb-sink"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.default_bucket.arn
      file_key   = aws_s3_object.camel_ddb_sink[0].key
    }
  }
}

resource "aws_s3_object" "camel_ddb_sink" {
  count = local.connect.to_create ? 1 : 0

  bucket = aws_s3_bucket.default_bucket.id
  key    = "plugins/camel-aws-ddb-sink-kafka-connector.zip"
  source = "connectors/camel-aws-ddb-sink-kafka-connector.zip"

  etag = filemd5("connectors/camel-aws-ddb-sink-kafka-connector.zip")
}

resource "aws_cloudwatch_log_group" "camel_ddb_sink" {
  count = local.connect.to_create ? 1 : 0

  name = "/msk/connect/camel-ddb-sink"

  retention_in_days = 1

  tags = local.tags
}
```

#### Connector IAM Role

The managed policy of the connector role has permission on MSK cluster resources (cluster, topic and group). It also has permission on S3 bucket and CloudWatch Log for logging. Finally, as the connector should be able to create records in a DynamoDB table, the DynamoDB full access policy (*AmazonDynamoDBFullAccess*) is attached to the role for simplicity.

```terraform
# infra/msk-connect.tf
resource "aws_iam_role" "kafka_connector_role" {
  count = local.connect.to_create ? 1 : 0

  name = "${local.name}-connector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    aws_iam_policy.kafka_connector_policy[0].arn
  ]
}

resource "aws_iam_policy" "kafka_connector_policy" {
  count = local.connect.to_create ? 1 : 0

  name = "${local.name}-connector-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PermissionOnCluster"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.name}-msk-cluster/*"
      },
      {
        Sid = "PermissionOnTopics"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:topic/${local.name}-msk-cluster/*"
      },
      {
        Sid = "PermissionOnGroups"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:group/${local.name}-msk-cluster/*"
      },
      {
        Sid = "PermissionOnDataBucket"
        Action = [
          "s3:ListBucket",
          "s3:*Object"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.default_bucket.arn}",
          "${aws_s3_bucket.default_bucket.arn}/*"
        ]
      },
      {
        Sid = "LoggingPermission"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
```

### DynamoDB Table

A simple DynamoDB table that has the *id* attribute as the partition key is configured as shown below. 

```terraform
# infra/msk-connect.tf
resource "aws_dynamodb_table" "taxi_rides" {
  name           = "${local.name}-taxi-rides"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = local.tags
}
```

The infrastructure can be deployed (as well as destroyed) using Terraform CLI. Note that the sink connector and DynamoDB table are created only when the *connect_to_create* variable is set to *true*.

```bash
# initialize
terraform init
# create an execution plan
terraform plan -var 'producer_to_create=true' -var 'connect_to_create=true'
# execute the actions proposed in a Terraform plan
terraform apply -auto-approve=true -var 'producer_to_create=true' -var 'connect_to_create=true'

# destroy all remote objects
# terraform destroy -auto-approve=true -var 'producer_to_create=true' -var 'connect_to_create=true'
```

Once the resources are deployed, we can check the sink connector on AWS Console.

![](kafka-connect.png#center)

### Local Development (Optional)

#### Create Kafka Connect on Docker

As discussed further later, we can use a local Kafka cluster deployed on Docker instead of one on Amazon MSK. For this option, we need to deploy a local Kafka Connect server on Docker as well, and it can be created by the following Docker Compose file. See [this post](/blog/2023-05-25-kafka-development-with-docker-part-3) for details about how to set up a Kafka Connect server on Docker.

```yaml
# compose-extra.yml
version: "3.5"

services:

  ...

  kafka-connect:
    image: bitnami/kafka:2.8.1
    container_name: connect
    command: >
      /opt/bitnami/kafka/bin/connect-distributed.sh
      /opt/bitnami/kafka/config/connect-distributed.properties
    ports:
      - "8083:8083"
    networks:
      - appnet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
    volumes:
      - "./configs/connect-distributed.properties:/opt/bitnami/kafka/config/connect-distributed.properties"
      - "./infra/connectors/camel-aws-ddb-sink-kafka-connector:/opt/connectors/camel-aws-ddb-sink-kafka-connector"

networks:
  appnet:
    external: true
    name: app-network

  ...
```

We can create a local Kafka cluster and Kafka Connect server as following.

```bash
## set aws credentials environment variables
export AWS_ACCESS_KEY_ID=<aws-access-key-id>
export AWS_SECRET_ACCESS_KEY=<aws-secret-access-key>

# create kafka cluster
docker-compose -f compose-local-kafka.yml up -d
# create kafka connect server
docker-compose -f compose-extra.yml up -d
```

#### Create DynamoDB Table with CLI

We still need to create a DynamoDB table, and it can be created using the AWS CLI as shown below.

```json
// configs/ddb.json
{
  "TableName": "real-time-streaming-taxi-rides",
  "KeySchema": [{ "AttributeName": "id", "KeyType": "HASH" }],
  "AttributeDefinitions": [{ "AttributeName": "id", "AttributeType": "S" }],
  "ProvisionedThroughput": {
    "ReadCapacityUnits": 1,
    "WriteCapacityUnits": 1
  }
}
```

```bash
$ aws dynamodb create-table --cli-input-json file://configs/ddb.json
```

#### Deploy Sink Connector Locally

As Kafka Connect provides a REST API that manages connectors, we can create a connector programmatically. The REST endpoint requires a JSON payload that includes connector configurations.

```json
// configs/sink.json
{
  "name": "real-time-streaming-taxi-rides-sink",
  "config": {
    "connector.class": "org.apache.camel.kafkaconnector.awsddbsink.CamelAwsddbsinkSinkConnector",
    "tasks.max": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,
    "topics": "taxi-rides",

    "camel.kamelet.aws-ddb-sink.table": "real-time-streaming-taxi-rides",
    "camel.kamelet.aws-ddb-sink.region": "ap-southeast-2",
    "camel.kamelet.aws-ddb-sink.operation": "PutItem",
    "camel.kamelet.aws-ddb-sink.writeCapacity": 1,
    "camel.kamelet.aws-ddb-sink.useDefaultCredentialsProvider": true,
    "camel.sink.unmarshal": "jackson"
  }
}
```

The connector can be created (or deleted) using *Curl* as shown below.

```bash
# deploy sink connector
$ curl -i -X POST -H "Accept:application/json" -H  "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/sink.json

# check status
$ curl http://localhost:8083/connectors/real-time-streaming-taxi-rides-sink/status

# # delete sink connector
# $ curl -X DELETE http://localhost:8083/connectors/real-time-streaming-taxi-rides-sink
```

## Application Result

### Kafka Topic

We can see the topic (*taxi-rides*) is created, and the details of the topic can be found on the *Topics* menu on *localhost:3000*. Note that, if the Kafka monitoring app (*kpow*) is not started, we can run it using *compose-ui.yml* - see [this post](/blog/http://localhost:1313/blog/2023-10-23-kafka-connect-for-aws-part-4) for details about *kpow* configuration.

![](kafka-topic.png#center)

### Table Records

We can check the ingested records on the DynamoDB table items view. Below shows a list of scanned records.

![](dynamodb.png#center)

## Summary

Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka. In this lab, we discussed how to create a data pipeline that ingests data from a Kafka topic into a DynamoDB table using the Camel DynamoDB sink connector.