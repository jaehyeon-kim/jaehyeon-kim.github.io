---
title: Kafka Development on Kubernetes - Part 2 Producer and Consumer
date: 2023-12-28
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development on Kubernetes
categories:
  - Apache Kafka
tags: 
  - Apache Kafka
  - Kubernetes
  - Minikube
  - Strimzi
  - Python
  - Docker
authors:
  - JaehyeonKim
images: []
description: Foo Bar
---


* [Part 1 Cluster Setup](/blog/2023-12-21-kafka-development-on-k8s-part-1)
* [Part 2 Producer and Consumer](#) (this post)
* Part 3 Kafka Connect

## Kafka Client Apps

### Producer

```python
# clients/producer.py
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
            api_version=(2, 8, 1)
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
        bootstrap_servers=os.environ["BOOTSTRAP_SERVERS"].split(","),
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

### Consumer

```python
# clients/consumer.py
import os
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
            api_version=(2, 8, 1)
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
                logging.info(
                    f"key={r.key}, value={r.value}, topic={t.topic}, partition={t.partition}, offset={r.offset}, ts={r.timestamp}"
                )


if __name__ == "__main__":
    consumer = Consumer(
        bootstrap_servers=os.environ["BOOTSTRAP_SERVERS"].split(","),
        topics=os.getenv("TOPIC_NAME", "orders").split(","),
        group_id=os.getenv("GROUP_ID", "orders-group"),
    )
    consumer.process()
```

## Testing on Host

```bash
minikube service kafka-ui --url

# http://127.0.0.1:36477
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

```bash
minikube service demo-cluster-kafka-external-bootstrap --url

# http://127.0.0.1:42289
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

```bash
BOOTSTRAP_SERVERS=127.0.0.1:42289 python clients/producer.py
BOOTSTRAP_SERVERS=127.0.0.1:42289 python clients/consumer.py
```

![](topic.png#center)

![](consumer-group.png#center)

## Deploy on Minikube

```bash
# use docker daemon inside minikube cluster
eval $(minikube docker-env)
# Host added: /home/jaehyeon/.ssh/known_hosts ([127.0.0.1]:32772)
```

```Dockerfile
# clients/Dockerfile
FROM bitnami/python:3.8

COPY . /app
RUN pip install -r requirements.txt
```

```bash
docker build -t=order-clients:0.1.0 clients/.

docker images order-clients
# REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
# order-clients   0.1.0     bc48046837b1   26 seconds ago   589MB
```

```bash
kubectl create -f manifests/kafka-clients.yml

# kubectl get all -l group=client
# NAME                                  READY   STATUS    RESTARTS   AGE
# pod/order-consumer-79785749d5-67bxz   1/1     Running   0          12s
# pod/order-producer-759d568fb8-rrl6w   1/1     Running   0          12s

# NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/order-consumer   1/1     1            1           12s
# deployment.apps/order-producer   1/1     1            1           12s

# NAME                                        DESIRED   CURRENT   READY   AGE
# replicaset.apps/order-consumer-79785749d5   1         1         1       12s
# replicaset.apps/order-producer-759d568fb8   1         1         1       12s
```

```bash
kubectl logs deploy/order-producer --tail=3
# INFO:root:current run - 104
# INFO:root:current run - 105
# INFO:root:current run - 106

kubectl logs deploy/order-consumer --tail=3
# INFO:root:key={"order_id": "d9b9e577-7a02-401e-b0e1-2d0cdcda51a3"}, value={"order_id": "d9b9e577-7a02-401e-b0e1-2d0cdcda51a3", "ordered_at": "2023-12-18T18:17:13.065654", "user_id": "061", "order_items": [{"product_id": 866, "quantity": 7}, {"product_id": 970, "quantity": 1}]}, topic=orders, partition=1, offset=7000, ts=1702923433077
# INFO:root:key={"order_id": "dfbd2e1f-1b18-4772-83b9-c689a3da4c03"}, value={"order_id": "dfbd2e1f-1b18-4772-83b9-c689a3da4c03", "ordered_at": "2023-12-18T18:17:13.065754", "user_id": "016", "order_items": [{"product_id": 853, "quantity": 10}]}, topic=orders, partition=1, offset=7001, ts=1702923433077
# INFO:root:key={"order_id": "eaf43f0b-53ed-419a-ba75-1d74bd0525a4"}, value={"order_id": "eaf43f0b-53ed-419a-ba75-1d74bd0525a4", "ordered_at": "2023-12-18T18:17:13.065795", "user_id": "072", "order_items": [{"product_id": 845, "quantity": 1}, {"product_id": 944, "quantity": 7}, {"product_id": 454, "quantity": 10}, {"product_id": 834, "quantity": 9}]}, topic=orders, partition=1, offset=7002, ts=1702923433078
```

## Delete Resources

```bash
## delete resources
kubectl delete -f manifests/kafka-clients.yml
kubectl delete -f manifests/kafka-cluster.yaml
kubectl delete -f manifests/kafka-ui.yaml
kubectl delete -f manifests/strimzi-cluster-operator-$STRIMZI_VERSION.yaml

## delete minikube
minikube delete
```

## Summary