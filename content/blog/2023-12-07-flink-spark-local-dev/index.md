---
title: Setup Local Development Environment for Apache Flink and Spark Using EMR Container Images
date: 2023-12-07
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
categories:
  - Data Engineering
tags: 
  - Apache Flink
  - PyFlink
  - Apache Spark
  - PySpark
  - Apache Kafka
  - Amazon EMR
  - Docker
  - Docker Compose
  - Python
authors:
  - JaehyeonKim
images: []
description: Apache Flink became generally available for Amazon EMR on EKS from the EMR 6.15.0 releases. As it is integrated with the Glue Data Catalog, it can be particularly useful if we develop real time data ingestion/processing via Flink and build analytical queries using Spark (or any other tools or services that can access to the Glue Data Catalog). In this post, we will discuss how to set up a local development environment for Apache Flink and Spark using the EMR container images. After illustrating the environment setup, we will discuss a solution where data ingestion/processing is performed in real time using Apache Flink and the processed data is consumed by Apache Spark for analysis.
---

[Apache Flink became generally available](https://aws.amazon.com/about-aws/whats-new/2023/11/apache-flink-available-amazon-emr-eks/) for [Amazon EMR on EKS](https://aws.amazon.com/emr/features/eks/) from the [EMR 6.15.0 releases](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks-6.15.0.html), and we are able to pull the Flink (as well as Spark) container images from the [ECR Public Gallery](https://gallery.ecr.aws/emr-on-eks). As both of them can be integrated with the *Glue Data Catalog*, it can be particularly useful if we develop real time data ingestion/processing via Flink and build analytical queries using Spark (or any other tools or services that can access to the Glue Data Catalog).

In this post, we will discuss how to set up a local development environment for Apache Flink and Spark using the EMR container images. For the former, a custom Docker image will be created, which downloads dependent connector Jar files into the Flink library folder, fixes process startup issues, and updates Hadoop configurations for Glue Data Catalog integration. For the latter, instead of creating a custom image, the EMR image is used to launch the Spark container where the required configuration updates are added at runtime via volume-mapping. After illustrating the environment setup, we will discuss a solution where data ingestion/processing is performed in real time using Apache Flink and the processed data is consumed by Apache Spark for analysis.

## Architecture

A PyFlink application produces messages into a Kafka topic and those messages are read and processed by another Flink application. For simplicity, the processor just buffers the messages and writes into S3 in Apache Hive style partitions. The sink (target) table is registered in the Glue Data Catalog for sharing the table details with other tools and services. A PySpark application is used to consume the processed data, which queries the Glue table using Spark SQL.

![](featured.png#center)

## Infrastructure

We create a Flink cluster, Spark container, Kafka cluster and Kafka management app. They are deployed using Docker Compose and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/general-demos/tree/master/spark-flink-local-dev) of this post.

### Flink Setup

#### Custom Docker Image

The custom Docker image extends the EMR Flink image (*public.ecr.aws/emr-on-eks/flink/emr-6.15.0-flink:latest*). It begins with downloading dependent Jar files into the Flink library folder (*/usr/lib/flink/lib*), which are in relation to the [Kafka](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/table/kafka/) and [Flink Faker](https://github.com/knaufk/flink-faker) connectors. 

When I started to run the [Flink SQL client](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/table/sqlclient/), I encountered a number of process startup issues. First, I had a runtime exception whose error message is *java.lang.RuntimeException: Could not find a free permitted port on the machine*. When it gets started, it reserves a port and writes the port details into a folder via the [*getAvailablePort*](https://github.com/apache/flink/blob/master/flink-core/src/main/java/org/apache/flink/util/NetUtils.java#L190) method of the *NetUtils* class. Unlike the official Flink Docker image where the details are written to the */tmp* folder, the EMR image writes into the */mnt/tmp* folder, and it throws an error due to insufficient permission. I was able to fix the issue by creating the */mnt/tmp* folder beforehand. Secondly, I also had additional issues that were caused by the *NoClassDefFoundError*, and they were fixed by adding the [Javax Inject](https://mvnrepository.com/artifact/javax.inject/javax.inject/1) and [AOP Alliance](https://mvnrepository.com/artifact/aopalliance/aopalliance/1.0) Jar files into the Flink library folder.

For Glue Data Catalog integration, we need Hadoop configuration. The EMR image keeps *core-site.xml* in the */glue/confs/hadoop/conf* folder, and I had to update the file. Specifically I updated the credentials providers from *WebIdentityTokenCredentialsProvider* to *EnvironmentVariableCredentialsProvider*. In this way, we are able to access AWS services with AWS credentials in environment variables - the updated Hadoop configuration file can be found below. I also created the */mnt/s3* folder as it is specified as the S3 buffer directory in *core-site.xml*.

```docker
# dockers/flink/Dockerfile
FROM public.ecr.aws/emr-on-eks/flink/emr-6.15.0-flink:latest

ARG FLINK_VERSION
ENV FLINK_VERSION=${FLINK_VERSION:-1.17.1}
ARG KAFKA_VERSION
ENV KAFKA_VERSION=${KAFKA_VERSION:-3.2.3}
ARG FAKER_VERSION
ENV FAKER_VERSION=${FAKER_VERSION:-0.5.3}

##
## add connectors (Kafka and flink faker) and related dependencies
##
RUN curl -o /usr/lib/flink/lib/flink-connector-kafka-${FLINK_VERSION}.jar \
      https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-kafka/${FLINK_VERSION}/flink-connector-kafka-${FLINK_VERSION}.jar \
  && curl -o /usr/lib/flink/lib/kafka-clients-${KAFKA_VERSION}.jar \
      https://repo.maven.apache.org/maven2/org/apache/kafka/kafka-clients/${KAFKA_VERSION}/kafka-clients-${KAFKA_VERSION}.jar \
  && curl -o /usr/lib/flink/lib/flink-sql-connector-kafka-${FLINK_VERSION}.jar \
      https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_VERSION}/flink-sql-connector-kafka-${FLINK_VERSION}.jar \
  && curl -L -o /usr/lib/flink/lib/flink-faker-${FAKER_VERSION}.jar \
      https://github.com/knaufk/flink-faker/releases/download/v${FAKER_VERSION}/flink-faker-${FAKER_VERSION}.jar

##
## fix process startup issues
##
# should be able to write a file in /mnt/tmp as getAvailablePort() in NetUtils class writes to /mnt/tmp instead of /tmp
#   see https://stackoverflow.com/questions/77539526/fail-to-start-flink-sql-client-on-emr-on-eks-docker-image
RUN mkdir -p /mnt/tmp

## add missing jar files
RUN curl -L -o /usr/lib/flink/lib/javax.inject-1.jar \
      https://repo1.maven.org/maven2/javax/inject/javax.inject/1/javax.inject-1.jar \
  && curl -L -o /usr/lib/flink/lib/aopalliance-1.0.jar \
      https://repo1.maven.org/maven2/aopalliance/aopalliance/1.0/aopalliance-1.0.jar

##
## update hadoop configuration for Glue data catalog integration
##
## create /mnt/s3 (value of fs.s3.buffer.dir) beforehand
RUN mkdir -p /mnt/s3

## copy updated core-site.xml
## update credentials providers and value of fs.s3.buffer.dir to /mnt/s3 only
USER root

COPY ./core-site.xml /glue/confs/hadoop/conf/core-site.xml

USER flink
```

Here is the updated Hadoop configuration file that is baked into the custom Docker image.

```xml
<!-- dockers/flink/core-site.xml -->
<configuration>
  <property>
    <name>fs.s3a.aws.credentials.provider</name>
    <value>com.amazonaws.auth.EnvironmentVariableCredentialsProvider</value>
  </property>

  <property>
    <name>fs.s3.customAWSCredentialsProvider</name>
    <value>com.amazonaws.auth.EnvironmentVariableCredentialsProvider</value>
  </property>

  <property>
    <name>fs.s3.impl</name>
    <value>com.amazon.ws.emr.hadoop.fs.EmrFileSystem</value>
  </property>

  <property>
    <name>fs.s3n.impl</name>
    <value>com.amazon.ws.emr.hadoop.fs.EmrFileSystem</value>
  </property>

  <property>
    <name>fs.AbstractFileSystem.s3.impl</name>
    <value>org.apache.hadoop.fs.s3.EMRFSDelegate</value>
  </property>

  <property>
    <name>fs.s3.buffer.dir</name>
    <value>/mnt/s3</value>
    <final>true</final>
  </property>
</configuration>
```

The Docker image can be built using the following command.

```bash
$ docker build -t emr-6.15.0-flink:local dockers/flink/.
```

#### Docker Compose Services

The Flink cluster is made up of a single master container (*jobmanager*) and one task container (*taskmanager*). The master container opens up the port 8081, and we are able to access the Flink Web UI on *localhost:8081*. Also, the current folder is *volume-mapped* into the */home/flink/project* folder, and it allows us to submit a Flink application in the host folder to the Flink cluster. 

Other than the environment variables of the Kafka bootstrap server addresses and AWS credentials, the following environment variables are important for deploying the Flink cluster and running Flink jobs without an issue.

- *K8S_FLINK_GLUE_ENABLED*
  - If this environment variable exists, the container entrypoint file (*docker-entrypoint.sh*) configures Apache Hive. It moves the Hive/Glue related dependencies into the Flink library folder (*/usr/lib/flink/lib*) for setting up Hive Catalog, which is integrated with the Glue Data Catalog.
- *K8S_FLINK_LOG_URL_STDERR* and *K8S_FLINK_LOG_URL_STDOUT*
  - The container entrypoint file (*docker-entrypoint.sh*) creates these folders, but I had an error due to insufficient permission. Therefore, I changed the values of those folders within the */tmp* folder.
- *HADOOP_CONF_DIR*
  - This variable is required when setting up a Hive catalog, or we can add it as an option when creating a catalog (*hadoop-config-dir*).
- *FLINK_PROPERTIES*
  - The properties will be appended into the Flink configuration file (*/usr/lib/flink/conf/flink-conf.yaml*). Among those, *jobmanager.memory.process.size* and *taskmanager.memory.process.size* are mandatory for the containers run without failure.

```yaml
# docker-compose.yml
version: "3.5"

services:
  jobmanager:
    image: emr-6.15.0-flink:local
    container_name: jobmanager
    command: jobmanager
    ports:
      - "8081:8081"
    networks:
      - appnet
    volumes:
      - ./:/home/flink/project
    environment:
      - RUNTIME_ENV=DOCKER
      - BOOTSTRAP_SERVERS=kafka-0:9092
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-not_set}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-not_set}
      - AWS_REGION=${AWS_REGION:-not_set}
      - K8S_FLINK_GLUE_ENABLED=true
      - K8S_FLINK_LOG_URL_STDERR=/tmp/stderr
      - K8S_FLINK_LOG_URL_STDOUT=/tmp/stdout
      - HADOOP_CONF_DIR=/glue/confs/hadoop/conf
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
        rest.flamegraph.enabled: true
        web.backpressure.refresh-interval: 10000
        jobmanager.memory.process.size: 1600m
        taskmanager.memory.process.size: 1728m
  taskmanager:
    image: emr-6.15.0-flink:local
    container_name: taskmanager
    command: taskmanager
    networks:
      - appnet
    volumes:
      - ./:/home/flink/project
      - flink_data:/tmp/
    environment:
      - RUNTIME_ENV=DOCKER
      - BOOTSTRAP_SERVERS=kafka-0:9092
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-not_set}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-not_set}
      - AWS_REGION=${AWS_REGION:-not_set}
      - K8S_FLINK_GLUE_ENABLED=true
      - K8S_FLINK_LOG_URL_STDERR=/tmp/stderr
      - K8S_FLINK_LOG_URL_STDOUT=/tmp/stdout
      - HADOOP_CONF_DIR=/glue/confs/hadoop/conf
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 5
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
        jobmanager.memory.process.size: 1600m
        taskmanager.memory.process.size: 1728m
    depends_on:
      - jobmanager

  ...

networks:
  appnet:
    name: app-network

volumes:
  flink_data:
    driver: local
    name: flink_data
  ...
```

### Spark Setup

In an [earlier post](/blog/2022-05-08-emr-local-dev), I illustrated how to set up a local development environment using an EMR container image. That post is based the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension of VS Code, and it is assumed that development takes place after attaching the project folder into a Docker container. Thanks to the [Docker](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker) extension, however, we no longer have to attach the project folder into a container always because the extension allows us to do so with just a few mouse clicks if necessary - see the screenshot below. Moreover, as Spark applications developed in the host folder can easily be submitted to the Spark container via volume-mapping, we can simplify Spark setup dramatically without creating a custom Docker image. Therefore, Spark will be set up using the EMR image where updated Spark configuration files and the project folder are volume-mapped to the container. Also, the Spark History Server will be running in the container, which allows us to monitor completed and running Spark applications.

![](vscode-attach.png#center)

#### Configuration Updates

Same to Flink Hadoop configuration updates, we need to update credentials providers from *WebIdentityTokenCredentialsProvider* to *EnvironmentVariableCredentialsProvider* to access AWS services with AWS credentials in environment variables. Also, we should specify the catalog implementation to *hive* and set *AWSGlueDataCatalogHiveClientFactory* as the Hive metastore factory class.

```properties
# dockers/spark/spark-defaults.conf

...

##
## Update credentials providers
##
spark.hadoop.fs.s3.customAWSCredentialsProvider  com.amazonaws.auth.EnvironmentVariableCredentialsProvider
spark.hadoop.dynamodb.customAWSCredentialsProvider  com.amazonaws.auth.EnvironmentVariableCredentialsProvider
# spark.authenticate               true

##
## Update to use Glue catalog
##
spark.sql.catalogImplementation  hive
spark.hadoop.hive.metastore.client.factory.class  com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory
```

Besides, I updated the log properties so that the log level of the root logger is set to be *warn* and warning messages due to EC2 metadata access failure are not logged.

```properties
# dockers/spark/log4j2.properties

...

# Set everything to be logged to the console
rootLogger.level = warn

...

## Ignore warn messages related to EC2 metadata access failure
logger.InstanceMetadataServiceResourceFetcher.name = com.amazonaws.internal.InstanceMetadataServiceResourceFetcher
logger.InstanceMetadataServiceResourceFetcher.level = fatal
logger.EC2MetadataUtils.name = com.amazonaws.util.EC2MetadataUtils
logger.EC2MetadataUtils.level = fatal
```

#### Docker Compose Service

The Spark container is created with the EMR image (*public.ecr.aws/emr-on-eks/spark/emr-6.15.0:latest*), and it starts the Spark History Server, which provides an interface to debug and diagnose completed and running Spark applications. Note that the server is configured to run in foreground (*SPARK_NO_DAEMONIZE=true*) in order for the container to keep alive. As mentioned, the updated Spark configuration files and the project folder are volume-mapped.

```yaml
# docker-compose.yml
version: "3.5"

services:

  ...

  spark:
    image: public.ecr.aws/emr-on-eks/spark/emr-6.15.0:latest
    container_name: spark
    command: /usr/lib/spark/sbin/start-history-server.sh
    ports:
      - "18080:18080"
    networks:
      - appnet
    environment:
      - BOOTSTRAP_SERVERS=kafka-0:9092
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-not_set}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-not_set}
      - AWS_REGION=${AWS_REGION:-not_set}
      - SPARK_NO_DAEMONIZE=true
    volumes:
      - ./:/home/hadoop/project
      - ./dockers/spark/spark-defaults.conf:/usr/lib/spark/conf/spark-defaults.conf
      - ./dockers/spark/log4j2.properties:/usr/lib/spark/conf/log4j2.properties

  ...

networks:
  appnet:
    name: app-network

  ...
```

### Kafka Setup

#### Docker Compose Services

A Kafka cluster with a single broker and zookeeper node is used in this post. The broker has two listeners and the port 9092 and 29092 are used for internal and external communication respectively. The default number of topic partitions is set to 3. More details about Kafka cluster setup can be found in [this post](/blog/2023-05-04-kafka-development-with-docker-part-1/).

The [UI for Apache Kafka (kafka-ui)](https://docs.kpow.io/ce/) is used for monitoring Kafka topics and related resources. The bootstrap server address and zookeeper access url are added as environment variables. See [this post](/blog/2023-05-18-kafka-development-with-docker-part-2/) for details about Kafka management apps.

```yaml
# docker-compose.yml
version: "3.5"

services:

  ...

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
      - KAFKA_CFG_NUM_PARTITIONS=3
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=1
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-ui:
    image: provectuslabs/kafka-ui:v0.7.1
    container_name: kafka-ui
    ports:
      - "8080:8080"
    networks:
      - appnet
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
    depends_on:
      - zookeeper
      - kafka-0

networks:
  appnet:
    name: app-network

volumes:
  ...
  zookeeper_data:
    driver: local
    name: zookeeper_data
  kafka_0_data:
    driver: local
    name: kafka_0_data
```

## Applications

### Flink Producer

A PyFlink application is created for data ingesting in real time. The app begins with generating timestamps using the [DataGen SQL Connector](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/connectors/table/datagen/) where three records are generated per second. Then extra values (*id* and *value*) are added to the records using Python user defined functions and the updated records are ingested into a Kafka topic named *orders*. Note that the output records are printed in the terminal additionally when the app is running locally for ease of checking them.

```python
# apps/flink/producer.py
import os
import uuid
import random

from pyflink.datastream import StreamExecutionEnvironment, RuntimeExecutionMode
from pyflink.table import StreamTableEnvironment
from pyflink.table.udf import udf

def _qry_source_table():
    stmt = """
    CREATE TABLE seeds (
        ts  AS PROCTIME()
    ) WITH (
        'connector' = 'datagen',
        'rows-per-second' = '3'
    )
    """
    print(stmt)
    return stmt

def _qry_sink_table(table_name: str, topic_name: str, bootstrap_servers: str):
    stmt = f"""
    CREATE TABLE {table_name} (
        `id`        VARCHAR,
        `value`     INT,
        `ts`        TIMESTAMP(3)
    ) WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{bootstrap_servers}',        
        'format' = 'json',
        'key.format' = 'json',
        'key.fields' = 'id',
        'properties.allow.auto.create.topics' = 'true'
    )
    """
    print(stmt)
    return stmt


def _qry_print_table():
    stmt = """
    CREATE TABLE print (
        `id`        VARCHAR,
        `value`     INT,
        `ts`        TIMESTAMP(3)  

    ) WITH (
        'connector' = 'print'
    )
    """
    print(stmt)
    return stmt

def _qry_insert(target_table: str):
    stmt = f"""
    INSERT INTO {target_table}
    SELECT
        add_id(),
        add_value(),
        ts    
    FROM seeds
    """
    print(stmt)
    return stmt

if __name__ == "__main__":
    RUNTIME_ENV = os.environ.get("RUNTIME_ENV", "LOCAL")  # DOCKER or LOCAL
    BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "localhost:29092")  # overwrite app config

    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_runtime_mode(RuntimeExecutionMode.STREAMING)
    if RUNTIME_ENV == "LOCAL":
        SRC_DIR = os.path.dirname(os.path.realpath(__file__))
        JAR_FILES = ["flink-sql-connector-kafka-1.17.1.jar"] # should exist where producer.py exists
        JAR_PATHS = tuple(
            [f"file://{os.path.join(SRC_DIR, name)}" for name in JAR_FILES]
        )        
        env.add_jars(*JAR_PATHS)
        print(JAR_PATHS)

    t_env = StreamTableEnvironment.create(stream_execution_environment=env)
    t_env.get_config().set_local_timezone("Australia/Sydney")
    t_env.create_temporary_function(
        "add_id", udf(lambda: str(uuid.uuid4()), result_type="STRING")
    )
    t_env.create_temporary_function(
        "add_value", udf(lambda: random.randrange(0, 1000), result_type="INT")
    )
    ## create source and sink tables
    SINK_TABLE_NAME = "orders_table"
    t_env.execute_sql(_qry_source_table())
    t_env.execute_sql(_qry_sink_table(SINK_TABLE_NAME, "orders", BOOTSTRAP_SERVERS))
    t_env.execute_sql(_qry_print_table())
    ## insert into sink table
    if RUNTIME_ENV == "LOCAL":
        statement_set = t_env.create_statement_set()
        statement_set.add_insert_sql(_qry_insert(SINK_TABLE_NAME))
        statement_set.add_insert_sql(_qry_insert("print"))
        statement_set.execute().wait()
    else:
        table_result = t_env.execute_sql(_qry_insert(SINK_TABLE_NAME))
        print(table_result.get_job_client().get_job_status())
```

The application can be submitted into the Flink cluster as shown below. Note that the dependent Jar files for the Kafka connector exist in the Flink library folder (*/usr/lib/flink/lib*) and we don't have to specify them separately. 

```bash
docker exec jobmanager /usr/lib/flink/bin/flink run \
  --python /home/flink/project/apps/flink/producer.py \
  -d
```

Once the app runs, we can see the status of the Flink job on the Flink Web UI (*localhost:8081*).

![](flink-producer.png#center)

Also, we can check the topic (*orders*) is created and messages are ingested on *kafka-ui* (*localhost:8080*).

![](kafka-topic.png#center)

### Flink Processor

The Flink processor application is created using Flink SQL on the [Flink SQL client](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/table/sqlclient/). The SQL client can be started by executing `docker exec -it jobmanager ./bin/sql-client.sh`.

![](sql-client.png#center)

#### Source Table in Default Catalog

We first create a source table that reads messages from the *orders* topic of the Kafka cluster. As the table is not necessarily be shared by other tools or services, it is created on the default catalog, not on the Glue catalog.

```sql
-- apps/flink/processor.sql
-- // create the source table, metadata not registered in glue datalog
CREATE TABLE source_tbl(
  `id`      STRING,
  `value`   INT,
  `ts`      TIMESTAMP(3)
) WITH (
  'connector' = 'kafka',
  'topic' = 'orders',
  'properties.bootstrap.servers' = 'kafka-0:9092',
  'properties.group.id' = 'orders-source',
  'format' = 'json',
  'scan.startup.mode' = 'latest-offset'
);
```

#### Sink Table in Glue Catalog

We create the sink table on the Glue Data Catalog because it needs to be accessed by a Spark application. First, we create a Hive catalog named *glue_catalog* with the Hive configuration that integrates with the Glue Data Catalog. The EMR Flink image includes the required Hive configuration file, and we can specify the corresponding path in the container (*/glue/confs/hive/conf*).

```sql
-- apps/flink/processor.sql
--// create a hive catalogs that integrates with the glue catalog
CREATE CATALOG glue_catalog WITH (
  'type' = 'hive',
  'default-database' = 'default',
  'hive-conf-dir' = '/glue/confs/hive/conf'
);

-- Flink SQL> show catalogs;
-- +-----------------+
-- |    catalog name |
-- +-----------------+
-- | default_catalog |
-- |    glue_catalog |
-- +-----------------+
```

Below shows the Hive configuration file (*/glue/confs/hive/conf/hive-site.xml*). Same as the Spark configuration, *AWSGlueDataCatalogHiveClientFactory* is specified as the Hive metastore factory class, which enables to use the Glue Data Catalog as the metastore of Hive databases and tables.

```xml
<configuration>
    <property>
        <name>hive.metastore.client.factory.class</name>
        <value>com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory</value>
    </property>

    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://dummy:9083</value>
    </property>
</configuration>
```

Secondly, we create a database named *demo* by specifying the S3 location URI - *s3://demo-ap-southeast-2/warehouse/*.

```sql
-- apps/flink/processor.sql
-- // create a database named demo
CREATE DATABASE IF NOT EXISTS glue_catalog.demo 
  WITH ('hive.database.location-uri'= 's3://demo-ap-southeast-2/warehouse/');
```

Once succeeded, we are able to see the database is created in the Glue Data Catalog.

![](glue-database.png#center)

Finally, we create the sink table in the Glue database. The Hive SQL dialect is used to create the table, and it is partitioned by *year*, *month*, *date* and *hour*.

```sql
-- apps/flink/processor.sql
-- // create the sink table using hive dialect
SET table.sql-dialect=hive;
CREATE TABLE glue_catalog.demo.sink_tbl(
  `id`      STRING,
  `value`   INT,
  `ts`      TIMESTAMP(9)
) 
PARTITIONED BY (`year` STRING, `month` STRING, `date` STRING, `hour` STRING) 
STORED AS parquet 
TBLPROPERTIES (
  'partition.time-extractor.timestamp-pattern'='$year-$month-$date $hour:00:00',
  'sink.partition-commit.trigger'='partition-time',
  'sink.partition-commit.delay'='1 h',
  'sink.partition-commit.policy.kind'='metastore,success-file'
);
```

We can check the sink table is created in the Glue database on AWS Console as shown below.

![](glue-table.png#center)

#### Flink Job

The Flink processor job gets submitted when we execute the *INSERT* statement on the SQL client. Note that the checkpoint interval is set to 60 seconds to simplify monitoring, and it is expected that a new file is added per minute.

```sql
-- apps/flink/processor.sql
SET 'state.checkpoints.dir' = 'file:///tmp/checkpoints/';
SET 'execution.checkpointing.interval' = '60000';

SET table.sql-dialect=hive;
-- // insert into the sink table
INSERT INTO TABLE glue_catalog.demo.sink_tbl
SELECT 
  `id`, 
  `value`, 
  `ts`,
  DATE_FORMAT(`ts`, 'yyyy') AS `year`,
  DATE_FORMAT(`ts`, 'MM') AS `month`,
  DATE_FORMAT(`ts`, 'dd') AS `date`,
  DATE_FORMAT(`ts`, 'HH') AS `hour`
FROM source_tbl;
```

Once the Flink app is submitted, we can check the Flink job on the Flink Web UI (*localhost:8081*).

![](flink-processor.png#center)

As expected, the output files are written into S3 in Apache Hive style partitions, and they are created in one minute interval.

![](s3-objects.png#center)

### Spark Consumer

A simple PySpark application is created to query the output table. Note that, as the partitions are not added dynamically, [*MSCK REPAIR TABLE*](https://spark.apache.org/docs/3.0.0-preview/sql-ref-syntax-ddl-repair-table.html) command is executed before querying the table.

```python
# apps/spark/consumer.py
from pyspark.sql import SparkSession

if __name__ == "__main__":
    spark = SparkSession.builder.appName("Consume Orders").getOrCreate()
    spark.sparkContext.setLogLevel("FATAL")
    spark.sql("MSCK REPAIR TABLE demo.sink_tbl")
    spark.sql("SELECT * FROM demo.sink_tbl").show()
```

The Spark app can be submitted as shown below. Note that the application is accessible in the container because the project folder is volume-mapped to the container folder (*/home/hadoop/project*).

```bash
docker exec spark /usr/lib/spark/bin/spark-submit \
  --master local[*] --deploy-mode client /home/hadoop/project/apps/spark/consumer.py
```

The app queries the output table successfully and shows the result as expected.

![](spark-consumer.png#center)

We can check the performance of the Spark application on the Spark History Server (*localhost:18080*).

![](spark-history-server.png#center)

## Summary

In this post, we discussed how to set up a local development environment for Apache Flink and Spark using the EMR container images. For the former, a custom Docker image was created, which downloads dependent connector Jar files into the Flink library folder, fixes process startup issues, and updates Hadoop configurations for Glue Data Catalog integration. For the latter, instead of creating a custom image, the EMR image was used to launch the Spark container where the required configuration updates are added at runtime via volume-mapping. After illustrating the environment setup, we discussed a solution where data ingestion/processing is performed in real time using Apache Flink and the processed data is consumed by Apache Spark for analysis.
