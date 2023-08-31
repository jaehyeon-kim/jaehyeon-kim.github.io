---
title: Getting Started with Pyflink on AWS - Part 1 Local Flink and Local Kafka
date: 2023-08-17
draft: false
featured: true
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
  - Apache Kafka
  - Amazon Managed Service for Apache Flink
  - Amazon MSK  
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Apache Flink is widely used for building real-time stream processing applications. On AWS, Amazon Managed Service for Apache Flink is the easiest option to develop a Flink app as it provides the underlying infrastructure. Updating a guide from AWS, this series of posts discuss how to develop and deploy a Flink (Pyflink) application via KDA where the data source and sink are Kafka topics. In part 1, the app will be developed locally targeting a Kafka cluster created by Docker. Furthermore, it will be executed in a virtual environment as well as in a local Flink cluster for improved monitoring.
---

[Apache Flink](https://flink.apache.org/) is an open-source, unified stream-processing and batch-processing framework. Its core is a distributed streaming data-flow engine that you can use to run real-time stream processing on high-throughput data sources. Currently, it is widely used to build applications for fraud/anomaly detection, rule-based alerting, business process monitoring, and continuous ETL to name a few. On AWS, we can deploy a Flink application via [Amazon Kinesis Data Analytics (KDA)](https://aws.amazon.com/kinesis/data-analytics/), [Amazon EMR](https://aws.amazon.com/emr/) and [Amazon EKS](https://aws.amazon.com/eks/). Among those, KDA is the easiest option as it provides the underlying infrastructure for your Apache Flink applications.

For those who are new to Flink (Pyflink) and KDA, AWS provides a good resource that guides how to develop a Flink application locally and deploy via KDA. The guide uses Amazon Kinesis Data Stream as a data source and demonstrates how to sink records into multiple destinations - Kinesis Data Stream, Kinesis Firehose Delivery Stream and S3. It can be found in this [GitHub project](https://github.com/aws-samples/pyflink-getting-started).

In this series of posts, we will update one of the examples of the guide by changing the data source and sink into [Apache Kafka](https://kafka.apache.org/) topics. In part 1, we will discuss how to develop a Flink application that targets a local Kafka cluster. Furthermore, it will be executed in a virtual environment as well as in a local Flink cluster for improved monitoring. The Flink application will be amended to connect a Kafka cluster on Amazon MSK in part 2. The Kafka cluster will be authenticated by [IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html), and the Flink app needs to change its configuration accordingly by creating a custom Uber Jar file. In part 3, the application will be deployed via KDA using an application package that is saved in S3. The application package is a zip file that includes the application script, custom Uber Jar file, and 3rd-party Python packages. The deployment will be made by [Terraform](https://www.terraform.io/).

* [Part 1 Local Flink and Local Kafka](#) (this post)
* [Part 2 Local Flink and MSK](/blog/2023-08-28-getting-started-with-pyflink-on-aws-part-2)
* Part 3 AWS Managed Flink and MSK

[**Update 2023-08-30**] Amazon Kinesis Data Analytics is renamed into [Amazon Managed Service for Apache Flink](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-managed-service-apache-flink/). In this post, Kinesis Data Analytics (KDA) and Amazon Managed Service for Apache Flink will be used interchangeably.

## Architecture

The Python source data generator (*producer.py*) sends random stock price records into a Kafka topic. The messages in the source topic are consumed by a Flink application, and it just writes those messages into a different sink topic. This is the simplest application of the AWS guide, and you may try [other examples](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) if interested.

![](featured.png#center)

## Infrastructure

A Kafka cluster and management app (*Kpow*) are created using Docker while the Python apps including the Flink app run in a virtual environment in the first trial. After that the Flink app is submitted to a local Flink cluster for improved monitoring. The Flink cluster is also created using Docker. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/pyflink-getting-started-on-aws/local) of this post.

### Preparation

As discussed later, the Flink application needs the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) artifact (*flink-sql-connector-kafka-1.15.2.jar*) in order to connect a Kafka cluster. Also, the *kafka-python* package is downloaded to check if `--pyFiles` option works when submitting the app to a Flink cluster or deploying via KDA. They can be downloaded by executing the following script.

```bash
# build.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
SRC_PATH=$SCRIPT_DIR/package
rm -rf $SRC_PATH && mkdir -p $SRC_PATH/lib

## Download flink sql connector kafka
echo "download flink sql connector kafka..."
VERSION=1.15.2
FILE_NAME=flink-sql-connector-kafka-$VERSION
DOWNLOAD_URL=https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/$VERSION/flink-sql-connector-kafka-$VERSION.jar
curl -L -o $SRC_PATH/lib/$FILE_NAME.jar ${DOWNLOAD_URL}

## Install pip packages
echo "install and zip pip packages..."
pip install -r requirements.txt --target $SRC_PATH/site_packages

## Package pyflink app
echo "package pyflink app"
zip -r kda-package.zip processor.py package/lib package/site_packages
```

Once downloaded, the Kafka SQL artifact and python package can be found in the *lib* and *site_packages* folders respectively as shown below.

![](source-folders.png#center)

### Kafka Cluster

A Kafka cluster with a single broker and zookeeper node is used in this post. The broker has two listeners and the port 9092 and 29092 are used for internal and external communication respectively. The default number of topic partitions is set to 2. Details about Kafka cluster setup can be found in [this post](/blog/2023-05-04-kafka-development-with-docker-part-1/).

The [Kpow CE](https://docs.kpow.io/ce/) is used for ease of monitoring Kafka topics and related resources. The bootstrap server address is added as an environment variable. See [this post](/blog/2023-05-18-kafka-development-with-docker-part-2/) for details about Kafka management apps.

The Kafka cluster can be started by `docker-compose -f compose-kafka.yml up -d`.

```yaml
# compose-kafka.yml
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
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP: kafka-0:9092
    depends_on:
      - zookeeper
      - kafka-0

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

### Flink Cluster

In order to run a PyFlink application in a Flink cluster, we need to install Python and the *apache-flink* package additionally. We can create a custom Docker image based on the [official Flink](https://hub.docker.com/_/flink) image. I chose the version 1.15.2 as it is the recommended Flink version by KDA. The custom image can be built by `docker build -t pyflink:1.15.2-scala_2.12 .`.

```Docker
FROM flink:1.15.2-scala_2.12

ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION:-3.8.10}
ARG FLINK_VERSION
ENV FLINK_VERSION=${FLINK_VERSION:-1.15.2}

# Currently only Python 3.6, 3.7 and 3.8 are supported officially.
RUN apt-get update -y && \
  apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev libffi-dev && \
  wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
  tar -xvf Python-${PYTHON_VERSION}.tgz && \
  cd Python-${PYTHON_VERSION} && \
  ./configure --without-tests --enable-shared && \
  make -j6 && \
  make install && \
  ldconfig /usr/local/lib && \
  cd .. && rm -f Python-${PYTHON_VERSION}.tgz && rm -rf Python-${PYTHON_VERSION} && \
  ln -s /usr/local/bin/python3 /usr/local/bin/python && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# install PyFlink
RUN pip3 install apache-flink==${FLINK_VERSION}
```

A Flink cluster is made up of a single Job Manger and Task Manager, and the cluster runs in the [Session Mode](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/deployment/overview/) where one or more Flink applications can be submitted/executed simultaneously. See [this page](https://nightlies.apache.org/flink/flink-docs-master/docs/deployment/resource-providers/standalone/docker/#flink-with-docker-compose) for details about how to create a Flink cluster using *docker-compose*.

Two environment variables are configured to adjust the application behaviour. The *RUNTIME_ENV* is set to *DOCKER*, and it determines which [pipeline jar](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/dependency_management/) and application property file to choose. Also, the *BOOTSTRAP_SERVERS* overrides the Kafka bootstrap server address value from the application property file. We will make use of it to configure the bootstrap server address dynamically for MSK in part 2. Finally, the current directory is volume-mapped into */etc/flink* so that the application and related resources can be available in the Flink cluster.

The Flink cluster can be started by `docker-compose -f compose-flink.yml up -d`.

```yaml
version: "3.5"

services:
  jobmanager:
    image: pyflink:1.15.2-scala_2.12
    container_name: jobmanager
    command: jobmanager
    ports:
      - "8081:8081"
    networks:
      - kafkanet
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
        rest.flamegraph.enabled: true
        web.backpressure.refresh-interval: 10000
      - RUNTIME_ENV=DOCKER
      - BOOTSTRAP_SERVERS=kafka-0:9092
    volumes:
      - $PWD:/etc/flink
  taskmanager:
    image: pyflink:1.15.2-scala_2.12
    container_name: taskmanager
    command: taskmanager
    networks:
      - kafkanet
    volumes:
      - flink_data:/tmp/
      - $PWD:/etc/flink
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 3
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
      - RUNTIME_ENV=DOCKER
      - BOOTSTRAP_SERVERS=kafka-0:9092
    depends_on:
      - jobmanager

networks:
  kafkanet:
    external: true
    name: kafka-network

volumes:
  flink_data:
    driver: local
    name: flink_data

```

### Virtual Environment

As mentioned earlier, all Python apps run in a virtual environment, and we have the following pip packages. We use the version 1.15.2 of the [apache-flink](https://pypi.org/project/apache-flink/) package because it is the recommended version by KDA. We also need the [kafka-python](https://pypi.org/project/kafka-python/) package for source data generation. The pip packages can be installed by `pip install -r requirements-dev.txt`.

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

A single Python script is created to generate fake stock price records. The class for the stock record has the *asdict*, *auto* and *create* methods. The *create* method generates a list of records where each element is instantiated by the *auto* method. Those records are sent into the relevant Kafka topic after being converted into a dictionary by the *asdict* method. 

A Kafka producer is created as an attribute of the *Producer* class. The source records are sent into the relevant topic by the *send* method. Note that both the key and value of the messages are serialized as json.

The data generator can be started simply by `python producer.py`.

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

datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")


@dataclasses.dataclass
class Stock:
    event_time: str
    ticker: str
    price: float

    def asdict(self):
        return dataclasses.asdict(self)

    @classmethod
    def auto(cls, ticker: str):
        # event_time = datetime.datetime.now().isoformat(timespec="milliseconds")
        event_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
        price = round(random.random() * 100, 2)
        return cls(event_time, ticker, price)

    @staticmethod
    def create():
        tickers = '["AAPL", "ACN", "ADBE", "AMD", "AVGO", "CRM", "CSCO", "IBM", "INTC", "MA", "MSFT", "NVDA", "ORCL", "PYPL", "QCOM", "TXN", "V"]'
        return [Stock.auto(ticker) for ticker in json.loads(tickers)]


class Producer:
    def __init__(self, bootstrap_servers: list, topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.producer = self.create()

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            key_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            value_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
        )

    def send(self, stocks: typing.List[Stock]):
        for stock in stocks:
            try:
                self.producer.send(self.topic, key={"ticker": stock.ticker}, value=stock.asdict())
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
        topic=os.getenv("TOPIC_NAME", "stocks-in"),
    )
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
        producer.send(Stock.create())
        secs = random.randint(5, 10)
        logging.info(f"messages sent... wait {secs} seconds")
        time.sleep(secs)
```

Once we start the app, we can check the topic for the source data is created and messages are ingested in *Kpow*.

![](source-topic.png#center)

### Process Data

The Flink application is built using the [Table API](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/table_api_tutorial/). We have two Kafka topics - one for the source and the other for the sink. Simply put, we can manipulate the records of the topics as tables of unbounded real-time streams with the Table API. In order to read/write records from/to a Kafka topic, we need to specify the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) artifact that we downloaded earlier as the [pipeline jar](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/dependency_management/#jar-dependencies). Note we only need to configure the connector jar when we develop the app locally as the jar file will be specified by the `--jarfile` option when submitting it to a Flink cluster or deploying via KDA. We also need the application properties file (*application_properties.json*) in order to be comparable with KDA. The file contains the Flink runtime options in KDA as well as application specific properties. All the properties should be specified when deploying via KDA and, for local development, we keep them as a json file and only the application specific properties are used.

The tables for the source and output topics can be created using SQL with options that are related to the Kafka connector. Key options cover the connector name (*connector*), topic name (*topic*), bootstrap server address (*properties.bootstrap.servers*) and format (*format*). See the [connector document](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) for more details about the connector configuration. When it comes to inserting the source records into the output table, we can use either SQL or built-in *add_insert* method.

In the *main* method, we create all the source and sink tables after mapping relevant application properties. Then the output records are inserted into the output Kafka topic. Note that the output records are printed in the terminal additionally when the app is running locally for ease of checking them.

```py
# processor.py
import os
import json
import re
import logging

import kafka  # check if --pyFiles works
from pyflink.table import EnvironmentSettings, TableEnvironment

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s.%(msecs)03d:%(levelname)s:%(name)s:%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "KDA")  # KDA, DOCKER, LOCAL
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS")  # overwrite app config

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


def create_source_table(
    table_name: str, topic_name: str, bootstrap_servers: str, startup_mode: str
):
    stmt = f"""
    CREATE TABLE {table_name} (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',
        'properties.group.id' = 'source-group',
        'format' = 'json',
        'scan.startup.mode' = '{startup_mode}'
    )
    """
    logging.info("source table statement...")
    logging.info(stmt)
    return stmt


def create_sink_table(table_name: str, topic_name: str, bootstrap_servers: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',        
        'format' = 'json',
        'key.format' = 'json',
        'key.fields' = 'ticker',
        'properties.allow.auto.create.topics' = 'true'
    )
    """
    logging.info("sint table statement...")
    logging.info(stmt)
    return stmt


def create_print_table(table_name: str):
    return f"""
    CREATE TABLE {table_name} (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'connector' = 'print'
    )
    """


def main():
    ## map consumer/producer properties
    props = get_application_properties()
    # consumer
    consumer_property_group_key = "consumer.config.0"
    consumer_properties = property_map(props, consumer_property_group_key)
    consumer_table_name = consumer_properties["table.name"]
    consumer_topic_name = consumer_properties["topic.name"]
    consumer_bootstrap_servers = BOOTSTRAP_SERVERS or consumer_properties["bootstrap.servers"]
    consumer_startup_mode = consumer_properties["startup.mode"]
    # producer
    producer_property_group_key = "producer.config.0"
    producer_properties = property_map(props, producer_property_group_key)
    producer_table_name = producer_properties["table.name"]
    producer_topic_name = producer_properties["topic.name"]
    producer_bootstrap_servers = BOOTSTRAP_SERVERS or producer_properties["bootstrap.servers"]
    # print
    print_table_name = "sink_print"
    ## create a souce table
    table_env.execute_sql(
        create_source_table(
            consumer_table_name,
            consumer_topic_name,
            consumer_bootstrap_servers,
            consumer_startup_mode,
        )
    )
    ## create sink tables
    table_env.execute_sql(
        create_sink_table(producer_table_name, producer_topic_name, producer_bootstrap_servers)
    )
    table_env.execute_sql(create_print_table("sink_print"))
    ## insert into sink tables
    if RUNTIME_ENV == "LOCAL":
        source_table = table_env.from_path(consumer_table_name)
        statement_set = table_env.create_statement_set()
        statement_set.add_insert(producer_table_name, source_table)
        statement_set.add_insert(print_table_name, source_table)
        statement_set.execute().wait()
    else:
        table_result = table_env.execute_sql(
            f"INSERT INTO {producer_table_name} SELECT * FROM {consumer_table_name}"
        )
        logging.info(table_result.get_job_client().get_job_status())


if __name__ == "__main__":
    main()
```

```json
// application_properties.json
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
      "table.name": "source_table",
      "topic.name": "stocks-in",
      "bootstrap.servers": "localhost:29092",
      "startup.mode": "earliest-offset"
    }
  },
  {
    "PropertyGroupId": "producer.config.0",
    "PropertyMap": {
      "table.name": "sink_table",
      "topic.name": "stocks-out",
      "bootstrap.servers": "localhost:29092"
    }
  }
]
```

#### Run Locally

We can run the app locally as following - `RUNTIME_ENV=LOCAL python processor.py`. The terminal on the right-hand side shows the output records of the Flink app while the left-hand side records logs of the producer app. We can see that the print output from the Flink app gets updated when new source records are sent into the source topic by the producer app.

![](terminal-result.png#center)

We can also see details of all the topics in *Kpow* as shown below. The total number of messages matches between the source and output topics but not within partitions.

![](all-topics.png#center)

#### Run in Flink Cluster

The execution in a terminal is limited for monitoring, and we can inspect and understand what is happening inside Flink using the Flink Web UI. For this, we need to submit the app to the Flink cluster we created earlier. Typically, a Pyflink app can be submitted using the [CLI interface](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/deployment/cli/) by specifying the main application (*--python*), Kafka connector artifact file (*--jarfile*), and 3rd-party Python packages (*--pyFiles*) if necessary. Once submitted, it shows the status with the job ID. 

```bash
$ docker exec jobmanager /opt/flink/bin/flink run \
  --python /etc/flink/processor.py \
  --jarfile /etc/flink/package/lib/flink-sql-connector-kafka-1.15.2.jar \
  --pyFiles /etc/flink/package/site_packages/ \
  -d
2023-08-08 02:07:13.220:INFO:root:runtime environment - DOCKER...
2023-08-08 02:07:14.341:INFO:root:app properties file path - /etc/flink/application_properties.json
2023-08-08 02:07:14.341:INFO:root:source table statement...
2023-08-08 02:07:14.341:INFO:root:
    CREATE TABLE source_table (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'connector' = 'kafka',
        'topic' = 'stocks-in',
        'properties.bootstrap.servers' = 'kafka-0:9092',
        'properties.group.id' = 'source-group',
        'format' = 'json',
        'scan.startup.mode' = 'earliest-offset'
    )
    
2023-08-08 02:07:14.439:INFO:root:sint table statement...
2023-08-08 02:07:14.439:INFO:root:
    CREATE TABLE sink_table (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'connector' = 'kafka',
        'topic' = 'stocks-out',
        'properties.bootstrap.servers' = 'kafka-0:9092',        
        'format' = 'json',
        'key.format' = 'json',
        'key.fields' = 'ticker',
        'properties.allow.auto.create.topics' = 'true'
    )
    
WARNING: An illegal reflective access operation has occurred
WARNING: Illegal reflective access by org.apache.flink.api.java.ClosureCleaner (file:/opt/flink/lib/flink-dist-1.15.4.jar) to field java.lang.String.value
WARNING: Please consider reporting this to the maintainers of org.apache.flink.api.java.ClosureCleaner
WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
WARNING: All illegal access operations will be denied in a future release
Job has been submitted with JobID 02d83c46d646aa498a986c0a9335e276
2023-08-08 02:07:23.010:INFO:root:java.util.concurrent.CompletableFuture@34e729a3[Not completed]
```

We can check the submitted job by listing all jobs as shown below.

```bash
$ docker exec jobmanager /opt/flink/bin/flink list
Waiting for response...
------------------ Running/Restarting Jobs -------------------
08.08.2023 02:07:18 : 02d83c46d646aa498a986c0a9335e276 : insert-into_default_catalog.default_database.sink_table (RUNNING)
--------------------------------------------------------------
No scheduled jobs.
```

The Flink Web UI can be accessed on port 8081. In the Overview section, it shows the available task slots, running jobs and completed jobs.

![](cluster-dashboard-01.png#center)

We can inspect an individual job in the Jobs menu. It shows key details about a job execution in *Overview*, *Exceptions*, *TimeLine*, *Checkpoints* and *Configuration* tabs.

![](cluster-dashboard-02.png#center)

We can cancel a job on the web UI or using the CLI. Below shows how to cancel the job we submitted earlier using the CLI.

```bash
$ docker exec jobmanager /opt/flink/bin/flink cancel 02d83c46d646aa498a986c0a9335e276
Cancelling job 02d83c46d646aa498a986c0a9335e276.
Cancelled job 02d83c46d646aa498a986c0a9335e276.
```

## Summary

Apache Flink is widely used for building real-time stream processing applications. On AWS, Kinesis Data Analytics (KDA) is the easiest option to develop a Flink app as it provides the underlying infrastructure. Updating a guide from AWS, this series of posts discuss how to develop and deploy a Flink (Pyflink) application via KDA where the data source and sink are Kafka topics. In part 1, the app was developed locally targeting a Kafka cluster created by Docker. Furthermore, it was executed in a virtual environment as well as in a local Flink cluster for improved monitoring.
