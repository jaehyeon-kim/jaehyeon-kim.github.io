---
title: Change Data Capture (CDC) Local Development with PostgreSQL, Debezium Server and Pub/Sub Emulator
date: 2024-11-07
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
categories:
  - Data Streaming
tags: 
  - Change Data Capture (CDC)
  - PostgreSQL
  - Debezium
  - Pub/Sub
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description:
---

*Change data capture* (CDC) is a data integration pattern to track changes in a database so that actions can be taken using the changed data. [*Debezium*](https://debezium.io/) is probably the most popular open source platform for CDC. Originally providing Kafka source connectors, it also supports a ready-to-use application called [Debezium server](https://debezium.io/documentation/reference/stable/operations/debezium-server.html). The standalone application can be used to stream change events to other messaging infrastructure such as Google Cloud Pub/Sub, Amazon Kinesis and Apache Pulsar. In this post, we develop a CDC solution locally using Docker. The source of the [theLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) is modified to generate data continuously, and the data is inserted into multiple tables of a PostgreSQL database. Among those tables, two of them are tracked by the Debezium server, and it pushes row-level changes of those tables into Pub/Sub topics on the [Pub/Sub emulator](https://cloud.google.com/pubsub/docs/emulator). Finally, messages of the topics are read by a Python application.

<!--more-->

## Docker Compose Services

We have three docker-compose services, and each service is illustrated separately. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/cdc-local).

### PostgreSQL

A PostgreSQL database server is configured so that it enables logical replication (`wal_level=logical`) at startup. It is necessary because we will be using the standard logical decoding output plug-in in PostgreSQL 10+ - see [this page](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-overview) for details.

```yaml
# docker-compose.yml
version: "3"
services:
  postgres:
    image: postgres:16
    container_name: postgres
    command: ["postgres", "-c", "wal_level=logical"]
    ports:
      - 5432:5432
    volumes:
      - ./config/postgres:/docker-entrypoint-initdb.d
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: develop
      POSTGRES_USER: develop
      POSTGRES_PASSWORD: password
      PGUSER: develop
      TZ: Australia/Sydney
...
volumes:
  postgres_data:
    driver: local
    name: postgres_data
```

The bootstrap script creates a dedicated schema named *ecommerce* and sets the schema as the default search path. It ends up creating a custom [publication](https://www.postgresql.org/docs/current/logical-replication-publication.html) for all tables in the *ecommerce* schema.

```sql
-- config/postgres/bootstrap.sql
CREATE SCHEMA ecommerce;
GRANT ALL ON SCHEMA ecommerce TO develop;

-- change search_path on a connection-level
SET search_path TO ecommerce;

-- change search_path on a database-level
ALTER database "develop" SET search_path TO ecommerce;

-- create a publication for all tables in the ecommerce schema
CREATE PUBLICATION cdc_publication FOR TABLES IN SCHEMA ecommerce;
```

### Debezium Server

The Debezium server configuration is fairly simple, and the application properties are supplied by volume mapping.

```yaml
# docker-compose.yml
version: "3"
services:
...
  debezium:
    image: debezium/server:3.0.0.Final
    container_name: debezium
    volumes:
      - ./config/debezium:/debezium/config
    depends_on:
      - postgres
    restart: always
...
```

The application properties can be grouped into four sections.
- Sink configuration
    - The sink type is set up as *pubsub*, and the address of the Pub/Sub emulator is specified as an extra.
- Source configuration
    - The PostgreSQL source connector class is specified, followed by adding the database details.
    - Only two tables in the *ecommerce* schema are included, and the output plugin and replication names are configuring as required.
    - Note that the topic prefix (*debezium.source.topic.prefix*) is mandatory, and the Debezium server expects the corresponding Pub/Sub topic exists where its name is in the `<prefix>.<schema>.<table-name>` format. Therefore, we need to create topics for the two tables before we start the server (if there are records already) or before we send records to the database (if there is no record).
- Message transform
    - The change messages are simplified using a [single message transform](https://debezium.io/documentation/reference/stable/transformations/event-flattening.html). With this transform, the message includes only a single payload that keeps record attributes and additional message metadata as specified in `debezium.transforms.unwrap.add.fields`.
- Log configuration
    - The default log format is JSON, and it is disabled to produce log messages as console outputs for ease of troubleshooting.

```properties
# config/debezium/application.properties
## sink config
debezium.sink.type=pubsub
debezium.sink.pubsub.project.id=test-project
debezium.sink.pubsub.ordering.enabled=true
debezium.sink.pubsub.address=pubsub:8085
## source config
debezium.source.connector.class=io.debezium.connector.postgresql.PostgresConnector
debezium.source.offset.storage.file.filename=data/offsets.dat
debezium.source.offset.flush.interval.ms=5000
debezium.source.database.hostname=postgres
debezium.source.database.port=5432
debezium.source.database.user=develop
debezium.source.database.password=password
debezium.source.database.dbname=develop
# topic.prefix is mandatory, topic name should be <prefix>.<schema>.<table-name>
debezium.source.topic.prefix=demo
debezium.source.table.include.list=ecommerce.orders,ecommerce.order_items
debezium.source.plugin.name=pgoutput
debezium.source.publication.name=cdc_publication
debezium.source.tombstones.on.delete=false
## SMT - unwrap
debezium.transforms=unwrap
debezium.transforms.unwrap.type=io.debezium.transforms.ExtractNewRecordState
debezium.transforms.unwrap.drop.tombstones=false
debezium.transforms.unwrap.delete.handling.mode=rewrite
debezium.transforms.unwrap.add.fields=op,db,table,schema,lsn,source.ts_ms
## log config
quarkus.log.console.json=false
quarkus.log.file.enable=false
quarkus.log.level=INFO
```

Below shows an output payload of one of the tables. Those that are prefixed by double underscore (`__`) are message metadata.

```json
{
  "order_id": "5db78495-2d65-4ebf-871f-cdc66eb1ed61",
  "user_id": "3e3ccd36-401b-4ea2-bd4b-eab63fcd1c5f",
  "status": "Shipped",
  "gender": "M",
  "created_at": 1724210040000000,
  "returned_at": null,
  "shipped_at": 1724446140000000,
  "delivered_at": null,
  "num_of_item": 2,
  "__deleted": "false",
  "__op": "r",
  "__db": "develop",
  "__table": "orders",
  "__schema": "ecommerce",
  "__lsn": 32919936,
  "__source_ts_ms": 1730183224763
}
```

### Pub/Sub Emulator

The Pub/Sub emulator is started as a gcloud component on port 8085.

```yaml
# docker-compose.yml
version: "3"
services:
...
  pubsub:
    image: google/cloud-sdk:497.0.0-emulators
    container_name: pubsub
    command: gcloud beta emulators pubsub start --host-port=0.0.0.0:8085
    ports:
      - "8085:8085"
...
```

## Solution Deployment

We can start the docker-compose services by `docker-compose up -d`. Then, we should create the topics into which the change messages are ingested. The topics and subscriptions to them can be created by the following Python script.

```python
# ps_setup.py
import os
import argparse

from src import ps_utils


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create PubSub resources")
    parser.add_argument(
        "--emulator-host",
        "-e",
        default="localhost:8085",
        help="PubSub emulator host address",
    )
    parser.add_argument(
        "--project-id", "-p", default="test-project", help="GCP project id"
    )
    parser.add_argument(
        "--topics",
        "-t",
        action="append",
        default=["demo.ecommerce.orders", "demo.ecommerce.order_items"],
        help="PubSub topic names",
    )
    args = parser.parse_args()
    os.environ["PUBSUB_EMULATOR_HOST"] = args.emulator_host
    os.environ["PUBSUB_PROJECT_ID"] = args.project_id

    for name in set(args.topics):
        ps_utils.create_topic(project_id=args.project_id, topic_name=name)
        ps_utils.create_subscription(
            project_id=args.project_id, sub_name=f"{name}.sub", topic_name=name
        )
    ps_utils.show_resources("topics", args.emulator_host, args.project_id)
    ps_utils.show_resources("subscriptions", args.emulator_host, args.project_id)
```

Once executed, the topics and subscriptions are created as shown below.

```bash
python ps_setup.py 
projects/test-project/topics/demo.ecommerce.order_items
projects/test-project/topics/demo.ecommerce.orders
projects/test-project/subscriptions/demo.ecommerce.order_items.sub
projects/test-project/subscriptions/demo.ecommerce.orders.sub
```

### Data Generator

The *theLook eCommerce* dataset has seven entities and five of them are generated dynamically. In each iteration, a *user* record is created, and it has zero or more orders. An *order* record creates zero or more order items in turn. Finally, an *order item* record creates zero or more *event* and *inventory item* objects. Once all records are generated, they are ingested into the relevant tables using pandas' `to_sql` method.

```python
# data_gen.py
import argparse
import time
import logging

import pandas as pd

from src.models import User
from src.utils import create_connection, insert_to_db, Connection, generate_from_csv

extraneous_headers = [
    "event_type",
    "ip_address",
    "browser",
    "traffic_source",
    "session_id",
    "sequence_number",
    "uri",
    "is_sold",
]


def write_dynamic_data(
    conn: Connection, schema_name: str = "ecommerce", if_exists: bool = "replace"
):
    tbl_map = {
        "users": [],
        "orders": [],
        "order_items": [],
        "inventory_items": [],
        "events": [],
    }
    user = User()
    logging.info(f"start to create user events - user id: {user.id}")
    tbl_map["users"].extend([user.asdict(["orders"])])
    orders = user.orders
    tbl_map["orders"].extend([o.asdict(["order_items"]) for o in orders])
    for order in orders:
        order_items = order.order_items
        tbl_map["order_items"].extend(
            [
                o.asdict(["events", "inventory_items"] + extraneous_headers)
                for o in order_items
            ]
        )
        for order_item in order_items:
            tbl_map["inventory_items"].extend(
                [i.asdict() for i in order_item.inventory_items]
            )
            tbl_map["events"].extend([e.asdict() for e in order_item.events])

    for tbl in tbl_map:
        df = pd.DataFrame(tbl_map[tbl])
        if len(df) > 0:
            logging.info(f"{if_exists} records, table - {tbl}, # records - {len(df)}")
            insert_to_db(
                df=df,
                tbl_name=tbl,
                schema_name=schema_name,
                conn=conn,
                if_exists=if_exists,
            )
        else:
            logging.info(
                f"skip records as no user event, table - {tbl}, # records - {len(df)}"
            )


def write_static_data(
    conn: Connection, schema_name: str = "ecommerce", if_exists: bool = "replace"
):
    tbl_map = {
        "products": generate_from_csv("products.csv"),
        "dist_centers": generate_from_csv("distribution_centers.csv"),
    }
    for tbl in tbl_map:
        df = pd.DataFrame(tbl_map[tbl])
        if len(df) > 0:
            logging.info(f"{if_exists} records, table - {tbl}, # records - {len(df)}")
            insert_to_db(
                df=df,
                tbl_name=tbl,
                schema_name=schema_name,
                conn=conn,
                if_exists=if_exists,
            )
        else:
            logging.info(f"skip writing, table - {tbl}, # records - {len(df)}")


def main(wait_for: float, max_iter: int, if_exists: str):
    conn = create_connection()
    write_static_data(conn=conn, if_exists="replace")
    curr_iter = 0
    while True:
        write_dynamic_data(conn=conn, if_exists=if_exists)
        time.sleep(wait_for)
        curr_iter += 1
        if max_iter > 0 and curr_iter >= max_iter:
            logging.info(f"stop generating records after {curr_iter} iterations")
            break


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    logging.info("Generate theLook eCommerce data...")

    parser = argparse.ArgumentParser(description="Generate theLook eCommerce data")
    parser.add_argument(
        "--if_exists",
        "-i",
        type=str,
        default="append",
        choices=["fail", "replace", "append"],
        help="The time to wait before generating new user records",
    )
    parser.add_argument(
        "--wait_for",
        "-w",
        type=float,
        default=1,
        help="The time to wait before generating new user records",
    )
    parser.add_argument(
        "--max_iter",
        "-m",
        type=int,
        default=-1,
        help="The maxium number of iterations to generate user records",
    )
    args = parser.parse_args()
    logging.info(args)
    main(args.wait_for, args.max_iter, if_exists=args.if_exists)
```

In the following example, we see data is generated in every two seconds (`-w 2`).

```bash
python data_gen.py -w 2
INFO:root:Generate theLook eCommerce data...
INFO:root:Namespace(if_exists='append', wait_for=2.0, max_iter=-1)
INFO:root:replace records, table - products, # records - 29120
INFO:root:replace records, table - dist_centers, # records - 10
INFO:root:start to create user events - user id: 2a444cd4-aa70-4247-b1c1-9cf9c8cc1924
INFO:root:append records, table - users, # records - 1
INFO:root:append records, table - orders, # records - 1
INFO:root:append records, table - order_items, # records - 2
INFO:root:append records, table - inventory_items, # records - 5
INFO:root:append records, table - events, # records - 14
INFO:root:start to create user events - user id: 7d40f7f8-c022-4104-a1a0-9228da07fbe4
INFO:root:append records, table - users, # records - 1
INFO:root:skip records as no user event, table - orders, # records - 0
INFO:root:skip records as no user event, table - order_items, # records - 0
INFO:root:skip records as no user event, table - inventory_items, # records - 0
INFO:root:skip records as no user event, table - events, # records - 0
INFO:root:start to create user events - user id: 45f8469c-3e79-40ee-9639-1cb17cd98132
INFO:root:append records, table - users, # records - 1
INFO:root:skip records as no user event, table - orders, # records - 0
INFO:root:skip records as no user event, table - order_items, # records - 0
INFO:root:skip records as no user event, table - inventory_items, # records - 0
INFO:root:skip records as no user event, table - events, # records - 0
INFO:root:start to create user events - user id: 839e353f-07ee-4d77-b1de-2f1af9b12501
INFO:root:append records, table - users, # records - 1
INFO:root:append records, table - orders, # records - 2
INFO:root:append records, table - order_items, # records - 3
INFO:root:append records, table - inventory_items, # records - 9
INFO:root:append records, table - events, # records - 19
```

When the data is ingested into the database, we see the following tables are created in the *ecommerce* schema.

![](diagram.png#center)

### Data Subscriber

The subscriber expects a topic name as an argument (default *demo.ecommerce.orders*) and assumes a subscription of the topic is named in the `<topic-name>.sub` format. While it subscribes a topic, it prints the payload attribute of each message, followed by acknowledging it.

```python
# ps_sub.py
import os
import json
import argparse

from google.cloud import pubsub_v1

from src import ps_utils


def callback(message):
    print(json.loads(message.data.decode())["payload"])
    message.ack()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create PubSub resources")
    parser.add_argument(
        "--emulator-host",
        "-e",
        default="localhost:8085",
        help="PubSub emulator host address",
    )
    parser.add_argument(
        "--project-id", "-p", default="test-project", help="GCP project id"
    )
    parser.add_argument(
        "--topic",
        "-t",
        default="demo.ecommerce.orders",
        help="PubSub topic name",
    )
    args = parser.parse_args()
    os.environ["PUBSUB_EMULATOR_HOST"] = args.emulator_host
    os.environ["PUBSUB_PROJECT_ID"] = args.project_id

    with pubsub_v1.SubscriberClient() as subscriber:
        future = subscriber.subscribe(
            ps_utils.set_sub_name(args.project_id, f"{args.topic}.sub"), callback
        )
        try:
            future.result()
        except KeyboardInterrupt:
            future.cancel()
```

Below shows an example of subscribing the topic that keeps the change messages of the orders table.

```bash
python ps_sub.py -t demo.ecommerce.orders
{'order_id': '5db78495-2d65-4ebf-871f-cdc66eb1ed61', 'user_id': '3e3ccd36-401b-4ea2-bd4b-eab63fcd1c5f', 'status': 'Shipped', 'gender': 'M', 'created_at': 1724210040000000, 'returned_at': None, 'shipped_at': 1724446140000000, 'delivered_at': None, 'num_of_item': 2, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': '040d7068-697c-4855-a5b1-fcf22d9ebd34', 'user_id': '3f9d209b-8042-47b0-ae2a-7ee1938f7c45', 'status': 'Cancelled', 'gender': 'F', 'created_at': 1702051020000000, 'returned_at': None, 'shipped_at': None, 'delivered_at': None, 'num_of_item': 1, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': '1d879c6e-ef5e-41b9-8120-6afaa6f054e6', 'user_id': '3f9d209b-8042-47b0-ae2a-7ee1938f7c45', 'status': 'Shipped', 'gender': 'F', 'created_at': 1714579020000000, 'returned_at': None, 'shipped_at': 1714592100000000, 'delivered_at': None, 'num_of_item': 1, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': 'b35ad9f1-583c-4b5d-8019-bcd1880223c8', 'user_id': 'e9c4a660-8b0b-4b50-a48f-f99480779070', 'status': 'Complete', 'gender': 'M', 'created_at': 1699584900000000, 'returned_at': None, 'shipped_at': 1699838520000000, 'delivered_at': '2023-11-15 16:52:00', 'num_of_item': 1, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': 'd06bd821-e2c7-4ee8-bc70-66b3fc5cc1a3', 'user_id': 'e9c4a660-8b0b-4b50-a48f-f99480779070', 'status': 'Complete', 'gender': 'M', 'created_at': 1670640900000000, 'returned_at': None, 'shipped_at': 1670896920000000, 'delivered_at': '2022-12-16 23:07:00', 'num_of_item': 1, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': '5928f275-9333-4036-ad25-c92d47c6b2ed', 'user_id': 'e9c4a660-8b0b-4b50-a48f-f99480779070', 'status': 'Complete', 'gender': 'M', 'created_at': 1615172100000000, 'returned_at': None, 'shipped_at': 1615278480000000, 'delivered_at': '2021-03-11 14:06:00', 'num_of_item': 1, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
{'order_id': '27937664-36b0-4b1c-a0f6-2e027701398e', 'user_id': 'e3ed22b9-4101-46e9-b642-a0317332f267', 'status': 'Cancelled', 'gender': 'M', 'created_at': 1719298320000000, 'returned_at': None, 'shipped_at': None, 'delivered_at': None, 'num_of_item': 2, '__deleted': 'false', '__op': 'r', '__db': 'develop', '__table': 'orders', '__schema': 'ecommerce', '__lsn': 32919936, '__source_ts_ms': 1730183224763}
```