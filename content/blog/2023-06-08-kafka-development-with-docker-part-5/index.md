---
title: Kafka Development with Docker - Part 5 Glue Schema Registry
date: 2023-06-08
draft: false
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
authors:
  - JaehyeonKim
images: []
description: The Glue Schema Registry supports features to manage and enforce schemas on data streaming applications using convenient integrations with Apache Kafka and other AWS managed services. In order to utilise those features, we need to use the client library. In this post, I'll illustrate how to build the client library after introducing how it works to integrate the Glue Schema Registry with Kafka producer and consumer apps.
---

As described in the [Confluent document](https://docs.confluent.io/platform/current/schema-registry/index.html#sr-overview), _Schema Registry_ provides a centralized repository for managing and validating schemas for topic message data, and for serialization and deserialization of the data over the network. Producers and consumers to Kafka topics can use schemas to ensure data consistency and compatibility as schemas evolve. In AWS, the [Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html) supports features to manage and enforce schemas on data streaming applications using convenient integrations with Apache Kafka, [Amazon Managed Streaming for Apache Kafka](https://aws.amazon.com/msk/), [Amazon Kinesis Data Streams](https://aws.amazon.com/kinesis/data-streams/), [Amazon Kinesis Data Analytics for Apache Flink](https://aws.amazon.com/kinesis/data-analytics/), and [AWS Lambda](https://aws.amazon.com/lambda/).

In order to integrate the *Glue Schema Registry* with an application, we need to use the [AWS Glue Schema Registry Client library](https://github.com/awslabs/aws-glue-schema-registry), which primarily provides serializers and deserializers for Avro, Json and Portobuf formats. It also supports other necessary features such as registering schemas and performing compatibility check. As the project doesn't provide pre-built binaries, we have to build them on our own. In this post, I'll illustrate how to build the client library after introducing how it works to integrate the Glue Schema Registry with Kafka producer and consumer apps. Once built successfully, we can obtain multiple binaries not only for Kafka Connect but also other applications such as Flink for Kinesis Data Analytics. Therefore, this post can be considered as a stepping stone for later posts.

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](#) (this post)
* [Part 6 Kafka Connect with Glue Schema Registry](/blog/2023-06-15-kafka-development-with-docker-part-6)
* [Part 7 Producer and Consumer with Glue Schema Registry](/blog/2023-06-22-kafka-development-with-docker-part-7)
* [Part 8 SSL Encryption](/blog/2023-06-29-kafka-development-with-docker-part-8)
* [Part 9 SSL Authentication](/blog/2023-07-06-kafka-development-with-docker-part-9)
* [Part 10 SASL Authentication](/blog/2023-07-13-kafka-development-with-docker-part-10)
* [Part 11 Kafka Authorization](/blog/2023-07-20-kafka-development-with-docker-part-11)

## How It Works with Apache Kafka

The below diagram shows how Kafka producer and consumer apps are integrated with the *Glue Schema Registry*. As Kafka producer and consumer apps are decoupled, they operate on Kafka topics rather than communicating with each other directly. Therefore, it is important to have a schema registry that manages/stores schemas and validates them.

![](featured.png#center)

1. The producer checks whether the schema that is used for serializing records is valid. Also, a new schema version is registered if it is yet to be done so. 
    + Note the schema registry preforms compatibility checks while registering a new schema version. If it turns out to be incompatible, registration fails and the producer fails to send messages. 
2. The producer serializes and compresses messages and sends them to the Kafka cluster.
3. The consumer reads the serialized and compressed messages.
4. The consumer retrieves the schema from the schema registry (if it is yet to be cached) and uses it to decompress and deserialize messages.

## Glue Schema Registry Client Library

As mentioned earlier, the *Glue Schema Registry Client library* primarily provides serializers and deserializers for Avro, Json and Portobuf formats. It also supports other necessary features such as registering schemas and performing compatibility check. Below lists the main features of the library.

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

It can work with Apache Kafka as well as other AWS services. See this [AWS documentation](https://docs.aws.amazon.com/glue/latest/dg/schema-registry-integrations.html) for its integration use cases listed below.

* Connecting Schema Registry to Amazon MSK or Apache Kafka
* Integrating Amazon Kinesis Data Streams with the AWS Glue Schema Registry
* Amazon Kinesis Data Analytics for Apache Flink
* Integration with AWS Lambda
* AWS Glue Data Catalog
* AWS Glue streaming
* Apache Kafka Streams
* Apache Kafka Connect

## Build Glue Schema Registry Client Library

In order to build the client library, we need to have both the [JDK](https://openjdk.org/) and [Maven](https://maven.apache.org/) installed. I use Ubuntu 18.04 on WSL2 and both the apps are downloaded from the Ubuntu package manager.

```bash
$ sudo apt update && sudo apt install -y openjdk-11-jdk maven
...
$ mvn --version
Apache Maven 3.6.3
Maven home: /usr/share/maven
Java version: 11.0.19, vendor: Ubuntu, runtime: /usr/lib/jvm/java-11-openjdk-amd64
Default locale: en, platform encoding: UTF-8
OS name: "linux", version: "5.4.72-microsoft-standard-wsl2", arch: "amd64", family: "unix"
```

We first need to download the source archive from the project repository. The latest version is *v.1.1.15* at the time of writing this post, and it can be downloaded using *curl* with *-L* flag in order to follow the redirected download URL. Once downloaded, we can build the binaries as indicated in the [project repository](https://github.com/awslabs/aws-glue-schema-registry#using-kafka-connect-with-aws-glue-schema-registry). The script shown below downloads and builds the client library. It can also be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-05) of this post.

```bash
# kafka-dev-with-docker/part-05/build.sh
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

Note that I skipped tests with the `-DskipTests` option in order to save build time. Note further that I also skipped [checkstyle execution](https://maven.apache.org/plugins/maven-checkstyle-plugin/) with the `-Dcheckstyle.skip` option as I encountered the following error.  

```bash
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-checkstyle-plugin:3.1.2:check (default) on project schema-registry-build-tools: Failed during checkstyle execution: Unable to find suppressions file at location: /tmp/kafka-pocs/kafka-dev-with-docker/part-05/plugins/aws-glue-schema-registry-v.1.1.15/build-tools/build-tools/src/main/resources/suppressions.xml: Could not find resource '/tmp/kafka-pocs/kafka-dev-with-docker/part-05/plugins/aws-glue-schema-registry-v.1.1.15/build-tools/build-tools/src/main/resources/suppressions.xml'. -> [Help 1]
```

Once it was built successfully, I was able to see the following messages.

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

As can be checked in the build messages, we can obtain binaries not only for Kafka Connect but also other applications such as Flink for Kinesis Data Analytics. Below shows all the available binaries.

```bash
## kafka connect
plugins/aws-glue-schema-registry-v.1.1.15/avro-kafkaconnect-converter/target/
├...
├── schema-registry-kafkaconnect-converter-1.1.15.jar
plugins/aws-glue-schema-registry-v.1.1.15/jsonschema-kafkaconnect-converter/target/
├...
├── jsonschema-kafkaconnect-converter-1.1.15.jar
plugins/aws-glue-schema-registry-v.1.1.15/protobuf-kafkaconnect-converter/target/
├...
├── protobuf-kafkaconnect-converter-1.1.15.jar
## flink
plugins/aws-glue-schema-registry-v.1.1.15/avro-flink-serde/target/
├...
├── schema-registry-flink-serde-1.1.15.jar
## kafka streams
plugins/aws-glue-schema-registry-v.1.1.15/kafkastreams-serde/target/
├...
├── schema-registry-kafkastreams-serde-1.1.15.jar
## serializer/descrializer
plugins/aws-glue-schema-registry-v.1.1.15/serializer-deserializer/target/
├...
├── schema-registry-serde-1.1.15.jar
plugins/aws-glue-schema-registry-v.1.1.15/serializer-deserializer-msk-iam/target/
├...
├── schema-registry-serde-msk-iam-1.1.15.jar
```

## Summary

The Glue Schema Registry supports features to manage and enforce schemas on data streaming applications using convenient integrations with Apache Kafka and other AWS managed services. In order to utilise those features, we need to use the client library. In this post, I illustrated how to build the client library after introducing how it works to integrate the Glue Schema Registry with Kafka producer and consumer apps.