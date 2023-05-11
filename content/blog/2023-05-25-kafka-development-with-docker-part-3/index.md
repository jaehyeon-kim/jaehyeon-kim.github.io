---
title: Kafka Development with Docker - Part 3 Kafka Connect
date: 2023-05-25
draft: true
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development with Docker
categories:
  - Apache Kafka
tags: 
  - Apache Kafka
  - Kafka Connect
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. In this post, I will introduce how to set up a source and sink connectors on Docker.I will introduce how to set up a source and sink connectors on Docker. Fake customer and order data will be ingested into the corresponding topics using the MSK Data Generator source connector. The messages in the topics will then be saved into a S3 bucket using the Confluent S3 sink connector.
---

According to the documentation of [Apache Kafka](https://kafka.apache.org/documentation/#connect), *Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka and other systems. It makes it simple to quickly define connectors that move large collections of data into and out of Kafka*. Kafka Connect supports two types of connectors - source and sink. Source connectors are used to ingest messages from external systems into Kafka topics while messages are ingested into external systems form Kafka topics with sink connectors. In this post, I will introduce how to set up a source and sink connectors on Docker. Fake customer and order data will be ingested into the corresponding topics using the [MSK Data Generator](https://github.com/awslabs/amazon-msk-data-generator) source connector. The messages in the topics will then be saved into a S3 bucket using the [Confluent S3](https://www.confluent.io/hub/confluentinc/kafka-connect-s3) sink connector.


* [Part 1 Kafka Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Kafka Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](#) (this post)
* Part 4 Glue Schema Registry
* Part 5 Kafka Connect with Glue Schema Registry
* Part 6 SSL Encryption
* Part 7 SSL Authentication
* Part 8 SASL Authentication
* Part 9 Kafka Authorization
* (More topics related to MSK, MSK Connect...)

## Kafka Connect Setup

*Kafka Connect* is included in the Kafka distribution, and we can use the same Docker image. As we will create multiple 

```yaml
# /kafka-dev-with-docker/part-03/compose-connect.yml
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
      - "./connectors/confluent-s3/lib:/opt/connectors/confluent-s3"
      - "./connectors/msk-datagen:/opt/connectors/msk-datagen"

networks:
  kafkanet:
    external: true
    name: kafka-network
```

### Connect Configuration

```java-properties
# kafka-dev-with-docker/part-03/configs/connect-distributed.properties

# A list of host/port pairs to use for establishing the initial connection to the Kafka cluster.
bootstrap.servers=kafka-0:9092,kafka-1:9092,kafka-2:9092

# unique name for the cluster, used in forming the Connect cluster group. Note that this must not conflict with consumer group IDs
group.id=connect-cluster

# The converters specify the format of data in Kafka and how to translate it into Connect data. Every Connect user will
# need to configure these based on the format they want their data in when loaded from or stored into Kafka
key.converter=org.apache.kafka.connect.storage.StringConverter
value.converter=org.apache.kafka.connect.storage.StringConverter
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

# Flush much faster than normal, which is useful for testing/debugging
offset.flush.interval.ms=10000

...

# Set to a list of filesystem paths separated by commas (,) to enable class loading isolation for plugins
# (connectors, converters, transformations). The list should consist of top level directories that include 
# any combination of: 
# a) directories immediately containing jars with plugins and their dependencies
# b) uber-jars with plugins and their dependencies
# c) directories immediately containing the package directory structure of classes of plugins and their dependencies
# Examples: 
# plugin.path=/usr/local/share/java,/usr/local/share/kafka/plugins,/opt/connectors,
# plugin.path=/opt/connectors/debezium-postgres,/opt/connectors/lenses-s3,/opt/connectors/mdrogalis-voluble
plugin.path=/opt/connectors
```

### Download Connectors

```bash
# /kafka-dev-with-docker/part-03/download.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

SRC_PATH=${SCRIPT_DIR}/connectors
rm -rf ${SRC_PATH} && mkdir -p ${SRC_PATH}/msk-datagen

## Confluent S3 Sink Connector
echo "downloading confluent s3 connector..."
DOWNLOAD_URL=https://d1i4a15mxbxib1.cloudfront.net/api/plugins/confluentinc/kafka-connect-s3/versions/10.4.3/confluentinc-kafka-connect-s3-10.4.3.zip

curl -o ${SRC_PATH}/confluent.zip ${DOWNLOAD_URL} \
  && unzip -qq ${SRC_PATH}/confluent.zip -d ${SRC_PATH} \
  && rm ${SRC_PATH}/confluent.zip \
  && mv ${SRC_PATH}/$(ls ${SRC_PATH} | grep confluentinc-kafka-connect-s3) ${SRC_PATH}/confluent-s3

## MSK Data Generator Souce Connector
echo "downloading msk data generator..."
DOWNLOAD_URL=https://github.com/awslabs/amazon-msk-data-generator/releases/download/v0.4.0/msk-data-generator-0.4-jar-with-dependencies.jar

curl -L -o ${SRC_PATH}/msk-datagen/msk-data-generator.jar ${DOWNLOAD_URL}
```

### Start All Services

```bash
$ cd kafka-dev-with-docker/part-03
$ docker-compose -f compose-kafka.yml up -d
$ docker-compose -f compose-connect.yml up -d
$ docker-compose -f compose-ui.yml up -d
```

## Source Connector Creation

```json
// kafka-dev-with-docker/part-03/configs/source.json
{
  "name": "order-source",
  "config": {
    "connector.class": "com.amazonaws.mskdatagen.GeneratorSourceConnector",
    "tasks.max": "2",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,

    "genkp.customer.with": "#{Code.isbn10}",
    "genv.customer.name.with": "#{Name.full_name}",

    "genkp.order.with": "#{Internet.uuid}",
    "genv.order.product_id.with": "#{number.number_between '101','109'}",
    "genv.order.quantity.with": "#{number.number_between '1','5'}",
    "genv.order.customer_id.matching": "customer.key",

    "global.throttle.ms": "500",
    "global.history.records.max": "1000"
  }
}
```

```bash
$ cd kafka-dev-with-docker/part-03
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/source.json
```

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
		},
		{
			"id": 1,
			"state": "RUNNING",
			"worker_id": "172.19.0.6:8083"
		}
	],
	"type": "source"
}
```

![](source-connector.png#center)

### Kafka Topics

![](topics-01.png#center)

![](topics-02.png#center)

## Sink Connector Creation

```json
// kafka-dev-with-docker/part-03/configs/sink.json
{
  "name": "order-sink",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
    "tasks.max": "2",
    "topics": "order,customer",
    "s3.bucket.name": "kafka-dev-ap-southeast-2",
    "s3.region": "ap-southeast-2",
    "flush.size": "100",
    "rotate.schedule.interval.ms": "60000",
    "timezone": "Australia/Sydney",
    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,
    "errors.log.enable": "true"
  }
}
```

```bash
$ cd kafka-dev-with-docker/part-03
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/sink.json
```

![](sink-connector.png#center)

### Kafka Consumers

![](consumer-01.png#center)

![](consumer-02.png#center)

### S3 Destination

![](s3-01.png#center)


![](s3-02.png#center)


![](s3-03.png#center)

## Summary