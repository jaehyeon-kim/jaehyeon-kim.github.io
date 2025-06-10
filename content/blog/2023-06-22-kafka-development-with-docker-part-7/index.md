---
title: Kafka Development with Docker - Part 7 Producer and Consumer with Glue Schema Registry
date: 2023-06-22
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
  - Data Streaming
tags: 
  - AWS
  - AWS Glue Schema Registry
  - Apache Kafka
  - Docker
  - Python
  - Kpow
authors:
  - JaehyeonKim
images: []
description: In Part 4, we developed Kafka producer and consumer applications using the kafka-python package without integrating schema registry. Later we discussed the benefits of schema registry when developing Kafka applications in Part 5. In this post, I'll demonstrate how to enhance the existing applications by integrating AWS Glue Schema Registry.
---

In [Part 4](/blog/2023-06-01-kafka-development-with-docker-part-4), we developed Kafka producer and consumer applications using the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package. The Kafka messages are serialized as Json, but are not associated with a schema as there was not an integrated schema registry. Later we discussed how producers and consumers to Kafka topics can use schemas to ensure data consistency and compatibility as schemas evolve in [Part 5](/blog/2023-06-08-kafka-development-with-docker-part-5). In this post, I'll demonstrate how to enhance the existing applications by integrating [*AWS Glue Schema Registry*](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html).

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](/blog/2023-06-08-kafka-development-with-docker-part-5)
* [Part 6 Kafka Connect with Glue Schema Registry](/blog/2023-06-15-kafka-development-with-docker-part-6)
* [Part 7 Producer and Consumer with Glue Schema Registry](#) (this post)
* [Part 8 SSL Encryption](/blog/2023-06-29-kafka-development-with-docker-part-8)
* [Part 9 SSL Authentication](/blog/2023-07-06-kafka-development-with-docker-part-9)
* [Part 10 SASL Authentication](/blog/2023-07-13-kafka-development-with-docker-part-10)
* [Part 11 Kafka Authorization](/blog/2023-07-20-kafka-development-with-docker-part-11)

## Producer

Fake order data is generated using the [Faker](https://faker.readthedocs.io/en/master/) package and the [dataclasses_avroschema](https://pypi.org/project/dataclasses-avroschema/) package is used to automatically generate the Avro schema according to its attributes. A mixin class called *InjectCompatMixin* is injected into the *Order* class, which specifies a schema [compatibility mode](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html#schema-registry-compatibility) into the generated schema. The `auto()` class method is used to generate an order record by instantiating the class.

The [aws-glue-schema-registry](https://pypi.org/project/aws-glue-schema-registry/) package is used serialize order records. It provides the *KafkaSerializer* class that validates, registers and serializes the relevant records. It supports Json and Avro schemas, and we can add it to the *value_serializer* argument of the *KafkaProducer* class. By default, the schemas are named as `<topic>-key` and `<topic>-value` and it can be changed by updating the [*schema_naming_strategy* argument](https://github.com/DisasterAWARE/aws-glue-schema-registry-python/blob/main/src/aws_schema_registry/serde.py#L54). Note that, when sending a message, the value should be a tuple of data and schema.

The producer application can be run simply by `python producer.py`. Note that, as the producer runs outside the Docker network, the host name of the external listener (`localhost:29092`) should be used as the bootstrap server address. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-07) of this post.

```python
# kafka-pocs/kafka-dev-with-docker/part-07/producer.py
import os
import datetime
import time
import json
import typing
import logging
import dataclasses
import enum

from faker import Faker
from dataclasses_avroschema import AvroModel
import boto3
import botocore.exceptions
from kafka import KafkaProducer
from aws_schema_registry import SchemaRegistryClient
from aws_schema_registry.avro import AvroSchema
from aws_schema_registry.adapter.kafka import KafkaSerializer

logging.basicConfig(level=logging.INFO)


class Compatibility(enum.Enum):
    NONE = "NONE"
    DISABLED = "DISABLED"
    BACKWARD = "BACKWARD"
    BACKWARD_ALL = "BACKWARD_ALL"
    FORWARD = "FORWARD"
    FORWARD_ALL = "FORWARD_ALL"
    FULL = "FULL"
    FULL_ALL = "FULL_ALL"


class InjectCompatMixin:
    @classmethod
    def updated_avro_schema_to_python(cls, compat: Compatibility = Compatibility.BACKWARD):
        schema = cls.avro_schema_to_python()
        schema["compatibility"] = compat.value
        return schema

    @classmethod
    def updated_avro_schema(cls, compat: Compatibility = Compatibility.BACKWARD):
        schema = cls.updated_avro_schema_to_python(compat)
        return json.dumps(schema)


@dataclasses.dataclass
class OrderItem(AvroModel):
    product_id: int
    quantity: int


@dataclasses.dataclass
class Order(AvroModel, InjectCompatMixin):
    "Online fake order item"
    order_id: str
    ordered_at: datetime.datetime
    user_id: str
    order_items: typing.List[OrderItem]

    class Meta:
        namespace = "Order V1"

    def asdict(self):
        return dataclasses.asdict(self)

    @classmethod
    def auto(cls, fake: Faker = Faker()):
        user_id = str(fake.random_int(1, 100)).zfill(3)
        order_items = [
            OrderItem(fake.random_int(1, 1000), fake.random_int(1, 10))
            for _ in range(fake.random_int(1, 4))
        ]
        return cls(fake.uuid4(), datetime.datetime.utcnow(), user_id, order_items)

    def create(self, num: int):
        return [self.auto() for _ in range(num)]


class Producer:
    def __init__(self, bootstrap_servers: list, topic: str, registry: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.registry = registry
        self.glue_client = boto3.client(
            "glue", region_name=os.getenv("AWS_DEFAULT_REGION", "ap-southeast-2")
        )
        self.producer = self.create()

    @property
    def serializer(self):
        client = SchemaRegistryClient(self.glue_client, registry_name=self.registry)
        return KafkaSerializer(client)

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            key_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            value_serializer=self.serializer,
        )

    def send(self, orders: typing.List[Order], schema: AvroSchema):
        if not self.check_registry():
            print(f"registry not found, create {self.registry}")
            self.create_registry()

        for order in orders:
            try:
                self.producer.send(
                    self.topic, key={"order_id": order.order_id}, value=(order.asdict(), schema)
                )
            except Exception as e:
                raise RuntimeError("fails to send a message") from e
        self.producer.flush()

    def serialize(self, obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        if isinstance(obj, datetime.date):
            return str(obj)
        return obj

    def check_registry(self):
        try:
            self.glue_client.get_registry(RegistryId={"RegistryName": self.registry})
            return True
        except botocore.exceptions.ClientError as e:
            if e.response["Error"]["Code"] == "EntityNotFoundException":
                return False
            else:
                raise e

    def create_registry(self):
        try:
            self.glue_client.create_registry(RegistryName=self.registry)
            return True
        except botocore.exceptions.ClientError as e:
            if e.response["Error"]["Code"] == "AlreadyExistsException":
                return True
            else:
                raise e


if __name__ == "__main__":
    producer = Producer(
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:29092").split(","),
        topic=os.getenv("TOPIC_NAME", "orders"),
        registry=os.getenv("REGISTRY_NAME", "online-order"),
    )
    max_run = int(os.getenv("MAX_RUN", "-1"))
    logging.info(f"max run - {max_run}")
    current_run = 0
    while True:
        current_run += 1
        logging.info(f"current run - {current_run}")
        if current_run > max_run and max_run >= 0:
            logging.info(f"exceeds max run, finish")
            producer.producer.close()
            break
        orders = Order.auto().create(1)
        schema = AvroSchema(Order.updated_avro_schema(Compatibility.BACKWARD))
        producer.send(Order.auto().create(100), schema)
        time.sleep(1)
```

The generated schema of the *Order* class can be found below.

```json
{
  "doc": "Online fake order item",
  "namespace": "Order V1",
  "name": "Order",
  "compatibility": "BACKWARD",
  "type": "record",
  "fields": [
    {
      "name": "order_id",
      "type": "string"
    },
    {
      "name": "ordered_at",
      "type": {
        "type": "long",
        "logicalType": "timestamp-millis"
      }
    },
    {
      "name": "user_id",
      "type": "string"
    },
    {
      "name": "order_items",
      "type": {
        "type": "array",
        "items": {
          "type": "record",
          "name": "OrderItem",
          "fields": [
            {
              "name": "product_id",
              "type": "long"
            },
            {
              "name": "quantity",
              "type": "long"
            }
          ]
        },
        "name": "order_item"
      }
    }
  ]
}
```

Below shows an example order record.

```json
{
	"order_id": "00328584-7db3-4cfb-a5b7-de2c7eed7f43",
	"ordered_at": "2023-05-23T08:30:52.461000",
	"user_id": "010",
	"order_items": [
		{
			"product_id": 213,
			"quantity": 5
		},
		{
			"product_id": 486,
			"quantity": 3
		}
	]
}
```

## Consumer

The *Consumer* class instantiates the *KafkaConsumer* class in the *create* method. The main consumer configuration values are provided by the constructor arguments: Kafka bootstrap server addresses (*bootstrap_servers*), topic names (*topics*) and [consumer group ID](https://kafka.apache.org/documentation/#consumerconfigs_group.id) (*group_id*). Note that the *aws-glue-schema-registry* package provides the *KafkaDeserializer* class that deserializes messages according to the corresponding schema version, and we should use it as the *value_deserializer*. The `process()` method of the class polls messages and logs details of consumer records.

```python
# kafka-pocs/kafka-dev-with-docker/part-07/consumer.py
import os
import time
import logging

from kafka import KafkaConsumer
from kafka.errors import KafkaError
import boto3
from aws_schema_registry import SchemaRegistryClient, DataAndSchema
from aws_schema_registry.adapter.kafka import KafkaDeserializer

logging.basicConfig(level=logging.INFO)


class Consumer:
    def __init__(self, bootstrap_servers: list, topics: list, group_id: str, registry: str) -> None:
        self.bootstrap_servers = bootstrap_servers
        self.topics = topics
        self.group_id = group_id
        self.registry = registry
        self.glue_client = boto3.client(
            "glue", region_name=os.getenv("AWS_DEFAULT_REGION", "ap-southeast-2")
        )
        self.consumer = self.create()

    @property
    def deserializer(self):
        client = SchemaRegistryClient(self.glue_client, registry_name=self.registry)
        return KafkaDeserializer(client)

    def create(self):
        return KafkaConsumer(
            *self.topics,
            bootstrap_servers=self.bootstrap_servers,
            auto_offset_reset="earliest",
            enable_auto_commit=True,
            group_id=self.group_id,
            key_deserializer=lambda v: v.decode("utf-8"),
            value_deserializer=self.deserializer,
        )

    def process(self):
        try:
            while True:
                msg = self.consumer.poll(timeout_ms=1000)
                if msg is None:
                    continue
                self.print_info(msg)
                time.sleep(1)
        except KafkaError as error:
            logging.error(error)

    def print_info(self, msg: dict):
        for t, v in msg.items():
            for r in v:
                value: DataAndSchema = r.value
                logging.info(
                    f"key={r.key}, value={value.data}, topic={t.topic}, partition={t.partition}, offset={r.offset}, ts={r.timestamp}"
                )


if __name__ == "__main__":
    consumer = Consumer(
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:29092").split(","),
        topics=os.getenv("TOPIC_NAME", "orders").split(","),
        group_id=os.getenv("GROUP_ID", "orders-group"),
        registry=os.getenv("REGISTRY_NAME", "online-order"),
    )
    consumer.process()
```

### Consumer Services

The default number of partitions is set to be 3 in the [compose-kafka.yml](https://github.com/jaehyeon-kim/kafka-pocs/blob/main/kafka-dev-with-docker/part-07/compose-kafka.yml). A docker compose file is created for the consumer in order to deploy multiple instances of the app using the [scale option](https://docs.docker.com/engine/reference/commandline/compose_up/#options). As the service uses the same docker network (*kafkanet*), we can take the service names of the brokers (e.g. *kafka-0*) on port 9092. Once started, it installs required packages and starts the consumer.

```yaml
# kafka-pocs/kafka-dev-with-docker/part-07/compose-consumer.yml
version: "3.5"

services:
  app:
    image: bitnami/python:3.9
    command: "sh -c 'pip install -r requirements.txt && python consumer.py'"
    networks:
      - kafkanet
    environment:
      AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN
      BOOTSTRAP_SERVERS: kafka-0:9092,kafka-1:9092,kafka-2:9092
      TOPIC_NAME: orders
      GROUP_ID: orders-group
      REGISTRY_NAME: online-order
      TZ: Australia/Sydney
    volumes:
      - ./consumer.py:/app/consumer.py
      - ./requirements.txt:/app/requirements.txt

networks:
  kafkanet:
    external: true
    name: kafka-network
```

## Kafka Management App

We should configure additional details in environment variables in order to integrate Glue Schema Registry. While both apps provide serializers/deserializers, *kpow* supports to manage schemas to some extent as well.

For *kafka-ui*, we can add one or more [serialization plugins](https://docs.kafka-ui.provectus.io/configuration/serialization-serde). I added the [Glue registry serializer](https://github.com/provectus/kafkaui-glue-sr-serde) as a plugin and named it *online-order*. It requires the plugin binary file path, class name, registry name and AWS region name. Another key configuration values are the key and value schema templates values, which are used for finding schema names. Only the value schema template is updated as it is different from the default value. Note that the template values are applicable for producing messages on the UI. Therefore, we can leave them commented out if we don't want to produce messages on it. Finally, the Glue registry serializer binary should be downloaded as it is volume-mapped in the compose file. It can be downloaded from the project repository - see [*download.sh*](https://github.com/jaehyeon-kim/kafka-pocs/blob/main/kafka-dev-with-docker/part-07/download.sh).

The configuration of *kpow* is simpler as it only requires the registry ARN and AWS region. Note that the app fails to start if the registry doesn't exit. I created the registry named *online-order* before starting it.

```yaml
# /kafka-dev-with-docker/part-07/compose-ui.yml
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
      # glue schema registry serde
      KAFKA_CLUSTERS_0_SERDE_0_NAME: online-order
      KAFKA_CLUSTERS_0_SERDE_0_FILEPATH: /glue-serde/kafkaui-glue-serde-v1.0.3-jar-with-dependencies.jar
      KAFKA_CLUSTERS_0_SERDE_0_CLASSNAME: com.provectus.kafka.ui.serdes.glue.GlueSerde
      KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_REGION: $AWS_DEFAULT_REGION #required
      KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_REGISTRY: online-order #required, name of Glue Schema Registry
      # template that will be used to find schema name for topic key. Optional, default is null (not set).
      # KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_KEYSCHEMANAMETEMPLATE: "%s-key"
      # template that will be used to find schema name for topic value. Optional, default is '%s'
      KAFKA_CLUSTERS_0_SERDE_0_PROPERTIES_VALUESCHEMANAMETEMPLATE: "%s-value"
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

networks:
  kafkanet:
    external: true
    name: kafka-network
```

## Start Applications

We can run the Kafka cluster by `docker-compose -f compose-kafka.yml up -d` and the producer by `python producer.py`. As mentioned earlier, we'll deploy 3 instances of the consumer, and they can be deployed with the scale option as shown below. We can check the running consumer instances using the *ps* command of Docker Compose.

```bash
$ docker-compose -f compose-consumer.yml up -d --scale app=3
$ docker-compose -f compose-consumer.yml ps
    Name                   Command               State    Ports  
-----------------------------------------------------------------
part-07_app_1   sh -c pip install -r requi ...   Up      8000/tcp
part-07_app_2   sh -c pip install -r requi ...   Up      8000/tcp
part-07_app_3   sh -c pip install -r requi ...   Up      8000/tcp
```

Each instance of the consumer subscribes to its own topic partition, and we can check that in container logs. Below shows the last 10 log entries of one of the instances. It shows it polls messages from partition 0 only.

```bash
$ docker logs -f --tail 10 part-07_app_1

INFO:root:key={"order_id": "91db5fac-8e6b-46d5-a8e1-3df911fa9c60"}, value={'order_id': '91db5fac-8e6b-46d5-a8e1-3df911fa9c60', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 459000, tzinfo=datetime.timezone.utc), 'user_id': '066', 'order_items': [{'product_id': 110, 'quantity': 7}, {'product_id': 599, 'quantity': 4}, {'product_id': 142, 'quantity': 3}, {'product_id': 923, 'quantity': 7}]}, topic=orders, partition=0, offset=4886, ts=1684794652579
INFO:root:key={"order_id": "260c0ccf-29d1-4cef-88a9-7fc00618616e"}, value={'order_id': '260c0ccf-29d1-4cef-88a9-7fc00618616e', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 459000, tzinfo=datetime.timezone.utc), 'user_id': '070', 'order_items': [{'product_id': 709, 'quantity': 6}, {'product_id': 523, 'quantity': 4}, {'product_id': 895, 'quantity': 4}, {'product_id': 944, 'quantity': 2}]}, topic=orders, partition=0, offset=4887, ts=1684794652583
INFO:root:key={"order_id": "5ec8c9a1-5ad6-40f1-b0a5-09e7a060adb7"}, value={'order_id': '5ec8c9a1-5ad6-40f1-b0a5-09e7a060adb7', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 459000, tzinfo=datetime.timezone.utc), 'user_id': '027', 'order_items': [{'product_id': 401, 'quantity': 7}]}, topic=orders, partition=0, offset=4888, ts=1684794652589
INFO:root:key={"order_id": "1d58572f-18d3-4181-9c35-5d179e1fc322"}, value={'order_id': '1d58572f-18d3-4181-9c35-5d179e1fc322', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 460000, tzinfo=datetime.timezone.utc), 'user_id': '076', 'order_items': [{'product_id': 30, 'quantity': 4}, {'product_id': 230, 'quantity': 3}, {'product_id': 351, 'quantity': 7}]}, topic=orders, partition=0, offset=4889, ts=1684794652609
INFO:root:key={"order_id": "13fbd9c3-87e8-4d25-aec6-00c0a897e2f2"}, value={'order_id': '13fbd9c3-87e8-4d25-aec6-00c0a897e2f2', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 461000, tzinfo=datetime.timezone.utc), 'user_id': '078', 'order_items': [{'product_id': 617, 'quantity': 6}]}, topic=orders, partition=0, offset=4890, ts=1684794652612
INFO:root:key={"order_id": "00328584-7db3-4cfb-a5b7-de2c7eed7f43"}, value={'order_id': '00328584-7db3-4cfb-a5b7-de2c7eed7f43', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 461000, tzinfo=datetime.timezone.utc), 'user_id': '010', 'order_items': [{'product_id': 213, 'quantity': 5}, {'product_id': 486, 'quantity': 3}]}, topic=orders, partition=0, offset=4891, ts=1684794652612
INFO:root:key={"order_id": "2b45ef3c-4061-4e24-ace9-a897878eb5a4"}, value={'order_id': '2b45ef3c-4061-4e24-ace9-a897878eb5a4', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 461000, tzinfo=datetime.timezone.utc), 'user_id': '061', 'order_items': [{'product_id': 240, 'quantity': 5}, {'product_id': 585, 'quantity': 5}, {'product_id': 356, 'quantity': 9}, {'product_id': 408, 'quantity': 2}]}, topic=orders, partition=0, offset=4892, ts=1684794652613
INFO:root:key={"order_id": "293f6008-b3c5-41b0-a37b-df90c04f8e0c"}, value={'order_id': '293f6008-b3c5-41b0-a37b-df90c04f8e0c', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 461000, tzinfo=datetime.timezone.utc), 'user_id': '066', 'order_items': [{'product_id': 96, 'quantity': 5}, {'product_id': 359, 'quantity': 2}, {'product_id': 682, 'quantity': 9}]}, topic=orders, partition=0, offset=4893, ts=1684794652614
INFO:root:key={"order_id": "b09d03bf-9500-460c-a3cc-028aa4812b46"}, value={'order_id': 'b09d03bf-9500-460c-a3cc-028aa4812b46', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 463000, tzinfo=datetime.timezone.utc), 'user_id': '071', 'order_items': [{'product_id': 369, 'quantity': 6}, {'product_id': 602, 'quantity': 6}, {'product_id': 252, 'quantity': 10}, {'product_id': 910, 'quantity': 7}]}, topic=orders, partition=0, offset=4894, ts=1684794652629
INFO:root:key={"order_id": "265c64a0-a520-494f-84d5-ebaf4496fe1c"}, value={'order_id': '265c64a0-a520-494f-84d5-ebaf4496fe1c', 'ordered_at': datetime.datetime(2023, 5, 22, 12, 30, 52, 463000, tzinfo=datetime.timezone.utc), 'user_id': '009', 'order_items': [{'product_id': 663, 'quantity': 5}, {'product_id': 351, 'quantity': 4}, {'product_id': 373, 'quantity': 5}]}, topic=orders, partition=0, offset=4895, ts=1684794652630
```

We can also check the consumers with the management apps. For example, the 3 running consumers can be seen in the *Consumers* menu of *kafka-ui*. As expected, each consumer subscribes to its own topic partition. We can run the management apps by `docker-compose -f compose-ui.yml up -d`.

![](consumers.png#center)


## Schemas

On AWS Console, we can check the schema of the value is created.

![](schema-01.png#center)

Also, we are able to see it on *kpow*. The community edition only supports a single schema registry and its name is marked as *glue1*.

![](schema-02.png#center)

## Kafka Topics

The *orders* topic can be found in the *Topics* menu of *kafka-ui*.

![](topic-01.png#center)

We can browse individual messages in the *Messages* tab. Note that we should select the Glue serializer plugin name (*online-order*) on the *Value Serde* drop down list. Otherwise, records won't be deserialized correctly.

![](topic-02.png#center)

We can check the topic messages on *kpow* as well. If we select *AVRO* on the *Value Deserializer* drop down list, it requires to select the associating schema registry. We can select the pre-set schema registry name of *glue1*. Upon hitting the *Search* button, messages show up after being deserialized properly.

![](topic-03-01.png#center)

![](topic-03-02.png#center)

## Summary

In Part 4, we developed Kafka producer and consumer applications using the *kafka-python* package without integrating schema registry. Later we discussed the benefits of schema registry when developing Kafka applications in Part 5. In this post, I demonstrated how to enhance the existing applications by integrating AWS Glue Schema Registry.