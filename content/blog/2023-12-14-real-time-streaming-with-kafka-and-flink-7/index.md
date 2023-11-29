---
title: Real Time Streaming with Kafka and Flink - Lab 6 Consume data from Kafka using Lambda
date: 2023-12-14
draft: true
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
  - AWS Lambda
  - Apache Kafka
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
description: Amazon MSK can be configured as an event source of a Lambda function. Lambda internally polls for new messages from the event source and then synchronously invokes the target Lambda function. With this feature, we can develop a Kafka consumer application in serverless environment where developers can focus on application logic. In this lab, we will discuss how to create a Kafka consumer using a Lambda function.
---

Amazon MSK can be configured as an [event source](https://docs.aws.amazon.com/lambda/latest/dg/with-msk.html) of a Lambda function. Lambda internally polls for new messages from the event source and then synchronously invokes the target Lambda function. With this feature, we can develop a Kafka consumer application in serverless environment where developers can focus on application logic. In this lab, we will discuss how to create a Kafka consumer using a Lambda function.

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](/blog/2023-11-16-real-time-streaming-with-kafka-and-flink-4)
* [Lab 4 Clean, Aggregate, and Enrich Events with Flink](/blog/2023-11-23-real-time-streaming-with-kafka-and-flink-5)
* [Lab 5 Write data to DynamoDB using Kafka Connect](/blog/2023-11-30-real-time-streaming-with-kafka-and-flink-6)
* [Lab 6 Consume data from Kafka using Lambda](#) (this post)

## Architecture

Fake taxi ride data is sent to a Kafka topic by the Kafka producer application that is discussed in [Lab 1](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2). The messages of the *taxi-rides* topic are consumed by a Lambda function where the MSK cluster is configured as an event source of the function.

![](featured.png#center)

## Infrastructure

The AWS infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post. See this [earlier post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details about how to create the resources. The key resources cover a VPC, VPN server, MSK cluster and Python Lambda producer app.

### Lambda Kafka Consumer

The Kafka consumer Lambda function is created additionally for this lab, and it is deployed conditionally by a flag variable called *consumer_to_create*. Once it is set to *true*, the function is created by the [AWS Lambda Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest) while referring to the associating configuration variables (_local.consumer.*_). Note that an event source mapping is created on the Lambda function where the event source is set to the Kafka cluster on Amazon MSK. We can also control which topics to poll by adding one or more topic names in the *topics* attribute - only a single topic named *taxi-rides* is specified for this lab. 

```terraform
# infra/variables.tf
variable "consumer_to_create" {
  description = "Flag to indicate whether to create Kafka consumer"
  type        = bool
  default     = false
}

...

locals {
  ...
  consumer = {
    to_create         = var.consumer_to_create
    src_path          = "../consumer"
    function_name     = "kafka_consumer"
    handler           = "app.lambda_function"
    timeout           = 600
    memory_size       = 128
    runtime           = "python3.8"
    topic_name        = "taxi-rides"
    starting_position = "TRIM_HORIZON"
  }
  ...
}

# infra/consumer.tf
module "kafka_consumer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = ">=5.1.0, <6.0.0"

  create = local.consumer.to_create

  function_name          = local.consumer.function_name
  handler                = local.consumer.handler
  runtime                = local.consumer.runtime
  timeout                = local.consumer.timeout
  memory_size            = local.consumer.memory_size
  source_path            = local.consumer.src_path
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = local.consumer.to_create ? [aws_security_group.kafka_consumer[0].id] : null
  attach_network_policy  = true
  attach_policies        = true
  policies               = local.consumer.to_create ? [aws_iam_policy.kafka_consumer[0].arn] : null
  number_of_policies     = 1

  depends_on = [
    aws_msk_cluster.msk_data_cluster
  ]

  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "kafka_consumer" {
  count             = local.consumer.to_create ? 1 : 0
  event_source_arn  = aws_msk_cluster.msk_data_cluster.arn
  function_name     = module.kafka_consumer.lambda_function_name
  topics            = [local.consumer.topic_name]
  starting_position = local.consumer.starting_position
  amazon_managed_kafka_event_source_config {
    consumer_group_id = "${local.consumer.topic_name}-group-01"
  }
}

resource "aws_lambda_permission" "kafka_consumer" {
  count         = local.consumer.to_create ? 1 : 0
  statement_id  = "InvokeLambdaFunction"
  action        = "lambda:InvokeFunction"
  function_name = local.consumer.function_name
  principal     = "kafka.amazonaws.com"
  source_arn    = aws_msk_cluster.msk_data_cluster.arn
}
```

#### IAM Permission

The consumer Lambda function needs permission to read messages to the Kafka topic. The following IAM policy is added to the Lambda function as illustrated in this [AWS documentation](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html). 

```terraform
# infra/consumer.tf
resource "aws_iam_policy" "kafka_consumer" {
  count = local.consumer.to_create ? 1 : 0
  name  = "${local.consumer.function_name}-msk-lambda-permission"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PermissionOnKafkaCluster"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeClusterDynamicConfiguration"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.name}-msk-cluster/*",
          "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:topic/${local.name}-msk-cluster/*",
          "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}:group/${local.name}-msk-cluster/*"
        ]
      },
      {
        Sid = "PermissionOnKafka"
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid = "PermissionOnNetwork"
        Action = [
          # The first three actions also exist in netwrok policy attachment in lambda module
          # "ec2:CreateNetworkInterface",
          # "ec2:DescribeNetworkInterfaces",
          # "ec2:DeleteNetworkInterface",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
```

#### Function Source

The *records* attribute of the Lambda event payload includes Kafka consumer records. Each of the records contains details of the Amazon MSK topic and partition identifier, together with a timestamp and a base64-encoded message (key and value). The Lambda function simply prints those records after decoding the message key and value as well as formatting the timestamp into the ISO format.

```python
# consumer/app.py
import json
import base64
import datetime


class ConsumerRecord:
    def __init__(self, record: dict):
        self.topic = record["topic"]
        self.partition = record["partition"]
        self.offset = record["offset"]
        self.timestamp = record["timestamp"]
        self.timestamp_type = record["timestampType"]
        self.key = record["key"]
        self.value = record["value"]
        self.headers = record["headers"]

    def parse_record(
        self,
        to_str: bool = True,
        to_json: bool = True,
    ):
        rec = {
            **self.__dict__,
            **{
                "key": json.loads(base64.b64decode(self.key).decode()),
                "value": json.loads(base64.b64decode(self.value).decode()),
                "timestamp": ConsumerRecord.format_timestamp(self.timestamp, to_str),
            },
        }
        return json.dumps(rec, default=ConsumerRecord.serialize) if to_json else rec

    @staticmethod
    def format_timestamp(value, to_str: bool = True):
        ts = datetime.datetime.fromtimestamp(value / 1000)
        return ts.isoformat(timespec="milliseconds") if to_str else ts

    @staticmethod
    def serialize(obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        if isinstance(obj, datetime.date):
            return str(obj)
        return obj


def lambda_function(event, context):
    for _, records in event["records"].items():
        for record in records:
            cr = ConsumerRecord(record)
            print(cr.parse_record())
```

## Deployment

The infrastructure can be deployed (as well as destroyed) using Terraform CLI. Note that the Lambda consumer function is created only when the *consumer_to_create* variable is set to *true*.

```bash
# initialize
terraform init
# create an execution plan
terraform plan -var 'producer_to_create=true' -var 'consumer_to_create=true'
# execute the actions proposed in a Terraform plan
terraform apply -auto-approve=true -var 'producer_to_create=true' -var 'consumer_to_create=true'

# destroy all remote objects
# terraform destroy -auto-approve=true -var 'producer_to_create=true' -var 'consumer_to_create=true'
```

Once the resources are deployed, we can check the Lambda function on AWS Console. Note that the MSK cluster is configured as the Lambda trigger as expected.

![](lambda-trigger.png#center)


## Application Result

### Kafka Topic

We can see the topic (*taxi-rides*) is created, and the details of the topic can be found on the *Topics* menu on *localhost:3000*. Note that, if the Kafka monitoring app (*kpow*) is not started, we can run it using [*compose-ui.yml*](https://github.com/jaehyeon-kim/flink-demos/blob/master/real-time-streaming-aws/compose-ui.yml) - see [this post](/blog/http://localhost:1313/blog/2023-10-23-kafka-connect-for-aws-part-4) for details about *kpow* configuration.

![](kafka-topic.png#center)

### Consumer Output

We can check the outputs of the Lambda function on CloudWatch Logs. As expected, the message key and value are decoded.

![](cloudwatch-log.png#center)

## Summary

Amazon MSK can be configured as an event source of a Lambda function. Lambda internally polls for new messages from the event source and then synchronously invokes the target Lambda function. With this feature, we can develop a Kafka consumer application in serverless environment where developers can focus on application logic. In this lab, we discussed how to create a Kafka consumer using a Lambda function.