---
title: Kafka Development with Docker - Part 5 Glue Schema Registry
date: 2023-06-08
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
  - Glue Schema Registry
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: ...
---

As Kafka producer and consumer apps are decoupled, they operate on Kafka topics rather than communicating with each other directly. As described in the [Confluent document](https://docs.confluent.io/platform/current/schema-registry/index.html#sr-overview), _Schema Registry_ provides a centralized repository for managing and validating schemas for topic message data, and for serialization and deserialization of the data over the network. Producers and consumers to Kafka topics can use schemas to ensure data consistency and compatibility as schemas evolve. In AWS, the [Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html) supports features to manage and enforce schemas on data streaming applications using convenient integrations with Apache Kafka, [Amazon Managed Streaming for Apache Kafka](https://aws.amazon.com/msk/), [Amazon Kinesis Data Streams](https://aws.amazon.com/kinesis/data-streams/), [Amazon Kinesis Data Analytics for Apache Flink](https://aws.amazon.com/kinesis/data-analytics/), and [AWS Lambda](https://aws.amazon.com/lambda/). In this post, we will discuss how to integrate Python Kafka producer and consumer apps In AWS Lambda with the Glue Schema Registry.


* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](#) (this post)
* Part 6 Kafka Connect with Glue Schema Registry
* Part 7 Producer and Consumer with Glue Schema Registry
* Part 8 SSL Encryption
* Part 9 SSL Authentication
* Part 10 SASL Authentication
* Part 11 Kafka Authorization

## How Schema Registry Works

![](featured.png#center)

1. Before sending a record, the producer validates that the schema it is using to serialize its records is valid. We can configure the producer to register a new schema version if the schema is not yet registered.
2. When registering the new schema version, the schema registry validates if the schema is compatible.
If the registry detects an incompatibility, the registration is rejected. This ensures that a producer fails early and cannot publish incompatible records in the first place.
Once the schema is valid, the producer serializes and compresses the record and sends it to the Kafka cluster.
3. The consumer reads the serialized and compressed record.
4. The consumer requests the schema from the schema registry (if it is not already cached) and uses the schema to decompress and deserialize the record.

## Alternative Tools

### Confluent Schema Registry

### Apicurio Registry

![](apicurio.png#center)

## Glue Schema Registry Library

In order to integrate the *Glue Schema Registry* with Kafka Connect, we need to use the Glue Schema Registry Library. It offers Serializers and Deserializers

1. Messages/records are serialized on producer front and deserialized on the consumer front by using schema-registry-serde.
2. Support for three data formats: AVRO, JSON (with JSON Schema Draft04, Draft06, Draft07), and Protocol Buffers (Protobuf syntax versions 2 and 3).
3. Kafka Streams support for AWS Glue Schema Registry.
4. Records can be compressed to reduce message size.
5. An inbuilt local in-memory cache to save calls to AWS Glue Schema Registry. The schema version id for a schema definition is cached on Producer side and schema for a schema version id is cached on the Consumer side.
6. Auto registration of schema can be enabled for any new schema to be auto-registered.
7. For Schemas, Evolution check is performed while registering.
8. Migration from a third party Schema Registry.
9. Flink support for AWS Glue Schema Registry.
10. *Kafka Connect support for AWS Glue Schema Registry.*

### Build Library

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"

SRC_PATH=${SCRIPT_DIR}/plugins
rm -rf ${SRC_PATH} && mkdir ${SRC_PATH}

## Dwonload and build glue schema registry
echo "downloading glue schema registry..."
VERSION=v.1.1.15
DOWNLOAD_URL=https://github.com/awslabs/aws-glue-schema-registry/archive/refs/tags/$VERSION.zip
SOURCE_NAME=aws-glue-schema-registry-$VERSION

curl -L -o ${SRC_PATH}/$SOURCE_NAME.zip ${DOWNLOAD_URL} \
  && unzip -qq ${SRC_PATH}/$SOURCE_NAME.zip -d ${SRC_PATH} \
  && rm ${SRC_PATH}/$SOURCE_NAME.zip

echo "building glue schema registry..."
cd plugins/$SOURCE_NAME/build-tools \
  && mvn clean install -DskipTests -Dcheckstyle.skip \
  && cd .. \
  && mvn clean install -DskipTests \
  && mvn dependency:copy-dependencies
```

```bash
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-checkstyle-plugin:3.1.2:check (default) on project schema-registry-build-tools: Failed during checkstyle execution: Unable to find suppressions file at location: /tmp/kafka-pocs/kafka-dev-with-docker/part-05/plugins/aws-glue-schema-registry-v.1.1.15/build-tools/build-tools/src/main/resources/suppressions.xml: Could not find resource '/tmp/kafka-pocs/kafka-dev-with-docker/part-05/plugins/aws-glue-schema-registry-v.1.1.15/build-tools/build-tools/src/main/resources/suppressions.xml'. -> [Help 1]
```

```bash
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for AWS Glue Schema Registry Library 1.1.15:
[INFO] 
[INFO] AWS Glue Schema Registry Library ................... SUCCESS [  0.644 s]
[INFO] AWS Glue Schema Registry Build Tools ............... SUCCESS [  0.038 s]
[INFO] AWS Glue Schema Registry common .................... SUCCESS [  0.432 s]
[INFO] AWS Glue Schema Registry Serializer Deserializer ... SUCCESS [  0.689 s]
[INFO] AWS Glue Schema Registry Serializer Deserializer with MSK IAM Authentication client SUCCESS [  0.216 s]
[INFO] AWS Glue Schema Registry Kafka Streams SerDe ....... SUCCESS [  0.173 s]
[INFO] AWS Glue Schema Registry Kafka Connect AVRO Converter SUCCESS [  0.190 s]
[INFO] AWS Glue Schema Registry Flink Avro Serialization Deserialization Schema SUCCESS [  0.541 s]
[INFO] AWS Glue Schema Registry examples .................. SUCCESS [  0.211 s]
[INFO] AWS Glue Schema Registry Integration Tests ......... SUCCESS [  0.648 s]
[INFO] AWS Glue Schema Registry Kafka Connect JSONSchema Converter SUCCESS [  0.239 s]
[INFO] AWS Glue Schema Registry Kafka Connect Converter for Protobuf SUCCESS [  0.296 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  5.287 s
[INFO] Finished at: 2023-05-19T08:08:51+10:00
[INFO] ------------------------------------------------------------------------
```

```bash
plugins/aws-glue-schema-registry-v.1.1.15/avro-kafkaconnect-converter/target/
├...
├── schema-registry-kafkaconnect-converter-1.1.15.jar

plugins/aws-glue-schema-registry-v.1.1.15/jsonschema-kafkaconnect-converter/target/
├...
├── jsonschema-kafkaconnect-converter-1.1.15.jar

plugins/aws-glue-schema-registry-v.1.1.15/protobuf-kafkaconnect-converter/target/
├...
├── protobuf-kafkaconnect-converter-1.1.15.jar
```

## Summary