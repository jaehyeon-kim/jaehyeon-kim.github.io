---
title: Kafka Development on Kubernetes - Part 2 Producer and Consumer
date: 2024-01-04
draft: false
featured: false
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
  - Docker
  - Python
authors:
  - JaehyeonKim
images: []
description: Apache Kafka has five core APIs, and we can develop applications to send/read streams of data to/from topics in a Kafka cluster using the producer and consumer APIs. While the main Kafka project maintains only the Java APIs, there are several open source projects that provide the Kafka client APIs in Python. In this post, we discuss how to develop Kafka client applications using the kafka-python package on Kubernetes.
---

Apache Kafka has five [core APIs](https://kafka.apache.org/documentation/#api), and we can develop applications to send/read streams of data to/from topics in a Kafka cluster using the producer and consumer APIs. While the main Kafka project maintains only the Java APIs, there are several [open source projects](https://cwiki.apache.org/confluence/display/KAFKA/Clients#Clients-Python) that provide the Kafka client APIs in Python. In this post, we discuss how to develop Kafka client applications using the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package on Kubernetes.


* [Part 1 Cluster Setup](/blog/2023-12-21-kafka-development-on-k8s-part-1)
* [Part 2 Producer and Consumer](#) (this post)
* [Part 3 Kafka Connect](/blog/2024-01-11-kafka-development-on-k8s-part-3)

## Kafka Client Apps

We create Kafka producer and consumer apps using the *kafka-python* package. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-on-k8s/part-02) of this post.

### Producer

The producer app sends fake order data that is generated by the [Faker package](https://faker.readthedocs.io/en/master/). The *Order* class generates one or more order records by the create method where each record includes order ID, order timestamp, user ID and order items. Both the key and value are serialized as JSON.

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

A sample order record is shown below.

```json
{
	"order_id": "79c0c393-9eca-4a44-8efd-3965752f3e16",
	"ordered_at": "2023-12-26T18:02:54.510497",
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

### Consumer

The *Consumer* class instantiates the [*KafkaConsumer*](https://kafka-python.readthedocs.io/en/master/apidoc/KafkaConsumer.html) in the *create* method. The main consumer configuration values are provided by the constructor arguments, and those are Kafka bootstrap server addresses (*bootstrap_servers*), topic names (*topics*) and [consumer group ID](https://kafka.apache.org/documentation/#consumerconfigs_group.id) (*group_id*). The *process* method of the class polls messages and logs details of the consumer records.

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

## Test Client Apps on Host

We assume that a Kafka cluster and management app are deployed on Minikube as discussed in [Part 1](/blog/2023-12-21-kafka-development-on-k8s-part-1). As mentioned in Part 1, the external listener of the Kafka bootstrap server is exposed by a service named *demo-cluster-kafka-external-bootstrap*. We can use the [*minikube service*](https://minikube.sigs.k8s.io/docs/handbook/accessing/) command to obtain the Kubernetes URL for the service.

```bash
minikube service demo-cluster-kafka-external-bootstrap --url

# http://127.0.0.1:42289
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

We can execute the Kafka client apps by replacing the bootstrap server address with the URL obtained in the previous step. Note that the apps should run in separate terminals.

```bash
# terminal 1
BOOTSTRAP_SERVERS=127.0.0.1:42289 python clients/producer.py
# terminal 2
BOOTSTRAP_SERVERS=127.0.0.1:42289 python clients/consumer.py
```

The access URL of the Kafka management app (*kafka-ui*) can be obtained using the *minikube service* command as shown below.

```bash
minikube service kafka-ui --url

# http://127.0.0.1:36477
# ❗  Because you are using a Docker driver on linux, the terminal needs to be open to run it.
```

On the management app, we can check messages are created in the *orders* topic. Note that the Kafka cluster is configured to allow automatic creation of topics and the default number of partitions is set to 3.

![](topic.png#center)

Also, we can see that messages are consumed by a single consumer in the consumer group named *orders-group*.

![](consumer-group.png#center)

## Deploy Client Apps

### Build Docker Image

We need a custom Docker image to deploy the client apps and normally images are pulled from an external Docker registry. Instead of relying on an external registry, however, we can [reuse the Docker daemon](https://minikube.sigs.k8s.io/docs/handbook/pushing/#1-pushing-directly-to-the-in-cluster-docker-daemon-docker-env) inside the Minikube cluster, which speeds up local development. It can be achieved by executing the following command.

```bash
# use docker daemon inside minikube cluster
eval $(minikube docker-env)
# Host added: /home/jaehyeon/.ssh/known_hosts ([127.0.0.1]:32772)
```

The Dockerfile copies the client apps into the */app* folder and installs dependent pip packages.

```Dockerfile
# clients/Dockerfile
FROM bitnami/python:3.8

COPY . /app
RUN pip install -r requirements.txt
```

We can check the image is found in the Docker daemon inside the Minikube cluster after building it with a name of *order-clients:0.1.0*.

```bash
docker build -t=order-clients:0.1.0 clients/.

docker images order-clients
# REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
# order-clients   0.1.0     bc48046837b1   26 seconds ago   589MB
```

### Deploy on Minikube

We can create the Kafka client apps using Kubernetes [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/). Both the apps have a single instance and Kafka cluster access details are added to environment variables. Note that, as we use the local Docker image (*order-clients:0.1.0*), the image pull policy (*imagePullPolicy*) is set to *Never* so that it will not be pulled from an external Docker registry.

```yaml
# manifests/kafka-clients.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: order-producer
    group: client
  name: order-producer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order-producer
  template:
    metadata:
      labels:
        app: order-producer
        group: client
    spec:
      containers:
        - image: order-clients:0.1.0
          name: producer-container
          args: ["python", "producer.py"]
          env:
            - name: BOOTSTRAP_SERVERS
              value: demo-cluster-kafka-bootstrap:9092
            - name: TOPIC_NAME
              value: orders
            - name: TZ
              value: Australia/Sydney
          resources: {}
          imagePullPolicy: Never # shouldn't be Always
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: order-consumer
    group: client
  name: order-consumer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order-consumer
  template:
    metadata:
      labels:
        app: order-consumer
        group: client
    spec:
      containers:
        - image: order-clients:0.1.0
          name: consumer-container
          args: ["python", "consumer.py"]
          env:
            - name: BOOTSTRAP_SERVERS
              value: demo-cluster-kafka-bootstrap:9092
            - name: TOPIC_NAME
              value: orders
            - name: GROUP_ID
              value: orders-group
            - name: TZ
              value: Australia/Sydney
          resources: {}
          imagePullPolicy: Never
```

The client apps can be deployed using the *kubectl create* command, and we can check the producer and consumer apps run on a single pod respectively.

```bash
kubectl create -f manifests/kafka-clients.yml

kubectl get all -l group=client
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

We can monitor the client apps using the log messages. Below shows the last 3 messages of them, and we see that they run as expected.

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

The Kubernetes resources and Minikube cluster can be removed by the *kubectl delete* and *minikube delete* commands respectively.

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

Apache Kafka has five core APIs, and we can develop applications to send/read streams of data to/from topics in a Kafka cluster using the producer and consumer APIs. In this post, we discussed how to develop Kafka client applications using the kafka-python package on Kubernetes.