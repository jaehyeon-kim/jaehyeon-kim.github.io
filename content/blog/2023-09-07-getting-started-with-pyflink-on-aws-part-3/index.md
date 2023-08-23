---
title: Getting Started with Pyflink on AWS - Part 3 KDA and MSK
date: 2023-09-07
draft: true
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Getting Started with Pyflink on AWS
categories:
  - Data Engineering
tags:
  - Apache Flink
  - Apache Kafka
  - Amazon Kinesis Data Analytics
  - Amazon MSK
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: This series aims to extend a guide from AWS that demonstrates how to develop a Flink application locally and deploy via KDA. While the guide uses Kinesis Data Stream as the source, we use Apache Kafka on Amazon MSK instead. In this post, we will use a Kafka cluster on Amazon MSK for the source and destination (sink) of the Flink app. We have to build a custom Uber Jar as the cluster is authenticated by IAM and KDA does not allow you to specify multiple pipeline jar files. After that the same application execution examples will be repeated.
---

This series aims to extend a [guide from AWS](https://github.com/aws-samples/pyflink-getting-started) that demonstrates how to develop a Flink application locally and deploy via KDA. While the guide uses Kinesis Data Stream as the source, we use Apache Kafka on Amazon MSK instead.

In part 1, we discussed how to develop a Flink app locally, which connects a local Kafka cluster. The app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring.

In this post, we will use a Kafka cluster on Amazon MSK for the source and destination (sink) of the Flink app. We have to build a custom Uber Jar as the cluster is authenticated by IAM and KDA does not allow you to specify multiple pipeline jar files. After that the same application execution examples will be repeated.

* [Part 1 Local Flink and Local Kafka](/blog/2023-08-17-getting-started-with-pyflink-on-aws-part-1)
* [Part 2 Local Flink and MSK](#) (this post)
* Part 3 KDA and MSK

## Architecture

The Python source data generator (*producer.py*) sends random stock price records into a Kafka topic. The messages in the source topic are consumed by a Flink application, and it just writes those messages into a different sink topic. This is the simplest application of the AWS guide, and you may try [other examples](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) if interested.

![](featured.png#center)

## Infrastructure

A Kafka cluster is created on Amazon MSK using Terraform, and the cluster is secured by IAM access control. Similar to part 1, the Python apps including the Flink app run in a virtual environment in the first trial. After that the Flink app is submitted to a local Flink cluster for improved monitoring. As with part 1, the Flink cluster is created using Docker. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/pyflink-getting-started-on-aws/remote) of this post.

### Preparation

#### Application Package

```bash
# build.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
SRC_PATH=$SCRIPT_DIR/package

# remove contents under $SRC_PATH (except for uber-jar-for-pyflink) and kda-package.zip file
shopt -s extglob
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

## Package pyflink app
echo "package pyflink app"
zip -r kda-package.zip processor.py package/lib package/site_packages
```

Once downloaded, the Uber Jar file and python package can be found in the *lib* and *site_packages* folders respectively as shown below.

![](package-contents.png#center)

#### Kafka Management App

The [Kpow CE](https://docs.kpow.io/ce/) is used for ease of monitoring Kafka topics and related resources. The bootstrap server address, security configuration for IAM authentication and AWS credentials are added as environment variables. See [this post](/blog/2023-05-18-kafka-development-with-docker-part-2/) for details about Kafka management apps.

```yaml
# compose-ui.yml
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
      # kafka cluster
      BOOTSTRAP: $BOOTSTRAP_SERVERS
      SECURITY_PROTOCOL: SASL_SSL
      SASL_MECHANISM: AWS_MSK_IAM
      SASL_CLIENT_CALLBACK_HANDLER_CLASS: software.amazon.msk.auth.iam.IAMClientCallbackHandler
      SASL_JAAS_CONFIG: software.amazon.msk.auth.iam.IAMLoginModule required;

networks:
  appnet:
    name: app-network
```

### VPC and VPN

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (*remote/vpc.tf*). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (*remote/vpn.tf*). It is particularly useful to monitor and manage the MSK cluster and Kafka topic locally. The details about how to configure the VPN server can be found in an [earlier post](/blog/2022-02-06-dev-infra-terraform).

### MSK Cluster

An MSK cluster with 2 brokers is created. The broker nodes are deployed with the *kafka.m5.large* instance type in private subnets and IAM authentication is used for the client authentication method. Finally, additional server configurations are added such as enabling auto creation of topics and topic deletion.

```terraform
# infra/variable.tf
locals {
  ...
  msk = {
    version                    = "2.8.1"
    instance_size              = "kafka.m5.large"
    ebs_volume_size            = 20
    log_retention_ms           = 604800000 # 7 days
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
    unauthenticated = true
    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
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

resource "aws_security_group" "msk" {
  name   = "${local.name}-msk-sg"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

...

resource "aws_security_group_rule" "msk_kda_inbound" {
  count                    = local.kda.to_create ? 1 : 0
  type                     = "ingress"
  description              = "Allow KDA access"
  security_group_id        = aws_security_group.msk.id
  protocol                 = "tcp"
  from_port                = 9098
  to_port                  = 9098
  source_security_group_id = aws_security_group.kda_sg[0].id
}
```

### KDA Application

```terraform
# infra/variable.tf
locals {
  ...
  kda = {
    to_create    = true
    runtime_env  = "FLINK-1_15"
    package_name = "kda-package.zip"
  }
  ...
}

resource "aws_kinesisanalyticsv2_application" "kda_app" {
  count = local.kda.to_create ? 1 : 0

  name                   = "${local.name}-kda-app"
  runtime_environment    = local.kda.runtime_env # FLINK-1_15
  service_execution_role = aws_iam_role.kda_app_role[0].arn

  ...
}
```

#### Application Configuration

##### Application Code Configuration

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
  count = local.kda.to_create ? 1 : 0

  bucket = aws_s3_bucket.default_bucket.id
  key    = "package/${local.kda.package_name}"
  source = "${dirname(path.cwd)}/${local.kda.package_name}"

  etag = filemd5("${dirname(path.cwd)}/${local.kda.package_name}")
}
```

##### VPC Configuration

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  application_configuration {
    
    ...

    vpc_configuration {
      security_group_ids = [aws_security_group.kda_sg[0].id]
      subnet_ids         = module.vpc.private_subnets
    }

    ...
  
  }

  ...

}

...

resource "aws_security_group" "kda_sg" {
  count = local.kda.to_create ? 1 : 0

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
          "table.name"        = "source_table"
          "topic.name"        = "stocks-in"
          "bootstrap.servers" = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam
          "startup.mode"      = "earliest-offset"
        }
      }

      property_group {
        property_group_id = "producer.config.0"

        property_map = {
          "table.name"        = "sink_table"
          "topic.name"        = "stocks-out"
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

```terraform
# infra/kda.tf
resource "aws_kinesisanalyticsv2_application" "kda_app" {
  
  ...

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.kda_ls[0].arn
  }

  ...

}

...

resource "aws_cloudwatch_log_group" "kda_lg" {
  count = local.kda.to_create ? 1 : 0

  name = "/${local.name}-kda-log-group"
}

resource "aws_cloudwatch_log_stream" "kda_ls" {
  count = local.kda.to_create ? 1 : 0

  name = "/${local.name}-kda-log-stream"

  log_group_name = aws_cloudwatch_log_group.kda_lg[0].name
}
```

#### IAM Role

```terraform
# infra/kda.tf
resource "aws_iam_role" "kda_app_role" {
  count = local.kda.to_create ? 1 : 0

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

![](kda-app.png#center)

## Run Application

source generation locally

![](source-topic.png#center)

run kda app with *Run without snapshot* option

![](kda-run.png#center)

flink dashboard

![](cluster-dashboard-00.png#center)

![](cluster-dashboard-01.png#center)

![](cluster-dashboard-02.png#center)

logging

![](kda-logging.png#center)

all topics

![](kda-logging.png#center)

## Summary

In this post, we used a Kafka cluster on Amazon MSK for the source and destination (sink) of the Flink app. We have to build a custom Uber Jar as the cluster is authenticated by IAM and KDA does not allow you to specify multiple pipeline jar files. After that the app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring.