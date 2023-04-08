---
title: How to configure Kafka consumers to seek offsets by timestamp
date: 2023-01-10
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - DBT for Effective Data Transformation on AWS
categories:
  - Data Engineering
tags: 
  - Apache Kafka
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
cevo: 23
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/kafka-seek-offset-by-timestamp/).

Normally we consume Kafka messages from the beginning/end of a topic or last committed offsets. For backfilling or troubleshooting, however, we need to consume messages from a certain timestamp occasionally. The Kafka consumer class of the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package has a method to [seek a particular offset](https://kafka-python.readthedocs.io/en/master/apidoc/KafkaConsumer.html#kafka.KafkaConsumer.seek) for a topic partition. Therefore, if we know which topic partition to choose e.g. by [assigning a topic partition](https://kafka-python.readthedocs.io/en/master/apidoc/KafkaConsumer.html#kafka.KafkaConsumer.assign), we can easily override the fetch offset. When we deploy multiple consumer instances together, however, we make them [subscribe to a topic](https://kafka-python.readthedocs.io/en/master/apidoc/KafkaConsumer.html#kafka.KafkaConsumer.subscribe) and topic partitions are dynamically assigned, which means we do not know which topic partition will be assigned to a consumer instance in advance. In this post, we will discuss how to configure the Kafka consumer to seek offsets by timestamp where topic partitions are dynamically assigned by subscription.


## Kafka Docker Environment

A single node Kafka cluster is created as a docker-compose service with Zookeeper, which is used to store the cluster metadata. Note that the Kafka and Zookeeper data directories are mapped to host directories so that Kafka topics and messages are preserved when the services are restarted. As discussed below, fake messages are published into a Kafka topic by a producer application, and it runs outside the docker network (_kafkanet_). In order for the producer to access the Kafka cluster, we need to add an external listener, and it is configured on port 9093. Finally, the [Kafka UI](https://github.com/provectus/kafka-ui) is added for monitoring the Kafka broker and related resources. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/offset-seeking) for this post. 


```yaml
# offset-seeking/compose-kafka.yml
version: "3"

services:
  zookeeper:
    image: bitnami/zookeeper:3.7.0
    container_name: zookeeper
    ports:
      - "2181:2181"
    networks:
      - kafkanet
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
    volumes:
      - ./.bitnami/zookeeper/data:/bitnami/zookeeper/data
  kafka:
    image: bitnami/kafka:2.8.1
    container_name: kafka
    expose:
      - 9092
    ports:
      - "9093:9093"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CLIENT:PLAINTEXT,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=CLIENT://:9092,EXTERNAL://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=CLIENT://kafka:9092,EXTERNAL://localhost:9093
      - KAFKA_INTER_BROKER_LISTENER_NAME=CLIENT
    volumes:
      - ./.bitnami/kafka/data:/bitnami/kafka/data
      - ./.bitnami/kafka/logs:/opt/bitnami/kafka/logs
    depends_on:
      - zookeeper
  kafka-ui:
    image: provectuslabs/kafka-ui:master
    container_name: kafka-ui
    ports:
      - "8080:8080"
    networks:
      - kafkanet
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
    depends_on:
      - zookeeper
      - kafka

networks:
  kafkanet:
    name: kafka-network
```


Before we start the services, we need to create the directories that are used for volume-mapping and to update their permission. Then the services can be started as usual. A Kafka topic having two partitions is used in this post, and it is created manually as it is different from the default configuration.


```bash
# create folders that will be volume-mapped and update permission
$ mkdir -p .bitnami/zookeeper/data .bitnami/kafka/data .bitnami/kafka/logs \
  && chmod 777 -R .bitnami

# start docker services - zookeeper, kafka and kafka-ui
$ docker-compose -f compose-kafka.yml up -d

# create a topic named orders with 2 partitions
$ docker exec -it kafka \
  bash -c "/opt/bitnami/kafka/bin/kafka-topics.sh \
  --create --topic orders --partitions 2 --bootstrap-server kafka:9092"
```

The topic can be checked in the Kafka UI as shown below.

![](topic-01.png#center)

## Kafka Producer

A Kafka producer is created to send messages to the orders topic and fake messages are generated using the [Faker package](https://faker.readthedocs.io/en/master/). 


### Order Data

The Order class generates one or more fake order records by the create method. An order record includes order ID, order timestamp, customer and order items. 


```python
# offset-seeking/producer.py
class Order:
    def __init__(self, fake: Faker = None):
        self.fake = fake or Faker()

    def order(self):
        return {"order_id": self.fake.uuid4(), "ordered_at": self.fake.date_time_this_decade()}

    def items(self):
        return [
            {"product_id": self.fake.uuid4(), "quantity": self.fake.random_int(1, 10)}
            for _ in range(self.fake.random_int(1, 4))
        ]

    def customer(self):
        name = self.fake.name()
        email = f'{re.sub(" ", "_", name.lower())}@{re.sub(r"^.*?@", "", self.fake.email())}'
        return {
            "user_id": self.fake.uuid4(),
            "name": name,
            "dob": self.fake.date_of_birth(),
            "address": self.fake.address(),
            "phone": self.fake.phone_number(),
            "email": email,
        }

    def create(self, num: int):
        return [
            {**self.order(), **{"items": self.items(), "customer": self.customer()}}
            for _ in range(num)
        ]
```


A sample order record is shown below.


```json
{
  "order_id": "567b3036-9ac4-440c-8849-ba4d263796db",
  "ordered_at": "2022-11-09T21:24:55",
  "items": [
    {
      "product_id": "7289ca92-eabf-4ebc-883c-530e16ecf9a3",
      "quantity": 7
    },
    {
      "product_id": "2ab8a155-bb15-4550-9ade-44d0bf2c730a",
      "quantity": 5
    },
    {
      "product_id": "81538fa2-6bc0-4903-a40f-a9303e5d3583",
      "quantity": 3
    }
  ],
  "customer": {
    "user_id": "9a18e5f0-62eb-4b50-ae12-9f6f1bd1a80b",
    "name": "David Boyle",
    "dob": "1965-11-25",
    "address": "8128 Whitney Branch\nNorth Brianmouth, MD 24870",
    "phone": "843-345-1004",
    "email": "david_boyle@example.org"
  }
}
```



### Kafka Producer

The Kafka producer sends one or more order records. A message is made up of an order ID as the key and an order record as the value. Both the key and value are serialised as JSON. Once started, it sends order messages to the topic indefinitely and ten messages are sent in a loop. Note that the external listener (_localhost:9093_) is specified as the bootstrap server because it runs outside the docker network. We can run the producer app simply by `python producer.py`.


```python
# offset-seeking/producer.py
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

    def send(self, orders: list):
        for order in orders:
            self.producer.send(self.topic, key={"order_id": order["order_id"]}, value=order)
        self.producer.flush()

    def serialize(self, obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        if isinstance(obj, datetime.date):
            return str(obj)
        return obj


if __name__ == "__main__":
    fake = Faker()
    # Faker.seed(1237)
    producer = Producer(bootstrap_servers=["localhost:9093"], topic="orders")

    while True:
        orders = Order(fake).create(10)
        producer.send(orders)
        print("messages sent...")
        time.sleep(5)
```


After a while, we can see that messages are sent to the orders topic. Out of 2390 messages, 1179 and 1211 messages are sent to the partition 0 and 1 respectively. 

![](topic-02.png#center)

## Kafka Consumer

Two consumer instances are deployed in the same consumer group. As the topic has two partitions, it is expected each instance is assigned to a single topic partition. A custom consumer rebalance listener is registered so that the fetch offset is overridden with an offset timestamp environment variable (offset_str) when a topic partition is assigned.


### Custom Consumer Rebalance Listener

The [consumer rebalancer listener](https://github.com/dpkp/kafka-python/blob/master/kafka/consumer/subscription_state.py#L423) is a callback interface that custom actions can be implemented when topic partitions are assigned or revoked. For each topic partition assigned, it obtains the earliest offset whose timestamp is greater than or equal to the given timestamp in the corresponding partition using the _offsets_for_times_ method. Then it overrides the fetch offset using the _seek_ method. Note that, as consumer instances can be rebalanced multiple times over time, the OFFSET_STR value is better to be stored in an external configuration store. In this way we can control whether to override fetch offsets by changing configuration externally.


```python
# offset-seeking/consumer.py
class RebalanceListener(ConsumerRebalanceListener):
    def __init__(self, consumer: KafkaConsumer, offset_str: str = None):
        self.consumer = consumer
        self.offset_str = offset_str

    def on_partitions_revoked(self, revoked):
        pass

    def on_partitions_assigned(self, assigned):
        ts = self.convert_to_ts(self.offset_str)
        logging.info(f"offset_str - {self.offset_str}, timestamp - {ts}")
        if ts is not None:
            for tp in assigned:
                logging.info(f"topic partition - {tp}")
                self.seek_by_timestamp(tp.topic, tp.partition, ts)

    def convert_to_ts(self, offset_str: str):
        try:
            dt = datetime.datetime.fromisoformat(offset_str)
            return int(dt.timestamp() * 1000)
        except Exception:
            return None

    def seek_by_timestamp(self, topic_name: str, partition: int, ts: int):
        tp = TopicPartition(topic_name, partition)
        offset_n_ts = self.consumer.offsets_for_times({tp: ts})
        logging.info(f"offset and ts - {offset_n_ts}")
        if offset_n_ts[tp] is not None:
            offset = offset_n_ts[tp].offset
            try:
                self.consumer.seek(tp, offset)
            except KafkaError:
                logging.error("fails to seek offset")
        else:
            logging.warning("offset is not looked up")
```

### Kafka Consumer

While it is a common practice to specify one or more Kafka topics in the Kafka consumer class when it is instantiated, the consumer omits them in the _create_ method. It is in order to register the custom rebalance listener. In the process method, the consumer subscribes to the orders topic while registering the custom listener. After subscribing to the topic, it polls a single message at a time for ease of tracking. 


```python
# offset-seeking/consumer.py
class Consumer:
    def __init__(
        self, topics: list, group_id: str, bootstrap_servers: list, offset_str: str = None
    ):
        self.topics = topics
        self.group_id = group_id
        self.bootstrap_servers = bootstrap_servers
        self.offset_str = offset_str
        self.consumer = self.create()

    def create(self):
        return KafkaConsumer(
            bootstrap_servers=self.bootstrap_servers,
            auto_offset_reset="earliest",
            enable_auto_commit=True,
            group_id=self.group_id,
            key_deserializer=lambda v: json.loads(v.decode("utf-8")),
            value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        )

    def process(self):
        self.consumer.subscribe(
            self.topics, listener=RebalanceListener(self.consumer, self.offset_str)
        )
        try:
            while True:
                msg = self.consumer.poll(timeout_ms=1000, max_records=1)
                if msg is None:
                    continue
                self.print_info(msg)
                time.sleep(5)
        except KafkaError as error:
            logging.error(error)
        finally:
            self.consumer.close()

    def print_info(self, msg: dict):
        for _, v in msg.items():
            for r in v:
                ts = r.timestamp
                dt = datetime.datetime.fromtimestamp(ts / 1000).isoformat()
                logging.info(
                    f"topic - {r.topic}, partition - {r.partition}, offset - {r.offset}, ts - {ts}, dt - {dt})"
                )


if __name__ == "__main__":
    consumer = Consumer(
        topics=os.getenv("TOPICS", "orders").split(","),
        group_id=os.getenv("GROUP_ID", "orders-group"),
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:9093").split(","),
        offset_str=os.getenv("OFFSET_STR", None),
    )
    consumer.process()
```


Docker-compose is used to deploy multiple instances of the producer. Note that the compose service uses the same docker network (_kafkanet_) so that it can use _kafka:9092_ as the bootstrap server address. The OFFSET_STR environment variable is used to override the fetch offset.


```yaml
# offset-seeking/compose-consumer.yml
version: "3"

services:
  consumer:
    image: bitnami/python:3.9
    command: "sh -c 'pip install -r requirements.txt && python consumer.py'"
    networks:
      - kafkanet
    environment:
      TOPICS: orders
      GROUP_ID: orders-group
      BOOTSTRAP_SERVERS: kafka:9092
      OFFSET_STR: "2023-01-06T19:00:00"
      TZ: Australia/Sydney
    volumes:
      - .:/app
networks:
  kafkanet:
    external: true
    name: kafka-network
```


We can start two consumer instances by scaling the consumer service number to 2.


```bash
# start 2 instances of kafka consumer
$ docker-compose -f compose-consumer.yml up -d --scale consumer=2
```


Soon after the instances start to poll messages, we can see that their fetch offsets are updated as the current offset values are much higher than 0. 

![](consumer-group-01.png#center)

We can check logs of the consumer instances in order to check their behaviour further. Below shows the logs of one of the instances. 


```bash
# check logs of consumer instance 1
$ docker logs offset-seeking-consumer-1
```


We see that the partition 1 is assigned to this instance. The offset 901 is taken to override and the message timestamp of that message is 2023-01-06T19:20:16.107000, which is later than the OFFSET_STR environment value.

![](consumer-group-02.png#center)

We can also check that the correct offset is obtained as the message timestamp of offset 900 is earlier than the OFFSET_STR value.  

![](consumer-group-03.png#center)

## Summary

In this post, we discussed how to configure Kafka consumers to seek offsets by timestamp. A single node Kafka cluster was created using docker compose and a Kafka producer was used to send fake order messages. While subscribing to the orders topic, the consumer registered a custom consumer rebalance listener that overrides the fetch offsets by timestamp. Two consumer instances were deployed using docker compose and their behaviour was analysed in detail.
