---
title: Kafka Development with Docker - Part 8 SSL Encryption
date: 2023-06-29
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
  - Security
tags: 
  - Apache Kafka
  - Docker
  - Python
  - SSL/TLS
authors:
  - JaehyeonKim
images: []
description: We can configure Kafka clients and other components to use TLS (SSL or TLS/SSL) encryption to secure communication. It is a one-way verification process where a server certificate is verified by a client via SSL Handshake. Moreover we can improve security by adding client authentication. In this post, we will discuss how to configure SSL encryption with Java and Python client examples while client authentication will be covered in later posts.
---

[**UPDATE 2025-10-01**]

Bitnami's public Docker images have been moved to the [**Bitnami Legacy**](https://hub.docker.com/u/bitnamilegacy) repository. To ensure continued access and compatibility, please update your Docker image references accordingly.

For example:

* `bitnami/kafka:2.8.1` → `bitnamilegacy/kafka:2.8.1`
* `bitnami/zookeeper:3.7.0` → `bitnamilegacy/zookeeper:3.7.0`
* `bitnami/python:3.9.0` → `bitnamilegacy/python:3.9.0`

---

By default, Apache Kafka communicates in *PLAINTEXT*, which means that all data is sent without being encrypted. To secure communication, we can configure Kafka clients and other components to use [Transport Layer Security (TLS)](https://en.wikipedia.org/wiki/Transport_Layer_Security) encryption. Note that TLS is also referred to [Secure Sockets Layer (SSL)](https://en.wikipedia.org/wiki/Transport_Layer_Security#SSL_1.0,_2.0,_and_3.0) or TLS/SSL. SSL is the predecessor of TLS, and has been deprecated since June 2015. However, it is used in configuration and code instead of TLS for historical reasons. In this post, SSL, TLS and TLS/SSL will be used interchangeably. SSL encryption is a one-way verification process where a server certificate is verified by a client via [SSL Handshake](https://en.wikipedia.org/wiki/Transport_Layer_Security#TLS_handshake). Moreover, we can improve security by adding client authentication. For example, we can enforce two-way verification so that a client certificate is verified by Kafka brokers as well (*SSL Authentication*). Alternatively we can choose a separate authentication mechanism and typically [Simple Authentication and Security Layer (SASL)](https://en.wikipedia.org/wiki/Simple_Authentication_and_Security_Layer) is used (*SASL Authentication*). In this post, we will discuss how to configure SSL encryption with Java and Python client examples while SSL and SASL client authentication will be covered in later posts.

* [Part 1 Cluster Setup](/blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Management App](/blog/2023-05-18-kafka-development-with-docker-part-2)
* [Part 3 Kafka Connect](/blog/2023-05-25-kafka-development-with-docker-part-3)
* [Part 4 Producer and Consumer](/blog/2023-06-01-kafka-development-with-docker-part-4)
* [Part 5 Glue Schema Registry](/blog/2023-06-08-kafka-development-with-docker-part-5)
* [Part 6 Kafka Connect with Glue Schema Registry](/blog/2023-06-15-kafka-development-with-docker-part-6)
* [Part 7 Producer and Consumer with Glue Schema Registry](/blog/2023-06-22-kafka-development-with-docker-part-7)
* [Part 8 SSL Encryption](#) (this post)
* [Part 9 SSL Authentication](/blog/2023-07-06-kafka-development-with-docker-part-9)
* [Part 10 SASL Authentication](/blog/2023-07-13-kafka-development-with-docker-part-10)
* [Part 11 Kafka Authorization](/blog/2023-07-20-kafka-development-with-docker-part-11)

## Certificate Setup

Below shows an overview of certificate setup and SSL Handshake. It is from *Apache Kafka Series - Kafka Security | SSL SASL Kerberos ACL by Stephane Maarek and Gerd Koenig* ([LINK](https://www.udemy.com/course/apache-kafka-security/)).

![](setup.png#center)

SSL encryption is a one-way verification process where a server certificate is verified by a client via [SSL Handshake](https://en.wikipedia.org/wiki/Transport_Layer_Security#TLS_handshake). The following components are required for setting-up certificates.

* Certificate Authority (CA) - CA is responsible for signing certificates. We'll be using our own CA rather than relying upon an external trusted CA. Two files will be created for the CA - private key (*ca-key*) and certificate (*ca-cert*).
* Keystore - Keystore stores the identity of each machine (Kafka broker or logical client), and the certificate of a machine is signed by the CA. As the CA's certificate is imported into the Truststore of a Kafka client, the machine's certificate is also trusted and verified during SSL Handshake. Note that each machine requires to have its own Keystore. As we have 3 Kafka brokers, 3 Java Keystore files will be created and each of the file names begins with the host name e.g. *kafka-0.server.keystore.jks*.
* Truststore - Truststore stores one or more certificates that a Kafka client should trust. Note that importing a certificate of a CA means the client should trust all other certificates that are signed by that certificate, which is called the chain of trust. We'll have a single Java Keystore file for the Truststore named *kafka.truststore.jks*, and it will be shared by all Kafka brokers and clients.

The following script generates the components mentioned above. It begins with creating the files for the CA followed by generating the Keystore of each Kafka broker and the Truststore of Kafka clients. Note that the host names of all Kafka brokers should be added to the Kafka host file (*kafka-hosts.txt*) so that their Keystore files are generated recursively. Note also that it ends up producing the CA certificate file in the *PEM (Privacy Enhanced Mail)* format as it is required by a non-Java client - *ca-root.pem*. The PEM file will be used by the Python clients below. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-08) of this post.

```bash
# kafka-dev-with-docker/part-08/generate.sh
#!/usr/bin/env bash
 
set -eu

CN="${CN:-kafka-admin}"
PASSWORD="${PASSWORD:-supersecret}"
TO_GENERATE_PEM="${CITY:-yes}"

VALIDITY_IN_DAYS=3650
CA_WORKING_DIRECTORY="certificate-authority"
TRUSTSTORE_WORKING_DIRECTORY="truststore"
KEYSTORE_WORKING_DIRECTORY="keystore"
PEM_WORKING_DIRECTORY="pem"
CA_KEY_FILE="ca-key"
CA_CERT_FILE="ca-cert"
DEFAULT_TRUSTSTORE_FILE="kafka.truststore.jks"
KEYSTORE_SIGN_REQUEST="cert-file"
KEYSTORE_SIGN_REQUEST_SRL="ca-cert.srl"
KEYSTORE_SIGNED_CERT="cert-signed"
KAFKA_HOSTS_FILE="kafka-hosts.txt"
 
if [ ! -f "$KAFKA_HOSTS_FILE" ]; then
  echo "'$KAFKA_HOSTS_FILE' does not exists. Create this file"
  exit 1
fi
 
echo "Welcome to the Kafka SSL certificate authority, key store and trust store generator script."

echo
echo "First we will create our own certificate authority"
echo "  Two files will be created if not existing:"
echo "    - $CA_WORKING_DIRECTORY/$CA_KEY_FILE -- the private key used later to sign certificates"
echo "    - $CA_WORKING_DIRECTORY/$CA_CERT_FILE -- the certificate that will be stored in the trust store" 
echo "                                                        and serve as the certificate authority (CA)."
if [ -f "$CA_WORKING_DIRECTORY/$CA_KEY_FILE" ] && [ -f "$CA_WORKING_DIRECTORY/$CA_CERT_FILE" ]; then
  echo "Use existing $CA_WORKING_DIRECTORY/$CA_KEY_FILE and $CA_WORKING_DIRECTORY/$CA_CERT_FILE ..."
else
  rm -rf $CA_WORKING_DIRECTORY && mkdir $CA_WORKING_DIRECTORY
  echo
  echo "Generate $CA_WORKING_DIRECTORY/$CA_KEY_FILE and $CA_WORKING_DIRECTORY/$CA_CERT_FILE ..."
  echo
  openssl req -new -newkey rsa:4096 -days $VALIDITY_IN_DAYS -x509 -subj "/CN=$CN" \
    -keyout $CA_WORKING_DIRECTORY/$CA_KEY_FILE -out $CA_WORKING_DIRECTORY/$CA_CERT_FILE -nodes
fi

echo
echo "A keystore will be generated for each host in $KAFKA_HOSTS_FILE as each broker and logical client needs its own keystore"
echo
echo " NOTE: currently in Kafka, the Common Name (CN) does not need to be the FQDN of"
echo " this host. However, at some point, this may change. As such, make the CN"
echo " the FQDN. Some operating systems call the CN prompt 'first / last name'" 
echo " To learn more about CNs and FQDNs, read:"
echo " https://docs.oracle.com/javase/7/docs/api/javax/net/ssl/X509ExtendedTrustManager.html"
rm -rf $KEYSTORE_WORKING_DIRECTORY && mkdir $KEYSTORE_WORKING_DIRECTORY
while read -r KAFKA_HOST || [ -n "$KAFKA_HOST" ]; do
  KEY_STORE_FILE_NAME="$KAFKA_HOST.server.keystore.jks"
  echo
  echo "'$KEYSTORE_WORKING_DIRECTORY/$KEY_STORE_FILE_NAME' will contain a key pair and a self-signed certificate."
  keytool -genkey -keystore $KEYSTORE_WORKING_DIRECTORY/"$KEY_STORE_FILE_NAME" \
    -alias localhost -validity $VALIDITY_IN_DAYS -keyalg RSA \
    -noprompt -dname "CN=$KAFKA_HOST" -keypass $PASSWORD -storepass $PASSWORD
 
  echo
  echo "Now a certificate signing request will be made to the keystore."
  keytool -certreq -keystore $KEYSTORE_WORKING_DIRECTORY/"$KEY_STORE_FILE_NAME" \
    -alias localhost -file $KEYSTORE_SIGN_REQUEST -keypass $PASSWORD -storepass $PASSWORD
 
  echo
  echo "Now the private key of the certificate authority (CA) will sign the keystore's certificate."
  openssl x509 -req -CA $CA_WORKING_DIRECTORY/$CA_CERT_FILE \
    -CAkey $CA_WORKING_DIRECTORY/$CA_KEY_FILE \
    -in $KEYSTORE_SIGN_REQUEST -out $KEYSTORE_SIGNED_CERT \
    -days $VALIDITY_IN_DAYS -CAcreateserial
  # creates $CA_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST_SRL which is never used or needed.
 
  echo
  echo "Now the CA will be imported into the keystore."
  keytool -keystore $KEYSTORE_WORKING_DIRECTORY/"$KEY_STORE_FILE_NAME" -alias CARoot \
    -import -file $CA_WORKING_DIRECTORY/$CA_CERT_FILE -keypass $PASSWORD -storepass $PASSWORD -noprompt
 
  echo
  echo "Now the keystore's signed certificate will be imported back into the keystore."
  keytool -keystore $KEYSTORE_WORKING_DIRECTORY/"$KEY_STORE_FILE_NAME" -alias localhost \
    -import -file $KEYSTORE_SIGNED_CERT -keypass $PASSWORD -storepass $PASSWORD

  echo
  echo "Complete keystore generation!"
  echo
  echo "Deleting intermediate files. They are:"
  echo " - '$CA_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST_SRL': CA serial number"
  echo " - '$KEYSTORE_SIGN_REQUEST': the keystore's certificate signing request"
  echo " - '$KEYSTORE_SIGNED_CERT': the keystore's certificate, signed by the CA, and stored back"
  echo " into the keystore"
  rm -f $CA_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST_SRL $KEYSTORE_SIGN_REQUEST $KEYSTORE_SIGNED_CERT
done < "$KAFKA_HOSTS_FILE"

echo
echo "Now the trust store will be generated from the certificate."
rm -rf $TRUSTSTORE_WORKING_DIRECTORY && mkdir $TRUSTSTORE_WORKING_DIRECTORY
keytool -keystore $TRUSTSTORE_WORKING_DIRECTORY/$DEFAULT_TRUSTSTORE_FILE \
  -alias CARoot -import -file $CA_WORKING_DIRECTORY/$CA_CERT_FILE \
  -noprompt -dname "CN=$CN" -keypass $PASSWORD -storepass $PASSWORD

if [ $TO_GENERATE_PEM == "yes" ]; then
  echo
  echo "The following files for SSL configuration will be created for a non-java client"
  echo "  $PEM_WORKING_DIRECTORY/ca-root.pem: CA file to use in certificate veriication"
  rm -rf $PEM_WORKING_DIRECTORY && mkdir $PEM_WORKING_DIRECTORY

  keytool -exportcert -alias CARoot -keystore $TRUSTSTORE_WORKING_DIRECTORY/$DEFAULT_TRUSTSTORE_FILE \
    -rfc -file $PEM_WORKING_DIRECTORY/ca-root.pem -storepass $PASSWORD
fi
```

The script generates the following files listed below.

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

We should add the *SSL* listener to the broker configuration and the port 9093 is reserved for it. Both the Keystore and Truststore files are specified in the broker configuration. The former is to send the broker certificate to clients while the latter is necessary because a Kafka broker can be a client of other brokers. The changes made to the first Kafka broker are shown below, and the same updates are made to the other brokers. The cluster can be started by `docker-compose -f compose-kafka.yml up -d`.

```yaml
# kafka-dev-with-docker/part-08/compose-kafka.yml
version: "3.5"

services:
...

  kafka-0:
    image: bitnami/kafka:2.8.1
    container_name: kafka-0
    expose:
      - 9092
      - 9093
    ports:
      - "29092:29092"
    networks:
      - kafkanet
    environment:
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BROKER_ID=0
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,SSL:SSL,EXTERNAL:PLAINTEXT
      - KAFKA_CFG_LISTENERS=INTERNAL://:9092,SSL://:9093,EXTERNAL://:29092
      - KAFKA_CFG_ADVERTISED_LISTENERS=INTERNAL://kafka-0:9092,SSL://kafka-0:9093,EXTERNAL://localhost:29092
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=SSL
      - KAFKA_CFG_SSL_KEYSTORE_LOCATION=/opt/bitnami/kafka/config/certs/kafka.keystore.jks
      - KAFKA_CFG_SSL_KEYSTORE_PASSWORD=supersecret
      - KAFKA_CFG_SSL_KEY_PASSWORD=supersecret
      - KAFKA_CFG_SSL_TRUSTSTORE_LOCATION=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
      - KAFKA_CFG_SSL_TRUSTSTORE_PASSWORD=supersecret
    volumes:
      - kafka_0_data:/bitnami/kafka
      - ./keystore/kafka-0.server.keystore.jks:/opt/bitnami/kafka/config/certs/kafka.keystore.jks:ro
      - ./truststore/kafka.truststore.jks:/opt/bitnami/kafka/config/certs/kafka.truststore.jks:ro
      - ./client.properties:/opt/bitnami/kafka/config/client.properties:ro
    depends_on:
      - zookeeper

...

networks:
  kafkanet:
    name: kafka-network

...
```

## Examples

Java and non-Java clients need different configurations. The former can use the Keystore file of the Truststore directly while the latter needs corresponding details in a PEM file. The Kafka CLI and Kafka-UI will be taken as Java client examples while Python producer/consumer will be used to illustrate non-Java clients.

### Kafka CLI

The following configuration is necessary to use the SSL listener. It includes the security protocol, the location of the Truststore file and the password to access it.

```properties
# kafka-dev-with-docker/part-08/client.properties
security.protocol=SSL
ssl.truststore.location=/opt/bitnami/kafka/config/certs/kafka.truststore.jks
ssl.truststore.password=supersecret
```

Below shows a producer example. It creates a topic named *inventory* and produces messages using corresponding scripts. Note the client configuration file (*client.properties*) is specified in configurations, and it is available via volume-mapping.

```bash
## producer example
$ docker exec -it kafka-1 bash
I have no name!@07d1ca934530:/$ cd /opt/bitnami/kafka/bin/

## create a topic
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-topics.sh --bootstrap-server kafka-0:9093 \
  --create --topic inventory --partitions 3 --replication-factor 3 \
  --command-config /opt/bitnami/kafka/config/client.properties
# Created topic inventory.

## produce messages
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-console-producer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --producer.config /opt/bitnami/kafka/config/client.properties
>product: apples, quantity: 5
>product: lemons, quantity: 7
```

Once messages are created, we can check it by a consumer. We can execute a consumer in a separate console.

```bash
## consumer example
$ docker exec -it kafka-1 bash
I have no name!@07d1ca934530:/$ cd /opt/bitnami/kafka/bin/

## consume messages
I have no name!@07d1ca934530:/opt/bitnami/kafka/bin$ ./kafka-console-consumer.sh --bootstrap-server kafka-0:9093 \
  --topic inventory --consumer.config /opt/bitnami/kafka/config/client.properties --from-beginning
product: apples, quantity: 5
product: lemons, quantity: 7
```

### Python Client

We will run the Python producer and consumer apps using docker-compose. At startup, each of them installs required packages and executes its corresponding app script. As it shares the same network to the Kafka cluster, we can take the service names (e.g. *kafka-0*) on port 9093 as Kafka bootstrap servers. As shown below, we will need the certificate of the CA (*ca-root.pem*) and it will be available via volume-mapping. The apps can be started by `docker-compose -f compose-apps.yml up -d`.

```yaml
# kafka-dev-with-docker/part-08/compose-apps.yml
version: "3.5"

services:
  producer:
    image: bitnami/python:3.9
    container_name: producer
    command: "sh -c 'pip install -r requirements.txt && python producer.py'"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP_SERVERS: kafka-0:9093,kafka-1:9093,kafka-2:9093
      TOPIC_NAME: orders
      TZ: Australia/Sydney
    volumes:
      - .:/app
  consumer:
    image: bitnami/python:3.9
    container_name: consumer
    command: "sh -c 'pip install -r requirements.txt && python consumer.py'"
    networks:
      - kafkanet
    environment:
      BOOTSTRAP_SERVERS: kafka-0:9093,kafka-1:9093,kafka-2:9093
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

#### Producer

The same producer app discussed in [Part 4](/blog/2023-06-01-kafka-development-with-docker-part-4) is used here. The following arguments are added to access the SSL listener.

- *security_protocol* - Protocol used to communicate with brokers.
- *ssl_check_hostname* - Flag to configure whether SSL handshake should verify that the certificate matches the broker's hostname.
- *ssl_cafile* - Optional filename of CA (certificate) file to use in certificate verification.

```python
# kafka-dev-with-docker/part-08/producer.py
...

class Producer:
    def __init__(self, bootstrap_servers: list, topic: str):
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.producer = self.create()

    def create(self):
        return KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            security_protocol="SSL",
            ssl_check_hostname=True,
            ssl_cafile="pem/ca-root.pem",
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

In the container log, we can check SSH Handshake is performed successfully by loading the CA certificate file.

```bash
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-0:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:Probing node bootstrap-1 broker version
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/ca-root.pem
INFO:kafka.conn:<BrokerConnection node_id=bootstrap-1 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:root:max run - -1
INFO:root:current run - 1
...
INFO:root:current run - 2
```

#### Consumer

The same consumer app in [Part 4](/blog/2023-06-01-kafka-development-with-docker-part-4) is used here as well. As the producer app, the following arguments are added - *security_protocol*, *ssl_check_hostname* and *ssl_cafile*.

```python
# kafka-dev-with-docker/part-08/consumer.py
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
            security_protocol="SSL",
            ssl_check_hostname=True,
            ssl_cafile="pem/ca-root.pem",
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

We can also check messages are consumed after SSH Handshake is succeeded in the container log.

```bash
...
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-0:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Loading SSL CA from pem/ca-root.pem
INFO:kafka.conn:<BrokerConnection node_id=0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.cluster:Group coordinator for orders-group is BrokerMetadata(nodeId='coordinator-0', host='kafka-0', port=9093, rack=None)
INFO:kafka.coordinator:Discovered coordinator coordinator-0 for group orders-group
WARNING:kafka.coordinator:Marking the coordinator dead (node coordinator-0) for group orders-group: Node Disconnected.
INFO:kafka.conn:<BrokerConnection node_id=coordinator-0 host=kafka-0:9093 <connecting> [IPv4 ('172.20.0.3', 9093)]>: connecting to kafka-0:9093 [('172.20.0.3', 9093) IPv4]
INFO:kafka.cluster:Group coordinator for orders-group is BrokerMetadata(nodeId='coordinator-0', host='kafka-0', port=9093, rack=None)
INFO:kafka.coordinator:Discovered coordinator coordinator-0 for group orders-group
INFO:kafka.conn:<BrokerConnection node_id=coordinator-0 host=kafka-0:9093 <handshake> [IPv4 ('172.20.0.3', 9093)]>: Connection complete.
INFO:kafka.coordinator:(Re-)joining group orders-group
INFO:kafka.coordinator:Elected group leader -- performing partition assignments using range
INFO:kafka.coordinator:Successfully joined group orders-group with generation 3
INFO:kafka.consumer.subscription_state:Updated partition assignment: [TopicPartition(topic='orders', partition=0)]
INFO:kafka.coordinator.consumer:Setting newly assigned partitions {TopicPartition(topic='orders', partition=0)} for group orders-group
...
INFO:root:key={"order_id": "6f642267-0497-4e63-8989-45e29e768351"}, value={"order_id": "6f642267-0497-4e63-8989-45e29e768351", "ordered_at": "2023-06-20T20:26:45.635986", "user_id": "003", "order_items": [{"product_id": 1000, "quantity": 2}, {"product_id": 541, "quantity": 10}, {"product_id": 431, "quantity": 10}, {"product_id": 770, "quantity": 7}]}, topic=orders, partition=0, offset=10700, ts=1687292805638
INFO:root:key={"order_id": "1d5a92bc-75e0-46e9-a334-43e03e408ea0"}, value={"order_id": "1d5a92bc-75e0-46e9-a334-43e03e408ea0", "ordered_at": "2023-06-20T20:26:45.636034", "user_id": "032", "order_items": [{"product_id": 404, "quantity": 7}, {"product_id": 932, "quantity": 8}]}, topic=orders, partition=0, offset=10701, ts=1687292805638
```

### Kafka-UI

Kafka-UI is also a Java client, and it accepts the Keystore file of the Kafka Truststore (*kafka.truststore.jks*). We can specify the file and password to access it as environment variables. The app can be started by `docker-compose -f compose-ui.yml up -d`.

```yaml
# kafka-dev-with-docker/part-08/compose-ui.yml
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
      KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: SSL
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-0:9093,kafka-1:9093,kafka-2:9093
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

Once started, we can check the messages of the *orders* topic successfully.

![](messages.png#center)

## Summary

By default, Apache Kafka communicates in *PLAINTEXT*, and we can configure Kafka clients and other components to use TLS (SSL or TLS/SSL) encryption to secure communication. In this post, we discussed how to configure SSL encryption with Java and Python client examples.