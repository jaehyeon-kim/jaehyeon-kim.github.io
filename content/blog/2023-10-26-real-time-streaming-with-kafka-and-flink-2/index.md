---
title: Real Time Streaming with Kafka and Flink - Lab 1 Produce data to Kafka using Lambda
date: 2023-10-26
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
  - AWS Lambda
  - Amazon EventBridge
  - Amazon MSK
  - Apache Kafka
  - Python
  - Kpow
authors:
  - JaehyeonKim
images: []
cevo: 34
docs: https://docs.google.com/document/d/1noUCJwNq9LCQRbW58axYjpn8L8ICSseLizVS-744WoE
description: In this lab, we will create a Kafka producer application using AWS Lambda, which sends fake taxi ride data into a Kafka topic on Amazon MSK. A configurable number of the producer Lambda function will be invoked by an Amazon EventBridge schedule rule. In this way we are able to generate test data concurrently based on the desired volume of messages. 
---

In this lab, we will create a Kafka producer application using [AWS Lambda](https://aws.amazon.com/lambda/), which sends fake taxi ride data into a Kafka topic on [Amazon MSK](https://aws.amazon.com/msk/). A configurable number of the producer Lambda function will be invoked by an [Amazon EventBridge](https://aws.amazon.com/eventbridge/) schedule rule. In this way we are able to generate test data concurrently based on the desired volume of messages. 

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](#) (this post)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](/blog/2023-11-16-real-time-streaming-with-kafka-and-flink-4)
* [Lab 4 Clean, Aggregate, and Enrich Events with Flink](/blog/2023-11-23-real-time-streaming-with-kafka-and-flink-5)
* [Lab 5 Write data to DynamoDB using Kafka Connect](/blog/2023-11-30-real-time-streaming-with-kafka-and-flink-6)
* [Lab 6 Consume data from Kafka using Lambda](/blog/2023-12-14-real-time-streaming-with-kafka-and-flink-7)

[**Update 2023-11-06**] Initially I planned to deploy Pyflink applications on [Amazon Managed Service for Apache Flink](https://aws.amazon.com/managed-service-apache-flink/), but I changed the plan to use a local Flink cluster deployed on Docker. The main reasons are

1. It is not clear how to configure a Pyflink application for the managed service. For example, Apache Flink supports [pluggable file systems](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/deployment/filesystems/overview/) and the required dependency (eg *flink-s3-fs-hadoop-1.15.2.jar*) should be placed under the *plugins* folder. However, the sample Pyflink applications from [pyflink-getting-started](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) and [amazon-kinesis-data-analytics-blueprints](https://github.com/aws-samples/amazon-kinesis-data-analytics-blueprints/tree/main/apps/python-table-api/msk-serverless-to-s3-tableapi-python) either ignore the S3 jar file for deployment or package it together with other dependencies - *none of them uses the S3 jar file as a plugin*. I tried multiple different configurations, but all ended up with having an error whose code is *CodeError.InvalidApplicationCode*. I don't have such an issue when I deploy the app on a local Flink cluster and I haven't found a way to configure the app for the managed service as yet.
2. The Pyflink app for *Lab 4* requires the OpenSearch sink connector and the connector is available on *1.16.0+*. However, the latest Flink version of the managed service is still *1.15.2* and the sink connector is not available on it. Normally the latest version of the managed service is behind two minor versions of the official release, but it seems to take a little longer to catch up at the moment - the version 1.18.0 was released a while ago.

## Architecture

Fake taxi ride data is generated by multiple Kafka Lambda producer functions that are invoked by an EventBridge schedule rule. The schedule is set to run _every minute_ and the associating rule has a configurable number (e.g. 5) of targets. Each target points to the same Lambda function. In this way we are able to generate test data using multiple Lambda functions based on the desired volume of messages. 

![](featured.png#center)

## Infrastructure

The infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post.

### VPC and VPN

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (*infra/vpc.tf*). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (*infra/vpn.tf*). The details about how to configure the VPN server can be found in [this post](/blog/2022-02-06-dev-infra-terraform).

### MSK Cluster

An MSK cluster with 2 brokers is created. The broker nodes are deployed with the *kafka.m5.large* instance type in private subnets and IAM authentication is used for the client authentication method. Finally, additional server configurations are added such as enabling topic auto-creation/deletion, (default) number of partitions and default replication factor.

```terraform
# infra/variables.tf
locals {
  ...
  msk = {
    version                    = "2.8.1"
    instance_size              = "kafka.m5.large"
    ebs_volume_size            = 20
    log_retention_ms           = 604800000 # 7 days
    number_of_broker_nodes     = 2
    num_partitions             = 5
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

The security group of the MSK cluster allows all inbound traffic from itself and all outbound traffic into all IP addresses. These are necessary for Kafka connectors on MSK Connect that we will develop in later posts. Note that both the rules are too generous, however, we can limit the protocol and port ranges in production. Also, the security group has additional inbound rules that can be accessed on port 9098 from the security groups of the VPN server and Lambda producer function.

```terraform
# infra/msk.tf
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
  from_port                = 9092
  to_port                  = 9098
  source_security_group_id = aws_security_group.vpn[0].id
}

resource "aws_security_group_rule" "msk_kafka_producer_inbound" {
  count                    = local.producer.to_create ? 1 : 0
  type                     = "ingress"
  description              = "lambda kafka producer access"
  security_group_id        = aws_security_group.msk.id
  protocol                 = "tcp"
  from_port                = 9098
  to_port                  = 9098
  source_security_group_id = aws_security_group.kafka_producer[0].id
}
```

### Lambda Function

The Kafka producer Lambda function is deployed conditionally by a flag variable called *producer_to_create*. Once it is set to *true*, the function is created by the [AWS Lambda Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest) while referring to the associating configuration variables (_local.producer.*_).

```terraform
# infra/variables.tf
variable "producer_to_create" {
  description = "Flag to indicate whether to create Lambda Kafka producer"
  type        = bool
  default     = false
}

...

locals {
  ...
  producer = {
    to_create     = var.producer_to_create
    src_path      = "../producer"
    function_name = "kafka_producer"
    handler       = "app.lambda_function"
    concurrency   = 5
    timeout       = 90
    memory_size   = 128
    runtime       = "python3.8"
    schedule_rate = "rate(1 minute)"
    environment = {
      topic_name  = "taxi-rides"
      max_run_sec = 60
    }
  }
  ...
}

# infra/producer.tf
module "kafka_producer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = ">=5.1.0, <6.0.0"

  create = local.producer.to_create

  function_name          = local.producer.function_name
  handler                = local.producer.handler
  runtime                = local.producer.runtime
  timeout                = local.producer.timeout
  memory_size            = local.producer.memory_size
  source_path            = local.producer.src_path
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = local.producer.to_create ? [aws_security_group.kafka_producer[0].id] : null
  attach_network_policy  = true
  attach_policies        = true
  policies               = local.producer.to_create ? [aws_iam_policy.kafka_producer[0].arn] : null
  number_of_policies     = 1
  environment_variables = {
    BOOTSTRAP_SERVERS = aws_msk_cluster.msk_data_cluster.bootstrap_brokers_sasl_iam
    TOPIC_NAME        = local.producer.environment.topic_name
    MAX_RUN_SEC       = local.producer.environment.max_run_sec
  }

  depends_on = [
    aws_msk_cluster.msk_data_cluster
  ]

  tags = local.tags
}

resource "aws_lambda_function_event_invoke_config" "kafka_producer" {
  count = local.producer.to_create ? 1 : 0

  function_name          = module.kafka_producer.lambda_function_name
  maximum_retry_attempts = 0
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = local.producer.to_create ? 1 : 0
  statement_id  = "InvokeLambdaFunction"
  action        = "lambda:InvokeFunction"
  function_name = local.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge.eventbridge_rule_arns["crons"]

  depends_on = [
    module.eventbridge
  ]
}
```

#### IAM Permission

The producer Lambda function needs permission to send messages to the Kafka topic. The following IAM policy is added to the Lambda function as illustrated in this [AWS documentation](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html). 

```terraform
# infra/producer.tf
resource "aws_iam_policy" "kafka_producer" {
  count = local.producer.to_create ? 1 : 0
  name  = "${local.producer.function_name}-msk-lambda-permission"

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
```

#### Lambda Security Group

We also need to add an outbound rule to the Lambda function's security group so that it can access the MSK cluster.

```terraform
# infra/producer.tf
resource "aws_security_group" "kafka_producer" {
  count = local.producer.to_create ? 1 : 0

  name   = "${local.name}-lambda-sg"
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

#### Function Source

The _TaxiRide_ class generates one or more taxi ride records by the _create _ method where random records are populated by the *random* module. The Lambda function sends 100 records at a time followed by sleeping for 1 second. It repeats until it reaches MAX_RUN_SEC (e.g. 60) environment variable value. A Kafka message is made up of an ID as the key and a taxi ride record as the value. Both the key and value are serialised as JSON. Note that the stable version of the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package does not support the IAM authentication method. Therefore, we need to install the package from a forked repository as discussed in this [GitHub issue](https://github.com/dpkp/kafka-python/pull/2255).

```python
# producer/app.py
import os
import datetime
import random
import json
import re
import time
import typing
import dataclasses

from kafka import KafkaProducer


@dataclasses.dataclass
class TaxiRide:
    id: str
    vendor_id: int
    pickup_date: str
    dropoff_date: str
    passenger_count: int
    pickup_longitude: str
    pickup_latitude: str
    dropoff_longitude: str
    dropoff_latitude: str
    store_and_fwd_flag: str
    gc_distance: int
    trip_duration: int
    google_distance: int
    google_duration: int

    def asdict(self):
        return dataclasses.asdict(self)

    @classmethod
    def auto(cls):
        pickup_lon, pickup_lat = tuple(TaxiRide.get_latlon().split(","))
        dropoff_lon, dropoff_lat = tuple(TaxiRide.get_latlon().split(","))
        distance, duration = random.randint(1, 7), random.randint(8, 10000)
        return cls(
            id=f"id{random.randint(1665586, 8888888)}",
            vendor_id=random.randint(1, 5),
            pickup_date=datetime.datetime.now().isoformat(timespec="milliseconds"),
            dropoff_date=(
                datetime.datetime.now() + datetime.timedelta(minutes=random.randint(30, 100))
            ).isoformat(timespec="milliseconds"),
            passenger_count=random.randint(1, 9),
            pickup_longitude=pickup_lon,
            pickup_latitude=pickup_lat,
            dropoff_longitude=dropoff_lon,
            dropoff_latitude=dropoff_lat,
            store_and_fwd_flag=["Y", "N"][random.randint(0, 1)],
            gc_distance=distance,
            trip_duration=duration,
            google_distance=distance,
            google_duration=duration,
        )

    @staticmethod
    def create(num: int):
        return [TaxiRide.auto() for _ in range(num)]

    # fmt: off
    @staticmethod
    def get_latlon():
        location_list = [
            "-73.98174286,40.71915817", "-73.98508453,40.74716568", "-73.97333527,40.76407242", "-73.99310303,40.75263214",
            "-73.98229218,40.75133133", "-73.96527863,40.80104065", "-73.97010803,40.75979996", "-73.99373627,40.74176025",
            "-73.98544312,40.73571014", "-73.97686005,40.68337631", "-73.9697876,40.75758362", "-73.99397278,40.74086761",
            "-74.00531769,40.72866058", "-73.99013519,40.74885178", "-73.9595108,40.76280975", "-73.99025726,40.73703384",
            "-73.99495697,40.745121", "-73.93579865,40.70730972", "-73.99046326,40.75100708", "-73.9536438,40.77526093",
            "-73.98226166,40.75159073", "-73.98831177,40.72318649", "-73.97222137,40.67683029", "-73.98626709,40.73276901",
            "-73.97852325,40.78910065", "-73.97612,40.74908066", "-73.98240662,40.73148727", "-73.98776245,40.75037384",
            "-73.97187042,40.75840378", "-73.87303925,40.77410507", "-73.9921875,40.73451996", "-73.98435974,40.74898529",
            "-73.98092651,40.74196243", "-74.00701904,40.72573853", "-74.00798798,40.74022675", "-73.99419403,40.74555969",
            "-73.97737885,40.75883865", "-73.97051239,40.79664993", "-73.97693634,40.7599144", "-73.99306488,40.73812866",
            "-74.00775146,40.74528885", "-73.98532867,40.74198914", "-73.99037933,40.76152802", "-73.98442078,40.74978638",
            "-73.99173737,40.75437927", "-73.96742249,40.78820801", "-73.97813416,40.72935867", "-73.97171021,40.75943375",
            "-74.00737,40.7431221", "-73.99498749,40.75517654", "-73.91600037,40.74634933", "-73.99924469,40.72764587",
            "-73.98488617,40.73621368", "-73.98627472,40.74737167",
        ]
        return location_list[random.randint(0, len(location_list) - 1)]


# fmt: on
class Producer:
    def __init__(self, bootstrap_servers: list, topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.producer = self.create()

    def create(self):
        kwargs = {
            "bootstrap_servers": self.bootstrap_servers,
            "value_serializer": lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            "key_serializer": lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            "api_version": (2, 8, 1),
        }
        if re.search("9098$", next(iter(self.bootstrap_servers))):
            kwargs = {
                **kwargs,
                **{
                    "security_protocol": "SASL_SSL",
                    "sasl_mechanism": "AWS_MSK_IAM",
                },
            }
        return KafkaProducer(**kwargs)

    def send(self, items: typing.List[TaxiRide]):
        for item in items:
            self.producer.send(self.topic, key={"id": item.id}, value=item.asdict())
        self.producer.flush()

    def serialize(self, obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        if isinstance(obj, datetime.date):
            return str(obj)
        return obj


def lambda_function(event, context):
    producer = Producer(
        bootstrap_servers=os.environ["BOOTSTRAP_SERVERS"].split(","), topic=os.environ["TOPIC_NAME"]
    )
    s = datetime.datetime.now()
    total_records = 0
    while True:
        items = TaxiRide.create(10)
        producer.send(items)
        total_records += len(items)
        print(f"sent {len(items)} messages")
        elapsed_sec = (datetime.datetime.now() - s).seconds
        if elapsed_sec > int(os.environ["MAX_RUN_SEC"]):
            print(f"{total_records} records are sent in {elapsed_sec} seconds ...")
            break
        time.sleep(1)
```

A sample taxi ride record is shown below.

```json
{
	"id": "id3464573",
	"vendor_id": 5,
	"pickup_date": "2023-10-13T01:59:05.422",
	"dropoff_date": "2023-10-13T02:52:05.422",
	"passenger_count": 9,
	"pickup_longitude": "-73.97813416",
	"pickup_latitude": "40.72935867",
	"dropoff_longitude": "-73.91600037",
	"dropoff_latitude": "40.74634933",
	"store_and_fwd_flag": "Y",
	"gc_distance": 3,
	"trip_duration": 4731,
	"google_distance": 3,
	"google_duration": 4731
}
```

### EventBridge Rule

The [AWS EventBridge Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/eventbridge/aws/latest) is used to create the EventBridge schedule rule and targets. Note that the rule named *crons* has a configurable number of targets (eg 5) and each target points to the same Lambda producer function. Therefore, we are able to generate test data using multiple Lambda functions based on the desired volume of messages.

```terraform
# infra/producer.tf
module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = ">=2.3.0, <3.0.0"

  create     = local.producer.to_create
  create_bus = false

  rules = {
    crons = {
      description         = "Kafka producer lambda schedule"
      schedule_expression = local.producer.schedule_rate
    }
  }

  targets = {
    crons = [for i in range(local.producer.concurrency) : {
      name = "lambda-target-${i}"
      arn  = module.kafka_producer.lambda_function_arn
    }]
  }

  depends_on = [
    module.kafka_producer
  ]

  tags = local.tags
}
```

## Deployment

The application can be deployed (as well as destroyed) using Terraform CLI as shown below. As the default value of *producer_to_create* is false, we need to set it to *true* in order to create the Lambda producer function.

```bash
# initialize
terraform init
# create an execution plan
terraform plan -var 'producer_to_create=true'
# execute the actions proposed in a Terraform plan
terraform apply -auto-approve=true -var 'producer_to_create=true'

# destroy all remote objects
# terraform destroy -auto-approve=true -var 'producer_to_create=true'
```

Once deployed, we can see that the schedule rule has 5 targets of the same Lambda function among others.

![](cron-rule.png#center)

### Monitor Topic

A Kafka management app can be a good companion for development as it helps monitor and manage resources on an easy-to-use user interface. We'll use [Kpow Community Edition](https://docs.kpow.io/ce/) in this post, which allows you to link a single Kafka cluster, Kafka connect server and schema registry. Note that the community edition is valid for 12 months and the licence can be requested on this [page](https://kpow.io/get-started/#individual). Once requested, the licence details will be emailed, and they can be added as an environment file (*env_file*).

The app needs additional configurations in environment variables because the Kafka cluster on Amazon MSK is authenticated by IAM - see [this page](https://docs.kpow.io/config/msk/) for details. The bootstrap server address can be found on AWS Console or executing the following Terraform command. 

```bash
$ terraform output -json | jq -r '.msk_bootstrap_brokers_sasl_iam.value'
```

Note that we need to specify the compose file name when starting it because the file name (*compose-ui.yml*) is different from the default file name (*docker-compose.yml*). We can run it by `docker-compose -f compose-ui.yml up -d` and access on a browser via *localhost:3000*.

```yaml
# compose-ui.yml
version: "3"

services:
  kpow:
    image: factorhouse/kpow-ce:91.5.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      BOOTSTRAP: $BOOTSTRAP_SERVERS
      SECURITY_PROTOCOL: SASL_SSL
      SASL_MECHANISM: AWS_MSK_IAM
      SASL_JAAS_CONFIG: software.amazon.msk.auth.iam.IAMLoginModule required;
      SASL_CLIENT_CALLBACK_HANDLER_CLASS: software.amazon.msk.auth.iam.IAMClientCallbackHandler
    env_file: # https://kpow.io/get-started/#individual
      - ./kpow.env

networks:
  kafkanet:
    name: kafka-network
```

We can see the topic (*taxi-rides*) is created, and it has 5 partitions, which is the default number of partitions.

![](kafka-topic.png#center)

Also, we can inspect topic messages in the *Data* tab as shown below.

![](topic-message.png#center)

## Summary

In this lab, we created a Kafka producer application using AWS Lambda, which sends fake taxi ride data into a Kafka topic on Amazon MSK. It was developed so that a configurable number of the producer Lambda function can be invoked by an Amazon EventBridge schedule rule. In this way, we are able to generate test data concurrently based on the desired volume of messages. 