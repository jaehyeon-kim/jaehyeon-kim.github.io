---
title: Kafka Development with Docker - Part 11 Kafka Authorization
date: 2023-07-20
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
  - Security
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: ...
---

...

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](/blog/2023-06-08-kafka-development-with-docker-part-5)
* [Part 6 Kafka Connect with Glue Schema Registry](/blog/2023-06-15-kafka-development-with-docker-part-6)
* [Part 7 Producer and Consumer with Glue Schema Registry](/blog/2023-06-22-kafka-development-with-docker-part-7)
* [Part 8 SSL Encryption](/blog/2023-06-29-kafka-development-with-docker-part-8)
* [Part 9 SSL Authentication](/blog/2023-07-06-kafka-development-with-docker-part-9)
* [Part 10 SASL Authentication](/blog/2023-07-13-kafka-development-with-docker-part-10)
* [Part 11 Kafka Authorization](#) (this post)

## Certificate Setup

```bash
$ tree certificate-authority keystore truststore pem
certificate-authority
├── ca-cert
└── ca-key
keystore
├── kafka-0.server.keystore.jks
├── kafka-1.server.keystore.jks
└── kafka-2.server.keystore.jks
truststore
└── kafka.truststore.jks
pem
└── ca-root.pem
```

## Kafka Broker Update

```yaml
# kafka-dev-with-docker/part-11/compose-kafka.yml
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
      - ZOO_ENABLE_AUTH=yes
      - ZOO_SERVER_USERS=admin
      - ZOO_SERVER_PASSWORDS=password
    volumes:
      - zookeeper_data:/bitnami/zookeeper
  kafka-0:
    image: bitnami/kafka:2.8.1
    container_name: kafka-0
    expose:
      - 9092
      - 9093
      - 9094
    ports:
      - "29092:29092"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,SSL:SSL,SASL_SSL:SASL_SSL,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,SSL://:9093,SASL_SSL://:9094,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,SSL://kafka-0:9093,SASL_SSL://kafka-0:9094,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=SSL
      - KAFKA_CFG_SSL_KEYSTORE_LOCATION=/opt/bitnami/kafka/config/certs/kafka.keystore.jks
      - KAFKA_CFG_SSL_KEYSTORE_PASSWORD=supersecret
      - KAFKA_CFG_SSL_KEY_PASSWORD=supersecret
      - KAFKA_CFG_SSL_TRUSTSTORE_LOCATION=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
      - KAFKA_CFG_SSL_TRUSTSTORE_PASSWORD=supersecret
      - KAFKA_CFG_SASL_ENABLED_MECHANISMS=SCRAM-SHA-256
      - KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=SCRAM-SHA-256
      - KAFKA_CFG_AUTHORIZER_CLASS_NAME=kafka.security.authorizer.AclAuthorizer
      - KAFKA_CFG_SUPER_USERS=User:superuser
      - KAFKA_CFG_ALLOW_EVERYONE_IF_NO_ACL_FOUND=true
    volumes:
      - kafka_0_data:/bitnami/kafka
      - ./keystore/kafka-0.server.keystore.jks:/opt/bitnami/kafka/config/certs/kafka.keystore.jks:ro
      - ./truststore/kafka.truststore.jks:/opt/bitnami/kafka/config/certs/kafka.truststore.jks:ro
      - ./kafka_jaas.conf:/opt/bitnami/kafka/config/kafka_jaas.conf:ro
      - ./client.properties:/opt/bitnami/kafka/config/client.properties:ro
      - ./command.properties:/opt/bitnami/kafka/config/command.properties:ro
      - ./superuser.properties:/opt/bitnami/kafka/config/superuser.properties:ro
    depends_on:
      - zookeeper

...

networks:
  kafkanet:
    name: kafka-network

...
```

```properties
# kafka-dev-with-docker/part-11/kafka_jaas.conf
KafkaServer {
  org.apache.kafka.common.security.scram.ScramLoginModule required
  username="_"
  password="_";
};

Client {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="admin"
  password="password";
};
```

## Examples

### User Creation

```properties
# kafka-dev-with-docker/part-11/command.properties
security.protocol=SSL
ssl.truststore.location=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
ssl.truststore.password=supersecret
```

```properties
# kafka-dev-with-docker/part-11/superuser.properties
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="superuser" password="password";
security.protocol=SASL_SSL
ssl.truststore.location=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
ssl.truststore.password=supersecret
```

```bash
$ docker exec -it kafka-0 bash
I have no name!@b28e71a2ae2c:/$ cd /opt/bitnami/kafka/bin/
## describe (list) all users (via SSH) - no user exists
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-configs.sh --bootstrap-server kafka-1:9093 --describe \
  --entity-type users --command-config /opt/bitnami/kafka/config/command.properties

## create superuser via (via SSH)
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-configs.sh --bootstrap-server kafka-1:9093 --alter \
  --add-config 'SCRAM-SHA-256=[iterations=8192,password=password]' \
  --entity-type users --entity-name superuser \
  --command-config /opt/bitnami/kafka/config/command.properties
# Completed updating config for user superuser.

## create users for Kafka client (via SASL_SSL as superuser)
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ for USER in "client" "producer" "consumer"; do
  ./kafka-configs.sh --bootstrap-server kafka-1:9094 --alter \
    --add-config 'SCRAM-SHA-256=[iterations=8192,password=password]' \
    --entity-type users --entity-name $USER \
    --command-config /opt/bitnami/kafka/config/superuser.properties
done
# Completed updating config for user client.
# Completed updating config for user producer.
# Completed updating config for user consumer.

## check if all users exist (via SASL_SSL as superuser)
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-configs.sh --bootstrap-server kafka-1:9094 --describe \
  --entity-type users --command-config /opt/bitnami/kafka/config/superuser.properties
# SCRAM credential configs for user-principal 'client' are SCRAM-SHA-256=iterations=8192
# SCRAM credential configs for user-principal 'consumer' are SCRAM-SHA-256=iterations=8192
# SCRAM credential configs for user-principal 'producer' are SCRAM-SHA-256=iterations=8192
# SCRAM credential configs for user-principal 'superuser' are SCRAM-SHA-256=iterations=8192
```

### ACL Creation

```bash
## create ACL for inventory topic. The user 'client' has permission on all operations
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-acls.sh --bootstrap-server kafka-1:9094 --add \
  --allow-principal User:client --operation All --group '*' \
  --topic inventory --command-config /opt/bitnami/kafka/config/superuser.properties
# Adding ACLs for resource `ResourcePattern(resourceType=TOPIC, name=inventory, patternType=LITERAL)`: 
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 

# Adding ACLs for resource `ResourcePattern(resourceType=GROUP, name=*, patternType=LITERAL)`: 
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 

# Current ACLs for resource `ResourcePattern(resourceType=GROUP, name=*, patternType=LITERAL)`: 
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 

# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=inventory, patternType=LITERAL)`: 
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 

I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-acls.sh --bootstrap-server kafka-1:9094 --list \
  --topic inventory --command-config /opt/bitnami/kafka/config/superuser.properties
# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=inventory, patternType=LITERAL)`: 
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 
```

```bash
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-acls.sh --bootstrap-server kafka-1:9094 --add \
  --allow-principal User:producer --producer \
  --topic orders --command-config /opt/bitnami/kafka/config/superuser.properties
# Adding ACLs for resource `ResourcePattern(resourceType=TOPIC, name=orders, patternType=LITERAL)`: 
#         (principal=User:producer, host=*, operation=WRITE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=DESCRIBE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=CREATE, permissionType=ALLOW) 

# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=orders, patternType=LITERAL)`: 
#         (principal=User:producer, host=*, operation=WRITE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=CREATE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=DESCRIBE, permissionType=ALLOW) 

I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-acls.sh --bootstrap-server kafka-1:9094 --add \
  --allow-principal User:consumer --consumer --group '*' \
  --topic orders --command-config /opt/bitnami/kafka/config/superuser.properties
# Adding ACLs for resource `ResourcePattern(resourceType=TOPIC, name=orders, patternType=LITERAL)`: 
#         (principal=User:consumer, host=*, operation=READ, permissionType=ALLOW)
#         (principal=User:consumer, host=*, operation=DESCRIBE, permissionType=ALLOW) 

# Adding ACLs for resource `ResourcePattern(resourceType=GROUP, name=*, patternType=LITERAL)`: 
#         (principal=User:consumer, host=*, operation=READ, permissionType=ALLOW) 

# Current ACLs for resource `ResourcePattern(resourceType=GROUP, name=*, patternType=LITERAL)`: 
#         (principal=User:consumer, host=*, operation=READ, permissionType=ALLOW)
#         (principal=User:client, host=*, operation=ALL, permissionType=ALLOW) 

# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=orders, patternType=LITERAL)`: 
#         (principal=User:producer, host=*, operation=CREATE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=DESCRIBE, permissionType=ALLOW)
#         (principal=User:consumer, host=*, operation=DESCRIBE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=WRITE, permissionType=ALLOW)
#         (principal=User:consumer, host=*, operation=READ, permissionType=ALLOW) 

I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-acls.sh --bootstrap-server kafka-1:9094 --list \
  --topic orders --command-config /opt/bitnami/kafka/config/superuser.properties
# Current ACLs for resource `ResourcePattern(resourceType=TOPIC, name=orders, patternType=LITERAL)`: 
#         (principal=User:producer, host=*, operation=CREATE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=DESCRIBE, permissionType=ALLOW)
#         (principal=User:consumer, host=*, operation=DESCRIBE, permissionType=ALLOW)
#         (principal=User:producer, host=*, operation=WRITE, permissionType=ALLOW)
#         (principal=User:consumer, host=*, operation=READ, permissionType=ALLOW) 
```

### Java Client

```properties
# kafka-dev-with-docker/part-11/client.properties
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="client" password="password";
security.protocol=SASL_SSL
ssl.truststore.location=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
ssl.truststore.password=supersecret
```

```bash
## producer
$ docker exec -it kafka-0 bash
I have no name!@b28e71a2ae2c:/$ cd /opt/bitnami/kafka/bin/
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-console-producer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --producer.config /opt/bitnami/kafka/config/client.properties
>product: apples, quantity: 5
>product: lemons, quantity: 7
```

```bash
## consumer
$ docker exec -it kafka-0 bash
I have no name!@b28e71a2ae2c:/$ cd /opt/bitnami/kafka/bin/
I have no name!@b28e71a2ae2c:/opt/bitnami/kafka/bin$ ./kafka-console-consumer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --consumer.config /opt/bitnami/kafka/config/client.properties --from-beginning
# [2023-06-21 01:30:01,890] WARN [Consumer clientId=consumer-console-consumer-94700-1, groupId=console-consumer-94700] Error while fetching metadata with correlation id 2 : {inventory=LEADER_NOT_AVAILABLE} (org.apache.kafka.clients.NetworkClient)
product: apples, quantity: 5
product: lemons, quantity: 7
```

### Python Client

```yaml
# kafka-dev-with-docker/part-11/compose-apps.yml
version: "3.5"

services:
  producer:
    image: bitnami/python:3.9
    container_name: producer
    command: "sh -c 'pip install -r requirements.txt && python producer.py'"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP_SERVERS: kafka-0:9094,kafka-1:9094,kafka-2:9094
      TOPIC_NAME: orders
      TZ: Australia/Sydney
      SASL_USERNAME: producer
      SASL_PASSWORD: password
    volumes:
      - .:/app
  consumer:
    image: bitnami/python:3.9
    container_name: consumer
    command: "sh -c 'pip install -r requirements.txt && python consumer.py'"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP_SERVERS: kafka-0:9094,kafka-1:9094,kafka-2:9094
      TOPIC_NAME: orders
      GROUP_ID: orders-group
      TZ: Australia/Sydney
      SASL_USERNAME: consumer
      SASL_PASSWORD: password
    volumes:
      - .:/app

networks:
  kafkanet:
    external: true
    name: kafka-network
```

#### Producer

```python
# kafka-dev-with-docker/part-11/producer.py
...

class Producer:
    def __init__(self, bootstrap_servers: list, topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.producer = self.create()

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            security_protocol="SASL_SSL",
            ssl_check_hostname=True,
            ssl_cafile="pem/ca-root.pem",
            sasl_mechanism="SCRAM-SHA-256",
            sasl_plain_username=os.environ["SASL_USERNAME"],
            sasl_plain_password=os.environ["SASL_PASSWORD"],
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

...

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

```bash
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9094 <handshake> [IPv4 ('192.168.0.3', 9094)]>: Loading SSL CA from pem/ca-root.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9094 <authenticating> [IPv4 ('192.168.0.3', 9094)]>: Authenticated as producer via SCRAM-SHA-256
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9094 <authenticating> [IPv4 ('192.168.0.3', 9094)]>: Connection complete.
INFO:root:max run - -1
INFO:root:current run - 1
...
INFO:root:current run - 2
```

#### Consumer

```python
# kafka-dev-with-docker/part-11/consumer.py
...

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
            security_protocol="SASL_SSL",
            ssl_check_hostname=True,
            ssl_cafile="pem/ca-root.pem",
            sasl_mechanism="SCRAM-SHA-256",
            sasl_plain_username=os.environ["SASL_USERNAME"],
            sasl_plain_password=os.environ["SASL_PASSWORD"],
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
        bootstrap_servers=os.getenv("BOOTSTRAP_SERVERS", "localhost:29092").split(","),
        topics=os.getenv("TOPIC_NAME", "orders").split(","),
        group_id=os.getenv("GROUP_ID", "orders-group"),
    )
    consumer.process()
```

```bash
INFO:kafka.coordinator:Elected group leader -- performing partition assignments using range
INFO:kafka.coordinator:Successfully joined group orders-group with generation 1
INFO:kafka.consumer.subscription_state:Updated partition assignment: [TopicPartition(topic='orders', partition=0)]
INFO:kafka.coordinator.consumer:Setting newly assigned partitions {TopicPartition(topic='orders', partition=0)} for group orders-group
...
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9094 <connecting> [IPv4 ('192.168.0.5', 9094)]>: connecting to kafka-2:9094 [('192.168.0.5', 9094) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9094 <handshake> [IPv4 ('192.168.0.5', 9094)]>: Loading SSL CA from pem/ca-root.pem
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9094 <authenticating> [IPv4 ('192.168.0.5', 9094)]>: Authenticated as consumer via SCRAM-SHA-256
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9094 <authenticating> [IPv4 ('192.168.0.5', 9094)]>: Connection complete.
INFO:root:key={"order_id": "7de9132b-c71e-4739-a2f8-7b6aed7ce8c9"}, value={"order_id": "7de9132b-c71e-4739-a2f8-7b6aed7ce8c9", "ordered_at": "2023-06-21T03:13:19.363325", "user_id": "017", "order_items": [{"product_id": 553, "quantity": 8}]}, topic=orders, partition=0, offset=0, ts=1687317199370
INFO:root:key={"order_id": "f222065e-489c-4ecd-b864-88163e800c79"}, value={"order_id": "f222065e-489c-4ecd-b864-88163e800c79", "ordered_at": "2023-06-21T03:13:19.363402", "user_id": "023", "order_items": [{"product_id": 417, "quantity": 10}, {"product_id": 554, "quantity": 1}, {"product_id": 942, "quantity": 6}]}, topic=orders, partition=0, offset=1, ts=1687317199371
```

### Kafka-UI

```yaml
# kafka-dev-with-docker/part-11/compose-ui.yml
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
      KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: SASL_SSL
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9094,kafka-1:9094,kafka-2:9094
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_MECHANISM: SCRAM-SHA-256
      KAFKA_CLUSTERS_0_PROPERTIES_PROTOCOL: SASL
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_JAAS_CONFIG: org.apache.kafka.common.security.scram.ScramLoginModule required username="superuser" password="password";
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
      KAFKA_CLUSTERS_0_SSL_TRUSTSTORELOCATION: /kafka.truststore.jks
      KAFKA_CLUSTERS_0_SSL_TRUSTSTOREPASSWORD: supersecret
    volumes:
      - ./truststore/kafka.truststore.jks:/kafka.truststore.jks:ro

networks:
  kafkanet:
    external: true
    name: kafka-network
```

![](messages.png#center)

## Summary