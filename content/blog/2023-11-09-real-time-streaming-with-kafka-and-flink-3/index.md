---
title: Real Time Streaming with Kafka and Flink - Lab 2 Write data to Kafka from S3 using Flink
date: 2023-11-09
draft: true
featured: false
comment: true
toc: false
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
  - Apache Kafka
  - Apache Flink
  - Pyflink
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
cevo: 35
docs: https://docs.google.com/document/d/1noUCJwNq9LCQRbW58axYjpn8L8ICSseLizVS-744WoE
description: In this lab, we will create a Pyflink application that reads records from S3 and sends them into a Kafka topic. We can assume the S3 data is static metadata that needs to be joined into a stream, and this exercise can be useful for data enrichment.
---

**[This article](https://cevo.com.au/post/real-time-streaming-with-kafka-and-flink-3/) was originally posted on Tech Insights of [Cevo Australia](https://cevo.com.au/).**

In this lab, we will create a Pyflink application that reads records from S3 and sends them into a Kafka topic. We can assume the S3 data is static metadata that needs to be joined into a stream, and this exercise can be useful for data enrichment.

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](#) (this post)
* Lab 3 Transform and write data to S3 from Kafka using Flink
* Lab 4 Clean, Aggregate, and Enrich Events with Flink
* Lab 5 Write data to DynamoDB using Kafka Connect
* Lab 6 Consume data from Kafka using Lambda

[**Update 2023-11-06**] Initially I planned to deploy Pyflink applications on [Amazon Managed Service for Apache Flink](https://aws.amazon.com/managed-service-apache-flink/), but I changed the plan to use a local Flink cluster deployed on Docker. The main reasons are

1. It is not clear how to configure a Pyflink application for the managed service. For example, Apache Flink supports [pluggable file systems](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/deployment/filesystems/overview/) and the required dependency (eg *flink-s3-fs-hadoop-1.15.2.jar*) should be placed under the *plugins* folder. However, the sample Pyflink applications from [pyflink-getting-started](https://github.com/aws-samples/pyflink-getting-started/tree/main/pyflink-examples/StreamingFileSink) and [amazon-kinesis-data-analytics-blueprints](https://github.com/aws-samples/amazon-kinesis-data-analytics-blueprints/tree/main/apps/python-table-api/msk-serverless-to-s3-tableapi-python) either ignore the S3 jar file for deployment or package it together with other dependencies - *none of them uses the S3 jar file as a plugin*. I tried multiple different configurations, but all ended up with having an error whose code is *CodeError.InvalidApplicationCode*. I don't have such an issue when I deployed the app on a local Flink cluster and I haven't found a way to configure the app for the managed service as yet.
2. The Pyflink app for *Lab 4* requires the OpenSearch sink connector and the connector is available on *1.16.0+*. However, the latest Flink version of the managed service is still *1.15.2* and the sink connector is not available on it. Normally the latest version of the managed service is behind two minor versions of the official release, but it seems to take a little longer to catch up at the moment as the version 1.18.0 was released a while ago.

## Architecture

Sample taxi ride data is stored in a S3 bucket, and a Pyflink application reads and ingests it into a Kafka topic on Amazon MSK. As [Apache Flink](https://flink.apache.org/) supports both stream and batch processing, we are able to process static data without an issue. We can assume the S3 data is static metadata that needs to be joined into a stream, and this exercise can be useful for data enrichment.

![](featured.png#center)

## Infrastructure

The AWS infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post - see the [previous post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details especially. The infrastructure can be deployed (as well as destroyed) using Terraform CLI as shown below. 

```bash
# initialize
$ terraform init
# create an execution plan
$ terraform plan
# execute the actions proposed in a Terraform plan
$ terraform apply -auto-approve=true

# # destroy all remote objects
# $ terraform destroy -auto-approve=true
```

### Flink Cluster on Docker

#### Docker Image with Python and Pyflink

The [official Flink docker image](https://hub.docker.com/_/flink) doesn't include Python and the Pyflink package, and we need to build a custom image from it. Beginning with placing the S3 jar file (*flink-s3-fs-hadoop-1.15.2.jar*) under the *plugins* folder, it installs Python and the Pyflink package. It can be built as following.

```bash
$ docker build -t=real-time-streaming-aws:1.17.1 .
```

```dockerfile
# Dockerfile
FROM flink:1.17.1

ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION:-3.8.10}
ARG FLINK_VERSION
ENV FLINK_VERSION=${FLINK_VERSION:-1.17.1}

RUN mkdir ./plugins/s3-fs-hadoop \
  && cp ./opt/flink-s3-fs-hadoop-${FLINK_VERSION}.jar ./plugins/s3-fs-hadoop 

RUN apt-get update -y && \
  apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev libffi-dev liblzma-dev && \
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

#### Flink Cluster on Docker Compose

The docker compose file includes services for a Flink cluster and [Kpow Community Edition](https://docs.kpow.io/ce/). For the Flink cluster, each of a single master container (*jobmanager*) and task container (*taskmanager*) is created. The former runs the job *Dispatcher* and *ResourceManager* while *TaskManager* is run in the latter. Once a Flink app (job) is submitted to the *Dispatcher*, it starts a *JobManager* thread and provides the *JobGraph* for execution. The *JobManager* requests the necessary processing slots from the *ResourceManager* and deploys the job for execution once the requested slots have been received.

Kafka bootstrap server addresses and AWS credentials are required for the Flink cluster and kpow app and they are specified as environment variables. The bootstrap server addresses can be obtained via terraform (`terraform output -json | jq -r '.msk_bootstrap_brokers_sasl_iam.value'`) or from AWS Console.

Finally, see the [previous post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details about how to configure the *kpow* app.

```yaml
# compose-msk.yml
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
      - ./loader:/etc/flink
      - ./package:/etc/package
    environment:
      - BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
      - RUNTIME_ENV=DOCKER
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
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
      - ./loader:/etc/flink
      - ./package:/etc/package
    environment:
      - BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
      - RUNTIME_ENV=DOCKER
      - AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
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
  kpow:
    image: factorhouse/kpow-ce:91.5.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - appnet
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
  appnet:
    name: app-network

volumes:
  flink_data:
    driver: local
    name: flink_data
```

The Docker Compose services can be deployed as shown below.

```bash
$ docker-compose -f compose-msk.yml up -d
```

## Pyflink Application

### Flink Pipeline Jar

We are going to include all dependent Jar files with the `--jarfile` option, and it only accepts a single Jar file. Therefore, we have to create a custom Uber jar file that consolidates all dependent Jar files. On top of the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/table/kafka/), we also need the [Amazon MSK Library for AWS Identity and Access Management (MSK IAM Auth)](https://github.com/aws/aws-msk-iam-auth) as the MSK cluster is authenticated via IAM. Note that, as the *MSK IAM Auth* library is not compatible with the *Apache Kafka SQL Connector* due to shade relocation, we have to build the Jar file based on the [Apache Kafka Connector](https://nightlies.apache.org/flink/flink-docs-release-1.15/docs/connectors/datastream/kafka/) instead. After some search, I found an example from the [amazon-kinesis-data-analytics-blueprints](https://github.com/aws-samples/amazon-kinesis-data-analytics-blueprints/tree/main/apps/python-table-api/msk-serverless-to-s3-tableapi-python/src/uber-jar-for-pyflink) and was able to modify the POM file with necessary dependencies for this post. The modified POM file can be shown below, and it creates the Uber Jar for this post - *pyflink-pipeline-1.0.0.jar*.

```xml
<!-- package/pyflink-pipeline/pom.xml -->
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>

	<groupId>com.amazonaws.services.kinesisanalytics</groupId>
	<artifactId>pyflink-pipeline</artifactId>
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

The Uber Jar file can be built using the following script (*build.sh*).

```bash
# build.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
SRC_PATH=$SCRIPT_DIR/package

# remove contents under $SRC_PATH (except for pyflink-pipeline)
shopt -s extglob
rm -rf $SRC_PATH/!(pyflink-pipeline)

## Generate Uber Jar for PyFlink app for MSK cluster with IAM authN
echo "generate Uber jar for PyFlink app..."
mkdir $SRC_PATH/lib
mvn clean install -f $SRC_PATH/pyflink-pipeline/pom.xml \
  && mv $SRC_PATH/pyflink-pipeline/target/pyflink-pipeline-1.0.0.jar $SRC_PATH/lib \
  && rm -rf $SRC_PATH/pyflink-pipeline/target
```

### Application Source

<!-- KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE


Caused by: org.apache.kafka.common.errors.TimeoutException: Topic taxi-trip not present in metadata after 60000 ms.

venv/lib/python3.8/site-packages/pyflink/lib/flink-s3-fs-hadoop-1.17.1.jar

docker-compose -f compose-msk.yml up -d -->

```python
# loader/processor.py
import os
import re
import json

from pyflink.table import EnvironmentSettings, TableEnvironment

RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "LOCAL")  # LOCAL or DOCKER
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS")  # overwrite app config

env_settings = EnvironmentSettings.in_streaming_mode()
table_env = TableEnvironment.create(env_settings)

if RUNTIME_ENV == "LOCAL":
    CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
    PARENT_DIR = os.path.dirname(CURRENT_DIR)
    PIPELINE_JAR = "pyflink-pipeline-1.0.0.jar"
    APPLICATION_PROPERTIES_FILE_PATH = os.path.join(CURRENT_DIR, "application_properties.json")
    print(f"file://{os.path.join(PARENT_DIR, 'package', 'lib', PIPELINE_JAR)}")
    table_env.get_config().set(
        "pipeline.jars",
        f"file://{os.path.join(PARENT_DIR, 'package', 'lib', PIPELINE_JAR)}",
    )
else:
    APPLICATION_PROPERTIES_FILE_PATH = "/etc/flink/application_properties.json"


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


def create_source_table(table_name: str, file_path: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_datetime     VARCHAR,
        dropoff_datetime    VARCHAR,
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         DOUBLE,
        trip_duration       INT,
        google_distance     VARCHAR,
        google_duration     VARCHAR
    ) WITH (
        'connector'= 'filesystem',
        'format' = 'csv',
        'path' = '{file_path}'
    )
    """
    print(stmt)
    return stmt


def create_sink_table(table_name: str, topic_name: str, bootstrap_servers: str):
    opts = {
        "connector": "kafka",
        "topic": topic_name,
        "properties.bootstrap.servers": bootstrap_servers,
        "format": "json",
        "key.format": "json",
        "key.fields": "id",
        "properties.allow.auto.create.topics": "true",
    }

    stmt = f"""
    CREATE TABLE {table_name} (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_datetime     VARCHAR,
        dropoff_datetime    VARCHAR,
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         DOUBLE,
        trip_duration       INT,
        google_distance     VARCHAR,
        google_duration     VARCHAR
    ) WITH (
        {inject_security_opts(opts, bootstrap_servers)}
    )
    """
    print(stmt)
    return stmt


def create_print_table(table_name: str):
    stmt = f"""
    CREATE TABLE sink_print (
        id                  VARCHAR,
        vendor_id           INT,
        pickup_datetime     VARCHAR,
        dropoff_datetime    VARCHAR,
        passenger_count     INT,
        pickup_longitude    VARCHAR,
        pickup_latitude     VARCHAR,
        dropoff_longitude   VARCHAR,
        dropoff_latitude    VARCHAR,
        store_and_fwd_flag  VARCHAR,
        gc_distance         DOUBLE,
        trip_duration       INT,
        google_distance     VARCHAR,
        google_duration     VARCHAR
    ) WITH (
        'connector'= 'print'
    )
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
    source_file_path = source_properties["file.path"]
    ## sink
    sink_property_group_key = "sink.config.0"
    sink_properties = property_map(props, sink_property_group_key)
    print(">> sink properties")
    print(sink_properties)
    sink_table_name = sink_properties["table.name"]
    sink_topic_name = sink_properties["topic.name"]
    sink_bootstrap_servers = BOOTSTRAP_SERVERS or sink_properties["bootstrap.servers"]
    ## print
    print_table_name = "sink_print"
    #### create tables
    table_env.execute_sql(create_source_table(source_table_name, source_file_path))
    table_env.execute_sql(
        create_sink_table(sink_table_name, sink_topic_name, sink_bootstrap_servers)
    )
    table_env.execute_sql(create_print_table(print_table_name))
    #### insert into sink tables
    if RUNTIME_ENV == "LOCAL":
        source_table = table_env.from_path(source_table_name)
        statement_set = table_env.create_statement_set()
        statement_set.add_insert(sink_table_name, source_table)
        statement_set.add_insert(print_table_name, source_table)
        statement_set.execute().wait()
    else:
        table_result = table_env.execute_sql(
            f"INSERT INTO {sink_table_name} SELECT * FROM {source_table_name}"
        )
        print(table_result.get_job_client().get_job_status())


if __name__ == "__main__":
    main()
```

```json
// loader/application_properties.json
[
  {
    "PropertyGroupId": "kinesis.analytics.flink.run.options",
    "PropertyMap": {
      "python": "processor.py",
      "jarfile": "package/lib/s3-data-loader-1.0.0.jar"
    }
  },
  {
    "PropertyGroupId": "source.config.0",
    "PropertyMap": {
      "table.name": "taxi_trip_source",
      "file.path": "s3://real-time-streaming-ap-southeast-2/taxi-csv/"
    }
  },
  {
    "PropertyGroupId": "sink.config.0",
    "PropertyMap": {
      "table.name": "taxi_trip_sink",
      "topic.name": "taxi-trip",
      "bootstrap.servers": "localhost:29092"
    }
  }
]
```

### Run Application

```bash
## update s3 bucket name in loader/application_properties.json if different

## set aws credentials environment variables
export AWS_ACCESS_KEY_ID=aws-access-key-id
export AWS_SECRET_ACCESS_KEY=aws-secret-access-key
export AWS_SESSION_TOKEN=aws-session-token

## run docker compose service
# with MSK
docker-compose -f compose-msk.yml up -d
# # or with local Kafka cluster
# docker-compose -f compose-local-kafka.yml up -d

## submit pyflink application
docker exec jobmanager /opt/flink/bin/flink run \
    --python /etc/flink/processor.py \
    --jarfile /etc/package/lib/pyflink-pipeline-1.0.0.jar \
    -d
```

![](flink-job.png#center)

### Monitor Topic

A Kafka management app can be a good companion for development as it helps monitor and manage resources on an easy-to-use user interface. We'll use [Kpow Community Edition](https://docs.kpow.io/ce/) in this post, which allows you to link a single Kafka cluster, Kafka connect server and schema registry. Note that the community edition is valid for 12 months and the licence can be requested on this [page](https://kpow.io/get-started/#individual). Once requested, the licence details will be emailed, and they can be added as an environment file (*env_file*).

The app needs additional configurations in environment variables because the Kafka cluster on Amazon MSK is authenticated by IAM - see [this page](https://docs.kpow.io/config/msk/) for details. The bootstrap server address can be found on AWS Console or executing the following Terraform command. 

```bash
$ terraform output -json | jq -r '.msk_bootstrap_brokers_sasl_iam.value'
```

Note that we need to specify the compose file name when starting it because the file name (*compose-ui.yml*) is different from the default file name (*docker-compose.yml*). We can run it by `docker-compose -f compose-ui.yml up -d` and access on a browser via *localhost:3000*.

We can see the topic (*taxi-rides*) is created, and it has 5 partitions, which is the default number of partitions.

![](kafka-topic.png#center)

Also, we can inspect topic messages in the *Data* tab as shown below.

![](kafka-message.png#center)

## Summary

In this lab, we created a Kafka producer application using AWS Lambda, which sends fake taxi ride data into a Kafka topic on Amazon MSK. It was developed so that a configurable number of the producer Lambda function can be invoked by an Amazon EventBridge schedule rule. In this way, we are able to generate test data concurrently based on the desired volume of messages. 