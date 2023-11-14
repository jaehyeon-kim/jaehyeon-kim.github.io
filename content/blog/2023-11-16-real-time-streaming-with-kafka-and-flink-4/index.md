---
title: Real Time Streaming with Kafka and Flink - Lab 3 Transform and write data to S3 from Kafka using Flink
date: 2023-11-16
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
  - Amazon S3
  - Amazon Athena
  - Apache Kafka
  - Apache Flink
  - Pyflink
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
description: In this lab, we will create a Pyflink application that exports Kafka topic messages into a S3 bucket. The app enriches the records by adding a new column using a user defined function and writes them via the FileSystem SQL connector. This allows us to achieve a simpler architecture compared to the original lab where the records are sent into Amazon Kinesis Data Firehose, enriched by a separate Lambda function and written to a S3 bucket afterwards. While the records are being written to the S3 bucket, a Glue table will be created to query them on Amazon Athena.
---

In this lab, we will create a Pyflink application that exports Kafka topic messages into a S3 bucket. The app enriches the records by adding a new column using a user defined function and writes them via the [FileSystem SQL connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/table/filesystem/). This allows us to achieve a simpler architecture compared to the [original lab](https://catalog.us-east-1.prod.workshops.aws/workshops/2300137e-f2ac-4eb9-a4ac-3d25026b235f/en-US/lab-3-kdf) where the records are sent into Amazon Kinesis Data Firehose, enriched by a separate Lambda function and written to a S3 bucket afterwards. While the records are being written to the S3 bucket, a Glue table will be created to query them on Amazon Athena.

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](#) (this post)
* Lab 4 Clean, Aggregate, and Enrich Events with Flink
* Lab 5 Write data to DynamoDB using Kafka Connect
* Lab 6 Consume data from Kafka using Lambda

## Architecture

Fake taxi ride data is sent to a Kafka topic by the Kafka producer application that is discussed in [Lab 1](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2). The records are read by a Pyflink application, and it writes them into a S3 bucket. The app enriches the records by adding a new column named *source* using a user defined function. The records in the S3 bucket can be queried on Amazon Athena after creating an external table that sources the bucket.

![](featured.png#center)

## Infrastructure

### AWS Infrastructure

The AWS infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post - see this [earlier post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details about how to create the resources. The infrastructure can be deployed (as well as destroyed) using Terraform CLI as shown below.

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

Note that deploying the AWS infrastructure is optional because we can create a local Kafka and Flink cluster on Docker for testing easily. We will not use a Kafka cluster deployed on MSK in this post.

### Kafka and Flink Cluster on Docker Compose

In the [previous post](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3), we discussed how to create a local Flink cluster on Docker. We can add additional Docker Compose services (*zookeeper* and *kafka-0*) for a Kafka cluster and the updated compose file can be found below. See [this post](/blog/2023-05-04-kafka-development-with-docker-part-1) for details how to set up a Kafka cluster on Docker.

```yaml
# compose-local-kafka.yml
# see compose-msk.yml for an msk cluster instead of a local kafka cluster
version: "3.5"

services:
  jobmanager:
    image: real-time-streaming-aws:1.17.1
    command: jobmanager
    container_name: jobmanager
    ports:
      - "8081:8081"
    networks:
      - appnet
    volumes:
      - ./:/etc/flink
    environment:
      - BOOTSTRAP_SERVERS=kafka-0:9092
      - RUNTIME_ENV=DOCKER
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      # - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
        rest.flamegraph.enabled: true
        web.backpressure.refresh-interval: 10000
  taskmanager:
    image: real-time-streaming-aws:1.17.1
    command: taskmanager
    container_name: taskmanager
    networks:
      - appnet
    volumes:
      - flink_data:/tmp/
      - ./:/etc/flink
    environment:
      - BOOTSTRAP_SERVERS=kafka-0:9092
      - RUNTIME_ENV=DOCKER
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      # - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 5
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
    depends_on:
      - jobmanager
  zookeeper:
    image: bitnami/zookeeper:3.5
    container_name: zookeeper
    ports:
      - "2181"
    networks:
      - appnet
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
      - appnet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=5
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=1
      - KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kpow:
    image: factorhouse/kpow-ce:91.5.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - appnet
    environment:
      BOOTSTRAP: kafka-0:9092
    env_file: # https://kpow.io/get-started/#individual
      - ./kpow.env
    depends_on:
      - zookeeper
      - kafka-0

networks:
  appnet:
    name: app-network

volumes:
  zookeeper_data:
    driver: local
    name: zookeeper_data
  kafka_0_data:
    driver: local
    name: kafka_0_data
  flink_data:
    driver: local
    name: flink_data
```

The Docker Compose services can be deployed as shown below.

```bash
$ docker-compose -f compose-local-kafka.yml up -d
```

## Pyflink Application

### Flink Pipeline Jar

The application has multiple dependencies and a single Jar file is created so that it can be specified in the `--jarfile` option. Note that we have to build the Jar file based on the [Apache Kafka Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/datastream/kafka/) instead of the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/table/kafka/) because the *MSK IAM Auth* library is not compatible with the latter due to shade relocation. The dependencies can be grouped as shown below.

- Flink Connectors
  - flink-connector-base
  - flink-connector-files
  - flink-connector-kafka
  - *Each of them can be placed in the Flink library folder (/opt/flink/lib)*
- Parquet Format
  - flink-parquet
  - hadoop dependencies
    - parquet-hadoop
    - hadoop-common
    - hadoop-mapreduce-client-core
  - *All of them can be combined as a single Jar file and be placed in the Flink library folder (/opt/flink/lib)*
- Kafka Communication and IAM Authentication
  - kafka-clients
    - for communicating with a Kafka cluster
    - *It can be placed in the Flink library folder (/opt/flink/lib)*
  - aws-msk-iam-auth
    - for IAM authentication
    - *It can be placed in the Flink library folder (/opt/flink/lib)*

A single Jar file is created in this post as the app may need to be deployed via Amazon Managed Flink potentially. If we do not have to deploy on it, however, they can be added to the Flink library folder separately, which is a more comprehensive way of managing dependency in my opinion. I added comments about how they may be placed into the Flink library folder in the dependencies list above. Note that the S3 file system Jar file (*flink-s3-fs-hadoop-1.17.1.jar*) is placed under the plugins (*/opt/flink/plugins/s3-fs-hadoop*) folder of the custom Docker image according to the [Flink documentation](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/deployment/filesystems/overview/).

The single Uber jar file is created by the following POM file and the Jar file is named as *lab3-pipeline-1.0.0.jar*.

```xml
<!-- package/lab3-pipeline/pom.xml -->
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>

	<groupId>com.amazonaws.services.kinesisanalytics</groupId>
	<artifactId>lab3-pipeline</artifactId>
	<version>1.0.0</version>
	<packaging>jar</packaging>

	<name>Uber Jar for Lab 3</name>

	<properties>
		<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
		<flink.version>1.17.1</flink.version>
		<target.java.version>1.11</target.java.version>
		<jdk.version>11</jdk.version>
		<scala.binary.version>2.12</scala.binary.version>
		<kda.connectors.version>2.0.0</kda.connectors.version>
		<kda.runtime.version>1.2.0</kda.runtime.version>
		<kafka.clients.version>3.2.3</kafka.clients.version>
		<hadoop.version>3.2.4</hadoop.version>
		<flink.format.parquet.version>1.12.3</flink.format.parquet.version>
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

		<!-- Flink Connectors -->

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

		<!-- Parquet -->
		<!-- See https://github.com/apache/flink/blob/release-1.17/flink-formats/flink-parquet/pom.xml -->

		<dependency>
			<groupId>org.apache.flink</groupId>
			<artifactId>flink-parquet</artifactId>
			<version>${flink.version}</version>
		</dependency>

		<!-- Hadoop is needed by Parquet -->

		<dependency>
			<groupId>org.apache.parquet</groupId>
			<artifactId>parquet-hadoop</artifactId>
			<version>${flink.format.parquet.version}</version>
			<exclusions>
				<exclusion>
					<groupId>org.xerial.snappy</groupId>
					<artifactId>snappy-java</artifactId>
				</exclusion>
				<exclusion>
					<groupId>commons-cli</groupId>
					<artifactId>commons-cli</artifactId>
				</exclusion>
			</exclusions>
		</dependency>

		<dependency>
			<groupId>org.apache.hadoop</groupId>
			<artifactId>hadoop-common</artifactId>
			<version>${hadoop.version}</version>
			<exclusions>
				<exclusion>
					<groupId>com.google.protobuf</groupId>
					<artifactId>protobuf-java</artifactId>
				</exclusion>
				<exclusion>
					<groupId>ch.qos.reload4j</groupId>
					<artifactId>reload4j</artifactId>
				</exclusion>
				<exclusion>
					<groupId>org.slf4j</groupId>
					<artifactId>slf4j-reload4j</artifactId>
				</exclusion>
				<exclusion>
					<groupId>commons-cli</groupId>
					<artifactId>commons-cli</artifactId>
				</exclusion>
			</exclusions>
		</dependency>

		<dependency>
			<groupId>org.apache.hadoop</groupId>
			<artifactId>hadoop-mapreduce-client-core</artifactId>
			<version>${hadoop.version}</version>
			<exclusions>
				<exclusion>
					<groupId>com.google.protobuf</groupId>
					<artifactId>protobuf-java</artifactId>
				</exclusion>
				<exclusion>
					<groupId>ch.qos.reload4j</groupId>
					<artifactId>reload4j</artifactId>
				</exclusion>
				<exclusion>
					<groupId>org.slf4j</groupId>
					<artifactId>slf4j-reload4j</artifactId>
				</exclusion>
				<exclusion>
					<groupId>commons-cli</groupId>
					<artifactId>commons-cli</artifactId>
				</exclusion>
			</exclusions>
		</dependency>

		<!-- Kafka Client and MSK IAM Auth Lib -->

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

The Uber Jar file can be built using the following script (*build.sh*).

```bash
# build.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
SRC_PATH=$SCRIPT_DIR/package

# remove contents under $SRC_PATH (except for the folders beginging with lab)
shopt -s extglob
rm -rf $SRC_PATH/!(lab*)

## Generate Uber jar file for individual labs
echo "generate Uber jar for PyFlink app..."
mkdir $SRC_PATH/lib
mvn clean install -f $SRC_PATH/lab2-pipeline/pom.xml \
  && mv $SRC_PATH/lab2-pipeline/target/lab2-pipeline-1.0.0.jar $SRC_PATH/lib \
  && rm -rf $SRC_PATH/lab2-pipeline/target

mvn clean install -f $SRC_PATH/lab3-pipeline/pom.xml \
  && mv $SRC_PATH/lab3-pipeline/target/lab3-pipeline-1.0.0.jar $SRC_PATH/lib \
  && rm -rf $SRC_PATH/lab3-pipeline/target
```

### Application Source

Although the Pyflink application uses the [Table API](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/python/table_api_tutorial/), the FileSystem connector completes file writing when [checkpointing](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/datastream/fault-tolerance/checkpointing/) is enabled. Therefore, the app creates a DataStream stream execution environment and enables checkpointing every 60 seconds. Then it creates a table environment, and the source and sink tables are created on it. An additional field named *source* is added to the sink table, and it is obtained by a user defined function (*add_source*). The sink table is partitioned by *year*, *month*, *date* and *hour*.

In the *main* method, we create all the source and sink tables after mapping relevant application properties. Then the output records are written to a S3 bucket. Note that the output records are printed in the terminal additionally when the app is running locally for ease of checking them.

```python
# exporter/processor.py
import os
import re
import json

from pyflink.datastream import StreamExecutionEnvironment, RuntimeExecutionMode
from pyflink.table import StreamTableEnvironment
from pyflink.table.udf import udf

RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "LOCAL")  # LOCAL or DOCKER
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS")  # overwrite app config


env = StreamExecutionEnvironment.get_execution_environment()
env.set_runtime_mode(RuntimeExecutionMode.STREAMING)
env.enable_checkpointing(60000)

if RUNTIME_ENV == "LOCAL":
    CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
    PARENT_DIR = os.path.dirname(CURRENT_DIR)
    APPLICATION_PROPERTIES_FILE_PATH = os.path.join(
        CURRENT_DIR, "application_properties.json"
    )
    JAR_FILES = ["lab3-pipeline-1.0.0.jar"]
    JAR_PATHS = tuple(
        [f"file://{os.path.join(PARENT_DIR, 'jars', name)}" for name in JAR_FILES]
    )
    print(JAR_PATHS)
    env.add_jars(*JAR_PATHS)
else:
    APPLICATION_PROPERTIES_FILE_PATH = "/etc/flink/exporter/application_properties.json"

table_env = StreamTableEnvironment.create(stream_execution_environment=env)
table_env.create_temporary_function(
    "add_source", udf(lambda: "NYCTAXI", result_type="STRING")
)


def get_application_properties():
    if os.path.isfile(APPLICATION_PROPERTIES_FILE_PATH):
        with open(APPLICATION_PROPERTIES_FILE_PATH, "r") as file:
            contents = file.read()
            properties = json.loads(contents)
            return properties
    else:
        raise RuntimeError(
            f"A file at '{APPLICATION_PROPERTIES_FILE_PATH}' was not found"
        )


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


def create_source_table(table_name: str, topic_name: str, bootstrap_servers: str):
    opts = {
        "connector": "kafka",
        "topic": topic_name,
        "properties.bootstrap.servers": bootstrap_servers,
        "properties.group.id": "soruce-group",
        "format": "json",
        "scan.startup.mode": "latest-offset",
    }

    stmt = f"""
    CREATE TABLE {table_name} (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_date         VARCHAR,
        pickup_datetime     AS TO_TIMESTAMP(REPLACE(pickup_date, 'T', ' ')),
        dropoff_date        VARCHAR,
        dropoff_datetime    AS TO_TIMESTAMP(REPLACE(dropoff_date, 'T', ' ')),
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         INT,
        trip_duration       INT,
        google_distance     INT,
        google_duration     INT
    ) WITH (
        {inject_security_opts(opts, bootstrap_servers)}
    )
    """
    print(stmt)
    return stmt


def create_sink_table(table_name: str, file_path: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_datetime     TIMESTAMP,
        dropoff_datetime    TIMESTAMP,
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         INT,
        trip_duration       INT,
        google_distance     INT,
        google_duration     INT,
        source              VARCHAR,
        `year`              VARCHAR,
        `month`             VARCHAR,
        `date`              VARCHAR,
        `hour`              VARCHAR
    ) PARTITIONED BY (`year`, `month`, `date`, `hour`) WITH (
        'connector'= 'filesystem',
        'path' = '{file_path}',
        'format' = 'parquet',
        'sink.partition-commit.delay'='1 h',
        'sink.partition-commit.policy.kind'='success-file'
    )
    """
    print(stmt)
    return stmt


def create_print_table(table_name: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_datetime     TIMESTAMP,
        dropoff_datetime    TIMESTAMP,
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         INT,
        trip_duration       INT,
        google_distance     INT,
        google_duration     INT,
        source              VARCHAR,
        `year`              VARCHAR,
        `month`             VARCHAR,
        `date`              VARCHAR,
        `hour`              VARCHAR
    ) WITH (
        'connector'= 'print'
    )
    """
    print(stmt)
    return stmt


def set_insert_sql(source_table_name: str, sink_table_name: str):
    stmt = f"""
    INSERT INTO {sink_table_name}
    SELECT
        id,
        vendor_id,
        pickup_datetime,
        dropoff_datetime,
        passenger_count,
        pickup_longitude,
        pickup_latitude,
        dropoff_longitude,
        dropoff_latitude,
        store_and_fwd_flag,
        gc_distance,
        trip_duration,
        google_distance,
        google_duration,
        add_source() AS source,
        DATE_FORMAT(pickup_datetime, 'yyyy') AS `year`,
        DATE_FORMAT(pickup_datetime, 'MM') AS `month`,
        DATE_FORMAT(pickup_datetime, 'dd') AS `date`,
        DATE_FORMAT(pickup_datetime, 'HH') AS `hour`
    FROM {source_table_name}
    """
    print(stmt)
    return stmt


def main():
    #### map source/sink properties
    props = get_application_properties()
    ## source
    source_property_group_key = "source.config.0"
    source_properties = property_map(props, source_property_group_key)
    print(">> source properties")
    print(source_properties)
    source_table_name = source_properties["table.name"]
    source_topic_name = source_properties["topic.name"]
    source_bootstrap_servers = (
        BOOTSTRAP_SERVERS or source_properties["bootstrap.servers"]
    )
    ## sink
    sink_property_group_key = "sink.config.0"
    sink_properties = property_map(props, sink_property_group_key)
    print(">> sink properties")
    print(sink_properties)
    sink_table_name = sink_properties["table.name"]
    sink_file_path = sink_properties["file.path"]
    ## print
    print_table_name = "sink_print"
    #### create tables
    table_env.execute_sql(
        create_source_table(
            source_table_name, source_topic_name, source_bootstrap_servers
        )
    )
    table_env.execute_sql(create_sink_table(sink_table_name, sink_file_path))
    table_env.execute_sql(create_print_table(print_table_name))
    #### insert into sink tables
    if RUNTIME_ENV == "LOCAL":
        statement_set = table_env.create_statement_set()
        statement_set.add_insert_sql(set_insert_sql(source_table_name, sink_table_name))
        statement_set.add_insert_sql(set_insert_sql(print_table_name, sink_table_name))
        statement_set.execute().wait()
    else:
        table_result = table_env.execute_sql(
            set_insert_sql(source_table_name, sink_table_name)
        )
        print(table_result.get_job_client().get_job_status())


if __name__ == "__main__":
    main()
```

```json
// exporter/application_properties.json
[
  {
    "PropertyGroupId": "kinesis.analytics.flink.run.options",
    "PropertyMap": {
      "python": "processor.py",
      "jarfile": "package/lib/lab3-pipeline-1.0.0.jar"
    }
  },
  {
    "PropertyGroupId": "source.config.0",
    "PropertyMap": {
      "table.name": "taxi_rides_src",
      "topic.name": "taxi-rides",
      "bootstrap.servers": "localhost:29092"
    }
  },
  {
    "PropertyGroupId": "sink.config.0",
    "PropertyMap": {
      "table.name": "taxi_rides_sink",
      "file.path": "s3://<s3-bucket-name-to-replace>/taxi-rides/"
    }
  }
]
```

### Run Application

#### Execute on Local Flink Cluster

We can run the application in the Flink cluster on Docker and the steps are shown below. Either the Kafka cluster on Amazon MSK or a local Kafka cluster can be used depending on which Docker Compose file we use. In either way, we can check the job details on the Flink web UI on *localhost:8081*. Note that, if we use the local Kafka cluster option, we have to start the producer application in a different terminal.

```bash
## prep - update s3 bucket name in loader/application_properties.json

## set aws credentials environment variables
export AWS_ACCESS_KEY_ID=<aws-access-key-id>
export AWS_SECRET_ACCESS_KEY=<aws-secret-access-key>
# export AWS_SESSION_TOKEN=<aws-session-token>

## run docker compose service
# with local kafka cluster
docker-compose -f compose-local-kafka.yml up -d
# # or with msk cluster
# docker-compose -f compose-msk.yml up -d

## run the producer application in another terminal
# python producer/app.py 

## submit pyflink application
docker exec jobmanager /opt/flink/bin/flink run \
    --python /etc/flink/exporter/processor.py \
    --jarfile /etc/flink/package/lib/lab3-pipeline-1.0.0.jar \
    -d
```

![](flink-job.png#center)

### Application Result

#### Kafka Topic

We can see the topic (*taxi-rides*) is created, and the details of the topic can be found on the *Topics* menu on *localhost:3000*.

![](kafka-topic.png#center)

Also, we can inspect topic messages in the *Data* tab as shown below.

![](kafka-message.png#center)

#### S3 Files

We can see the Pyflink app writes the records into the S3 bucket as expected. The files are written in Apache Hive style partitions and only completed files are found. Note that, when I tested the sink connector on the local file system, the file names of *in-progress* and *pending* files begin with dot (.) and the dot is removed when they are completed. I don't see those incomplete files in the S3 bucket, and it seems that only completed files are moved. Note also that, as the checkpoint interval is set to 60 seconds, new files are created every minute. We can adjust the interval if it creates too many small files.

![](s3-files.png#center)

#### Athena Table

To query the output records, we can create a partitioned table on Amazon Athena by specifying the S3 location. It can be created by executing the following SQL statement.

```sql
CREATE EXTERNAL TABLE taxi_rides (
    id                  STRING,
    vendor_id           INT,
    pickup_datetime     TIMESTAMP,
    dropoff_datetime    TIMESTAMP,
    passenger_count     INT,
    pickup_longitude    STRING,
    pickup_latitude     STRING,
    dropoff_longitude   STRING,
    dropoff_latitude    STRING,
    store_and_fwd_flag  STRING,
    gc_distance         INT,
    trip_duration       INT,
    google_distance     INT,
    google_duration     INT,
    source              STRING
) 
PARTITIONED BY (year STRING, month STRING, date STRING, hour STRING)
STORED AS parquet
LOCATION 's3://real-time-streaming-ap-southeast-2/taxi-rides/';
```

Then we can [add the existing partition](https://docs.aws.amazon.com/athena/latest/ug/msck-repair-table.html) by updating the metadata in the catalog i.e. run `MSCK REPAIR TABLE taxi_rides;`.

```bash
Partitions not in metastore:	taxi_rides:year=2023/month=11/date=14/hour=15
Repair: Added partition to metastore taxi_rides:year=2023/month=11/date=14/hour=15
```

After the partition is added, we can query the records as shown below.

![](athena-query.png#center)

## Summary

In this lab, we created a Pyflink application that exports Kafka topic messages into a S3 bucket. The app enriched the records by adding a new column using a user defined function and wrote them via the FileSystem SQL connector. While the records were being written to the S3 bucket, a Glue table was created to query them on Amazon Athena.