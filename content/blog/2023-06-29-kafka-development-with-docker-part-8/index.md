---
title: Kafka Development with Docker - Part 8 SSL Encryption
date: 2023-06-29
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
  - Encryption
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: ...
---

By default, Apache Kafka communicates in *PLAINTEXT*, which means that all data is sent without being encrypted. To encrypt communication, we can configure Kafka clients and other components to use [Transport Layer Security (TLS)](https://en.wikipedia.org/wiki/Transport_Layer_Security) encryption. Note that TLS is also referred to [Secure Sockets Layer (SSL)](https://en.wikipedia.org/wiki/Transport_Layer_Security#SSL_1.0,_2.0,_and_3.0) or TLS/SSL. SSL is the predecessor of TLS, and has been deprecated since June 2015. However, it is used in configuration and code instead of TLS for historical reasons. In this post, SSL, TLS and TLS/SSL will be used interchangeably. SSL encryption is a one-way verification process where a server certificate is verified by a client via [SSL handshake](https://en.wikipedia.org/wiki/Transport_Layer_Security#TLS_handshake). For client authentication, we can enforce two-way verification so that a client certificate is verified by Kafka brokers as well (*SSL Authentication*). Alternatively we can choose a separate mechanism and typically [Simple Authentication and Security Layer (SASL)](https://en.wikipedia.org/wiki/Simple_Authentication_and_Security_Layer) used (*SASL Authentication*). In this post, we will discuss how to configure SSL encryption while client authentication methods are implemented in later posts.

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](/blog/2023-06-08-kafka-development-with-docker-part-5)
* [Part 6 Kafka Connect with Glue Schema Registry](/blog/2023-06-15-kafka-development-with-docker-part-6)
* [Part 7 Producer and Consumer with Glue Schema Registry](/blog/2023-06-22-kafka-development-with-docker-part-7)
* [Part 8 SSL Encryption](#) (this post)
* Part 9 SSL Authentication
* Part 10 SASL Authentication
* Part 11 Kafka Authorization

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
└── CARoot.pem
```

```bash
$ docker exec -it kafka-1 bash
I have no name!@07d1ca934530:/$ cd /opt/bitnami/kafka/bin/
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-topics.sh --bootstrap-server kafka-0:9093 \
  --create --topic inventory --partitions 3 --replication-factor 3 \
  --command-config /opt/bitnami/kafka/config/client.properties
Created topic inventory.
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-console-producer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --producer.config /opt/bitnami/kafka/config/client.properties
>product: apples, quantity: 5
>product: lemons, quantity: 7
```

```bash
$ docker exec -it kafka-1 bash
I have no name!@07d1ca934530:/$ cd /opt/bitnami/kafka/bin/
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-console-consumer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --consumer.config /opt/bitnami/kafka/config/client.properties --from-beginning
product: apples, quantity: 5
product: lemons, quantity: 7
```

```bash
# producer log
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-1:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:Probing node bootstrap-0 broker version
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.conn:Broker version identified as 2.5.0
INFO:kafka.conn:Set configuration api_version=(2, 5, 0) to skip auto check_version requests on startup
INFO:root:max run - -1
INFO:root:current run - 1
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-1:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-0 host=kafka-1:9093 <connected> [IPv4 ('172.20.0.3', 9093)]>: Closing connection. 
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 0 connection failed -- refreshing metadata
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 0 connection failed -- refreshing metadata
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 0 connection failed -- refreshing metadata
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
```

```bash
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:Probing node bootstrap-2 broker version
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:Broker version identified as 2.5.0
INFO:kafka.conn:Set configuration api_version=(2, 5, 0) to skip auto check_version requests on startup
INFO:kafka.consumer.subscription_state:Updating subscribed topics to: ('orders',)
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <connecting> [IPv4 ('172.20.0.4', 9093)]>: connecting to kafka-2:9093 [('172.20.0.4', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.cluster:Group coordinator for orders-group is BrokerMetadata(nodeId='coordinator-1', host='kafka-1', port=9093, rack=None)
INFO:kafka.coordinator:Discovered coordinator coordinator-1 for group orders-group
INFO:kafka.coordinator:Starting new heartbeat thread
INFO:kafka.coordinator.consumer:Revoking previously assigned partitions set() for group orders-group
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-1:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. 
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <connected> [IPv4 ('172.20.0.4', 9093)]>: Closing connection. 
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <connected> [IPv4 ('172.20.0.3', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node coordinator-1 connection failed -- refreshing metadata
WARNING:kafka.coordinator:Marking the coordinator dead (node coordinator-1) for group orders-group: Node Disconnected.
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <connecting> [IPv4 ('172.20.0.4', 9093)]>: connecting to kafka-2:9093 [('172.20.0.4', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-1:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-2:9093 <connected> [IPv4 ('172.20.0.4', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-2 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. 
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9093 <connecting> [IPv4 ('172.20.0.4', 9093)]>: connecting to kafka-2:9093 [('172.20.0.4', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=1 host=kafka-1:9093 <connected> [IPv4 ('172.20.0.3', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 1 connection failed -- refreshing metadata
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=2 host=kafka-2:9093 <handshake> [IPv4 ('172.20.0.4', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Loading SSL CA from pem/CARoot.pem
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 0 connection failed -- refreshing metadata
INFO:kafka.cluster:Group coordinator for orders-group is BrokerMetadata(nodeId='coordinator-1', host='kafka-1', port=9093, rack=None)
INFO:kafka.coordinator:Discovered coordinator coordinator-1 for group orders-group
WARNING:kafka.coordinator:Marking the coordinator dead (node coordinator-1) for group orders-group: Node Disconnected.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-1:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.cluster:Group coordinator for orders-group is BrokerMetadata(nodeId='coordinator-1', host='kafka-1', port=9093, rack=None)
INFO:kafka.coordinator:Discovered coordinator coordinator-1 for group orders-group
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=coordinator-1 host=kafka-1:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connected> [IPv4 ('172.20.0.5', 9093)]>: Closing connection. KafkaConnectionError: Socket EVENT_READ without in-flight-requests
WARNING:kafka.client:Node 0 connection failed -- refreshing metadata
INFO:kafka.coordinator:(Re-)joining group orders-group
INFO:kafka.coordinator:Elected group leader -- performing partition assignments using range
INFO:kafka.coordinator:Successfully joined group orders-group with generation 1
INFO:kafka.consumer.subscription_state:Updated partition assignment: [TopicPartition(topic='orders', partition=0)]
INFO:kafka.coordinator.consumer:Setting newly assigned partitions {TopicPartition(topic='orders', partition=0)} for group orders-group
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.5', 9093)]>: connecting to kafka-0:9093 [('172.20.0.5', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.5', 9093)]>: Connection complete.                                                                                      > 
```