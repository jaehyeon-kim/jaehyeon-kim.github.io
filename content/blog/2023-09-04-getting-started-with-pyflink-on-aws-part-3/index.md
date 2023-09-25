---
title: Getting Started with Pyflink on AWS - Part 3 AWS Managed Flink and MSK
date: 2023-09-04
draft: false
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
  - Apache Flink
tags:
  - Apache Flink
  - Pyflink
  - Apache Kafka
  - Amazon Managed Service for Apache Flink
  - Amazon MSK
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: In this series of posts, we discuss a Flink (Pyflink) application that reads/writes from/to Kafka topics. In the previous posts, I demonstrated a Pyflink app that targets a local Kafka cluster as well as a Kafka cluster on Amazon MSK. The app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring. In this post, the app will be deployed via Amazon Managed Service for Apache Flink.
---

In this series of posts, we discuss a Flink (Pyflink) application that reads/writes from/to Kafka topics. In the previous posts, I demonstrated a Pyflink app that targets a local Kafka cluster as well as a Kafka cluster on Amazon MSK. The app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring. In this post, the app will be deployed via [Amazon Managed Service for Apache Flink](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-managed-service-apache-flink/), which is the easiest option to run Flink applications on AWS.

* [Part 1 Local Flink and Local Kafka](/blog/2023-08-17-getting-started-with-pyflink-on-aws-part-1)
* [Part 2 Local Flink and MSK](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2)
* [Part 3 AWS Managed Flink and MSK](#) (this post)

[**Update 2023-08-30**] Amazon Kinesis Data Analytics is renamed into [Amazon Managed Service for Apache Flink](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-managed-service-apache-flink/). In this post, Kinesis Data Analytics (KDA) and Amazon Managed Service for Apache Flink will be used interchangeably.

## Architecture

The Python source data generator sends random stock price records into a Kafka topic. The messages in the source topic are consumed by a Flink application, and it just writes those messages into a different sink topic. As the Kafka cluster is deployed in private subnets, a VPN server is used to generate records from the developer machine. This is the simplest application of the [Pyflink getting started guide](https://github.com/aws-samples/pyflink-getting-started) from AWS, and you may try [other examples](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) if interested.

![](featured.png#center)

## Infrastructure

A Kafka cluster is created on Amazon MSK using Terraform, and the cluster is secured by IAM access control. Unlike the previous posts, the Pyflink app is deployed via *Kinesis Data Analytics (KDA)*. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/pyflink-getting-started-on-aws/remote) of this post.

### Preparation

#### Application Package

As discussed in [part 2](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2), the app has multiple jar dependencies, and they have to be combined into a single Uber jar file. This is because KDA does not allow you to specify multiple pipeline jar files. The details about how to create the custom jar file can be found in [part 2](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2).

The following script (*build.sh*) builds to create the Uber Jar file for this post, followed by downloading the *kafka-python* package and creating a zip file that can be used to deploy the Flink app via KDA. Although the Flink app does not need the *kafka-python* package, it is added in order to check if `--pyFiles` option works when deploying the app via KDA. The zip package file will be used for KDA deployment in this post.

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

Once completed, we can check the following contents are included in the application package file.
- Flink application - *processor.py*
- Pipeline jar file - *package/lib/pyflink-getting-started-1.0.0.jar*
- kafka-python package - *package/site_packages/kafka*

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

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (*infra/vpc.tf*). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (*infra/vpn.tf*). It is particularly useful to monitor and manage the MSK cluster and Kafka topic locally. The details about how to configure the VPN server can be found in an [earlier post](/blog/2022-02-06-dev-infra-terraform).

### MSK Cluster

A MSK cluster with 2 brokers is created. The broker nodes are deployed with the *kafka.m5.large* instance type in private subnets and IAM authentication is used for the client authentication method. Finally, additional server configurations are added such as enabling auto creation of topics and topic deletion. Note that the Flink application needs to have access to the Kafka brokers, and it is allowed by adding an inbound connection from the KDA app into the brokers on port 9098.

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

The runtime environment and service execution role are required to create a Flink app. The latest supported Flink version (1.15.2) is specified for the former and an IAM role is created for the latter - it'll be discussed more in a later section. Furthermore, we need to specify more configurations that are related to the Flink application and CloudWatch logging, and they will be covered below in detail as well.

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
  count = local.kda.to_create ? 1 : 0

  bucket = aws_s3_bucket.default_bucket.id
  key    = "package/${local.kda.package_name}"
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

The Flink application configurations constitute of the following.

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

The service execution role has the following permissions.

* Full access to CloudWatch, CloudWatch Log and Amazon Kinesis Data Analytics. It is given by AWS managed policies for logging, metrics generation etc. However, it is by no means recommended and should be updated according to the least privilege principle for production.
* 3 inline policies for connecting to the MSK cluster (*kda-msk-access*) in private subnets (*kda-vpc-access*) as well as giving access to the application package in S3 (*kda-s3-access*).

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

Once deployed, we can see the application on AWS console, and it stays in the ready status.

![](kda-app.png#center)

## Run Application

We first need to create records in the source Kafka topic. It is done by executing the data generator app (*producer.py*). See [part 2](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2) for details about the generator app and how to execute it. Note that we should connect to the VPN server in order to create records from the developer machine.

Once executed, we can check the source topic is created and messages are ingested.

![](source-topic.png#center)

### Monitoring on Flink Web UI

We can run the Flink application on AWS console with the *Run without snapshot* option as we haven't enabled [snapshots](https://docs.aws.amazon.com/managed-flink/latest/java/how-fault-snapshot.html).

![](kda-run.png#center)

Once the app is running, we can monitor it on the Flink Web UI available on AWS Console. 

![](cluster-dashboard-00.png#center)

In the Overview section, it shows the available task slots, running jobs and completed jobs.

![](cluster-dashboard-01.png#center)

We can inspect an individual job in the Jobs menu. It shows key details about a job execution in *Overview*, *Exceptions*, *TimeLine*, *Checkpoints* and *Configuration* tabs.

![](cluster-dashboard-02.png#center)

### CloudWatch Logging

The application log messages can be checked in the CloudWatch Console, and it gives additional capability to debug the application.

![](kda-logging.png#center)

### Application Output

We can see details of all the topics in *Kpow*. The total number of messages matches between the source and output topics but not within partitions.

![](all-topics.png#center)

## Summary

In this series of posts, we discussed a Flink (Pyflink) application that reads/writes from/to Kafka topics. In the previous posts, I demonstrated a Pyflink app that targets a local Kafka cluster as well as a Kafka cluster on Amazon MSK. The app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring. In this post, the app was deployed via Amazon Managed Service for Apache Flink, which is the easiest option to run Flink applications on AWS.