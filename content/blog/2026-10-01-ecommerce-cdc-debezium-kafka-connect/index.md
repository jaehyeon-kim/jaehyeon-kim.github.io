---
title: "Change Data Capture on a Simulated Online Shop with Debezium and Kafka Connect"
date: 2026-10-01
draft: false
featured: true
comment: true
toc: true
categories:
  - Data Engineering
  - Open Source
tags:
  - Change Data Capture (CDC)
  - Debezium
  - Kafka Connect
  - Apache Kafka
  - PostgreSQL
  - SeaweedFS
  - odctl
  - desflow
  - Benchtop
description: |
  Capturing every insert and update in PostgreSQL without changing the application: Debezium streams the changes to Kafka, and an S3 sink connector saves them as files.
---

Most databases change all day: users sign up, orders are placed, and each order moves from one status to the next. Change data capture (CDC) turns those changes into a stream of events that other systems can read as they happen. In this post, a simulated online shop writes to PostgreSQL in real time, Debezium streams every change to Kafka, and a sink connector saves the changes as files in object storage. Everything runs on your own machine.

<!--more-->

[**Update 2026-11-15**] The simulation is now one YAML file, `ecommerce/simulation/shop.yaml`, which desflow 1.0.0 runs with `desflow run`. It replaces `run.py`, `shop.py` and `catalogue.py`, and reads the distribution centres, products and cities from CSV files beside it. The code, commands, log and figures below show the new version.

[**Update 2026-10-16**] dynamic-des is now desflow (0.20.0). The code and commands below use the new name: pip install desflow, import desflow and the desflow command.

The shop's data model follows the [theLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) dataset. The source code is in [benchtop/ecommerce-cdc](https://github.com/jaehyeon-kim/benchtop/tree/main/ecommerce-cdc). It is one of the [Benchtop](/blog/2026-09-30-introducing-benchtop/) projects, which run locally from a fresh clone.

## What You Will Build

1. Run the simulation, which fills the tables and keeps changing them.
2. Deploy the connectors: Debezium streams every insert and update to Kafka, and the S3 sink saves them as files.
3. Look at the changes in Kafka and in SeaweedFS.
4. Change the simulation while it runs, and see the change in the stream.

To start again at any point, `python -m ecommerce.stores.cleanup` removes everything this project has created and keeps the services running. [Clean Up](#clean-up) describes what it removes.

## Architecture

![Architecture: a simulated shop writes to PostgreSQL, Debezium streams the changes to Kafka, and an S3 sink saves them as files](architecture.png)

The data moves in one direction: a simulation writes to PostgreSQL, Debezium reads the changes into Kafka topics, and the S3 sink writes the topics to files in SeaweedFS.

- **Change data capture** means reading a database's changes as a stream of events, instead of querying its tables again and again. PostgreSQL records every change in its write-ahead log (WAL) before it applies it, and CDC reads that log.
- **Kafka** stores streams of events in topics. A topic keeps its events in order, and any number of readers can read it.
- **Kafka Connect** runs connectors. A source connector copies data into Kafka, and a sink connector copies data out of it. You deploy a connector by sending its settings, as JSON, to Connect's REST API.
- **Debezium** is a source connector for CDC. It first copies every existing row, which is called a snapshot. It then streams each new change from the WAL, and writes one topic per table.
- **A replication slot** is PostgreSQL's record of how far a reader has got in the WAL. PostgreSQL keeps the part of the WAL the slot has not read yet, so Debezium can stop and carry on without losing a change.
- **A publication** names the tables whose changes PostgreSQL sends. odctl's PostgreSQL has a publication, `cdc_pub`, that covers every table in the `cdc` schema.
- **Aiven's S3 sink** is a sink connector. It reads the topics and writes their events to files in SeaweedFS, an object store with the same API as Amazon S3.
- **desflow** runs the simulation, a discrete-event model of the shop written in one YAML file. [desflow](https://github.com/jaehyeon-kim/desflow) ([documentation](https://jaehyeon.me/desflow/latest/architecture/connectors/)) is a Python library for simulations that stream their output.

The simulation writes six tables in PostgreSQL's `cdc` schema:

| Table | Rows | Changes |
|---|---|---|
| `dist_centers` | 10 distribution centres | inserted once |
| `products` | 260 products | inserted once |
| `users` | registered users | inserted, and updated when a user moves address |
| `orders` | orders | inserted as Processing, then updated to Shipped, Delivered, Cancelled or Returned |
| `order_items` | the products in each order | inserted, and updated with their order's status |
| `events` | page views in web sessions, including anonymous visitors | inserted only |

## Setup

You need Docker (Docker Desktop, OrbStack or Docker Engine), [uv](https://docs.astral.sh/uv/) and Python 3.13. Clone the repository and run every command from the project folder:

```bash
git clone https://github.com/jaehyeon-kim/benchtop.git
cd benchtop/ecommerce-cdc

uv venv                             # create .venv
source .venv/bin/activate           # activate it, in each new shell
uv pip install -r requirements.txt

odctl up postgres kafka-lite storage
```

[odctl](https://github.com/jaehyeon-kim/odctl) is a command line tool that starts a local data stack with Docker Compose. Its profiles start these services:

- `postgres`: PostgreSQL, already set up for CDC. It runs with `wal_level=logical`, which makes the WAL hold enough detail for CDC. It also has the schema `cdc` with the publication `cdc_pub`.
- `kafka-lite`: one Kafka broker, Kafka Connect with the Debezium and Aiven S3 connectors, Karapace and Kafka UI. Karapace is a schema registry: it stores the schema of each topic's messages, so a message carries only a short schema id.
- `storage`: SeaweedFS.

The web UIs:

- Kafka UI: http://127.0.0.1:8086, for the topics, their messages and the connectors
- SeaweedFS file browser: http://127.0.0.1:8889

## Simulation Model

A discrete-event simulation (DES) moves a clock from one event to the next, such as a visitor arriving or an order being packed. Nothing happens between events, so the model only has to say what each event does and how long it is until the next one. Here the clock runs at the speed of real time.

The model is one YAML file, `ecommerce/simulation/shop.yaml`. It has three kinds of entity. An entity, such as a visit or an order, goes through a chain of tasks, and each task names the next one:

- **Visitor:** visitors arrive at random, about one a second. Each views the home page and one to four products, and spends a few seconds on each page. Six in ten are registered users. Three in ten buy: they view the cart, sign up first if they are new, and place an order of one to four products.
- **Order:** each order waits for one of the warehouse's pickers. Three pickers pack orders, one at a time each. When orders arrive faster than they are packed, they queue. An order that waits longer than its customer's patience, about two minutes, is cancelled. A packed order is shipped, delivered about a minute later, and one in ten is returned.
- **Move:** now and then a registered user moves to a new address.

Each part of this model is a section of the file:

| Part | Key in `shop.yaml` | Here |
|---|---|---|
| random arrivals | `arrivals` | visitors, and address moves |
| fixed rows at the start | `arrivals` with `initial` | the distribution centres and products, read from CSV files, and the first 100 users |
| time spent on a step | `services` | a page view, packing, transit, patience and the time until a return |
| limited capacity | `resources` | the pickers, which make orders queue |
| chances | `variables` | a visitor is registered, a visitor buys, an order is returned |
| the steps of a visit or an order | `tasks`, with `next` and `spawn` | each page of a visit, and each status of an order |
| live changes | the registry and `ingress` | any of the above, while it runs |
| writes | `egress` | one per table, upserting on `id` |

Each parameter is added to desflow's registry, a store of named parameters that the model reads each time it draws a value. The top of the file holds the Kafka reader for live changes and the parameters:

```yaml
# Parameter changes from ecommerce.simulation.control
ingress:
  - type: Kafka
    config:
      bootstrap_servers: "127.0.0.1:9092"
      topic: ecommerce-control

# Shares of visitors or orders, from 0 to 1
variables:
  returning: 0.6 # a visitor is a registered user
  buy: 0.3 # a visitor buys at the end of the visit
  return: 0.1 # a delivered order is returned

# Warehouse pickers packing orders at once
resources:
  pickers: {current_cap: "${PICKERS:-3}", max_cap: 10}

# Mean and standard deviation, in seconds
services:
  page_view: {dist: lognormal, mean: 4.0, std: 2.0} # time on a page before the next one
  # how long an order waits for a picker before it is cancelled
  patience: {dist: lognormal, mean: 120.0, std: 60.0}
  pick: {dist: lognormal, mean: 5.0, std: 2.0} # a picker packs an order
  transit: {dist: lognormal, mean: 60.0, std: 20.0} # a shipped order reaches the customer
  return_after: {dist: lognormal, mean: 60.0, std: 30.0} # a returned order comes back
```

The order's tasks are in the same file. `pick_order` asks for a picker, with a patience time drawn from the `patience` service. If the order waits longer than its patience, it leaves the queue and goes to `cancel_order` (`on_renege`). Each status change sets the order's attributes, and `order_row` writes the order again with the same `id`. `items` then writes a row for each of its items and chooses the next status. `*now` is the simulated time as ISO 8601 text, defined once earlier in the file with a YAML anchor:

```yaml
  # A picker packs the order and it ships, unless it waits for a picker longer than
  # its patience and is cancelled.
  pick_order:
    resource: pickers
    service: pick
    patience: {gen: sample, service: patience}
    on_renege: cancel_order
    payload: null
    set: {status: Shipped, updated_at: *now, shipped_at: *now}
    next: order_row
  cancel_order:
    payload: null
    set: {status: Cancelled, updated_at: *now, cancelled_at: *now}
    next: order_row
  deliver_order:
    service: transit
    payload: null
    set:
      status: Delivered
      updated_at: *now
      delivered_at: *now
      sent_back: {gen: boolean, p: {gen: param, path: ecommerce.variables.return}}
    next: order_row
  return_order:
    service: return_after
    payload: null
    set: {status: Returned, updated_at: *now, returned_at: *now}
    next: order_row
  # The orders row after each status change, then a row for each of its items
  order_row:
    payload:
      __table__: cdc.orders
      id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user_id}
      status: {gen: attr, name: status}
      num_of_items: {gen: expr, expr: "len(attr.items)"}
      created_at: {gen: attr, name: created_at}
      updated_at: {gen: attr, name: updated_at}
      shipped_at: {gen: attr, name: shipped_at}
      delivered_at: {gen: attr, name: delivered_at}
      cancelled_at: {gen: attr, name: cancelled_at}
      returned_at: {gen: attr, name: returned_at}
    next: items
  items:
    wait:
      each: attr.items
      branch: {task: item_row, args: {item: {gen: expr, expr: each.value}}}
    payload: null
    next:
      when:
        - {condition: "attr.status == 'Processing'", task: pick_order}
        - {condition: "attr.status == 'Shipped'", task: deliver_order}
        - {condition: "attr.status == 'Delivered' and attr.sent_back", task: return_order}
```

The `egress` section has one PostgreSQL writer per table, each upserting on `id`. An upsert inserts a row, or updates it when a row with the same key exists. So a changed order reaches PostgreSQL as an update, and Debezium sees it as one. Each writer also creates its table when it is missing, from the columns its `tables` entry lists. The first writer is shown here, and the other five differ only in their table and its columns:

```yaml
# A few rows a second for each table
batching: {batch_size: 4, flush_interval: 1.0}

# One sink for each table. Each creates its table at the start when it does not exist,
# and upserts on `id`, so a changed order or user reaches PostgreSQL as an update. Times
# are ISO 8601 text in UTC. A row's `__table__` names the sink that writes it, and
# `envelope: false` writes the row alone, with no record of a task being queued or
# started, and `when` drops the record of an order that leaves the picking queue,
# which `cancel_order` writes as a row instead.
egress:
  - type: Postgres
    when: &rows {expr: "record.stream_type == 'event' and record.value.status != 'reneged'"}
    envelope: false
    config:
      connection_dsn: &dsn "postgresql://user:password@127.0.0.1:5432/odctl"
      upsert_keys: &key [id]
      tables:
        cdc.dist_centers:
          primary_key: id
          columns:
            id: BIGINT
            name: TEXT
            latitude: DOUBLE PRECISION
            longitude: DOUBLE PRECISION
```

Times are stored as ISO 8601 text in UTC. desflow publishes each row as JSON-friendly values, so a time reaches PostgreSQL as a string, and a timestamp column does not accept a string.

## Step 1: Run the Simulation

```bash
desflow run ecommerce/simulation/shop.yaml --until "16 min"   # or leave out --until, and stop with Ctrl + C
```

It creates the six tables if they are missing, and writes the centres, the products and 100 users. It then runs in real time. With the default parameters it places about 18 orders a minute, and each order changes three or four times over the next few minutes. Its log shows the Kafka reader and one PostgreSQL writer per table:

```
14:40:26 [INFO] desflow.builder.context: Building SimulationContext for 'ecommerce'...
14:40:26 [INFO] desflow.builder.context: No random_seed was given, so this run uses 1778597616. Repeat it with: desflow run ecommerce/simulation/shop.yaml --seed 1778597616 --until 13min
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:40:26 [INFO] desflow.builder.context: Simulation engine started.
14:40:26 [INFO] aiokafka.consumer.subscription_state: Updating subscribed topics to: frozenset({'ecommerce-control'})
14:40:26 [INFO] aiokafka.consumer.group_coordinator: Metadata for topic has changed from {} to {'ecommerce-control': 1}. 
14:40:26 [INFO] desflow.connectors.ingress.kafka: Connected to Kafka Ingress topic: ecommerce-control
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.products
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.users
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.order_items
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.events
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.orders
14:40:26 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to cdc.dist_centers
```

Leave it running, and use a second terminal for the next steps.

## Step 2: Deploy the Connectors

```bash
python -m ecommerce.cdc.connectors
```

It sends two JSON files to Kafka Connect. Connect creates each connector, or updates it if it exists. The source connector's settings are in `ecommerce/cdc/source.json`:

```json
{
  "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
  "tasks.max": "1",
  "database.hostname": "postgres",
  "database.port": "5432",
  "database.user": "user",
  "database.password": "password",
  "database.dbname": "odctl",
  "plugin.name": "pgoutput",
  "publication.name": "cdc_pub",
  "publication.autocreate.mode": "disabled",
  "slot.name": "ecommerce_cdc",
  "table.include.list": "cdc.users,cdc.products,cdc.dist_centers,cdc.orders,cdc.order_items,cdc.events",
  "topic.prefix": "ecommerce",
  "snapshot.mode": "initial",
  "key.converter": "io.confluent.connect.avro.AvroConverter",
  "key.converter.schema.registry.url": "http://karapace:8081",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://karapace:8081"
}
```

These settings tell Debezium to:

- read the database `odctl` with PostgreSQL's built-in `pgoutput` decoder;
- use the existing publication `cdc_pub`, and never create one (`publication.autocreate.mode` is `disabled`);
- keep its place in the WAL in its own replication slot, `ecommerce_cdc`;
- capture only this project's six tables, and name the topics `ecommerce.cdc.<table>`;
- take a snapshot of the existing rows first (`snapshot.mode` is `initial`);
- write Avro, a compact binary format, with each table's key and value schemas registered in Karapace as the subjects `ecommerce.cdc.<table>-key` and `ecommerce.cdc.<table>-value`.

The sink connector's settings are in `ecommerce/cdc/s3-sink.json`:

```json
{
  "connector.class": "io.aiven.kafka.connect.s3.AivenKafkaConnectS3SinkConnector",
  "tasks.max": "1",
  "topics.regex": "ecommerce\\.cdc\\..*",
  "consumer.override.metadata.max.age.ms": "30000",
  "aws.access.key.id": "user",
  "aws.secret.access.key": "password",
  "aws.s3.endpoint": "http://seaweed:8333",
  "aws.s3.region": "us-east-1",
  "aws.s3.bucket.name": "odctl-dev",
  "file.name.template": "ecommerce-cdc/{{topic}}/{{partition}}-{{start_offset}}.jsonl",
  "file.compression.type": "none",
  "format.output.type": "jsonl",
  "format.output.fields": "key,value,offset,timestamp",
  "format.output.fields.value.encoding": "none",
  "key.converter": "io.confluent.connect.avro.AvroConverter",
  "key.converter.schema.registry.url": "http://karapace:8081",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://karapace:8081"
}
```

It reads every topic whose name matches `ecommerce.cdc.*`, and decodes each message with its schema from Karapace. It writes JSON lines files to the bucket `odctl-dev`, under `ecommerce-cdc/<topic>/`, with one change event on each line. The sink writes a file each time Connect commits its offsets, which record how far the sink has read. That happens about once a minute. The `orders` topic is created only when the first order is placed, after the sink has started. The sink subscribes by a topic pattern, and a Kafka consumer looks for new topics only when it refreshes its list of topics, every five minutes by default. `consumer.override.metadata.max.age.ms` makes the sink's consumer refresh it every 30 seconds instead. In a test run, the first `orders` file appeared after about a minute.

Each connector's status should show `RUNNING` for the connector and its task:

```bash
curl -s http://127.0.0.1:8083/connectors/ecommerce-cdc-source/status
curl -s http://127.0.0.1:8083/connectors/ecommerce-cdc-s3/status
```

Kafka UI lists both connectors under Kafka Connect.

![Kafka UI listing the Debezium source and the S3 sink, both running](kafka-ui-connectors.png#center "Both connectors in Kafka UI")

## Step 3: Look at the Changes

Debezium creates one topic per table. The simulation creates `ecommerce-control`, which carries parameter changes. The topics after a run:

```
ecommerce-control
ecommerce.cdc.dist_centers
ecommerce.cdc.events
ecommerce.cdc.order_items
ecommerce.cdc.orders
ecommerce.cdc.products
ecommerce.cdc.users
```

![Kafka UI listing the six ecommerce.cdc topics and the control topic, with their message counts](kafka-ui-topics.png#center "The change topics in Kafka UI")

![Kafka UI's schema registry page listing a key and a value subject for each ecommerce.cdc topic](kafka-ui-schemas.png#center "The Avro subjects in Karapace")

In Kafka UI, open a topic such as `ecommerce.cdc.orders`. Each message is one change, and its `op` field says which kind:

| `op` | Meaning |
|---|---|
| `r` | a row read in the first snapshot |
| `c` | a new row (create) |
| `u` | an update: `after` holds the row's new values |

![Kafka UI showing the newest ecommerce.cdc.orders messages, decoded with their Avro schemas](kafka-ui-orders-messages.png#center "Change events on the orders topic")

This update shows an order moving from Processing to Shipped, with the time it shipped. `source` records where the change came from: the table, the transaction and its position in the WAL (`lsn`).

```json
{
  "before": null,
  "after": {
    "id": "23b2d4a9-360d-4973-a6da-fd1cc394ca10",
    "user_id": "862dd089-c746-4127-89d7-db4fcab59a2e",
    "status": "Shipped",
    "num_of_items": 1,
    "created_at": "2026-09-30T13:38:56+00:00",
    "updated_at": "2026-09-30T13:39:01+00:00",
    "shipped_at": "2026-09-30T13:39:01+00:00",
    "delivered_at": null,
    "cancelled_at": null,
    "returned_at": null
  },
  "source": {
    "version": "3.7.0.Final",
    "connector": "postgresql",
    "name": "ecommerce",
    "ts_ms": 1790775541329,
    "snapshot": "false",
    "db": "odctl",
    "sequence": "[\"161004032\",\"161004832\"]",
    "ts_us": 1790775541329358,
    "ts_ns": 1790775541329358000,
    "schema": "cdc",
    "table": "orders",
    "txId": 45922,
    "lsn": 161004832,
    "xmin": null,
    "origin": null,
    "origin_lsn": null
  },
  "transaction": null,
  "op": "u",
  "ts_ms": 1790775541830,
  "ts_us": 1790775541830602,
  "ts_ns": 1790775541830602065
}
```

`before` is null for updates, because PostgreSQL logs only the new row by default.

In the SeaweedFS file browser, go to `odctl-dev/ecommerce-cdc/`. There is a folder per topic. Each file holds the change events of one partition, one per line. The first line of the first `orders` file, `0-0.jsonl`, is a create event. The sink adds the message's key, offset and time around the change event:

```json
{
  "offset": 0,
  "value": {
    "before": null,
    "after": {
      "id": "23b2d4a9-360d-4973-a6da-fd1cc394ca10",
      "user_id": "862dd089-c746-4127-89d7-db4fcab59a2e",
      "status": "Processing",
      "num_of_items": 1,
      "created_at": "2026-09-30T13:38:56+00:00",
      "updated_at": "2026-09-30T13:38:56+00:00",
      "shipped_at": null,
      "delivered_at": null,
      "cancelled_at": null,
      "returned_at": null
    },
    "op": "c"
  },
  "key": {
    "id": "23b2d4a9-360d-4973-a6da-fd1cc394ca10"
  },
  "timestamp": "2026-09-30T13:38:57.992Z"
}
```

The line is shown across several lines here. `source`, `transaction` and the `ts_*` times are left out of `value`, because they have the same fields as the change event above.

![SeaweedFS file browser listing the JSON lines files the sink wrote for the orders topic](seaweedfs-files.png#center "Files the S3 sink wrote to SeaweedFS")

## Step 4: Change the Simulation While It Runs

The simulation reads parameter changes from the Kafka topic `ecommerce-control`, through the `ingress` entry of `shop.yaml`. It uses each new value from the next time it draws one. `control.py` sends a change. With the simulation and both connectors running, cut the pickers from three to one:

```bash
python -m ecommerce.simulation.control ecommerce.resources.pickers.current_cap 1
```

```
Sent ecommerce.resources.pickers.current_cap = 1.0 to ecommerce-control
```

One picker packs about 12 orders a minute, which is fewer than the 18 or so placed, so the queue grows. The `Shipped` updates in `ecommerce.cdc.orders` fall from about 20 a minute to about 13. `Cancelled` updates appear as customers' patience runs out, which never happens with three pickers. In one run, the change was sent at 03:45:11 UTC. These are the changes per minute in `ecommerce.cdc.orders`, counted by the minute of each Debezium event:

| Minute (UTC) | Pickers | New orders | Shipped | Cancelled |
|---|---|---|---|---|
| 03:41 | 3 | 16 | 20 | 0 |
| 03:42 | 3 | 21 | 17 | 0 |
| 03:43 | 3 | 22 | 23 | 0 |
| 03:44 | 3 | 16 | 18 | 0 |
| 03:46 | 1 | 26 | 12 | 0 |
| 03:47 | 1 | 16 | 14 | 1 |
| 03:48 | 1 | 20 | 12 | 6 |
| 03:49 | 1 | 20 | 14 | 2 |
| 03:50 | 1 | 19 | 13 | 4 |
| 03:51 | 1 | 20 | 12 | 10 |
| 03:52 | 1 | 13 | 12 | 6 |

Other parameters work the same way, such as `ecommerce.arrival.visitor.rate` for visitors a second, or `ecommerce.variables.buy` for the chance a visitor buys. `python -m ecommerce.simulation.control --help` lists them all. A change lasts until the simulation stops.

## Clean Up

```bash
python -m ecommerce.stores.cleanup
```

It removes only this project's objects, and keeps the services running:

- **Connectors:** it stops both and deletes their stored offsets, so a new source connector takes a fresh snapshot. It then deletes them.
- **Replication slot:** it drops `ecommerce_cdc`. PostgreSQL keeps the WAL for an unused slot forever, so a slot left behind makes the WAL grow without limit.
- **Tables:** it drops the six tables in `cdc`.
- **Kafka:** it deletes the topics starting with `ecommerce.`, and `ecommerce-control`.
- **SeaweedFS:** it deletes the files under `odctl-dev/ecommerce-cdc/`.

In a test run, the first clean-up deleted both connectors, the seven topics and 45 files. A second run found nothing left to delete, so it is safe to run twice.

To stop the services and delete their data:

```bash
odctl down --all --volumes          # answer y; --volumes also deletes the data
deactivate
rm -rf .venv
```

## Related posts

* [Change Data Capture (CDC) Local Development with PostgreSQL, Debezium Server and Pub/Sub Emulator](/blog/2024-11-07-cdc-local-dev/) - change data capture from PostgreSQL with Debezium Server and a Pub/Sub emulator instead of Kafka Connect
* [Data Lake Demo using Change Data Capture (CDC) on AWS - Part 1 Local Development](/blog/2021-12-05-datalake-demo-part1/) - an earlier local setup with Debezium and an S3 sink connector on Kafka Connect, the start of a data lake series
* [Defining Data-Streaming Simulations in YAML, Without Writing Python](/blog/2026-10-06-simulations-in-yaml-dynamic-des/) - the simulation library that runs the shop, now configurable in plain YAML
