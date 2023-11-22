---
title: Real Time Streaming with Kafka and Flink - Lab 4 Clean, Aggregate, and Enrich Events with Flink
date: 2023-11-23
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
  - Amazon OpenSearch Service
  - Apache Kafka
  - Apache Flink
  - OpenSearch
  - Pyflink
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
description: The value of data can be maximised when it is used without delay. With Apache Flink, we can build streaming analytics applications that incorporate the latest events with low latency. In this lab, we will create a Pyflink application that writes accumulated taxi rides data into an OpenSearch cluster. It aggregates the number of trips/passengers and trip durations by vendor ID for a window of 5 seconds. The data is then used to create a chart that monitors the status of taxi rides in the OpenSearch Dashboard.
---

The value of data can be maximised when it is used without delay. With Apache Flink, we can build streaming analytics applications that incorporate the latest events with low latency. In this lab, we will create a Pyflink application that writes accumulated taxi rides data into an OpenSearch cluster. It aggregates the number of trips/passengers and trip durations by vendor ID for a window of 5 seconds. The data is then used to create a chart that monitors the status of taxi rides in the OpenSearch Dashboard.

* [Introduction](/blog/2023-10-05-real-time-streaming-with-kafka-and-flink-1)
* [Lab 1 Produce data to Kafka using Lambda](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2)
* [Lab 2 Write data to Kafka from S3 using Flink](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3)
* [Lab 3 Transform and write data to S3 from Kafka using Flink](/blog/2023-11-16-real-time-streaming-with-kafka-and-flink-4)
* [Lab 4 Clean, Aggregate, and Enrich Events with Flink](#) (this post)
* [Lab 5 Write data to DynamoDB using Kafka Connect](/blog/2023-11-30-real-time-streaming-with-kafka-and-flink-6)
* [Lab 6 Consume data from Kafka using Lambda](/blog/2023-12-07-real-time-streaming-with-kafka-and-flink-7)

## Architecture

Fake taxi ride data is sent to a Kafka topic by the Kafka producer application that is discussed in [Lab 1](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2). The Pyflink app aggregates the number of trips/passengers and trip durations by vendor ID for a window of 5 seconds and sends the accumulated records into an OpenSearch cluster. The data is then used to create a chart that monitors the status of taxi rides in the OpenSearch Dashboard.

![](featured.png#center)

## Infrastructure

The AWS infrastructure is created using [Terraform](https://www.terraform.io/) and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/real-time-streaming-aws) of this post. See this [earlier post](/blog/2023-10-26-real-time-streaming-with-kafka-and-flink-2) for details about how to create the resources. The key resources cover a VPC, VPN server, MSK cluster and Python Lambda producer app.

### OpenSearch Cluster

For this lab, an OpenSearch cluster is created additionally, and it is deployed with the *m5.large.search* instance type in private subnets. For simplicity, [anonymous authentication](https://opensearch.org/docs/latest/security/configuration/configuration/#http) is enabled so that we don't have to specify user credentials when making an HTTP request. Overall only network-level security is enforced on the OpenSearch domain. Note that the cluster is created only when the *opensearch_to_create* variable is set to *true*.

```terraform
# infra/variables.tf
variable "opensearch_to_create" {
  description = "Flag to indicate whether to create OpenSearch cluster"
  type        = bool
  default     = false
}

...

locals {

  ...

  opensearch = {
    to_create      = var.opensearch_to_create
    engine_version = "2.7"
    instance_type  = "m5.large.search"
    instance_count = 2
  }

  ...

}

# infra/opensearch.tf
resource "aws_opensearch_domain" "opensearch" {
  count = local.opensearch.to_create ? 1 : 0

  domain_name    = local.name
  engine_version = "OpenSearch_${local.opensearch.engine_version}"

  cluster_config {
    dedicated_master_enabled = false
    instance_type            = local.opensearch.instance_type  # m5.large.search
    instance_count           = local.opensearch.instance_count # 2
    zone_awareness_enabled   = true
  }

  advanced_security_options {
    enabled                        = false
    anonymous_auth_enabled         = true
    internal_user_database_enabled = true
  }

  domain_endpoint_options {
    enforce_https           = true
    tls_security_policy     = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_log_group_index_slow_logs[0].arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  vpc_options {
    subnet_ids         = slice(module.vpc.private_subnets, 0, local.opensearch.instance_count)
    security_group_ids = [aws_security_group.opensearch[0].id]
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "es:*",
        Principal = "*",
        Effect    = "Allow",
        Resource  = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
      }
    ]
  })
}
```

#### OpenSearch Security Group

The security group of the OpenSearch domain has inbound rules that allow connection from the security groups of the VPN server. It is important to configure those rules because the Pyflink application will be executed in the developer machine and access to the OpenSearch cluster will be made through the VPN server. Only port 443 and 9200 are open for accessing the OpenSearch Dashboard and making HTTP requests.

```terraform
# infra/opensearch.tf
resource "aws_security_group" "opensearch" {
  count = local.opensearch.to_create ? 1 : 0

  name   = "${local.name}-opensearch-sg"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

...

resource "aws_security_group_rule" "opensearch_vpn_inbound_https" {
  count                    = local.vpn.to_create && local.opensearch.to_create ? 1 : 0
  type                     = "ingress"
  description              = "Allow inbound traffic for OpenSearch Dashboard from VPN"
  security_group_id        = aws_security_group.opensearch[0].id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.vpn[0].id
}

resource "aws_security_group_rule" "opensearch_vpn_inbound_rest" {
  count                    = local.vpn.to_create && local.opensearch.to_create ? 1 : 0
  type                     = "ingress"
  description              = "Allow inbound traffic for OpenSearch REST API from VPN"
  security_group_id        = aws_security_group.opensearch[0].id
  protocol                 = "tcp"
  from_port                = 9200
  to_port                  = 9200
  source_security_group_id = aws_security_group.vpn[0].id
}
```

The infrastructure can be deployed (as well as destroyed) using Terraform CLI as shown below.

```bash
# initialize
terraform init
# create an execution plan
terraform plan -var 'producer_to_create=true' -var 'opensearch_to_create=true'
# execute the actions proposed in a Terraform plan
terraform apply -auto-approve=true -var 'producer_to_create=true' -var 'opensearch_to_create=true'

# destroy all remote objects
# terraform destroy -auto-approve=true -var 'producer_to_create=true' -var 'opensearch_to_create=true'
```

Once the resources are deployed, we can check the OpenSearch cluster on AWS Console as shown below.

![](opensearch-cluster.png#center)

### Local OpenSearch Cluster on Docker (Optional)

As discussed further later, we can use a local Kafka cluster deployed on Docker instead of one on Amazon MSK. For this option, we need to deploy a local OpenSearch cluster on Docker and the following Docker Compose file defines a single node OpenSearch Cluster and OpenSearch Dashboard services.

```yaml
# compose-extra.yml
version: "3.5"

services:
  opensearch:
    image: opensearchproject/opensearch:2.7.0
    container_name: opensearch
    environment:
      - discovery.type=single-node
      - node.name=opensearch
      - DISABLE_SECURITY_PLUGIN=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - opensearch_data:/usr/share/opensearch/data
    ports:
      - 9200:9200
      - 9600:9600
    networks:
      - appnet
  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:2.7.0
    container_name: opensearch-dashboards
    ports:
      - 5601:5601
    expose:
      - "5601"
    environment:
      OPENSEARCH_HOSTS: '["http://opensearch:9200"]'
      DISABLE_SECURITY_DASHBOARDS_PLUGIN: true
    networks:
      - appnet

networks:
  appnet:
    external: true
    name: app-network

volumes:
  opensearch_data:
    driver: local
    name: opensearch_data
```

### Flink Cluster on Docker Compose

There are two Docker Compose files that deploy a Flink Cluster locally. The first one ([*compose-msk.yml*](https://github.com/jaehyeon-kim/flink-demos/blob/master/real-time-streaming-aws/compose-msk.yml)) relies on the Kafka cluster on Amazon MSK while a local Kafka cluster is created together with a Flink cluster in the second file ([*compose-local-kafka.yml*](https://github.com/jaehyeon-kim/flink-demos/blob/master/real-time-streaming-aws/compose-local-kafka.yml)) - see [Lab 2](/blog/2023-11-09-real-time-streaming-with-kafka-and-flink-3) and [Lab 3](/blog/2023-11-16-real-time-streaming-with-kafka-and-flink-4) respectively for details about them. Note that, if we use a local Kafka and Flink clusters, we don't have to deploy the AWS resources. Instead, we can use a local OpenSearch cluster, and it can be deployed by using [*compose-extra.yml*](https://github.com/jaehyeon-kim/flink-demos/blob/master/real-time-streaming-aws/compose-extra.yml).

The Docker Compose services can be deployed as shown below.

```bash
## flink cluster with msk cluster
$ docker-compose -f compose-msk.yml up -d

## local kafka/flink cluster
$ docker-compose -f compose-local-kafka.yml up -d
# opensearch cluster
$ docker-compose -f compose-extra.yml up -d
```

## Pyflink Application

### Flink Pipeline Jar

The application has multiple dependencies and a single Jar file is created so that it can be specified in the `--jarfile` option. Note that we have to build the Jar file based on the [Apache Kafka Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/datastream/kafka/) instead of the [Apache Kafka SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/table/kafka/) because the *MSK IAM Auth* library is not compatible with the latter due to shade relocation. The dependencies are grouped as shown below.

- Kafka Connector
  - flink-connector-base
  - flink-connector-kafka
  - aws-msk-iam-auth (for IAM authentication)
- OpenSearch Connector
  - flink-connector-opensearch
  - opensearch
  - opensearch-rest-high-level-client
  - org.apache.httpcomponents
  - httpcore-nio

A single Jar file is created for this lab as the app may need to be deployed via Amazon Managed Flink potentially. If we do not have to deploy on it, however, they can be added to the Flink library folder (*/opt/flink/lib*) separately.

The single Uber jar file is created by the following POM file and the Jar file is named as *lab4-pipeline-1.0.0.jar*.

```xml
<!-- package/lab4-pipeline/pom.xml -->
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>

	<groupId>com.amazonaws.services.kinesisanalytics</groupId>
	<artifactId>lab4-pipeline</artifactId>
	<version>1.0.0</version>
	<packaging>jar</packaging>

	<name>Uber Jar for Lab 4</name>

	<properties>
		<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
		<flink.version>1.17.1</flink.version>
		<jdk.version>11</jdk.version>
		<kafka.clients.version>3.2.3</kafka.clients.version>
		<log4j.version>2.17.1</log4j.version>
		<aws-msk-iam-auth.version>1.1.7</aws-msk-iam-auth.version>
		<opensearch.connector.version>1.0.1-1.17</opensearch.connector.version>
		<opensearch.version>2.7.0</opensearch.version>
		<httpcore-nio.version>4.4.12</httpcore-nio.version>
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

		<!-- Kafkf Connector -->

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
			<groupId>org.apache.kafka</groupId>
			<artifactId>kafka-clients</artifactId>
			<version>${kafka.clients.version}</version>
		</dependency>

		<dependency>
			<groupId>software.amazon.msk</groupId>
			<artifactId>aws-msk-iam-auth</artifactId>
			<version>${aws-msk-iam-auth.version}</version>
		</dependency>

		<!-- OpenSearch -->

		<dependency>
			<groupId>org.apache.flink</groupId>
			<artifactId>flink-connector-opensearch</artifactId>
			<version>${opensearch.connector.version}</version>
		</dependency>

		<dependency>
			<groupId>org.opensearch</groupId>
			<artifactId>opensearch</artifactId>
			<version>${opensearch.version}</version>
		</dependency>

		<dependency>
			<groupId>org.opensearch.client</groupId>
			<artifactId>opensearch-rest-high-level-client</artifactId>
			<version>${opensearch.version}</version>
			<exclusions>
				<exclusion>
					<groupId>org.apache.httpcomponents</groupId>
					<artifactId>httpcore-nio</artifactId>
				</exclusion>
			</exclusions>
		</dependency>

		<!-- We need to include httpcore-nio again in the correct version due to the exclusion above -->
		<dependency>
			<groupId>org.apache.httpcomponents</groupId>
			<artifactId>httpcore-nio</artifactId>
			<version>${httpcore-nio.version}</version>
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

...

mvn clean install -f $SRC_PATH/lab4-pipeline/pom.xml \
  && mv $SRC_PATH/lab4-pipeline/target/lab4-pipeline-1.0.0.jar $SRC_PATH/lib \
  && rm -rf $SRC_PATH/lab4-pipeline/target
```

### Application Source

A source table is created to read messages from the *taxi-rides* topic using the Kafka Connector. The source records are *bucketed* in a window of 5 seconds using the [*TUMBLE* windowing table-valued function](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/table/sql/queries/window-tvf/#tumble), and those within buckets are aggregated by vendor ID, window start and window end variables. Then they are inserted into the sink table, which leads to ingesting them into an OpenSearch index named *trip_stats* using the OpenSearch connector.

In the *main* method, we create all the source and sink tables after mapping relevant application properties. Then the output records are written to the OpenSearch index. Note that the output records are printed in the terminal additionally when the app is running locally for checking them easily.

```python
# forwarder/processor.py
import os
import re
import json

from pyflink.datastream import StreamExecutionEnvironment, RuntimeExecutionMode
from pyflink.table import StreamTableEnvironment

RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "LOCAL")  # LOCAL or DOCKER
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS")  # overwrite app config
OPENSEARCH_HOSTS = os.environ.get("OPENSEARCH_HOSTS")  # overwrite app config

env = StreamExecutionEnvironment.get_execution_environment()
env.set_runtime_mode(RuntimeExecutionMode.STREAMING)
env.enable_checkpointing(5000)

if RUNTIME_ENV == "LOCAL":
    CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))
    PARENT_DIR = os.path.dirname(CURRENT_DIR)
    APPLICATION_PROPERTIES_FILE_PATH = os.path.join(
        CURRENT_DIR, "application_properties.json"
    )
    JAR_FILES = ["lab4-pipeline-1.0.0.jar"]
    JAR_PATHS = tuple(
        [f"file://{os.path.join(PARENT_DIR, 'jars', name)}" for name in JAR_FILES]
    )
    print(JAR_PATHS)
    env.add_jars(*JAR_PATHS)
else:
    APPLICATION_PROPERTIES_FILE_PATH = (
        "/etc/flink/forwarder/application_properties.json"
    )

table_env = StreamTableEnvironment.create(stream_execution_environment=env)


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
        dropoff_date        VARCHAR,
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
        process_time        AS PROCTIME()
    ) WITH (
        {inject_security_opts(opts, bootstrap_servers)}
    )
    """
    print(stmt)
    return stmt


def create_sink_table(table_name: str, os_hosts: str, os_index: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        vendor_id           VARCHAR,
        trip_count          BIGINT NOT NULL,
        passenger_count     INT,
        trip_duration       INT,
        window_start        TIMESTAMP(3) NOT NULL,
        window_end          TIMESTAMP(3) NOT NULL
    ) WITH (
        'connector'= 'opensearch',
        'hosts' = '{os_hosts}',
        'index' = '{os_index}'
    )
    """
    print(stmt)
    return stmt


def create_print_table(table_name: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        vendor_id           VARCHAR,
        trip_count          BIGINT NOT NULL,
        passenger_count     INT,
        trip_duration       INT,
        window_start        TIMESTAMP(3) NOT NULL,
        window_end          TIMESTAMP(3) NOT NULL
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
        CAST(vendor_id AS STRING) AS vendor_id,
        COUNT(id) AS trip_count,
        SUM(passenger_count) AS passenger_count,
        SUM(trip_duration) AS trip_duration,
        window_start,
        window_end
    FROM TABLE(
    TUMBLE(TABLE {source_table_name}, DESCRIPTOR(process_time), INTERVAL '5' SECONDS))
    GROUP BY vendor_id, window_start, window_end
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
    sink_os_hosts = OPENSEARCH_HOSTS or sink_properties["os_hosts"]
    sink_os_index = sink_properties["os_index"]
    ## print
    print_table_name = "sink_print"
    #### create tables
    table_env.execute_sql(
        create_source_table(
            source_table_name, source_topic_name, source_bootstrap_servers
        )
    )
    table_env.execute_sql(
        create_sink_table(sink_table_name, sink_os_hosts, sink_os_index)
    )
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
// forwarder/application_properties.json
[
  {
    "PropertyGroupId": "kinesis.analytics.flink.run.options",
    "PropertyMap": {
      "python": "processor.py",
      "jarfile": "package/lib/lab4-pipeline-1.0.0.jar"
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
      "table.name": "trip_stats_sink",
      "os_hosts": "http://opensearch:9200",
      "os_index": "trip_stats"
    }
  }
]
```

### Run Application

#### Execute on Local Flink Cluster

We can run the application in the Flink cluster on Docker and the steps are shown below. Either the Kafka cluster on Amazon MSK or a local Kafka cluster can be used depending on which Docker Compose file we use. In either way, we can check the job details on the Flink web UI on *localhost:8081*. Note that, if we use the local Kafka cluster option, we have to start the producer application in a different terminal as well as to deploy a local OpenSearch cluster.

```bash
## set aws credentials environment variables
export AWS_ACCESS_KEY_ID=<aws-access-key-id>
export AWS_SECRET_ACCESS_KEY=<aws-secret-access-key>

# set addtional environment variables when using AWS services if using compose-msk.yml
#   values can be obtained in Terraform outputs or AWS Console
export BOOTSTRAP_SERVERS=<bootstrap-servers>
export OPENSEARCH_HOSTS=<opensearch-hosts>

## run docker compose service
# or with msk cluster
docker-compose -f compose-msk.yml up -d

# # with local kafka and opensearch cluster
# docker-compose -f compose-local-kafka.yml up -d
# docker-compose -f compose-extra.yml up -d

## run the producer application in another terminal if using a local cluster
# python producer/app.py 

## submit pyflink application
docker exec jobmanager /opt/flink/bin/flink run \
    --python /etc/flink/forwarder/processor.py \
    --jarfile /etc/flink/package/lib/lab4-pipeline-1.0.0.jar \
    -d
```

Once the Pyflink application is submitted, we can check the details of it on the Flink UI as shown below.

![](flink-job.png#center)

### Application Result

#### Kafka Topic

We can see the topic (*taxi-rides*) is created, and the details of the topic can be found on the *Topics* menu on *localhost:3000*.

![](kafka-topic.png#center)

#### OpenSearch Index

The ingested data can be checked easily using the [Query Workbench](https://opensearch.org/docs/latest/dashboards/query-workbench/) as shown below.

![](opensearch-query.png#center)

To monitor the status of taxi rides, a horizontal bar chart is created in the OpenSearch Dashboard. The average trip duration is selected as the metric, and the records are grouped by vendor ID. We can see the values change while new records arrives.

![](opensearch-chart.png#center)

## Summary

In this lab, we created a Pyflink application that writes accumulated taxi rides data into an OpenSearch cluster. It aggregated the number of trips/passengers and trip durations by vendor ID for a window of 5 seconds. The data was then used to create a chart that monitors the status of taxi rides in the OpenSearch Dashboard.