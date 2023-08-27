---
title: Getting Started with Pyflink on AWS - Part 2 Local Flink and MSK
date: 2023-08-28
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
  - Apache Kafka
  - Amazon Kinesis Data Analytics
  - Amazon MSK
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: In this series of posts, we discuss a Flink (Pyflink) application that reads/writes from/to Kafka topics. In part 1, an app that targets a local Kafka cluster was created. In this post, we will update the app by connecting a Kafka cluster on Amazon MSK. The Kafka cluster is authenticated by IAM and the app has additional jar dependency. As Kinesis Data Analytics (KDA) does not allow you to specify multiple pipeline jar files, we have to build a custom Uber Jar that combines multiple jar files. Same as part 1, the app will be executed in a virtual environment as well as in a local Flink cluster for improved monitoring with the updated pipeline jar file.
---

In this series of posts, we discuss a Flink (Pyflink) application that reads/writes from/to Kafka topics. In part 1, an app that targets a local Kafka cluster was created. In this post, we will update the app by connecting a Kafka cluster on Amazon MSK. The Kafka cluster is authenticated by IAM and the app has additional jar dependency. As Kinesis Data Analytics (KDA) does not allow you to specify multiple pipeline jar files, we have to build a custom Uber Jar that combines multiple jar files. Same as part 1, the app will be executed in a virtual environment as well as in a local Flink cluster for improved monitoring with the updated pipeline jar file.

* [Part 1 Local Flink and Local Kafka](/blog/2023-08-17-getting-started-with-pyflink-on-aws-part-1)
* [Part 2 Local Flink and MSK](#) (this post)
* Part 3 KDA and MSK

## Architecture

The Python source data generator sends random stock price records into a Kafka topic. The messages in the source topic are consumed by a Flink application, and it just writes those messages into a different sink topic. As the Kafka cluster is deployed in private subnets, it is accessed via a VPN server from the developer machine. This is the simplest application of the AWS guide, and you may try [other examples](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples) if interested.

![](featured.png#center)

## Infrastructure

A Kafka cluster is created on Amazon MSK using Terraform, and the cluster is secured by IAM access control. Similar to part 1, the Python apps including the Flink app run in a virtual environment in the first trial. After that the Flink app is submitted to a local Flink cluster for improved monitoring. Same as part 1, the Flink cluster is created using Docker. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/pyflink-getting-started-on-aws/remote) of this post.

### Preparation

#### Flink Pipeline Jar

The Flink application should be able to connect a Kafka cluster on Amazon MSK, and we used the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) artifact (*flink-sql-connector-kafka-1.15.2.jar*) in part 1. The Kafka cluster is authenticated by IAM, however, it should be able to refer to the [Amazon MSK Library for AWS Identity and Access Management (MSK IAM Auth)](https://github.com/aws/aws-msk-iam-auth). So far KDA does not allow you to specify multiple [pipeline jar](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/dependency_management/) files, and we have to build a single Jar file (Uber Jar) that includes all the dependencies of the application. Moreover, as the *MSK IAM Auth* library is not compatible with the *Apache Kafka SQL Connector* due to shade relocation, we have to build the Jar file based on the [Apache Kafka Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/datastream/kafka/) instead. After some search, I found an example from the [Blueprints: Kinesis Data Analytics for Apache Flink](https://github.com/aws-samples/amazon-kinesis-data-analytics-blueprints/tree/main/apps/python-table-api/msk-serverless-to-s3-tableapi-python/src/uber-jar-for-pyflink) and was able to modify the POM file with necessary dependencies for this post. The modified POM file can be shown below, and it creates the Uber Jar for this post - *pyflink-getting-started-1.0.0.jar*.

```xml
<!--package/uber-jar-for-pyflink/pom.xml-->
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>

	<groupId>com.amazonaws.services.kinesisanalytics</groupId>
	<artifactId>pyflink-getting-started</artifactId>
	<version>1.0.0</version>
	<packaging>jar</packaging>

	<name>Uber Jar for PyFlink App</name>

	<properties>
		<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
		<flink.version>1.15.2</flink.version>
		<target.java.version>1.11</target.java.version>
		<jdk.version>11</jdk.version>
		<scala.binary.version>2.12</scala.binary.version>
		<kda.connectors.version>2.0.0</kda.connectors.version>
		<kda.runtime.version>1.2.0</kda.runtime.version>
		<kafka.clients.version>2.8.1</kafka.clients.version>
		<log4j.version>2.17.1</log4j.version>
		<aws-msk-iam-auth.version>1.1.7</aws-msk-iam-auth.version>
	</properties>

	<repositories>
		<repository>
			<id>apache.snapshots</id>
			<name>Apache Development Snapshot Repository</name>
			<url>https://repository.apache.org/content/repositories/snapshots/</url>
			<releases>
				<enabled>false</enabled>
			</releases>
			<snapshots>
				<enabled>true</enabled>
			</snapshots>
		</repository>
	</repositories>

	<dependencies>

		<dependency>
			<groupId>org.apache.flink</groupId>
			<artifactId>flink-connector-base</artifactId>
			<version>${flink.version}</version>
		</dependency>

		<dependency>
			<groupId>org.apache.flink</groupId>
			<artifactId>flink-connector-kafka</artifactId>
			<version>${flink.version}</version>
		</dependency>

		<dependency>
			<groupId>org.apache.flink</groupId>
			<artifactId>flink-connector-files</artifactId>
			<version>${flink.version}</version>
		</dependency>

		<dependency>
			<groupId>org.apache.kafka</groupId>
			<artifactId>kafka-clients</artifactId>
			<version>${kafka.clients.version}</version>
		</dependency>

		<dependency>
			<groupId>software.amazon.msk</groupId>
			<artifactId>aws-msk-iam-auth</artifactId>
			<version>${aws-msk-iam-auth.version}</version>
		</dependency>

		<!-- Add logging framework, to produce console output when running in the IDE. -->
		<!-- These dependencies are excluded from the application JAR by default. -->
		<dependency>
			<groupId>org.apache.logging.log4j</groupId>
			<artifactId>log4j-slf4j-impl</artifactId>
			<version>${log4j.version}</version>
			<scope>runtime</scope>
		</dependency>
		<dependency>
			<groupId>org.apache.logging.log4j</groupId>
			<artifactId>log4j-api</artifactId>
			<version>${log4j.version}</version>
			<scope>runtime</scope>
		</dependency>
		<dependency>
			<groupId>org.apache.logging.log4j</groupId>
			<artifactId>log4j-core</artifactId>
			<version>${log4j.version}</version>
			<scope>runtime</scope>
		</dependency>
	</dependencies>

	<build>
		<plugins>

			<!-- Java Compiler -->
			<plugin>
				<groupId>org.apache.maven.plugins</groupId>
				<artifactId>maven-compiler-plugin</artifactId>
				<version>3.8.0</version>
				<configuration>
					<source>${jdk.version}</source>
					<target>${jdk.version}</target>
				</configuration>
			</plugin>

			<!-- We use the maven-shade plugin to create a fat jar that contains all necessary dependencies. -->
			<!-- Change the value of <mainClass>...</mainClass> if your program entry point changes. -->
			<plugin>
				<groupId>org.apache.maven.plugins</groupId>
				<artifactId>maven-shade-plugin</artifactId>
				<version>3.4.1</version>
				<executions>
					<!-- Run shade goal on package phase -->
					<execution>
						<phase>package</phase>
						<goals>
							<goal>shade</goal>
						</goals>
						<configuration>
							<artifactSet>
								<excludes>
									<exclude>org.apache.flink:force-shading</exclude>
									<exclude>com.google.code.findbugs:jsr305</exclude>
									<exclude>org.slf4j:*</exclude>
									<exclude>org.apache.logging.log4j:*</exclude>
								</excludes>
							</artifactSet>
							<filters>
								<filter>
									<!-- Do not copy the signatures in the META-INF folder.
									Otherwise, this might cause SecurityExceptions when using the JAR. -->
									<artifact>*:*</artifact>
									<excludes>
										<exclude>META-INF/*.SF</exclude>
										<exclude>META-INF/*.DSA</exclude>
										<exclude>META-INF/*.RSA</exclude>
									</excludes>
								</filter>
							</filters>
							<transformers>
								<transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
							</transformers>
						</configuration>
					</execution>
				</executions>
			</plugin>
		</plugins>

		<pluginManagement>
			<plugins>

				<!-- This improves the out-of-the-box experience in Eclipse by resolving some warnings. -->
				<plugin>
					<groupId>org.eclipse.m2e</groupId>
					<artifactId>lifecycle-mapping</artifactId>
					<version>1.0.0</version>
					<configuration>
						<lifecycleMappingMetadata>
							<pluginExecutions>
								<pluginExecution>
									<pluginExecutionFilter>
										<groupId>org.apache.maven.plugins</groupId>
										<artifactId>maven-shade-plugin</artifactId>
										<versionRange>[3.1.1,)</versionRange>
										<goals>
											<goal>shade</goal>
										</goals>
									</pluginExecutionFilter>
									<action>
										<ignore/>
									</action>
								</pluginExecution>
								<pluginExecution>
									<pluginExecutionFilter>
										<groupId>org.apache.maven.plugins</groupId>
										<artifactId>maven-compiler-plugin</artifactId>
										<versionRange>[3.1,)</versionRange>
										<goals>
											<goal>testCompile</goal>
											<goal>compile</goal>
										</goals>
									</pluginExecutionFilter>
									<action>
										<ignore/>
									</action>
								</pluginExecution>
							</pluginExecutions>
						</lifecycleMappingMetadata>
					</configuration>
				</plugin>
			</plugins>
		</pluginManagement>
	</build>
</project>
```

The following script (*build.sh*) builds to create the Uber Jar file for this post, followed by downloading the *kafka-python* package and creating a zip file that can be used to deploy the Flink app via KDA. Although the Flink app does not need the package, it is added in order to check if `--pyFiles` option works when submitting the app to a Flink cluster or deploying via KDA. The zip package file will be used for KDA deployment in the next post.


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

Once completed, the Uber Jar file and python package can be found in the *lib* and *site_packages* folders respectively as shown below.

![](source-folders.png#center)

### VPC and VPN

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) (*remote/vpc.tf*). Also, a [SoftEther VPN](https://www.softether.org/) server is deployed in order to access the resources in the private subnets from the developer machine (*remote/vpn.tf*). It is particularly useful to monitor and manage the MSK cluster and Kafka topic locally. The details about how to configure the VPN server can be found in an [earlier post](/blog/2022-02-06-dev-infra-terraform).

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

### Kafka Management App

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

### Flink Cluster

We can create a Flink cluster using the custom Docker image that we used in [part 1](/blog/2023-08-17-getting-started-with-pyflink-on-aws-part-1). The cluster is made up of a single Job Manger and Task Manager, and the cluster runs in the [Session Mode](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/deployment/overview/) where one or more Flink applications can be submitted/executed simultaneously. See [this page](https://nightlies.apache.org/flink/flink-docs-master/docs/deployment/resource-providers/standalone/docker/#flink-with-docker-compose) for details about how to create a Flink cluster using *docker-compose*.

A set of environment variables are configured to adjust the application behaviour and to give permission to read/write messages from the Kafka cluster with IAM authentication. The *RUNTIME_ENV* is set to *DOCKER*, and it determines which pipeline jar and application property file to choose. Also, the *BOOTSTRAP_SERVERS* overrides the Kafka bootstrap server address value from the application property file. The bootstrap server address of the MSK cluster are referred from the host environment variable that has the same name. Finally, the current directory is volume-mapped into */etc/flink* so that the application and related resources can be available in the Flink cluster.

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
      - flinknet
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
      - BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
    volumes:
      - $PWD:/etc/flink
  taskmanager:
    image: pyflink:1.15.2-scala_2.12
    container_name: taskmanager
    command: taskmanager
    networks:
      - flinknet
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
      - BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
    depends_on:
      - jobmanager

networks:
  flinknet:
    name: flink-network

volumes:
  flink_data:
    driver: local
    name: flink_data
```

### Virtual Environment

As mentioned earlier, all Python apps run in a virtual environment, and we have the following pip packages. We use the version 1.15.2 of the [apache-flink](https://pypi.org/project/apache-flink/) package because it is the latest supported version by KDA. We also need the [kafka-python](https://pypi.org/project/kafka-python/) package for source data generation. As the Kafka cluster is IAM-authenticated, a patched version is installed instead of the stable version. The pip packages can be installed by `pip install -r requirements-dev.txt`.

```txt
# kafka-python with IAM auth support - https://github.com/dpkp/kafka-python/pull/2255
https://github.com/mattoberle/kafka-python/archive/7ff323727d99e0c33a68423300e7f88a9cf3f830.tar.gz

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

A Kafka producer is created as an attribute of the *Producer* class. The producer adds security configuration for IAM authentication when the bootstrap server address ends with *9098*. The source records are sent into the relevant topic by the *send* method. Note that both the key and value of the messages are serialized as json.

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
import re
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
        params = {
            "bootstrap_servers": self.bootstrap_servers,
            "key_serializer": lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            "value_serializer": lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            "api_version": (2, 8, 1),
        }
        if re.search("9098$", self.bootstrap_servers[0]):
            params = {
                **params,
                **{"security_protocol": "SASL_SSL", "sasl_mechanism": "AWS_MSK_IAM"},
            }
        return KafkaProducer(**params)

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

The Flink application is built using the [Table API](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/dev/python/table_api_tutorial/). We have two Kafka topics - one for the source and the other for the sink. Simply put, we can manipulate the records of the topics as tables of unbounded real-time streams with the Table API. In order to read/write records from/to a Kafka topic where the cluster is IAM authenticated, we need to specify the custom Uber Jar that we created earlier - *pyflink-getting-started-1.0.0.jar*. Note we only need to configure the connector jar when we develop the app locally as the jar file will be specified by the `--jarfile` option when submitting it to a Flink cluster or deploying via KDA. We also need the application properties file (*application_properties.json*) in order to be comparable with KDA. The file contains the Flink runtime options in KDA as well as application specific properties. All the properties should be specified when deploying via KDA and, for local development, we keep them as a json file and only the application specific properties are used.

The tables for the source and output topics can be created using SQL with options that are related to the Kafka connector. Key options cover the connector name (*connector*), topic name (*topic*), bootstrap server address (*properties.bootstrap.servers*) and format (*format*). See the [connector document](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/) for more details about the connector configuration. Note that the security options of the tables are updated for IAM authentication when the bootstrap server argument ends with *9098* using the *inject_security_opts* function. When it comes to inserting the source records into the output table, we can use either SQL or built-in *add_insert* method.

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
    PIPELINE_JAR = "pyflink-getting-started-1.0.0.jar"
    # PIPELINE_JAR = "uber-jar-for-pyflink-1.0.1.jar"
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


def inject_security_opts(opts: dict, bootstrap_servers: str):
    if re.search("9098$", bootstrap_servers):
        opts = {
            **opts,
            **{
                "properties.security.protocol": "SASL_SSL",
                "properties.sasl.mechanism": "AWS_MSK_IAM",
                "properties.sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
                "properties.sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
            },
        }
    return ", ".join({f"'{k}' = '{v}'" for k, v in opts.items()})


def create_source_table(
    table_name: str, topic_name: str, bootstrap_servers: str, startup_mode: str
):
    opts = {
        "connector": "kafka",
        "topic": topic_name,
        "properties.bootstrap.servers": bootstrap_servers,
        "properties.group.id": "soruce-group",
        "format": "json",
        "scan.startup.mode": startup_mode,
    }
    stmt = f"""
    CREATE TABLE {table_name} (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        {inject_security_opts(opts, bootstrap_servers)}
    )
    """
    logging.info("source table statement...")
    logging.info(stmt)
    return stmt


def create_sink_table(table_name: str, topic_name: str, bootstrap_servers: str):
    opts = {
        "connector": "kafka",
        "topic": topic_name,
        "properties.bootstrap.servers": bootstrap_servers,
        "format": "json",
        "key.format": "json",
        "key.fields": "ticker",
        "properties.allow.auto.create.topics": "true",
    }
    stmt = f"""
    CREATE TABLE {table_name} (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        {inject_security_opts(opts, bootstrap_servers)}
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
      "jarfile": "package/lib/pyflink-getting-started-1.0.0.jar",
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
  --jarfile /etc/flink/package/lib/pyflink-getting-started-1.0.0.jar \
  --pyFiles /etc/flink/package/site_packages/ \
  -d
2023-08-08 04:21:48.198:INFO:root:runtime environment - DOCKER...
2023-08-08 04:21:49.187:INFO:root:app properties file path - /etc/flink/application_properties.json
2023-08-08 04:21:49.187:INFO:root:source table statement...
2023-08-08 04:21:49.187:INFO:root:
    CREATE TABLE source_table (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;', 'scan.startup.mode' = 'earliest-offset', 'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler', 'connector' = 'kafka', 'properties.bootstrap.servers' = 'b-1.kdagettingstarted.j92edp.c3.kafka.ap-southeast-2.amazonaws.com:9098,b-2.kdagettingstarted.j92edp.c3.kafka.ap-southeast-2.amazonaws.com:9098', 'properties.sasl.mechanism' = 'AWS_MSK_IAM', 'format' = 'json', 'properties.security.protocol' = 'SASL_SSL', 'topic' = 'stocks-in', 'properties.group.id' = 'soruce-group'
    )
    
2023-08-08 04:21:49.301:INFO:root:sint table statement...
2023-08-08 04:21:49.301:INFO:root:
    CREATE TABLE sink_table (
        event_time TIMESTAMP(3),
        ticker VARCHAR(6),
        price DOUBLE
    )
    WITH (
        'topic' = 'stocks-out', 'key.fields' = 'ticker', 'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;', 'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler', 'key.format' = 'json', 'connector' = 'kafka', 'properties.bootstrap.servers' = 'b-1.kdagettingstarted.j92edp.c3.kafka.ap-southeast-2.amazonaws.com:9098,b-2.kdagettingstarted.j92edp.c3.kafka.ap-southeast-2.amazonaws.com:9098', 'properties.allow.auto.create.topics' = 'true', 'properties.sasl.mechanism' = 'AWS_MSK_IAM', 'format' = 'json', 'properties.security.protocol' = 'SASL_SSL'
    )
    
WARNING: An illegal reflective access operation has occurred
WARNING: Illegal reflective access by org.apache.flink.api.java.ClosureCleaner (file:/opt/flink/lib/flink-dist-1.15.4.jar) to field java.lang.String.value
WARNING: Please consider reporting this to the maintainers of org.apache.flink.api.java.ClosureCleaner
WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
WARNING: All illegal access operations will be denied in a future release
Job has been submitted with JobID 4827bc6fbafd8b628a26f1095dfc28f9
2023-08-08 04:21:56.327:INFO:root:java.util.concurrent.CompletableFuture@2da94b9a[Not completed]
```

We can check the submitted job by listing all jobs as shown below.

```bash
$ docker exec jobmanager /opt/flink/bin/flink list
Waiting for response...
------------------ Running/Restarting Jobs -------------------
08.08.2023 04:21:52 : 4827bc6fbafd8b628a26f1095dfc28f9 : insert-into_default_catalog.default_database.sink_table (RUNNING)
--------------------------------------------------------------
No scheduled jobs.
```

The Flink Web UI can be accessed on port 8081. In the Overview section, it shows the available task slots, running jobs and completed jobs.

![](cluster-dashboard-01.png#center)

We can inspect an individual job in the Jobs menu. It shows key details about a job execution in *Overview*, *Exceptions*, *TimeLine*, *Checkpoints* and *Configuration* tabs.

![](cluster-dashboard-02.png#center)

We can cancel a job on the web UI or using the CLI. Below shows how to cancel the job we submitted earlier using the CLI.

```bash
$ docker exec jobmanager /opt/flink/bin/flink cancel 4827bc6fbafd8b628a26f1095dfc28f9
Cancelling job 4827bc6fbafd8b628a26f1095dfc28f9.
Cancelled job 4827bc6fbafd8b628a26f1095dfc28f9.
```

## Summary

In this post, we updated the Pyflink app developed in part 1 by connecting a Kafka cluster on Amazon MSK. The Kafka cluster is authenticated by IAM and the app has additional jar dependency. As Kinesis Data Analytics (KDA) does not allow you to specify multiple pipeline jar files, we had to build a custom Uber Jar that combines multiple jar files. Same as part 1, the app was executed in a virtual environment as well as in a local Flink cluster for improved monitoring with the updated pipeline jar file.