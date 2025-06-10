---
title: Kafka Connect for AWS Services Integration - Part 3 Deploy Camel DynamoDB Sink Connector
date: 2023-07-03
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Connect for AWS Services Integration
categories:
  - Data Streaming
  - Data Integration
tags: 
  - AWS
  - Amazon DynamoDB
  - Amazon MSK
  - Apache Camel
  - Apache Kafka
  - Kafka Connect
  - Kpow
authors:
  - JaehyeonKim
images: []
cevo: 30
description: As part of investigating how to utilize Kafka Connect effectively for AWS services integration, I demonstrated how to develop the Camel DynamoDB sink connector using Docker in Part 2. Fake order data was generated using the MSK Data Generator source connector, and the sink connector was configured to consume the topic messages to ingest them into a DynamoDB table. In this post, I will illustrate how to deploy the data ingestion applications using Amazon MSK and MSK Connect.
---

As part of investigating how to utilize Kafka Connect effectively for AWS services integration, I demonstrated how to develop the [Camel DynamoDB sink connector](https://camel.apache.org/camel-kafka-connector/latest/index.html) using Docker in [Part 2](/blog/2023-06-04-kafka-connect-for-aws-part-2). Fake order data was generated using the [MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator) source connector, and the sink connector was configured to consume the topic messages to ingest them into a DynamoDB table. In this post, I will illustrate how to deploy the data ingestion applications using [Amazon MSK](https://aws.amazon.com/msk/) and [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/).

* [Part 1 Introduction](/blog/2023-05-03-kafka-connect-for-aws-part-1)
* [Part 2 Develop Camel DynamoDB Sink Connector](/blog/2023-06-04-kafka-connect-for-aws-part-2)
* [Part 3 Deploy Camel DynamoDB Sink Connector](#) (this post)
* [Part 4 Develop Aiven OpenSearch Sink Connector](/blog/2023-10-23-kafka-connect-for-aws-part-4)
* [Part 5 Deploy Aiven OpenSearch Sink Connector](/blog/2023-10-30-kafka-connect-for-aws-part-5)

## Infrastructure

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (`vpc.tf`). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (`vpn.tf`). It is particularly useful to monitor and manage the MSK cluster and Kafka topic locally. The details about how to configure the VPN server can be found in an [earlier post](/blog/2022-02-06-dev-infra-terraform). The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-connect-for-aws/part-03) of this post.

### MSK

An MSK cluster with 3 brokers is created. The broker nodes are deployed with the *kafka.m5.large* instance type in private subnets and IAM authentication is used for the client authentication method. Finally, additional server configurations are added such as enabling auto creation of topics and topic deletion.

```terraform
# kafka-connect-for-aws/part-03/variable.tf
locals {
  ...
  msk = {
    version                    = "2.8.1"
    instance_size              = "kafka.m5.large"
    ebs_volume_size            = 20
    log_retention_ms           = 604800000 # 7 days
    num_partitions             = 3
    default_replication_factor = 3
  }
  ...
}
# kafka-connect-for-aws/part-03/msk.tf
resource "aws_msk_cluster" "msk_data_cluster" {
  cluster_name           = "${local.name}-msk-cluster"
  kafka_version          = local.msk.version
  number_of_broker_nodes = length(module.vpc.private_subnets)
  configuration_info {
    arn      = aws_msk_configuration.msk_config.arn
    revision = aws_msk_configuration.msk_config.latest_revision
  }

  broker_node_group_info {
    instance_type   = local.msk.instance_size
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk.id]
    storage_info {
      ebs_storage_info {
        volume_size = local.msk.ebs_volume_size
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_cluster_lg.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.default_bucket.id
        prefix  = "logs/msk/cluster/"
      }
    }
  }

  tags = local.tags

  depends_on = [aws_msk_configuration.msk_config]
}

resource "aws_msk_configuration" "msk_config" {
  name = "${local.name}-msk-configuration"

  kafka_versions = [local.msk.version]

  server_properties = <<PROPERTIES
    auto.create.topics.enable = true
    delete.topic.enable = true
    log.retention.ms = ${local.msk.log_retention_ms}
    num.partitions = ${local.msk.num_partitions}
    default.replication.factor = ${local.msk.default_replication_factor}
  PROPERTIES
}
```

#### Security Group

The security group for the MSK cluster allows all inbound traffic from itself and all outbound traffic into all IP addresses. The Kafka connectors will use the same security group and the former is necessary. Both the rules are configured too generously, and we can limit the protocol and port ranges in production. The last inbound rule is for VPN access.

```terraform
# kafka-connect-for-aws/part-03/msk.tf
resource "aws_security_group" "msk" {
  name   = "${local.name}-msk-sg"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_security_group_rule" "msk_self_inbound_all" {
  type                     = "ingress"
  description              = "Allow ingress from itself - required for MSK Connect"
  security_group_id        = aws_security_group.msk.id
  protocol                 = "-1"
  from_port                = "0"
  to_port                  = "0"
  source_security_group_id = aws_security_group.msk.id
}

resource "aws_security_group_rule" "msk_self_outbound_all" {
  type              = "egress"
  description       = "Allow outbound all"
  security_group_id = aws_security_group.msk.id
  protocol          = "-1"
  from_port         = "0"
  to_port           = "0"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "msk_vpn_inbound" {
  count                    = local.vpn.to_create ? 1 : 0
  type                     = "ingress"
  description              = "Allow VPN access"
  security_group_id        = aws_security_group.msk.id
  protocol                 = "tcp"
  from_port                = 9098
  to_port                  = 9098
  source_security_group_id = aws_security_group.vpn[0].id
}
```

### DynamoDB

The destination table is named *connect-for-aws-orders* (`${local.name}-orders`), and it has the primary key where *order_id* and *ordered_at* are the hash and range key respectively. It also has a global secondary index where *customer_id* and *ordered_at* constitute the primary key. Note that *ordered_at* is not generated by the source connector as the Java faker library doesn't have a method to generate a current timestamp. As illustrated below it'll be created by the sink connector using SMTs. The table can be created using as shown below.

```terraform
# kafka-connect-for-aws/part-03/ddb.tf
resource "aws_dynamodb_table" "orders_table" {
  name           = "${local.name}-orders"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "order_id"
  range_key      = "ordered_at"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "ordered_at"
    type = "S"
  }

  global_secondary_index {
    name            = "customer"
    hash_key        = "customer_id"
    range_key       = "ordered_at"
    write_capacity  = 1
    read_capacity   = 1
    projection_type = "ALL"
  }

  tags = local.tags
}
```

## Kafka Management App

A Kafka management app can be a good companion for development as it helps monitor and manage resources on an easy-to-use user interface. We'll use [*Kpow Community Edition (CE)*](https://docs.kpow.io/ce/) in this post. It allows you to manage one Kafka Cluster, one Schema Registry, and one Connect Cluster, with the UI supporting a single user session at a time. In the following compose file, we added connection details of the MSK cluster and MSK Connect.

```yaml
# kafka-connect-for-aws/part-03/docker-compose.yml
version: "3"

services:
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      # broker details
      BOOTSTRAP: $BOOTSTRAP_SERVERS
      # client authentication
      SECURITY_PROTOCOL: SASL_SSL
      SASL_MECHANISM: AWS_MSK_IAM
      SASL_JAAS_CONFIG: software.amazon.msk.auth.iam.IAMLoginModule required;
      SASL_CLIENT_CALLBACK_HANDLER_CLASS: software.amazon.msk.auth.iam.IAMClientCallbackHandler
      # MSK connect
      CONNECT_AWS_REGION: ap-southeast-2

networks:
  kafkanet:
    name: kafka-network
```

## Data Ingestion Pipeline

### Connector Source Download

Before we deploy the connectors, their sources need to be downloaded into the `./connectors` path so that they can be saved into S3 followed by being created as custom plugins. The MSK Data Generator is a single Jar file, and it can be kept it as is. On the other hand, the Camel DynamoDB sink connector is an archive file, and the contents should be compressed as the zip format.

```bash
# kafka-connect-for-aws/part-03/download.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

SRC_PATH=${SCRIPT_DIR}/connectors
rm -rf ${SRC_PATH} && mkdir ${SRC_PATH}

## MSK Data Generator Souce Connector
echo "downloading msk data generator..."
DOWNLOAD_URL=https://github.com/awslabs/amazon-msk-data-generator/releases/download/v0.4.0/msk-data-generator-0.4-jar-with-dependencies.jar

curl -L -o ${SRC_PATH}/msk-data-generator.jar ${DOWNLOAD_URL}

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

Below shows the connector sources that can be used to create custom plugins.

```bash
$ tree connectors -I 'camel-aws-ddb-sink-kafka-connector|docs'
connectors
├── camel-aws-ddb-sink-kafka-connector.zip
└── msk-data-generator.jar
```

### Connector IAM Role

For simplicity, a single IAM role will be used for both the source and sink connectors. The custom managed policy has permission on MSK cluster resources (cluster, topic and group). It also has permission on S3 bucket and CloudWatch Log for logging. Also, an AWS managed policy for DynamoDB (*AmazonDynamoDBFullAccess*) is attached for the sink connector.

```terraform
# kafka-connect-for-aws/part-03/msk-connect.tf
resource "aws_iam_role" "kafka_connector_role" {
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
    aws_iam_policy.kafka_connector_policy.arn
  ]
}

resource "aws_iam_policy" "kafka_connector_policy" {
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

### Source Connector

The connector source will be uploaded into S3 and a custom plugin is created with it. Then the source connector will be created using the custom plugin. 

In connector configuration, the connector class (*connector.class*) is required for any connector and I set it for the MSK Data Generator. Also, a single worker is allocated to the connector (*tasks.max*). As mentioned earlier, the converter-related properties are overridden. Specifically, the key converter is set to the string converter as the key of the topic is set to be primitive values (*genkp*). Also, schemas are not enabled for both the key and value.

Those properties in the middle are specific to the source connector. Basically it sends messages to a topic named *order*. The key is marked as *to-replace* as it will be replaced with the *order_id* attribute of the value - see below. The value has *order_id*, *product_id*, *quantity*, *customer_id* and *customer_name* attributes, and they are generated by the [Java faker library](https://github.com/DiUS/java-faker).

It can be easier to manage messages if the same order ID is shared with the key and value. We can achieve it using [single message transforms (SMTs)](https://kafka.apache.org/documentation.html#connect_transforms). Specifically I used two transforms - *ValueToKey* and *ExtractField* to achieve it. As the name suggests, the former copies the *order_id* value into the key. The latter is used additionally because the key is set to have primitive string values. Finally, the last transform (*Cast*) is to change the *quantity* value into integer.

```terraform
# kafka-connect-for-aws/part-03/msk-connect.tf
resource "aws_mskconnect_connector" "msk_data_generator" {
  name = "${local.name}-order-source"

  kafkaconnect_version = "2.7.1"

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = {
    # connector configuration
    "connector.class"                = "com.amazonaws.mskdatagen.GeneratorSourceConnector",
    "tasks.max"                      = "1",
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable"   = false,
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable" = false,
    # msk data generator configuration
    "genkp.order.with"              = "to-replace",
    "genv.order.order_id.with"      = "#{Internet.uuid}",
    "genv.order.product_id.with"    = "#{Code.isbn10}",
    "genv.order.quantity.with"      = "#{number.number_between '1','5'}",
    "genv.order.customer_id.with"   = "#{number.number_between '100','199'}",
    "genv.order.customer_name.with" = "#{Name.full_name}",
    "global.throttle.ms"            = "500",
    "global.history.records.max"    = "1000",
    # single message transforms
    "transforms"                            = "copyIdToKey,extractKeyFromStruct,cast",
    "transforms.copyIdToKey.type"           = "org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.copyIdToKey.fields"         = "order_id",
    "transforms.extractKeyFromStruct.type"  = "org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractKeyFromStruct.field" = "order_id",
    "transforms.cast.type"                  = "org.apache.kafka.connect.transforms.Cast$Value",
    "transforms.cast.spec"                  = "quantity:int8"
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
      arn      = aws_mskconnect_custom_plugin.msk_data_generator.arn
      revision = aws_mskconnect_custom_plugin.msk_data_generator.latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_data_generator.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.default_bucket.id
        prefix  = "logs/msk/connect/msk-data-generator"
      }
    }
  }

  service_execution_role_arn = aws_iam_role.kafka_connector_role.arn
}

resource "aws_mskconnect_custom_plugin" "msk_data_generator" {
  name         = "${local.name}-msk-data-generator"
  content_type = "JAR"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.default_bucket.arn
      file_key   = aws_s3_object.msk_data_generator.key
    }
  }
}

resource "aws_s3_object" "msk_data_generator" {
  bucket = aws_s3_bucket.default_bucket.id
  key    = "plugins/msk-data-generator.jar"
  source = "connectors/msk-data-generator.jar"

  etag = filemd5("connectors/msk-data-generator.jar")
}

resource "aws_cloudwatch_log_group" "msk_data_generator" {
  name = "/msk/connect/msk-data-generator"

  retention_in_days = 1

  tags = local.tags
}
```

We can check the details of the connector on AWS Console as shown below. 

![](source-connector.png#center)

#### Kafka Topic

As configured, the source connector ingests messages to the *order* topic, and we can check it on *kpow*.

![](topic-01.png#center)

We can browse individual messages in the *Inspect* tab in the *Data* menu.

![](topic-02.png#center)
![](topic-03.png#center)

### Sink Connector

The connector is configured to write messages from the *order* topic into the DynamoDB table created earlier. It requires to specify the table name, AWS region, operation, write capacity and whether to use the [default credential provider](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) - see the [documentation](https://camel.apache.org/camel-kafka-connector/latest/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) for details. Note that, if you don't use the default credential provider, you have to specify the *access key id* and *secret access key*. Note further that, although the current LTS version is *v3.18.2*, the default credential provider option didn't work for me, and I was recommended [to use *v3.20.3* instead](https://github.com/apache/camel-kafka-connector/issues/1533). Finally, the [*camel.sink.unmarshal* option](https://github.com/apache/camel-kafka-connector/blob/camel-kafka-connector-3.20.3/connectors/camel-aws-ddb-sink-kafka-connector/src/main/resources/kamelets/aws-ddb-sink.kamelet.yaml#L123) is to convert data from the internal *java.util.HashMap* type into the required *java.io.InputStream* type. Without this configuration, the [connector fails](https://github.com/apache/camel-kafka-connector/issues/1532) with *org.apache.camel.NoTypeConversionAvailableException* error.

Although the destination table has *ordered_at* as the range key, it is not created by the source connector because the Java faker library doesn't have a method to generate a current timestamp. Therefore, it is created by the sink connector using two SMTs - *InsertField* and *TimestampConverter*. Specifically they add a timestamp value to the *order_at* attribute, format the value as *yyyy-MM-dd HH:mm:ss:SSS*, and convert its type into string.

```terraform
# kafka-connect-for-aws/part-03/msk-connect.tf
resource "aws_mskconnect_connector" "camel_ddb_sink" {
  name = "${local.name}-order-sink"

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
    "topics"                                                   = "order",
    "camel.kamelet.aws-ddb-sink.table"                         = aws_dynamodb_table.orders_table.id,
    "camel.kamelet.aws-ddb-sink.region"                        = local.region,
    "camel.kamelet.aws-ddb-sink.operation"                     = "PutItem",
    "camel.kamelet.aws-ddb-sink.writeCapacity"                 = 1,
    "camel.kamelet.aws-ddb-sink.useDefaultCredentialsProvider" = true,
    "camel.sink.unmarshal"                                     = "jackson",
    # single message transforms
    "transforms"                          = "insertTS,formatTS",
    "transforms.insertTS.type"            = "org.apache.kafka.connect.transforms.InsertField$Value",
    "transforms.insertTS.timestamp.field" = "ordered_at",
    "transforms.formatTS.type"            = "org.apache.kafka.connect.transforms.TimestampConverter$Value",
    "transforms.formatTS.format"          = "yyyy-MM-dd HH:mm:ss:SSS",
    "transforms.formatTS.field"           = "ordered_at",
    "transforms.formatTS.target.type"     = "string"
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
      arn      = aws_mskconnect_custom_plugin.camel_ddb_sink.arn
      revision = aws_mskconnect_custom_plugin.camel_ddb_sink.latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.camel_ddb_sink.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.default_bucket.id
        prefix  = "logs/msk/connect/camel-ddb-sink"
      }
    }
  }

  service_execution_role_arn = aws_iam_role.kafka_connector_role.arn

  depends_on = [
    aws_mskconnect_connector.msk_data_generator
  ]
}

resource "aws_mskconnect_custom_plugin" "camel_ddb_sink" {
  name         = "${local.name}-camel-ddb-sink"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.default_bucket.arn
      file_key   = aws_s3_object.camel_ddb_sink.key
    }
  }
}

resource "aws_s3_object" "camel_ddb_sink" {
  bucket = aws_s3_bucket.default_bucket.id
  key    = "plugins/camel-aws-ddb-sink-kafka-connector.zip"
  source = "connectors/camel-aws-ddb-sink-kafka-connector.zip"

  etag = filemd5("connectors/camel-aws-ddb-sink-kafka-connector.zip")
}

resource "aws_cloudwatch_log_group" "camel_ddb_sink" {
  name = "/msk/connect/camel-ddb-sink"

  retention_in_days = 1

  tags = local.tags
}
```

The sink connector can be checked on AWS Console as shown below. 

![](sink-connector.png#center)

#### DynamoDB Destination

We can check the ingested records on the DynamoDB table items view. Below shows a list of scanned records. As expected, it has the *order_id*, *ordered_at* and other attributes.

![](ddb-01.png#center)

We can also obtain an individual Json record by clicking an *order_id* value as shown below.

![](ddb-02.png#center)

## Summary

As part of investigating how to utilize Kafka Connect effectively for AWS services integration, I demonstrated how to develop the [Camel DynamoDB sink connector](https://camel.apache.org/camel-kafka-connector/latest/index.html) using Docker in [Part 2](/blog/2023-06-04-kafka-connect-for-aws-part-2). Fake order data was generated using the [MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator) source connector, and the sink connector was configured to consume the topic messages to ingest them into a DynamoDB table. In this post, I illustrated how to deploy the data ingestion applications using [Amazon MSK](https://aws.amazon.com/msk/) and [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/).