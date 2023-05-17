---
title: Kafka Development with Docker - Part 4 Produce/Consume Messages
date: 2023-06-01
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
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Kafka includes the Producer/Consumer APIs that allow client applications to send/read streams of data to/from topics in the Kafka cluster. While the main Kafka project maintains only the Java clients, there are several open source projects that provides Kafka client functionalities in Python. In this post, I'll demonstrate how to develop producer/consumer applications using the kafka-python package.
---

In the previous post, we discussed [Kafka Connect](https://kafka.apache.org/documentation/#connect) to stream data to/from a Kafka cluster. Kafka also includes the [Producer/Consumer APIs](https://kafka.apache.org/documentation/#api) that allow client applications to send/read streams of data to/from topics in the Kafka cluster. While the main Kafka project maintains only the Java clients, there are several [open source projects](https://cwiki.apache.org/confluence/display/KAFKA/Clients#Clients-Python) that provides Kafka client functionalities in Python. In this post, I'll demonstrate how to develop producer/consumer applications using the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package.


* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Produce/Consume Messages](#) (this post)
* Part 5 Glue Schema Registry
* Part 6 Kafka Connect with Glue Schema Registry
* Part 7 Produce/Consume Messages with Glue Schema Registry
* Part 8 SSL Encryption
* Part 9 SSL Authentication
* Part 10 SASL Authentication
* Part 11 Kafka Authorization


## Producer

The same Kafka producer app that is introduced in [Part 2](/blog/2023-05-18-kafka-development-with-docker-part-2) is used again. It sends fake order data that is generated by the [Faker package](https://faker.readthedocs.io/en/master/). The *Order* class generates one or more fake order records by the create method, and a record includes order ID, order timestamp, user ID and order items. Both the key and value are serialised as JSON. Note, as the producer runs outside the Docker network, the host name of the external listener (`localhost:29092`) is used as the bootstrap server address. It can run simply by `python producer.py`.

```python
# kafka-pocs/kafka-dev-with-docker/part-04/producer.py
import os
import datetime
import time
import json
import typing
import logging
import dataclasses

from faker import Faker
from kafka import KafkaProducer

logging.basicConfig(level=logging.INFO)


@dataclasses.dataclass
class OrderItem:
    product_id: int
    quantity: int


@dataclasses.dataclass
class Order:
    order_id: str
    ordered_at: datetime.datetime
    user_id: str
    order_items: typing.List[OrderItem]

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
    def __init__(self, bootstrap_servers: list, topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.producer = self.create()

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            value_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
            key_serializer=lambda v: json.dumps(v, default=self.serialize).encode("utf-8"),
        )

    def send(self, orders: typing.List[Order]):
        for order in orders:
            try:
                self.producer.send(
                    self.topic, key={"order_id": order.order_id}, value=order.asdict()
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


if __name__ == "__main__":
    producer = Producer(
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:29092").split(","),
        topic=os.getenv("TOPIC_NAME", "orders"),
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
        producer.send(Order.auto().create(100))
        time.sleep(1)
```

A sample order record is shown below.

```json
{
	"order_id": "79c0c393-9eca-4a44-8efd-3965752f3e16",
	"ordered_at": "2023-05-13T18:02:54.510497",
	"user_id": "050",
	"order_items": [
		{
			"product_id": 113,
			"quantity": 9
		},
		{
			"product_id": 58,
			"quantity": 5
		}
	]
}
```

## Consumer

The *Consumer* class instantiates *KafkaConsumer* in the *create* method. The main consumer configuration values are provided by the constructor arguments: Kafka bootstrap server addresses (*bootstrap_servers*), topic names (*topics*) and [consumer group ID](https://kafka.apache.org/documentation/#consumerconfigs_group.id) (*group_id*). It has the *process* method, which polls messages and logs details of consumer records.

```python
# kafka-pocs/kafka-dev-with-docker/part-04/consumer.py
import os
import datetime
import time
import logging
from kafka import KafkaConsumer
from kafka.errors import KafkaError

logging.basicConfig(level=logging.INFO)


class Consumer:
    def __init__(self, bootstrap_servers: list, topics: list, group_id: str) -> None:
        self.bootstrap_servers = bootstrap_servers
        self.topics = topics
        self.group_id = group_id
        self.consumer = self.create()

    def create(self):
        return KafkaConsumer(
            *self.topics,
            bootstrap_servers=self.bootstrap_servers,
            auto_offset_reset="earliest",
            enable_auto_commit=True,
            group_id=self.group_id,
            key_deserializer=lambda v: v.decode("utf-8"),
            value_deserializer=lambda v: v.decode("utf-8"),
        )

    def process(self):
        try:
            while True:
                msg = self.consumer.poll(timeout_ms=1000)
                if msg is None:
                    continue
                self.print_info(msg)
                time.sleep(3)
        except KafkaError as error:
            logging.error(error)

    def print_info(self, msg: dict):
        for t, v in msg.items():
            for r in v:
                logging.info(
                    f"key={r.key}, value={r.value}, topic={t.topic}, partition={t.partition}, offset={r.offset}, ts={r.timestamp}"
                )


if __name__ == "__main__":
    consumer = Consumer(
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:9093").split(","),
        topics=os.getenv("TOPIC_NAME", "orders").split(","),
        group_id=os.getenv("GROUP_ID", "orders-group"),
    )
    consumer.process()
```

### Consumer Services

The default number of partitions is set to be 3 in the [compose-kafka.yml](https://github.com/jaehyeon-kim/kafka-pocs/blob/main/kafka-dev-with-docker/part-04/compose-kafka.yml). A docker compose file is created for the consumer in order to deploy multiple instances of the app using the [scale option](https://docs.docker.com/engine/reference/commandline/compose_up/#options). As the service uses the same docker network (*kafkanet*), we can take the service names of the brokers (e.g. *kafka-0*) on port 9092. Once started, it installs required packages and starts the consumer.

```yaml
# kafka-pocs/kafka-dev-with-docker/part-04/compose-consumer.yml
version: "3.5"

services:
  app:
    image: bitnami/python:3.9
    command: "sh -c 'pip install -r requirements.txt && python consumer.py'"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP_SERVERS: kafka-0:9092,kafka-1:9092,kafka-2:9092
      TOPIC_NAME: orders
      GROUP_ID: orders-group
      TZ: Australia/Sydney
    volumes:
      - .:/app

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
part-04_app_1   sh -c pip install -r requi ...   Up      8000/tcp
part-04_app_2   sh -c pip install -r requi ...   Up      8000/tcp
part-04_app_3   sh -c pip install -r requi ...   Up      8000/tcp
```

Each instance of the consumer subscribes its own topic partition, and we can check it by container logs. Below shows the last 10 log entries of one of the instances. It shows it polls messages from partition 0 only.

```bash
$ docker logs -f --tail 10 part-04_app_1

INFO:root:key={"order_id": "79c0c393-9eca-4a44-8efd-3965752f3e16"}, value={"order_id": "79c0c393-9eca-4a44-8efd-3965752f3e16", "ordered_at": "2023-05-13T18:02:54.510497", "user_id": "050", "order_items": [{"product_id": 113, "quantity": 9}, {"product_id": 58, "quantity": 5}]}, topic=orders, partition=0, offset=11407, ts=1684000974514
INFO:root:key={"order_id": "d57427fc-5325-49eb-9fb7-e4fac1eca9b4"}, value={"order_id": "d57427fc-5325-49eb-9fb7-e4fac1eca9b4", "ordered_at": "2023-05-13T18:02:54.510548", "user_id": "078", "order_items": [{"product_id": 111, "quantity": 4}]}, topic=orders, partition=0, offset=11408, ts=1684000974514
INFO:root:key={"order_id": "66c4ca6f-30e2-4f94-a971-ec23c9952430"}, value={"order_id": "66c4ca6f-30e2-4f94-a971-ec23c9952430", "ordered_at": "2023-05-13T18:02:54.510565", "user_id": "004", "order_items": [{"product_id": 647, "quantity": 2}, {"product_id": 894, "quantity": 1}]}, topic=orders, partition=0, offset=11409, ts=1684000974514
INFO:root:key={"order_id": "518a6812-4357-4ec1-9e5c-aad7853646ee"}, value={"order_id": "518a6812-4357-4ec1-9e5c-aad7853646ee", "ordered_at": "2023-05-13T18:02:54.510609", "user_id": "043", "order_items": [{"product_id": 882, "quantity": 5}]}, topic=orders, partition=0, offset=11410, ts=1684000974514
INFO:root:key={"order_id": "b22922e8-8ad0-48c3-b970-a486d4576d5c"}, value={"order_id": "b22922e8-8ad0-48c3-b970-a486d4576d5c", "ordered_at": "2023-05-13T18:02:54.510625", "user_id": "002", "order_items": [{"product_id": 206, "quantity": 6}, {"product_id": 810, "quantity": 9}]}, topic=orders, partition=0, offset=11411, ts=1684000974514
INFO:root:key={"order_id": "1ef36da0-6a0b-4ec2-9ecd-10a020acfbfd"}, value={"order_id": "1ef36da0-6a0b-4ec2-9ecd-10a020acfbfd", "ordered_at": "2023-05-13T18:02:54.510660", "user_id": "085", "order_items": [{"product_id": 18, "quantity": 3}]}, topic=orders, partition=0, offset=11412, ts=1684000974515
INFO:root:key={"order_id": "e9efdfd8-dc55-47b9-9cb0-c2e87e864435"}, value={"order_id": "e9efdfd8-dc55-47b9-9cb0-c2e87e864435", "ordered_at": "2023-05-13T18:02:54.510692", "user_id": "051", "order_items": [{"product_id": 951, "quantity": 6}]}, topic=orders, partition=0, offset=11413, ts=1684000974515
INFO:root:key={"order_id": "b24ed1c0-150a-41b3-b1cb-a27fb5581b2b"}, value={"order_id": "b24ed1c0-150a-41b3-b1cb-a27fb5581b2b", "ordered_at": "2023-05-13T18:02:54.510737", "user_id": "096", "order_items": [{"product_id": 734, "quantity": 3}]}, topic=orders, partition=0, offset=11414, ts=1684000974515
INFO:root:key={"order_id": "74b06957-2c6c-4e46-be49-d2915cc80b74"}, value={"order_id": "74b06957-2c6c-4e46-be49-d2915cc80b74", "ordered_at": "2023-05-13T18:02:54.510774", "user_id": "072", "order_items": [{"product_id": 968, "quantity": 2}, {"product_id": 602, "quantity": 3}, {"product_id": 316, "quantity": 9}, {"product_id": 971, "quantity": 8}]}, topic=orders, partition=0, offset=11415, ts=1684000974515
INFO:root:key={"order_id": "fce38c6b-4806-4579-b11e-8eac24b5166b"}, value={"order_id": "fce38c6b-4806-4579-b11e-8eac24b5166b", "ordered_at": "2023-05-13T18:02:54.510863", "user_id": "071", "order_items": [{"product_id": 751, "quantity": 8}]}, topic=orders, partition=0, offset=11416, ts=1684000974515
```

## Summary

Kafka includes the Producer/Consumer APIs that allow client applications to send/read streams of data to/from topics in the Kafka cluster. While the main Kafka project maintains only the Java clients, there are several open source projects that provides Kafka client functionalities in Python. In this post, I demonstrated how to develop producer/consumer applications using the *kafka-python* package.