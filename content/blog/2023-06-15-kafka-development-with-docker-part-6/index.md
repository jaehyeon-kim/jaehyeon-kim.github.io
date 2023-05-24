---
title: Kafka Development with Docker - Part 6 Kafka Connect with Glue Schema Registry
date: 2023-06-15
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
  - Glue Schema Registry
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: In Part 3, we developed a data ingestion pipeline of fake online orders data using Kafka Connect source and sink connectors without integrating schema registry. Later we discussed the benefits of schema registry when developing Kafka applications in Part 5. In this post, I'll demonstrate how to enhance the existing data ingestion pipeline by integrating AWS Glue Schema Registry.
---

In [Part 3](/blog/2023-05-25-kafka-development-with-docker-part-3), we developed a data ingestion pipeline of fake online orders data using Kafka Connect source and sink connectors. Schemas are not enabled on both the connectors as there was not an integrated schema registry. In [Part 5](/blog/2023-06-08-kafka-development-with-docker-part-5), we discussed how schema registry can improve robustness of Kafka applications by validating schemas. In this post, I'll demonstrate how to enhance the existing data ingestion pipeline by integrating [*AWS Glue Schema Registry*](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html).

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](/blog/2023-06-08-kafka-development-with-docker-part-5)
* [Part 6 Kafka Connect with Glue Schema Registry](#) (this post)
* Part 7 Producer and Consumer with Glue Schema Registry
* Part 8 SSL Encryption
* Part 9 SSL Authentication
* Part 10 SASL Authentication
* Part 11 Kafka Authorization

## Kafka Connect Setup

We can use the same Docker image because *Kafka Connect* is included in the Kafka distribution. The Kafka Connect server runs as a separate docker compose service, and its key configurations are listed below.

* We'll run it as the [distributed mode](https://docs.confluent.io/platform/current/connect/concepts.html#distributed-workers), and it can be started by executing *connect-distributed.sh* on the Docker command. 
  * The startup script requires the properties file (*connect-distributed.properties*). It includes configurations such as Kafka broker server addresses - see below for details. 
* The Connect server is accessible on port 8083, and we can manage connectors via a REST API as demonstrated below.
* The properties file, connector sources, and binary of Kafka Connect Avro converter are volume-mapped.
* AWS credentials are added to environment variables as the sink connector requires permission to write data into S3. 

The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-06) of this post.

```yaml
# /kafka-dev-with-docker/part-06/compose-connect.yml
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
      - "./plugins/aws-glue-schema-registry-v.1.1.15/avro-kafkaconnect-converter/target:/opt/glue-schema-registry/avro"

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
  - `/opt/glue-schema-registry` is for the binary file of Kafka Connect Avro converter.

```java-properties
# kafka-dev-with-docker/part-06/configs/connect-distributed.properties

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
plugin.path=/opt/connectors,/opt/glue-schema-registry
```

### Download Connectors

The connector sources need to be downloaded into the respective host paths (`./connectors/confluent-s3` and `./connectors/msk-datagen`) so that they are volume-mapped to the container's plugin path (`/opt/connectors`). The following script downloads them into the host paths. Not that it also downloads the [serde binary](https://github.com/provectus/kafkaui-glue-sr-serde) of kafka-ui, and it'll be used separately for the kafka-ui service.

```bash
# /kafka-dev-with-docker/part-06/download.sh
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

## Kafka UI Glue SERDE
echo "downloading kafka ui glue serde..."
DOWNLOAD_URL=https://github.com/provectus/kafkaui-glue-sr-serde/releases/download/v1.0.3/kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar

curl -L -o ${SCRIPT_DIR}/kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar ${DOWNLOAD_URL}
```

Below shows the folder structure after the connectors are downloaded successfully.

```bash
$ tree connectors/ -d
connectors/
├── confluent-s3
│   ├── assets
│   ├── doc
│   │   ├── licenses
│   │   └── notices
│   ├── etc
│   └── lib
└── msk-datagen
```

### Build Glue Schema Registry Client

As demonstrated in [Part 5](/blog/2023-06-08-kafka-development-with-docker-part-5), we need to build the [Glue Schema Registry Client library](https://github.com/awslabs/aws-glue-schema-registry) as it provides serializers/deserializers and related functionalities. It can be built with the following script - see the previous post for details. 

```bash
# /kafka-dev-with-docker/part-06/build.sh
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

Once it is build successfully, we should be able to use the following binary files. We'll only use the Avro converter in this post.

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
...
```

## Kafka Management App

We should configure additional details in environment variables in order to integrate Glue Schema Registry. While both apps provide serializers/deserializers, *kpow* supports to manage schemas to some extent as well.

For *kafka-ui*, we can add one or more [serialization plugins](https://docs.kafka-ui.provectus.io/configuration/serialization-serde). I added the [Glue registry serializer](https://github.com/provectus/kafkaui-glue-sr-serde) as a plugin and named it *online-order*. It requires the plugin binary file path, class name, registry name and AWS region name. Another key configuration values are the key and value schema templates values, which are used for finding schema names. They are left unchanged because I will not enable schema for the key and the default template rule (`%s`) for the value matches the default naming convention of the client library. Note that the template values are applicable for producing messages on the UI. Therefore, we can leave them commented out if we don't produce messages on it.

The configuration of *kpow* is simpler as it only requires the registry ARN and AWS region. Note that the app fails to start if the registry doesn't exit. I created the registry named *online-order* before starting it.

```yaml
# /kafka-dev-with-docker/part-06/compose-ui.yml
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
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      # kafka cluster
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9092,kafka-1:9092,kafka-2:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
      # kafka connect
      KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: local
      KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: http://kafka-connect:8083
      # glue schema registry serde
      KAFKA_CLUSTERS_0_SERDE_0_NAME: online-order
      KAFKA_CLUSTERS_0_SERDE_0_FILEPATH: /glue-serde/kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar
      KAFKA_CLUSTERS_0_SERDE_0_CLASSNAME: com.provectus.kafka.ui.serdes.glue.GlueSerde
      KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_REGION: $AWS_DEFAULT_REGION #required
      KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_REGISTRY: online-order #required, name of Glue Schema Registry
      # template that will be used to find schema name for topic key. Optional, default is null (not set).
      # KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_KEYSCHEMANAMETEMPLATE: "%s-key"
      # template that will be used to find schema name for topic value. Optional, default is '%s'
      # KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_VALUESCHEMANAMETEMPLATE: "%s-value"
    volumes:
      - ./kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar:/glue-serde/kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar
  kpow:
    image: factorhouse/kpow-ce:91.2.1
    container_name: kpow
    ports:
      - "3000:3000"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      # kafka cluster
      BOOTSTRAP: kafka-0:9092,kafka-1:9092,kafka-2:9092
      # glue schema registry
      SCHEMA_REGISTRY_ARN: $SCHEMA_REGISTRY_ARN
      SCHEMA_REGISTRY_REGION: $AWS_DEFAULT_REGION
      # kafka connect
      CONNECT_REST_URL: http://kafka-connect:8083

networks:
  kafkanet:
    external: true
    name: kafka-network
```

## Start Docker Compose Services

There are 3 docker compose files for the Kafka cluster, Kafka Connect and management applications. We can run the whole services by starting them in order. The order matters as the Connect server relies on the Kafka cluster and *kpow* in *compose-ui.yml* fails if the Connect server is not up and running.

```bash
$ cd kafka-dev-with-docker/part-06
# download connectors
$ ./download.sh
# build glue schema registry client library
$ ./build.sh
# starts 3 node kafka cluster
$ docker-compose -f compose-kafka.yml up -d
# starts kafka connect server in distributed mode
$ docker-compose -f compose-connect.yml up -d
# starts kafka-ui and kpow
$ docker-compose -f compose-ui.yml up -d
```

## Source Connector Creation

As mentioned earlier, Kafka Connect provides a REST API that manages connectors. We can create a connector programmatically. The REST endpoint requires a JSON payload that includes connector configurations.

```bash
$ cd kafka-dev-with-docker/part-06
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/source.json
```

The connector class (*connector.class*) is required for any connector and I set it for the MSK Data Generator. Also, as many as two workers are allocated to the connector (*tasks.max*). As mentioned earlier, the converter-related properties are overridden. Specifically, the key converter is set to the string converter as the keys of both topics are set to be primitive values (*genkp*). Also, schema is not enabled for the key. On the other hand, schema is enabled for the value and the value converter is configured to the Avro converter of the Glue Schema Registry client library. The converter requires additional properties that cover AWS region, registry name, record type and flag to indicate whether to auto-generate schemas. Note that the generated schema name is the same to the topic name by default. You can configure a custom schema name by the *schemaName* property.

The remaining properties are specific to the source connectors. Basically it sends messages to two topics (*customer* and *order*). They are linked by the *customer_id* attribute of the *order* topic where the value is from the key of the *customer* topic. This is useful for practicing stream processing e.g. for joining two streams.

```json
// kafka-dev-with-docker/part-06/configs/source.json
{
  "name": "order-source",
  "config": {
    "connector.class": "com.amazonaws.mskdatagen.GeneratorSourceConnector",
    "tasks.max": "2",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": false,
    "value.converter": "com.amazonaws.services.schemaregistry.kafkaconnect.AWSKafkaAvroConverter",
    "value.converter.schemas.enable": true,
    "value.converter.region": "ap-southeast-2",
    "value.converter.schemaAutoRegistrationEnabled": true,
    "value.converter.avroRecordType": "GENERIC_RECORD",
    "value.converter.registry.name": "online-order",

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

As we've added the connector URL, the *Kafka Connect* menu gets appeared on *kafka-ui*. We can check the details of the connector on the app as well. 

![](source-connector.png#center)

### Schemas

As we enabled auto-registration of schemas, the source connector generates two schemas. Below shows the schema for the order topic.

```json
// kafka-dev-with-docker/part-06/configs/order.avsc
{
  "type": "record",
  "name": "Gen0",
  "namespace": "com.amazonaws.mskdatagen",
  "fields": [
    {
      "name": "quantity",
      "type": ["null", "string"],
      "default": null
    },
    {
      "name": "product_id",
      "type": ["null", "string"],
      "default": null
    },
    {
      "name": "customer_id",
      "type": ["null", "string"],
      "default": null
    }
  ],
  "connect.name": "com.amazonaws.mskdatagen.Gen0"
}
```

On AWS Console, we can check the schemas of the two topics are created.

![](schemas-01.png#center)

Also, we are able to see the schemas on *kpow*. The community edition only supports a single schema registry and its name is marked as *glue1*.

![](schemas-02.png#center)

### Kafka Topics

As configured, the source connector ingests messages to the *customer* and *order* topics.

![](topics-01.png#center)

We can browse individual messages in the *Messages* tab. Note that we should select the Glue serializer plugin name (*online-order*) on the *Value Serde* drop down list. Otherwise, records won't be deserialized correctly.

![](topics-02.png#center)

We can check the topic messages on *kpow* as well. If we select *AVRO* on the *Value Deserializer* drop down list, it requires to select the associating schema registry. We can select the pre-set schema registry name of *glue1*. Upon hitting the *Search* button, messages show up after being deserialized properly.

![](topics-03-01.png#center)

![](topics-03-02.png#center)

## Sink Connector Creation

Similar to the source connector, we can create the sink connector using the REST API.

```bash
$ cd kafka-dev-with-docker/part-06
$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @configs/sink.json
```

The connector is configured to write messages from both the topics (*topics*) into a S3 bucket (*s3.bucket.name*) where files are prefixed by the partition number (*DefaultPartitioner*). Also, it invokes file commits every 60 seconds (*rotate.schedule.interval.ms*) or the number of messages reach 100 (*flush.size*). Like the source connector, it overrides the converter-related properties.

```json
// kafka-dev-with-docker/part-06/configs/sink.json
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
    "value.converter": "com.amazonaws.services.schemaregistry.kafkaconnect.AWSKafkaAvroConverter",
    "value.converter.schemas.enable": true,
    "value.converter.region": "ap-southeast-2",
    "value.converter.avroRecordType": "GENERIC_RECORD",
    "value.converter.registry.name": "online-order",
    "errors.log.enable": "true"
  }
}
```

Below shows the sink connector details on *kafka-ui*.

![](sink-connector.png#center)

### Kafka Consumers

The sink connector creates a Kafka consumer, and it is named as *connect-order-sink*. We see that it subscribes the two topics and is in the stable state. It has two members because it is configured to have as many as 2 tasks.

![](consumer-01.png#center)

### S3 Destination

The sink connector writes messages of the two topics (*customer* and *order*), and topic names are used as prefixes. 

![](s3-01.png#center)

As mentioned, the default partitioner prefixes files further by the partition number, and it can be checked below.

![](s3-02.png#center)

The files are generated by `<topic>+<partiton>+<start-offset>.json`. The sink connector's format class is set to *io.confluent.connect.s3.format.json.JsonFormat* so that it writes to Json files.

![](s3-03.png#center)

## Summary

In Part 3, we developed a data ingestion pipeline of fake online orders data using Kafka Connect source and sink connectors without integrating schema registry. Later we discussed the benefits of schema registry when developing Kafka applications in Part 5. In this post, I demonstrated how to enhance the existing data ingestion pipeline by integrating AWS Glue Schema Registry.