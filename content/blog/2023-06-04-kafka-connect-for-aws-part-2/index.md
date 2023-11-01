---
title: Kafka Connect for AWS Services Integration - Part 2 Develop Camel DynamoDB Sink Connector
date: 2023-06-04
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Connect for AWS Services Integration
categories:
  - Apache Kafka
tags: 
  - AWS
  - Apache Kafka
  - Kafka Connect
  - Apache Camel
  - Amazon DynamoDB
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
cevo: 29
description: The suite of Apache Camel Kafka connectors and the Kinesis Kafka connector from the AWS Labs can be effective for building data ingestion pipelines that integrate AWS services. In this post, I will illustrate how to develop the Camel DynamoDB sink connector using Docker. Fake order data will be generated using the MSK Data Generator source connector, and the sink connector will be configured to consume the topic messages to ingest them into a DynamoDB table.
---

**[This article](https://cevo.com.au/post/kafka-connect-for-aws-part-2/) was originally posted on Tech Insights of [Cevo Australia](https://cevo.com.au/).**

In [Part 1](/blog/2023-05-03-kafka-connect-for-aws-part-1), we reviewed Kafka connectors focusing on AWS services integration. Among the available connectors, the suite of [Apache Camel Kafka connectors](https://camel.apache.org/camel-kafka-connector/3.18.x/index.html) and the [Kinesis Kafka connector](https://github.com/awslabs/kinesis-kafka-connector) from the AWS Labs can be effective for building data ingestion pipelines on AWS. In this post, I will illustrate how to develop the Camel DynamoDB sink connector using Docker. Fake order data will be generated using the [MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator) source connector, and the sink connector will be configured to consume the topic messages to ingest them into a DynamoDB table.

* [Part 1 Introduction](/blog/2023-05-03-kafka-connect-for-aws-part-1)
* [Part 2 Develop Camel DynamoDB Sink Connector](#) (this post)
* [Part 3 Deploy Camel DynamoDB Sink Connector](/blog/2023-07-03-kafka-connect-for-aws-part-3)
* [Part 4 Develop Aiven OpenSearch Sink Connector](/blog/2023-10-23-kafka-connect-for-aws-part-4)
* [Part 5 Deploy Aiven OpenSearch Sink Connector](/blog/2023-10-30-kafka-connect-for-aws-part-5)

## Kafka Cluster

We will create a Kafka cluster with 3 brokers and 1 Zookeeper node using the [bitnami/kafka](https://hub.docker.com/r/bitnami/kafka) image. *Kafka 2.8.1* is used as it is the [recommended Kafka version by Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html#2.8.1). The following Docker Compose file is used to create the Kafka cluster, and the source can also be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-connect-for-aws/part-02) of this post. The resources created by the compose file are illustrated below.
- services
  - zookeeper
    - A Zookeeper node is created with minimal configuration. It allows anonymous login.
  - kafka-*[id]*
    - Each broker has a unique ID (*KAFKA_CFG_BROKER_ID*) and shares the same Zookeeper connect parameter (*KAFKA_CFG_ZOOKEEPER_CONNECT*). These are required to connect to the Zookeeper node.
    - Each has two listeners - *INTERNAL* and *EXTERNAL*. The former is accessed on port 9092, and it is used within the same Docker network. The latter is mapped from port 29092 to 29094, and it can be used to connect from outside the network.
    - Each can be accessed without authentication (*ALLOW_PLAINTEXT_LISTENER*).
    - The number of partitions (*KAFKA_CFG_NUM_PARTITIONS*) and default replica factor (*KAFKA_CFG_DEFAULT_REPLICATION_FACTOR*) are set to 3 respectively.
- networks
  - A network named *kafka-network* is created and used by all services. Having a custom network can be beneficial when services are launched by multiple Docker Compose files. This custom network can be referred to by services in other compose files.
- volumes
  - Each service has its own volume that will be mapped to the container's data folder. We can check the contents of the folder in the Docker volume path. More importantly data is preserved in the Docker volume unless it is deleted so that we don't have to recreate data every time the Kafka cluster gets started.

```yaml
# kafka-connect-for-aws/part-02/compose-kafka.yml
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
      - KAFKA_CFG_NUM_PARTITIONS=3
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=3
    volumes:
      - kafka_0_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-1:
    image: bitnami/kafka:2.8.1
    container_name: kafka-1
    expose:
      - 9092
    ports:
      - "29093:29093"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=1
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29093
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-1:9092,EXTERNAL://localhost:29093
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=3
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=3
    volumes:
      - kafka_1_data:/bitnami/kafka
    depends_on:
      - zookeeper
  kafka-2:
    image: bitnami/kafka:2.8.1
    container_name: kafka-2
    expose:
      - 9092
    ports:
      - "29094:29094"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=2
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,EXTERNAL://:29094
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-2:9092,EXTERNAL://localhost:29094
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=INTERNAL
      - KAFKA_CFG_NUM_PARTITIONS=3
      - KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=3
    volumes:
      - kafka_2_data:/bitnami/kafka
    depends_on:
      - zookeeper

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
  kafka_1_data:
    driver: local
    name: kafka_1_data
  kafka_2_data:
    driver: local
    name: kafka_2_data
```

## Kafka Connect

We can use the same Docker image because *Kafka Connect* is included in the Kafka distribution. The Kafka Connect server runs as a separate docker compose service, and its key configurations are listed below.

* We run it as the [distributed mode](https://docs.confluent.io/platform/current/connect/concepts.html#distributed-workers), and it can be started by executing *connect-distributed.sh* on the Docker command. 
  * The startup script requires the properties file (*connect-distributed.properties*). It includes configurations such as Kafka broker server addresses - see below for details. 
* The Connect server is accessible on port 8083, and we can manage connectors via a REST API as demonstrated below.
* The properties file and connector sources are volume-mapped.
* AWS credentials are added to environment variables as the sink connector requires permission to write data into DynamoDB. 

```yaml
# kafka-connect-for-aws/part-02/compose-connect.yml
version: "3.5"

services:
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
      - "./connectors/msk-data-generator.jar:/opt/connectors/datagen/msk-data-generator.jar"
      - "./connectors/camel-aws-ddb-sink-kafka-connector:/opt/connectors/camel-aws-ddb-sink-kafka-connector"

networks:
  kafkanet:
    external: true
    name: kafka-network
```

### Connect Properties File

The properties file includes configurations of the Connect server. Below shows key config values.

- Bootstrap Server 
  - I changed the Kafka bootstrap server addresses. As it shares the same Docker network, we can take the service names (e.g. *kafka-0*) on port 9092.
- Cluster group id
  - In distributed mode, multiple worker processes use the same *group.id*, and they automatically coordinate to schedule execution of connectors and tasks across all available workers.
- Converter-related properties
  - Converters are necessary to have a Kafka Connect deployment support a particular data format when writing to or reading from Kafka.
  - By default, *org.apache.kafka.connect.json.JsonConverter* is set for both the key and value converters and schemas are enabled for both of them.
  - As shown later, these properties can be overridden when creating a connector.
- Topics for offsets, configs, status
  - Several topics are created to manage connectors by multiple worker processes.
- Plugin path
  - Paths that contains plugins (connectors, converters, transformations) can be set to a list of filesystem paths separated by commas (,)
  - `/opt/connectors` is added and connector sources will be volume-mapped to it.

```java-properties
## kafka-connect-for-aws/part-02/connect-distributed.properties
# A list of host/port pairs to use for establishing the initial connection to the Kafka cluster.
bootstrap.servers=kafka-0:9092,kafka-1:9092,kafka-2:9092

# unique name for the cluster, used in forming the Connect cluster group. Note that this must not conflict with consumer group IDs
group.id=connect-cluster

# The converters specify the format of data in Kafka and how to translate it into Connect data. Every Connect user will
# need to configure these based on the format they want their data in when loaded from or stored into Kafka
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
# Converter-specific settings can be passed in by prefixing the Converter's setting with the converter we want to apply
# it to
key.converter.schemas.enable=true
value.converter.schemas.enable=true

# Topic to use for storing offsets.
offset.storage.topic=connect-offsets
offset.storage.replication.factor=1
#offset.storage.partitions=25

# Topic to use for storing connector and task configurations.
config.storage.topic=connect-configs
config.storage.replication.factor=1

# Topic to use for storing statuses. 
status.storage.topic=connect-status
status.storage.replication.factor=1
#status.storage.partitions=5

...

# Set to a list of filesystem paths separated by commas (,) to enable class loading isolation for plugins
# (connectors, converters, transformations).
plugin.path=/opt/connectors
```

### Download Connectors

The connector sources need to be downloaded into the `./connectors` path so that they can be volume-mapped to the container's plugin path (`/opt/connectors`). The MSK Data Generator is a single Jar file, and it can be kept as it is. On the other hand, the Camel DynamoDB sink connector is an archive file, and it should be decompressed. Note a separate zip file is made as well, and it will be used to create a custom plugin of MSK Connect in a later post. The following script downloads them into the host path.

```bash
# kafka-connect-for-aws/part-02/download.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

SRC_PATH=${SCRIPT_DIR}/connectors
rm -rf ${SRC_PATH} && mkdir ${SRC_PATH}

## MSK Data Generator Souce Connector
echo "downloading msk data generator..."
DOWNLOAD_URL=https://github.com/awslabs/amazon-msk-data-generator/releases/download/v0.4.0/msk-data-generator-0.4-jar-with-dependencies.jar

curl -L -o ${SRC_PATH}/msk-data-generator.jar ${DOWNLOAD_URL}

## Download camel dynamodb sink connector
echo "download camel dynamodb sink connector..."
DOWNLOAD_URL=https://repo.maven.apache.org/maven2/org/apache/camel/kafkaconnector/camel-aws-ddb-sink-kafka-connector/3.20.3/camel-aws-ddb-sink-kafka-connector-3.20.3-package.tar.gz

# decompress and zip contents to create custom plugin of msk connect later
curl -o ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz ${DOWNLOAD_URL} \
  && tar -xvzf ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz -C ${SRC_PATH} \
  && cd ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector \
  && zip -r camel-aws-ddb-sink-kafka-connector.zip . \
  && mv camel-aws-ddb-sink-kafka-connector.zip ${SRC_PATH} \
  && rm ${SRC_PATH}/camel-aws-ddb-sink-kafka-connector.tar.gz
```

Below shows the folder structure after the connectors are downloaded successfully.

```bash
connectors/
├── camel-aws-ddb-sink-kafka-connector
...
│   ├── camel-api-3.20.3.jar
│   ├── camel-aws-ddb-sink-kafka-connector-3.20.3.jar **
│   ├── camel-aws2-ddb-3.20.3.jar
...
├── camel-aws-ddb-sink-kafka-connector.zip **
...
└── msk-data-generator.jar **

3 directories, 128 files
```

## Kafka Management App

A Kafka management app can be a good companion for development as it helps monitor and manage resources on an easy-to-use user interface. We'll use [*kafka-ui*](https://docs.kafka-ui.provectus.io/overview/readme) in this post. It provides a docker image, and we can link one or more Kafka clusters and related resources to it. In the following compose file, we added connection details of the Kafka cluster and Kafka Connect server.

```yaml
# kafka-connect-for-aws/part-02/compose-ui.yml
version: "3.5"

services:
  kafka-ui:
    image: provectuslabs/kafka-ui:master
    container_name: kafka-ui
    ports:
      - "8080:8080"
    networks:
      - kafkanet
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9092,kafka-1:9092,kafka-2:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
      KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: local
      KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: http://kafka-connect:8083

networks:
  kafkanet:
    external: true
    name: kafka-network
```

## Start Services

There are 3 docker compose files for the Kafka cluster, Kafka Connect and management application. We can run the whole services by starting them in order as illustrated below.

```bash
$ cd kafka-connect-for-aws/part-02
# download connectors
$ ./download.sh
# starts 3 node kafka cluster
$ docker-compose -f compose-kafka.yml up -d
# starts kafka connect server in distributed mode
$ docker-compose -f compose-connect.yml up -d
# starts kafka-ui
$ docker-compose -f compose-ui.yml up -d
```

## Data Ingestion to Kafka Topic

### Source Connector Creation

As mentioned earlier, Kafka Connect provides a REST API that manages connectors, and we can create a connector programmatically using it. The REST endpoint requires a JSON payload that includes connector configurations.

```bash
$ cd kafka-connect-for-aws/part-02
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/source.json
```

The connector class (*connector.class*) is required for any connector and I set it for the MSK Data Generator. Also, a single worker is allocated to the connector (*tasks.max*). As mentioned earlier, the converter-related properties are overridden. Specifically, the key converter is set to the string converter as the key of the topic is set to be primitive values (*genkp*). Also, schemas are not enabled for both the key and value.

Those properties in the middle are specific to the source connector. Basically it sends messages to a topic named *order*. The key is marked as *to-replace* as it will be replaced with the *order_id* attribute of the value - see below. The value has *order_id*, *product_id*, *quantity*, *customer_id* and *customer_name* attributes, and they are generated by the [Java faker library](https://github.com/DiUS/java-faker).

It can be easier to manage messages if the same order ID is shared with the key and value. We can achieve it using [single message transforms (SMTs)](https://kafka.apache.org/documentation.html#connect_transforms). Specifically I used two transforms - *ValueToKey* and *ExtractField* to achieve it. As the name suggests, the former copies the *order_id* value into the key. The latter is used additionally because the key is set to have primitive string values. Finally, the last transform (*Cast*) is to change the *quantity* value into integer.

```json
// kafka-connect-for-aws/part-02/configs/source.json
{
  "name": "order-source",
  "config": {
    "connector.class": "com.amazonaws.mskdatagen.GeneratorSourceConnector",
    "tasks.max": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,

    "genkp.order.with": "to-replace",
    "genv.order.order_id.with": "#{Internet.uuid}",
    "genv.order.product_id.with": "#{Code.isbn10}",
    "genv.order.quantity.with": "#{number.number_between '1','5'}",
    "genv.order.customer_id.with": "#{number.number_between '100','199'}",
    "genv.order.customer_name.with": "#{Name.full_name}",
    "global.throttle.ms": "500",
    "global.history.records.max": "1000",

    "transforms": "copyIdToKey,extractKeyFromStruct,cast",
    "transforms.copyIdToKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.copyIdToKey.fields": "order_id",
    "transforms.extractKeyFromStruct.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractKeyFromStruct.field": "order_id",
    "transforms.cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
    "transforms.cast.spec": "quantity:int8"
  }
}
```

Once created successfully, we can check the connector status as shown below.

```bash
$ curl http://localhost:8083/connectors/order-source/status
```

```json
{
	"name": "order-source",
	"connector": {
		"state": "RUNNING",
		"worker_id": "172.19.0.6:8083"
	},
	"tasks": [
		{
			"id": 0,
			"state": "RUNNING",
			"worker_id": "172.19.0.6:8083"
		}
	],
	"type": "source"
}
```

As we've added the connector URL, the *Kafka Connect* menu appears on *kafka-ui*. We can check the details of the connector on the app as well. 

![](source-connector.png#center)

### Kafka Topics

As configured, the source connector ingests messages to the *order* topic.

![](topic-01.png#center)

We can browse individual messages in the *Messages* tab of the topic.

![](topic-02.png#center)

## Data Ingestion to DynamoDB
### Table Creation

The destination table is named *orders*, and it has the primary key where *order_id* and *ordered_at* are the hash and range key respectively. It also has a global secondary index where *customer_id* and *ordered_at* constitute the primary key. Note that *ordered_at* is not generated by the source connector as the Java faker library doesn't have a method to generate a current timestamp. As illustrated below it'll be created by the sink connector using SMTs. The table can be created using the AWS CLI as shown below.

```bash
aws dynamodb create-table \
  --cli-input-json file://configs/ddb.json
```

```json
// kafka-connect-for-aws/part-02/configs/ddb.json
{
  "TableName": "orders",
  "KeySchema": [
    { "AttributeName": "order_id", "KeyType": "HASH" },
    { "AttributeName": "ordered_at", "KeyType": "RANGE" }
  ],
  "AttributeDefinitions": [
    { "AttributeName": "order_id", "AttributeType": "S" },
    { "AttributeName": "customer_id", "AttributeType": "S" },
    { "AttributeName": "ordered_at", "AttributeType": "S" }
  ],
  "ProvisionedThroughput": {
    "ReadCapacityUnits": 1,
    "WriteCapacityUnits": 1
  },
  "GlobalSecondaryIndexes": [
    {
      "IndexName": "customer",
      "KeySchema": [
        { "AttributeName": "customer_id", "KeyType": "HASH" },
        { "AttributeName": "ordered_at", "KeyType": "RANGE" }
      ],
      "Projection": { "ProjectionType": "ALL" },
      "ProvisionedThroughput": {
        "ReadCapacityUnits": 1,
        "WriteCapacityUnits": 1
      }
    }
  ]
}
```
### Sink Connector Creation

Similar to the source connector, we can create the sink connector using the REST API.

```bash
$ cd kafka-connect-for-aws/part-02
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/sink.json
```

The connector is configured to write messages from the *order* topic into the DynamoDB table created earlier. It requires to specify the table name, AWS region, operation, write capacity and whether to use the [default credential provider](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html) - see the [documentation](https://camel.apache.org/camel-kafka-connector/3.18.x/reference/connectors/camel-aws-ddb-sink-kafka-sink-connector.html) for details. Note that, if you don't use the default credential provider, you have to specify the *access key id* and *secret access key*. Note further that, although the current LTS version is *v3.18.2*, the default credential provider option didn't work for me, and I was recommended [to use *v3.20.3* instead](https://github.com/apache/camel-kafka-connector/issues/1533). Finally, the [*camel.sink.unmarshal* option](https://github.com/apache/camel-kafka-connector/blob/camel-kafka-connector-3.20.3/connectors/camel-aws-ddb-sink-kafka-connector/src/main/resources/kamelets/aws-ddb-sink.kamelet.yaml#L123) is to convert data from the internal *java.util.HashMap* type into the required *java.io.InputStream* type. Without this configuration, the [connector fails](https://github.com/apache/camel-kafka-connector/issues/1532) with *org.apache.camel.NoTypeConversionAvailableException* error.

Although the destination table has *ordered_at* as the range key, it is not created by the source connector because the Java faker library doesn't have a method to generate a current timestamp. Therefore, it is created by the sink connector using two SMTs - *InsertField* and *TimestampConverter*. Specifically they add a timestamp value to the *order_at* attribute, format the value as *yyyy-MM-dd HH:mm:ss:SSS*, and convert its type into string.

```json
// kafka-connect-for-aws/part-02/configs/sink.json
{
  "name": "order-sink",
  "config": {
    "connector.class": "org.apache.camel.kafkaconnector.awsddbsink.CamelAwsddbsinkSinkConnector",
    "tasks.max": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,
    "topics": "order",

    "camel.kamelet.aws-ddb-sink.table": "orders",
    "camel.kamelet.aws-ddb-sink.region": "ap-southeast-2",
    "camel.kamelet.aws-ddb-sink.operation": "PutItem",
    "camel.kamelet.aws-ddb-sink.writeCapacity": 1,
    "camel.kamelet.aws-ddb-sink.useDefaultCredentialsProvider": true,
    "camel.sink.unmarshal": "jackson",

    "transforms": "insertTS,formatTS",
    "transforms.insertTS.type": "org.apache.kafka.connect.transforms.InsertField$Value",
    "transforms.insertTS.timestamp.field": "ordered_at",
    "transforms.formatTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
    "transforms.formatTS.format": "yyyy-MM-dd HH:mm:ss:SSS",
    "transforms.formatTS.field": "ordered_at",
    "transforms.formatTS.target.type": "string"
  }
}
```

Below shows the sink connector details on *kafka-ui*.

![](sink-connector.png#center)

### DynamoDB Destination

We can check the ingested records on the DynamoDB table items view. Below shows a list of scanned records. As expected, it has the *order_id*, *ordered_at* and other attributes.

![](ddb-01.png#center)

We can also obtain an individual Json record by clicking an *order_id* value as shown below.

![](ddb-02.png#center)

## Summary

The suite of Apache Camel Kafka connectors and the Kinesis Kafka connector from the AWS Labs can be effective for building data ingestion pipelines that integrate AWS services. In this post, I illustrated how to develop the Camel DynamoDB sink connector using Docker. Fake order data was generated using the MSK Data Generator source connector, and the sink connector was configured to consume the topic messages to ingest them into a DynamoDB table.