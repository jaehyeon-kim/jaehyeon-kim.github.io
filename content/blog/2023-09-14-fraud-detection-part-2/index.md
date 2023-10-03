---
title: Kafka, Flink and DynamoDB for Real Time Fraud Detection - Part 2 Deployment via AWS Managed Flink
date: 2023-09-14
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka, Flink and DynamoDB for Real Time Fraud Detection
categories:
  - Data Streaming
tags:
  - Apache Flink
  - Pyflink
  - Apache Kafka
  - Kafka Connect
  - Amazon DynamoDB
  - Amazon MSK
  - Amazon MSK Connect
  - Amazon Managed Service for Apache Flink
  - Amazon Managed Flink
  - Python
  - Fraud Detection
authors:
  - JaehyeonKim
images: []
cevo: 32
docs: https://docs.google.com/document/d/1kRB3XeccUAjNwRH_sFwjJ_fCSnUw3NrQnzF202QGx4o
description: This series aims to help those who are new to Apache Flink and Amazon Managed Service for Apache Flink by re-implementing a simple fraud detection application that is discussed in an AWS workshop titled AWS Kafka and DynamoDB for real time fraud detection. In part 1, I demonstrated how to develop the application locally, and the app will be deployed via Amazon Managed Service for Apache Flink in this post.
---

This series aims to help those who are new to [Apache Flink](https://flink.apache.org/) and [Amazon Managed Service for Apache Flink](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-managed-service-apache-flink/) by re-implementing a simple fraud detection application that is discussed in an AWS workshop titled [AWS Kafka and DynamoDB for real time fraud detection](https://catalog.us-east-1.prod.workshops.aws/workshops/ad026e95-37fd-4605-a327-b585a53b1300/en-US). In part 1, I demonstrated how to develop the application locally, and the app will be deployed via *Amazon Managed Service for Apache Flink* in this post.

* [Part 1 Local Development](/blog/2023-08-10-fraud-detection-part-1)
* [Part 2 Deployment via AWS Managed Flink](#) (this post)

[**Update 2023-08-30**] Amazon Kinesis Data Analytics is renamed into [Amazon Managed Service for Apache Flink](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-managed-service-apache-flink/). In this post, Kinesis Data Analytics (KDA) and Amazon Managed Service for Apache Flink will be used interchangeably.

## Architecture

There are two Python applications that send transaction and flagged account records into the corresponding topics - the transaction app sends records indefinitely in a loop. Note that, as the Kafka cluster is deployed in private subnets, a VPN server is used to generate records from the developer machine. Both the topics are consumed by a Flink application, and it filters the transactions from the flagged accounts followed by sending them into an output topic of flagged transactions. Finally, the flagged transaction records are sent into a DynamoDB table by the [Camel DynamoDB sink connector](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) in order to serve real-time requests from an API.

![](featured.png#center)

## Infrastructure

The infrastructure resources are created using Terraform. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/fraud-detection/remote) of this post.

### Preparation

#### Flink Application and Kafka Connector Packages

The Flink application has multiple jar dependencies as the Kafka cluster is authenticated via IAM. Therefore, the jar files have to be combined into a single Uber jar file because KDA does not allow you to specify multiple pipeline jar files. The details about how to create the custom jar file can be found in [this post](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2). Also, the Camel DynamoDB sink connector needs to be packaged into a zip file, and it can be performed after downloading the binaries from the Maven repository.

The following script (*build.sh*) creates the Flink app and Kafka connector packages. For the former, it builds the Uber Jar file, followed by downloading the *kafka-python* package, creating a zip file that can be used to deploy the Flink app via KDA. Note that, although the Flink app does not need the *kafka-python* package, it is added in order to check if `--pyFiles` option works.

```bash
# build.sh
#!/usr/bin/env bash
shopt -s extglob

PKG_ALL="${PKG_ALL:-yes}"
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

#### Steps to package the flink app
# remove contents under $SRC_PATH (except for uber-jar-for-pyflink) and kda-package.zip file
SRC_PATH=$SCRIPT_DIR/package
rm -rf $SRC_PATH/!(uber-jar-for-pyflink) kda-package.zip

## Generate Uber Jar for PyFlink app for MSK cluster with IAM authN
echo "generate Uber jar for PyFlink app..."
mkdir $SRC_PATH/lib
mvn clean install -f $SRC_PATH/uber-jar-for-pyflink/pom.xml \
  && mv $SRC_PATH/uber-jar-for-pyflink/target/pyflink-getting-started-1.0.0.jar $SRC_PATH/lib \
  && rm -rf $SRC_PATH/uber-jar-for-pyflink/target

## Install pip packages
echo "install and zip pip packages..."
pip install -r requirements.txt --target $SRC_PATH/site_packages

if [ $PKG_ALL == "yes" ]; then
  ## Package pyflink app
  echo "package pyflink app"
  zip -r kda-package.zip processor.py package/lib package/site_packages
fi

#### Steps to create the sink connector
CONN_PATH=$SCRIPT_DIR/connectors
rm -rf $CONN_PATH && mkdir $CONN_PATH

## Download camel dynamodb sink connector
echo "download camel dynamodb sink connector..."
CONNECTOR_SRC_DOWNLOAD_URL=https://repo.maven.apache.org/maven2/org/apache/camel/kafkaconnector/camel-aws-ddb-sink-kafka-connector/3.20.3/camel-aws-ddb-sink-kafka-connector-3.20.3-package.tar.gz

## decompress and zip contents to create custom plugin of msk connect later
curl -o $CONN_PATH/camel-aws-ddb-sink-kafka-connector.tar.gz $CONNECTOR_SRC_DOWNLOAD_URL \
  && tar -xvzf $CONN_PATH/camel-aws-ddb-sink-kafka-connector.tar.gz -C $CONN_PATH \
  && cd $CONN_PATH/camel-aws-ddb-sink-kafka-connector \
  && zip -r camel-aws-ddb-sink-kafka-connector.zip . \
  && mv camel-aws-ddb-sink-kafka-connector.zip $CONN_PATH \
  && rm $CONN_PATH/camel-aws-ddb-sink-kafka-connector.tar.gz
```

Once completed, we can obtain the following zip files.

- Kafka sink connector - *connectors/camel-aws-ddb-sink-kafka-connector.zip*
- Flink application - *kda-package.zip*
  - Flink application - *processor.py*
  - Pipeline jar file - *package/lib/pyflink-getting-started-1.0.0.jar*
  - kafka-python package - *package/site_packages/kafka*

#### Kafka Management App

The [Kpow CE](https://docs.kpow.io/ce/) is used for ease of monitoring Kafka topics and related resources. The bootstrap server address, security configuration for IAM authentication and AWS credentials are added as environment variables. See [this post](/blog/2023-05-18-kafka-development-with-docker-part-2/) for details about Kafka management apps.

```yaml
# docker-compose.yml
version: "3"

services:
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - appnet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      # MSK cluster
      BOOTSTRAP: $BOOTSTRAP_SERVERS
      SECURITY_PROTOCOL: SASL_SSL
      SASL_MECHANISM: AWS_MSK_IAM
      SASL_CLIENT_CALLBACK_HANDLER_CLASS: software.amazon.msk.auth.iam.IAMClientCallbackHandler
      SASL_JAAS_CONFIG: software.amazon.msk.auth.iam.IAMLoginModule required;
      # MSK connect
      CONNECT_AWS_REGION: $AWS_DEFAULT_REGION

networks:
  appnet:
    name: app-network
```

### VPC and VPN

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (*infra/vpc.tf*). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (*infra/vpn.tf*). It is particularly useful to monitor and manage the MSK cluster and Kafka topic locally. The details about how to configure the VPN server can be found in [this post](/blog/2022-02-06-dev-infra-terraform).

### MSK Cluster

A MSK cluster with 2 brokers is created. The broker nodes are deployed with the *kafka.m5.large* instance type in private subnets and IAM authentication is used for the client authentication method. Finally, additional server configurations are added such as enabling auto creation of topics and topic deletion.

```terraform
# infra/variable.tf
locals {
  ...
  msk = {
    version                    = "2.8.1"
    instance_size              = "kafka.m5.large"
    ebs_volume_size            = 20
    log_retention_ms           = 604800000 # 7 days
    number_of_broker_nodes     = 2
    num_partitions             = 2
    default_replication_factor = 2
  }
  ...
}
# infra/msk.tf
resource "aws_msk_cluster" "msk_data_cluster" {
  cluster_name           = "${local.name}-msk-cluster"
  kafka_version          = local.msk.version
  number_of_broker_nodes = local.msk.number_of_broker_nodes
  configuration_info {
    arn      = aws_msk_configuration.msk_config.arn
    revision = aws_msk_configuration.msk_config.latest_revision
  }

  broker_node_group_info {
    instance_type   = local.msk.instance_size
    client_subnets  = slice(module.vpc.private_subnets, 0, local.msk.number_of_broker_nodes)
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

The security group of the MSK cluster allows all inbound traffic from itself and all outbound traffic into all IP addresses. The Kafka connectors will use the same security group and the former is necessary. Both the rules are configured too generously, however, we can limit the protocol and port ranges in production. Also, the security group has an additional inbound rule that permits it to connect on port 9098 from the security group of the Flink application.

```terraform
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

resource "aws_security_group_rule" "msk_kda_inbound" {
  type                     = "ingress"
  description              = "Allow KDA access"
  security_group_id        = aws_security_group.msk.id
  protocol                 = "tcp"
  from_port                = 9098
  to_port                  = 9098
  source_security_group_id = aws_security_group.kda_sg.id
}
```

### DynamoDB Table

The destination table is configured to have a composite primary key where *transaction_id* and *transaction_date* are the hash and range key respectively. It also has a global secondary index (GSI) where *account_id* and *transaction_date* constitute the primary key. The GSI is to facilitate querying by account id.

```terraform
# infra/ddb.tf
resource "aws_dynamodb_table" "transactions_table" {
  name           = "${local.name}-flagged-transactions"
  billing_mode   = "PROVISIONED"
  read_capacity  = 2
  write_capacity = 2
  hash_key       = "transaction_id"
  range_key      = "transaction_date"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "account_id"
    type = "N"
  }

  attribute {
    name = "transaction_date"
    type = "S"
  }

  global_secondary_index {
    name            = "account"
    hash_key        = "account_id"
    range_key       = "transaction_date"
    write_capacity  = 2
    read_capacity   = 2
    projection_type = "ALL"
  }

  tags = local.tags
}
```

### Flink Application

The runtime environment and service execution role are required to create a Flink app. The latest supported Flink version (1.15.2) is specified for the former and an IAM role is created for the latter - it'll be discussed more in a later section. Furthermore, we need to specify more configurations that are related to the Flink application and CloudWatch logging, and they will be covered below in detail as well.

```terraform
# infra/variable.tf
locals {
  ...
  kda = {
    runtime_env  = "FLINK-1_15"
    package_name = "kda-package.zip"
    consumer_0 = {
      table_name = "flagged_accounts"
      topic_name = "flagged-accounts"
    }
    consumer_1 = {
      table_name = "transactions"
      topic_name = "transactions"
    }
    producer_0 = {
      table_name = "flagged_transactions"
      topic_name = "flagged-transactions"
    }
  }
  ...
}

resource "aws_kinesisanalyticsv2_application" "kda_app" {
  name                   = "${local.name}-kda-app"
  runtime_environment    = local.kda.runtime_env
  service_execution_role = aws_iam_role.kda_app_role.arn

  ...
}
```

#### Application Configuration

In the application configuration section, we can specify details of the application code, VPC, environment properties, and application itself.

##### Application Code Configuration

The application package (*kda-package.zip*) is uploaded into the default S3 bucket using the *aws_s3_object* Terraform resource. Then it can be used as the code content by specifying the bucket and key names.

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.default_bucket.arn
          file_key   = aws_s3_object.kda_package[0].key
        }
      }

      code_content_type = "ZIPFILE"
    }

    ...
  
  }

  ...

}

...


resource "aws_s3_object" "kda_package" {
  bucket = aws_s3_bucket.default_bucket.id
  key    = "packages/${local.kda.package_name}"
  source = "${dirname(path.cwd)}/${local.kda.package_name}"

  etag = filemd5("${dirname(path.cwd)}/${local.kda.package_name}")
}
```

##### VPC Configuration

The app can be deployed in the private subnets as it doesn't need to be connected from outside. Note that an outbound rule that permits connection on port 9098 is created in its security group because it should be able to access the Kafka brokers.

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  application_configuration {
    
    ...

    vpc_configuration {
      security_group_ids = [aws_security_group.kda_sg.id]
      subnet_ids         = module.vpc.private_subnets
    }

    ...
  
  }

  ...

}

...

resource "aws_security_group" "kda_sg" {
  name   = "${local.name}-kda-sg"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}
```

##### Environment Properties

In environment properties, we first add [Flink CLI options](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/deployment/cli/#submitting-pyflink-jobs) in the *kinesis.analytics.flink.run.options* group. The values of the Pyflink app (*python*), pipeline jar (*jarfile*) and 3rd-party python package location (*pyFiles*) should match those in the application package (*kda-package.zip*). The other property groups are related to the Kafka source/sink table options, and they will be read by the application.

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  application_configuration {
    
    ...

    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"

        property_map = {
          python  = "processor.py"
          jarfile = "package/lib/pyflink-getting-started-1.0.0.jar"
          pyFiles = "package/site_packages/"
        }
      }

      property_group {
        property_group_id = "consumer.config.0"

        property_map = {
          "table.name"        = local.kda.consumer_0.table_name
          "topic.name"        = local.kda.consumer_0.topic_name
          "bootstrap.servers" = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam
          "startup.mode"      = "earliest-offset"
        }
      }

      property_group {
        property_group_id = "consumer.config.1"

        property_map = {
          "table.name"        = local.kda.consumer_1.table_name
          "topic.name"        = local.kda.consumer_1.topic_name
          "bootstrap.servers" = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam
          "startup.mode"      = "earliest-offset"
        }
      }

      property_group {
        property_group_id = "producer.config.0"

        property_map = {
          "table.name"        = local.kda.producer_0.table_name
          "topic.name"        = local.kda.producer_0.topic_name
          "bootstrap.servers" = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam
        }
      }
    }

    ...
  
  }

  ...

}

```

##### Flink Application Configuration

The Flink application configurations consist of the following.

- [Checkpoints](https://docs.aws.amazon.com/managed-flink/latest/java/disaster-recovery-resiliency.html) - Checkpoints are backups of application state that Managed Service for Apache Flink automatically creates periodically and uses to restore from faults. By default, the following values are configured.
  - *CheckpointingEnabled: true*
  - *CheckpointInterval: 60000*
  - *MinPauseBetweenCheckpoints: 5000*
- [Monitoring](https://docs.aws.amazon.com/managed-flink/latest/java/monitoring.html) - The metrics level determines which metrics are created to CloudWatch - see [this page](https://docs.aws.amazon.com/managed-flink/latest/java/metrics-dimensions.html) for details. The supported values are *APPLICATION*, *OPERATOR*, *PARALLELISM*, and *TASK*. Here *APPLICATION* is selected as the metrics level value.
- [Parallelism](https://docs.aws.amazon.com/managed-flink/latest/java/how-scaling.html) - We can configure the [parallel execution](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/datastream/execution/parallel/) of tasks and the allocation of resources to implement scaling. The *parallelism* indicates the initial number of parallel tasks that an application can perform while the *parallelism_per_kpu* is the number of parallel tasks that an application can perform per Kinesis Processing Unit (KPU). The application parallelism can be updated by enabling auto-scaling.

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  application_configuration {
    
    ...

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        auto_scaling_enabled = true
        parallelism          = 1
        parallelism_per_kpu  = 1
      }
    }
  }

  ...

}

```

#### Cloudwatch Logging Options

We can add a CloudWatch log stream ARN to the CloudWatch logging options. Note that, when I missed it at first, I saw a CloudWatch log group and log stream are created automatically, but logging was not enabled. It was only when I specified a custom log stream ARN that logging was enabled and log messages were ingested.

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.kda_ls.arn
  }

  ...

}

...

resource "aws_cloudwatch_log_group" "kda_lg" {
  name = "/${local.name}-kda-log-group"
}

resource "aws_cloudwatch_log_stream" "kda_ls" {
  name = "${local.name}-kda-log-stream"

  log_group_name = aws_cloudwatch_log_group.kda_lg.name
}
```

#### IAM Role

The service execution role has the following permissions.

* Full access to CloudWatch, CloudWatch Log and Amazon Kinesis Data Analytics. It is given by AWS managed policies for logging, metrics generation etc. However, it is by no means recommended and should be updated according to the least privilege principle for production.
* 3 inline policies for connecting to the MSK cluster (*kda-msk-access*) in private subnets (*kda-vpc-access*) as well as giving access to the application package in S3 (*kda-s3-access*).

```terraform
# infra/kda.tf
resource "aws_iam_role" "kda_app_role" {
  name = "${local.name}-kda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::aws:policy/AmazonKinesisAnalyticsFullAccess"
  ]

  inline_policy {
    name = "kda-msk-access"

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
        }
      ]
    })
  }

  inline_policy {
    name = "kda-vpc-access"
    # https://docs.aws.amazon.com/kinesisanalytics/latest/java/vpc-permissions.html

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid = "VPCReadOnlyPermissions"
          Action = [
            "ec2:DescribeVpcs",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeDhcpOptions"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Sid = "ENIReadWritePermissions"
          Action = [
            "ec2:CreateNetworkInterface",
            "ec2:CreateNetworkInterfacePermission",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface"
          ]
          Effect   = "Allow"
          Resource = "*"
        }

      ]
    })
  }

  inline_policy {
    name = "kda-s3-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListObjectsInBucket"
          Action   = ["s3:ListBucket"]
          Effect   = "Allow"
          Resource = "arn:aws:s3:::${aws_s3_bucket.default_bucket.id}"
        },
        {
          Sid      = "AllObjectActions"
          Action   = ["s3:*Object"]
          Effect   = "Allow"
          Resource = "arn:aws:s3:::${aws_s3_bucket.default_bucket.id}/*"
        },
      ]
    })
  }

  tags = local.tags
}
```

Once deployed, we can see the application on AWS console, and it stays in the ready status.

![](flink-app.png#center)

### Camel DynamoDB Sink Connector

The connector is configured to write messages from the *flagged-transactions* topic into the DynamoDB table created earlier. It requires to specify the table name, AWS region, operation, write capacity and whether to use the [default credential provider](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) - see the [documentation](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) for details. See [this post](/blog/2023-07-03-kafka-connect-for-aws-part-3) for details about how to set up the sink connector.

```terraform
# infra/msk-connect.tf
resource "aws_mskconnect_connector" "camel_ddb_sink" {
  name = "${local.name}-transactions-sink"

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
    "tasks.max"                      = "2",
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable"   = false,
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable" = false,
    # camel ddb sink configuration
    "topics"                                                   = local.kda.producer_0.topic_name,
    "camel.kamelet.aws-ddb-sink.table"                         = aws_dynamodb_table.transactions_table.id,
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
  key    = "plugins/${local.msk_connect.package_name}"
  source = "${dirname(path.cwd)}/connectors/${local.msk_connect.package_name}"

  etag = filemd5("${dirname(path.cwd)}/connectors/${local.msk_connect.package_name}")
}

resource "aws_cloudwatch_log_group" "camel_ddb_sink" {
  name = "/msk/connect/camel-ddb-sink"

  retention_in_days = 1

  tags = local.tags
}
```

The sink connector can be checked on AWS Console as shown below. 

![](sink-connector.png#center)

## Run Application

We first need to create records in the source Kafka topics. It is performed by executing the data generator app (*producer.py*). See [part 1](/blog/2023-08-10-fraud-detection-part-1) for details about the generator app and how to execute it. Note that we should connect to the VPN server in order to create records from the developer machine.

Once executed, we can check the source topics are created and messages are ingested.

![](source-topics.png#center)

### Monitoring on Flink Web UI

We can run the Flink application on AWS console with the *Run without snapshot* option as we haven't enabled [snapshots](https://docs.aws.amazon.com/managed-flink/latest/java/how-fault-snapshot.html).

![](flink-run.png#center)

Once the app is running, we can monitor it on the Flink Web UI available on AWS Console. 

![](flink-dashboard-00.png#center)

In the Overview section, it shows the available task slots, running jobs and completed jobs.

![](flink-dashboard-01.png#center)

We can inspect an individual job in the Jobs menu. It shows key details about a job execution in *Overview*, *Exceptions*, *TimeLine*, *Checkpoints* and *Configuration* tabs.

![](flink-dashboard-02.png#center)

### CloudWatch Logging

The application log messages can be checked in the CloudWatch Console, and it gives additional capability to debug the application.

![](flink-logging.png#center)

### Application Output

We can see details of all the topics in *Kpow*. The output topic (*flagged-transactions*) is created by the Flink application, and fraudulent transaction records are created in it.

![](all-topics.png#center)

Finally, we can check the output records on the DynamoDB table items view. All account IDs end with odd numbers, and it indicates they are from flagged accounts.

![](ddb-output.png#center)

## Summary

This series aims to help those who are new to Apache Flink and Amazon Managed Service for Apache Flink by re-implementing a simple fraud detection application that is discussed in an AWS workshop titled AWS Kafka and DynamoDB for real time fraud detection. In part 1, I demonstrated how to develop the application locally, and the app was deployed via Amazon Managed Service for Apache Flink in this post.