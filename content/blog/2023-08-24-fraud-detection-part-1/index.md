---
title: Kafka and DynamoDB for Real Time Fraud Detection - Part 1 Local Development
date: 2023-08-14
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka and DynamoDB for Real Time Fraud Detection
categories:
  - Data Engineering
tags:
  - Apache Flink
  - Apache Kafka
  - Kafka Connect
  - Amazon DynamoDB
  - Python
  - Docker
  - Docker Compose
  - Fraud Detection
authors:
  - JaehyeonKim
images: []
cevo: 31
description: The suite of Apache Camel Kafka connectors and the Kinesis Kafka connector from the AWS Labs can be effective for building data ingestion pipelines that integrate AWS services. In this post, I will illustrate how to develop the Camel DynamoDB sink connector using Docker. Fake order data will be generated using the MSK Data Generator source connector, and the sink connector will be configured to consume the topic messages to ingest them into a DynamoDB table.
---

[Apache Flink](https://flink.apache.org/) is an open-source, unified stream-processing and batch-processing framework. Its core is a distributed streaming data-flow engine that you can use to run real-time stream processing on high-throughput data sources. Currently, it is widely used to build applications for fraud/anomaly detection, rule-based alerting, business process monitoring, and continuous ETL to name a few. On AWS, we can deploy a Flink application via [Amazon Kinesis Data Analytics (KDA)](https://aws.amazon.com/kinesis/data-analytics/), [Amazon EMR](https://aws.amazon.com/emr/) and [Amazon EKS](https://aws.amazon.com/eks/). Among those, KDA is the easiest option as it provides the underlying infrastructure for your Apache Flink applications.

There are a number of AWS workshops and blog posts that we can learn Flink development on AWS and one of those is [AWS Kafka and DynamoDB for real time fraud detection](https://catalog.us-east-1.prod.workshops.aws/workshops/ad026e95-37fd-4605-a327-b585a53b1300/en-US). While this workshop targets a Flink application on KDA, it would have been easier if it illustrated local development before moving into deployment via KDA. In this series of posts, we will re-implement the fraud detection application of the workshop for those who are new to Flink and KDA. Specifically the app will be developed locally using Docker in part 1, and it will be deployed via KDA in part 2.

* [Part 1 Local Development](#) (this post)
* Part 2 Deployment via KDA

## Architecture

There are two Python applications that send transaction and flagged account records into the corresponding topics - the transaction app sends records indefinitely in a loop. Both the topics are consumed by a Flink application, and it filters the transactions from the flagged accounts followed by sending them into an output topic of flagged transactions. Finally, the flagged transaction records are sent into a DynamoDB table by the [Camel DynamoDB sink connector](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) in order to serve real-time requests from an API.

![](featured.png#center)

## Infrastructure

The Kafka cluster, Kafka connect and management app (kpow) are created using Docker while the python apps including the Flink app run in a virtual environment. The source of this post can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/fraud-detection/local) of this post.

### Preparation

As discussed later, the Flink application needs the Kafka connector artifact (*flink-sql-connector-kafka-1.15.2.jar*) in order to connect a Kafka cluster. Also, the source of the Camel DynamoDB sink connector should be available in the Kafka connect service. They can be downloaded by executing the following script.

```bash
# build.sh
#!/usr/bin/env bash
PKG_ALL="${PKG_ALL:-no}"

SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

#### Steps to package the flink app
SRC_PATH=$SCRIPT_DIR/package
rm -rf $SRC_PATH && mkdir -p $SRC_PATH/lib

## Download flink sql connector kafka
echo "download flink sql connector kafka..."
VERSION=1.15.2
FILE_NAME=flink-sql-connector-kafka-$VERSION
FLINK_SRC_DOWNLOAD_URL=https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/$VERSION/flink-sql-connector-kafka-$VERSION.jar
curl -L -o $SRC_PATH/lib/$FILE_NAME.jar ${FLINK_SRC_DOWNLOAD_URL}

## Install pip packages
echo "install and zip pip packages..."
pip3 install -r requirements.txt --target $SRC_PATH/site_packages

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

Once downloaded, they can be found in the corresponding folders as shown below. Although the Flink app doesn't need the *kafka-python* package, it is included in the *site_packages* folder in order to check if `--pyFiles` option works in KDA - it'll be used in part 2.

![](source-folders.png#center)

### Kafka and Related Services

A Kafka cluster with a single broker and zookeeper node is used in this post. The broker has two listeners and the port 9092 and 29092 are used for internal and external communication respectively. The default number of topic partitions is set to 2. Details about Kafka cluster setup can be found in [this post](https://jaehyeon.me/blog/2023-05-04-kafka-development-with-docker-part-1/).

A Kafka connect is configured to run in a distributed mode. The connect properties file and the source of the Camel DynamoDB sink connector are volume-mapped. Also AWS credentials are added to environment variables as it needs permission to put items into a DynamoDB table. Details about Kafka connect setup can be found in [this post](https://jaehyeon.me/blog/2023-06-04-kafka-connect-for-aws-part-2/).

Finally, the [Kpow CE](https://docs.kpow.io/ce/) is used for ease of monitoring Kafka topics and related objects. The bootstrap server address and connect REST URL are added as environment variables. See [this post](https://jaehyeon.me/blog/2023-05-18-kafka-development-with-docker-part-2/) for details about Kafka management apps.

```yaml
version: "3.5"

services:
  zookeeper:
    image: bitnami/zookeeper:3.5
    container_name: zookeeper
    ports:
      - "2181"
    networks:
      - kafkanet
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
    volumes:
      - zookeeper_data:/bitnami/zookeeper
  kafka-0:
    image: bitnami/kafka:2.8.1
    container_name: kafka-0
    expose:
      - 9092
    ports:
      - "29092:29092"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=2
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-connect:
    image: bitnami/kafka:2.8.1
    container_name: connect
    command: >
      /opt/bitnami/kafka/bin/connect-distributed.sh
      /opt/bitnami/kafka/config/connect-distributed.properties
    ports:
      - "8083:8083"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
    volumes:
      - "./configs/connect-distributed.properties:/opt/bitnami/kafka/config/connect-distributed.properties"
      - "./connectors/camel-aws-ddb-sink-kafka-connector:/opt/connectors/camel-aws-ddb-sink-kafka-connector"
    depends_on:
      - zookeeper
      - kafka-0
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP: kafka-0:9092
      CONNECT_REST_URL: http://kafka-connect:8083
    depends_on:
      - zookeeper
      - kafka-0
      - kafka-connect

networks:
  kafkanet:
    name: kafka-network

volumes:
  zookeeper_data:
    driver: local
    name: zookeeper_data
  kafka_0_data:
    driver: local
    name: kafka_0_data
```

### DynamoDB Table

The destination table is named *flagged-transactions*, and it has the primary key where *transaction_id* and *transaction_date* are the hash and range key respectively. It also has a global secondary index (GSI) where *account_id* and *transaction_date* constitute the primary key. The purpose of the GSI is for ease of querying transactions by account ID. The table can be created using the AWS CLI as shown below.

```bash
aws dynamodb create-table \
  --cli-input-json file://configs/ddb.json
```

```json
// configs/ddb.json
{
  "TableName": "flagged-transactions",
  "KeySchema": [
    { "AttributeName": "transaction_id", "KeyType": "HASH" },
    { "AttributeName": "transaction_date", "KeyType": "RANGE" }
  ],
  "AttributeDefinitions": [
    { "AttributeName": "transaction_id", "AttributeType": "S" },
    { "AttributeName": "account_id", "AttributeType": "N" },
    { "AttributeName": "transaction_date", "AttributeType": "S" }
  ],
  "ProvisionedThroughput": {
    "ReadCapacityUnits": 2,
    "WriteCapacityUnits": 2
  },
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "account",
      "KeySchema": [
        { "AttributeName": "account_id", "KeyType": "HASH" },
        { "AttributeName": "transaction_date", "KeyType": "RANGE" }
      ],
      "Projection": { "ProjectionType": "ALL" },
      "ProvisionedThroughput": {
        "ReadCapacityUnits": 2,
        "WriteCapacityUnits": 2
      }
    }
  ]
}

```

### Virtual Environment

As mentioned earlier, all Python apps are run in a virtual environment, and we need the following pip packages. We use the version 1.15.2 of the [apache-flink](https://pypi.org/project/apache-flink/) package because it is the latest supported version by KDA. We also need the [kafka-python](https://pypi.org/project/kafka-python/) package for source data generation. The pip packages can be installed by `pip install -r requirements-dev.txt`.

```txt
# requirements.txt
kafka-python==2.0.2

# requirements-dev.txt
-r requirements.txt
apache-flink==1.15.2
black==19.10b0
pytest
pytest-cov
```

## Application

### Source Data

A single Python script is created for the apps that generate and send source data into Kafka topics. Each of the classes for the flagged account and transaction has the *asdict*, *auto* and *create* methods. The *create* method generates a list of records where each element is instantiated by the *auto* method. Those records are sent into the relevant Kafka topic after being converted into dictionary by the *asdict* method. 

A Kafka producer is created as an attribute of the *Producer* class. The source records are sent into the relevant topic by the *send* method. Note that both the key and value of the messages are serialized as json.

Whether to send flagged account or transaction records is determined by an environment variable called *DATA_TYPE*. We can run those apps as shown below.
* flagged account - `DATE_TYPE=account python producer.py`
* transaction - `DATE_TYPE=transaction python producer.py`

```py
# producer.py
import os
import datetime
import time
import json
import typing
import random
import logging
import dataclasses

from kafka import KafkaProducer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s.%(msecs)03d:%(levelname)s:%(name)s:%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


@dataclasses.dataclass
class FlagAccount:
    account_id: int
    flag_date: str

    def asdict(self):
        return dataclasses.asdict(self)

    @classmethod
    def auto(cls, account_id: int):
        flag_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
        return cls(account_id, flag_date)

    @staticmethod
    def create():
        return [FlagAccount.auto(account_id) for account_id in range(1000000001, 1000000010, 2)]


@dataclasses.dataclass
class Transaction:
    account_id: int
    customer_id: str
    merchant_type: str
    transaction_id: str
    transaction_type: str
    transaction_amount: float
    transaction_date: str

    def asdict(self):
        return dataclasses.asdict(self)

    @classmethod
    def auto(cls):
        account_id = random.randint(1000000001, 1000000010)
        customer_id = f"C{str(account_id)[::-1]}"
        merchant_type = random.choice(["Online", "In Store"])
        transaction_id = "".join(random.choice("0123456789ABCDEF") for i in range(16))
        transaction_type = random.choice(
            [
                "Grocery_Store",
                "Gas_Station",
                "Shopping_Mall",
                "City_Services",
                "HealthCare_Service",
                "Food and Beverage",
                "Others",
            ]
        )
        transaction_amount = round(random.randint(100, 10000) * random.random(), 2)
        transaction_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
        return cls(
            account_id,
            customer_id,
            merchant_type,
            transaction_id,
            transaction_type,
            transaction_amount,
            transaction_date,
        )

    @staticmethod
    def create(num: int):
        return [Transaction.auto() for _ in range(num)]


class Producer:
    def __init__(self, bootstrap_servers: list, account_topic: str, transaction_topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.account_topic = account_topic
        self.transaction_topic = transaction_topic
        self.producer = self.create()

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            key_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            value_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            api_version=(2, 8, 1),
        )

    def send(self, records: typing.Union[typing.List[FlagAccount], typing.List[Transaction]]):
        for record in records:
            try:
                key = {"account_id": record.account_id}
                topic = self.account_topic
                if hasattr(record, "transaction_id"):
                    key["transaction_id"] = record.transaction_id
                    topic = self.transaction_topic
                self.producer.send(topic=topic, key=key, value=record.asdict())
            except Exception as e:
                raise RuntimeError("fails to send a message") from e
        self.producer.flush()

    def serialize(self, obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        if isinstance(obj, datetime.date):
            return str(obj)
        return obj


if __name__ == "__main__":
    producer = Producer(
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:29092").split(","),
        account_topic=os.getenv("CUSTOMER_TOPIC_NAME", "flagged-accounts"),
        transaction_topic=os.getenv("TRANSACTION_TOPIC_NAME", "transactions"),
    )
    if os.getenv("DATE_TYPE", "account") == "account":
        producer.send(FlagAccount.create())
        producer.producer.close()
    else:
        max_run = int(os.getenv("MAX_RUN", "-1"))
        logging.info(f"max run - {max_run}")
        current_run = 0
        while True:
            current_run += 1
            logging.info(f"current run - {current_run}")
            if current_run - max_run == 0:
                logging.info(f"reached max run, finish")
                producer.producer.close()
                break
            producer.send(Transaction.create(5))
            secs = random.randint(2, 5)
            logging.info(f"messages sent... wait {secs} seconds")
            time.sleep(secs)
```

Once we start the apps, we can check the topics for the source data are created and messages are ingested in *Kpow*.

![](source-topics.png#center)

### Output Data

The Flink application is built using the [Table API](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/table_api_tutorial/). We have two Kafka source topics and one output topic. Simply put, we can query the records of the topics as tables of unbounded real-time streams with the Table API. In order to read/write records from/to a Kafka topic, we need to specify the [Kafka connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) artifact that we downloaded earlier as the [pipeline jar](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/python/dependency_management/#jar-dependencies). Note we only need to configure the connector jar when we develop the app locally as the jar file will be specified by the `--jarfile` option for KDA. We also need the application properties file (*application_properties.json*) in order to be comparable with KDA. The file contains the Flink runtime options in KDA as well as application specific properties. All the properties should be specified when deploying via KDA and, for local development, we keep them as a json file and only the application specific properties are used.

The tables for the source and output topics can be created using SQL with options that are related to the Kafka connector. Key options cover the connector name (*connector*), topic name (*topic*), bootstrap sever address (*properties.bootstrap.servers*) and format (*format*). See the [connector document](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) for more details about the connector configuration. We also have a function to insert flagged transaction records into the output topic in SQL (*insert_into_stmt*).

In the *main* method, we create all the source and sink tables after mapping relevant application properties. Then the output records are inserted into the output Kafka topic. Note that the output records are printed in the terminal additionally when the app is running locally for ease of checking them.

```py
import os
import json
import logging

import kafka  # check if --pyFiles works
from pyflink.table import EnvironmentSettings, TableEnvironment

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s.%(msecs)03d:%(levelname)s:%(name)s:%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "KDA")  # KDA, LOCAL
logging.info(f"runtime environment - {RUNTIME_ENV}...")

env_settings = EnvironmentSettings.in_streaming_mode()
table_env = TableEnvironment.create(env_settings)

APPLICATION_PROPERTIES_FILE_PATH = (
    "/etc/flink/application_properties.json"  # on kda or docker-compose
    if RUNTIME_ENV != "LOCAL"
    else "application_properties.json"
)

if RUNTIME_ENV != "KDA":
    # on non-KDA, multiple jar files can be passed after being delimited by a semicolon
    CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
    PIPELINE_JAR = "flink-sql-connector-kafka-1.15.2.jar"
    table_env.get_config().set(
        "pipeline.jars", f"file://{os.path.join(CURRENT_DIR, 'package', 'lib', PIPELINE_JAR)}"
    )
logging.info(f"app properties file path - {APPLICATION_PROPERTIES_FILE_PATH}")

def get_application_properties():
    if os.path.isfile(APPLICATION_PROPERTIES_FILE_PATH):
        with open(APPLICATION_PROPERTIES_FILE_PATH, "r") as file:
            contents = file.read()
            properties = json.loads(contents)
            return properties
    else:
        raise RuntimeError(f"A file at '{APPLICATION_PROPERTIES_FILE_PATH}' was not found")

def property_map(props: dict, property_group_id: str):
    for prop in props:
        if prop["PropertyGroupId"] == property_group_id:
            return prop["PropertyMap"]

def create_flagged_account_source_table(
    table_name: str, topic_name: str, bootstrap_servers: str, startup_mode: str
):
    stmt = f"""
    CREATE TABLE {table_name} (
        account_id BIGINT,
        flag_date TIMESTAMP(3)
    )
    WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',
        'properties.group.id' = 'flagged-account-source-group',
        'format' = 'json',
        'scan.startup.mode' = '{startup_mode}'
    )
    """
    logging.info("flagged account source table statement...")
    logging.info(stmt)
    return stmt

def create_transaction_source_table(
    table_name: str, topic_name: str, bootstrap_servers: str, startup_mode: str
):
    stmt = f"""
    CREATE TABLE {table_name} (
        account_id BIGINT,
        customer_id VARCHAR(15),
        merchant_type VARCHAR(8),
        transaction_id VARCHAR(16),
        transaction_type VARCHAR(20),
        transaction_amount DECIMAL(10,2),
        transaction_date TIMESTAMP(3)
    )
    WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',
        'properties.group.id' = 'transaction-source-group',
        'format' = 'json',
        'scan.startup.mode' = '{startup_mode}'
    )
    """
    logging.info("transaction source table statement...")
    logging.info(stmt)
    return stmt

def create_flagged_transaction_sink_table(table_name: str, topic_name: str, bootstrap_servers: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        account_id BIGINT,
        customer_id VARCHAR(15),
        merchant_type VARCHAR(8),
        transaction_id VARCHAR(16),
        transaction_type VARCHAR(20),
        transaction_amount DECIMAL(10,2),
        transaction_date TIMESTAMP(3)
    )
    WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',        
        'format' = 'json',
        'key.format' = 'json',
        'key.fields' = 'account_id;transaction_id',
        'properties.allow.auto.create.topics' = 'true'
    )
    """
    logging.info("transaction sink table statement...")
    logging.info(stmt)
    return stmt

def create_print_table(table_name: str):
    return f"""
    CREATE TABLE {table_name} (
        account_id BIGINT,
        customer_id VARCHAR(15),
        merchant_type VARCHAR(8),
        transaction_id VARCHAR(16),
        transaction_type VARCHAR(20),
        transaction_amount DECIMAL(10,2),
        transaction_date TIMESTAMP(3)
    )
    WITH (
        'connector' = 'print'
    )
    """

def insert_into_stmt(insert_from_tbl: str, compare_with_tbl: str, insert_into_tbl: str):
    return f"""
    INSERT INTO {insert_into_tbl}
        SELECT l.*
        FROM {insert_from_tbl} AS l
        JOIN {compare_with_tbl} AS r
            ON l.account_id = r.account_id 
            AND l.transaction_date > r.flag_date
    """

def main():
    ## map consumer/producer properties
    props = get_application_properties()
    # consumer for flagged account
    consumer_0_property_group_key = "consumer.config.0"
    consumer_0_properties = property_map(props, consumer_0_property_group_key)
    consumer_0_table_name = consumer_0_properties["table.name"]
    consumer_0_topic_name = consumer_0_properties["topic.name"]
    consumer_0_bootstrap_servers = consumer_0_properties["bootstrap.servers"]
    consumer_0_startup_mode = consumer_0_properties["startup.mode"]
    # consumer for transactions
    consumer_1_property_group_key = "consumer.config.1"
    consumer_1_properties = property_map(props, consumer_1_property_group_key)
    consumer_1_table_name = consumer_1_properties["table.name"]
    consumer_1_topic_name = consumer_1_properties["topic.name"]
    consumer_1_bootstrap_servers = consumer_1_properties["bootstrap.servers"]
    consumer_1_startup_mode = consumer_1_properties["startup.mode"]
    # producer
    producer_0_property_group_key = "producer.config.0"
    producer_0_properties = property_map(props, producer_0_property_group_key)
    producer_0_table_name = producer_0_properties["table.name"]
    producer_0_topic_name = producer_0_properties["topic.name"]
    producer_0_bootstrap_servers = producer_0_properties["bootstrap.servers"]
    # print
    print_table_name = "sink_print"
    ## create the source table for flagged accounts
    table_env.execute_sql(
        create_flagged_account_source_table(
            consumer_0_table_name,
            consumer_0_topic_name,
            consumer_0_bootstrap_servers,
            consumer_0_startup_mode,
        )
    )
    table_env.from_path(consumer_0_table_name).print_schema()
    ## create the source table for transactions
    table_env.execute_sql(
        create_transaction_source_table(
            consumer_1_table_name,
            consumer_1_topic_name,
            consumer_1_bootstrap_servers,
            consumer_1_startup_mode,
        )
    )
    table_env.from_path(consumer_1_table_name).print_schema()
    ## create sink table for flagged accounts
    table_env.execute_sql(
        create_flagged_transaction_sink_table(
            producer_0_table_name, producer_0_topic_name, producer_0_bootstrap_servers
        )
    )
    table_env.from_path(producer_0_table_name).print_schema()
    table_env.execute_sql(create_print_table("sink_print"))
    ## insert into sink tables
    if RUNTIME_ENV == "LOCAL":
        statement_set = table_env.create_statement_set()
        statement_set.add_insert_sql(
            insert_into_stmt(consumer_1_table_name, consumer_0_table_name, producer_0_table_name)
        )
        statement_set.add_insert_sql(
            insert_into_stmt(consumer_1_table_name, consumer_0_table_name, print_table_name)
        )
        statement_set.execute().wait()
    else:
        table_result = table_env.execute_sql(
            insert_into_stmt(consumer_1_table_name, consumer_0_table_name, producer_0_table_name)
        )
        logging.info(table_result.get_job_client().get_job_status())


if __name__ == "__main__":
    main()
```

```json
[
  {
    "PropertyGroupId": "kinesis.analytics.flink.run.options",
    "PropertyMap": {
      "python": "processor.py",
      "jarfile": "package/lib/flink-sql-connector-kinesis-1.15.2.jar",
      "pyFiles": "package/site_packages/"
    }
  },
  {
    "PropertyGroupId": "consumer.config.0",
    "PropertyMap": {
      "table.name": "flagged_accounts",
      "topic.name": "flagged-accounts",
      "bootstrap.servers": "localhost:29092",
      "startup.mode": "earliest-offset"
    }
  },
  {
    "PropertyGroupId": "consumer.config.1",
    "PropertyMap": {
      "table.name": "transactions",
      "topic.name": "transactions",
      "bootstrap.servers": "localhost:29092",
      "startup.mode": "earliest-offset"
    }
  },
  {
    "PropertyGroupId": "producer.config.0",
    "PropertyMap": {
      "table.name": "flagged_transactions",
      "topic.name": "flagged-transactions",
      "bootstrap.servers": "localhost:29092"
    }
  }
]
```

The terminal on the right-hand side shows the output records. We see that the account IDs ends with all odd numbers, which matches transactions from flagged accounts.

![](terminal-result.png#center)

We can also see details of all the topics in *Kpow* as shown below.

![](all-topics.png#center)

### Sink Output Data

Kafka Connect provides a REST API that manages connectors, and we can create a connector programmatically using it. The REST endpoint requires a JSON payload that includes connector configurations.

```bash
$ curl -i -X POST -H "Accept:application/json" -H  "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/sink.json
```

The connector is configured to write messages from the *flagged-transactions* topic into the DynamoDB table created earlier. It requires to specify the table name, AWS region, operation, write capacity and whether to use the [default credential provider](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) - see the [documentation](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) for details. Note that, if you don't use the default credential provider, you have to specify the *access key id* and *secret access key*. Note further that, although the current LTS version is *v3.18.2*, the default credential provider option didn't work for me, and I was recommended [to use *v3.20.3* instead](https://github.com/apache/camel-kafka-connector/issues/1533). Finally, the [*camel.sink.unmarshal* option](https://github.com/apache/camel-kafka-connector/blob/camel-kafka-connector-3.20.3/connectors/camel-aws-ddb-sink-kafka-connector/src/main/resources/kamelets/aws-ddb-sink.kamelet.yaml#L123) is to convert data from the internal *java.util.HashMap* type into the required *java.io.InputStream* type. Without this configuration, the [connector fails](https://github.com/apache/camel-kafka-connector/issues/1532) with *org.apache.camel.NoTypeConversionAvailableException* error.

```json
// configs/sink.json
{
  "name": "transactions-sink",
  "config": {
    "connector.class": "org.apache.camel.kafkaconnector.awsddbsink.CamelAwsddbsinkSinkConnector",
    "tasks.max": "2",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,
    "topics": "flagged-transactions",

    "camel.kamelet.aws-ddb-sink.table": "flagged-transactions",
    "camel.kamelet.aws-ddb-sink.region": "ap-southeast-2",
    "camel.kamelet.aws-ddb-sink.operation": "PutItem",
    "camel.kamelet.aws-ddb-sink.writeCapacity": 1,
    "camel.kamelet.aws-ddb-sink.useDefaultCredentialsProvider": true,
    "camel.sink.unmarshal": "jackson"
  }
}
```

Below shows the sink connector details on *Kpow*.

![](sink-connector.png#center)

We can check the ingested records on the DynamoDB table items view. Below shows a list of scanned records.

![](ddb-output.png#center)

## Summary