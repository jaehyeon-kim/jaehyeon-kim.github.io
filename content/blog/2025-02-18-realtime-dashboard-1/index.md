---
title: Realtime Dashboard with FastAPI, Streamlit and Next.js - Part 1 Data Producer
date: 2025-02-18
draft: false
featured: false
comment: true
toc: true
series:
  - Realtime Dashboard with FastAPI, Streamlit and Next.js
categories:
  - Development
tags: 
  - FastAPI
  - PostgreSQL
  - Python
  - Docker
  - WebSocket
  - Benchtop
description: A desflow simulation, written in YAML, loads theLook eCommerce data into PostgreSQL, and a FastAPI WebSocket server queries it on a timer to serve live dashboards.
---

A data generating app is written as a YAML simulation that desflow runs, and it ingests the [theLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) data continuously into a PostgreSQL database. A WebSocket server, built by [FastAPI](https://fastapi.tiangolo.com/), periodically queries the data to serve its clients. In this series, we develop real-time monitoring dashboard applications, and this post walks through the data generation app and backend API. The monitoring dashboards will be developed using [Streamlit](https://streamlit.io/) and [Next.js](https://nextjs.org/), with [Apache ECharts](https://echarts.apache.org/en/index.html) for visualization. They will be discussed in later posts.

<!--more-->

* [Part 1 Data Producer](#) (this post)
* [Part 2 Streamlit Dashboard](/blog/2025-02-25-realtime-dashboard-2/)
* [Part 3 Next.js Dashboard](/blog/2025-03-04-realtime-dashboard-3/)

<!--more-->

[**Update 2026-11-15**] The data generator is now one YAML file, `model.yaml`, which desflow 1.0.0 runs with `desflow run model.yaml`. It replaces the Python modules in `sales/simulation`, apart from the control command, and it creates the tables itself. The code, commands and log below show the new version.

[**Update 2026-10-16**] dynamic-des is now desflow: pip install desflow, import desflow and the desflow command. The parameter table's columns are `path` and `value`, which the PostgreSQL ingress reads from desflow 0.21.0.

## Services

![The simulation writes to PostgreSQL, the WebSocket server sends the recent order items on /ws, and a terminal client prints them](part-1.png#center "Architecture")

We have three services, and they are illustrated separately below. The source of this post can be found in the **live-dashboard** folder of the [**benchtop**](https://github.com/jaehyeon-kim/benchtop/tree/main/live-dashboard) GitHub repository. It is one of the [Benchtop](/blog/2026-09-30-introducing-benchtop/) projects, which run locally from a fresh clone. The development environment can be constructed as follows:

```bash
$ git clone https://github.com/jaehyeon-kim/benchtop.git
$ cd benchtop/live-dashboard
$ uv venv
$ source .venv/bin/activate
(.venv) $ uv pip install -r requirements.txt
```

### PostgreSQL

A PostgreSQL database server is started with [odctl](https://github.com/jaehyeon-kim/odctl), which runs it with Docker Compose on port 5432.

```bash
(.venv) $ odctl up postgres
```

The data generator creates a dedicated schema named *dashboard* and its tables when it starts. Each table's columns and primary key are set in the data generator's model file, shown below.

### Data Generator

The data generator is a [desflow](https://github.com/jaehyeon-kim/desflow) simulation of the shop. The simulation is one YAML file, `model.yaml`, and the `desflow` command runs it in its own terminal. The file sets the PostgreSQL address and every setting of the simulation. It runs until it is stopped (`--until '10 min'` stops it after ten minutes).

```bash
(.venv) $ desflow run model.yaml
```

#### Data Generator Source

The *theLook eCommerce* dataset is reduced to four entities, three of which are dynamically generated. Visitors arrive at random, view a few pages, and some buy. A buyer is a new or a returning *user*, and each purchase creates an *order* with one or more *order items*. Each order waits for a warehouse picker, then ships and completes, or is cancelled when no picker comes in time. Every change of status updates the order and its items. In the file, each step is a task, and a task's `payload` is the row it writes, with `__table__` naming the table. The `egress` section writes each row to its table, and the `ingress` section applies parameter changes while the simulation runs.

```yaml
# live-dashboard/model.yaml
# The shop, run in real time into PostgreSQL. Visitors arrive and browse, and some buy.
# Each order waits for a picker, ships and completes, or is cancelled when no picker
# comes in time. Every rate, time and chance is a registry parameter, so a row added to
# dashboard.params (sales.simulation.control) changes it while the model runs.
simulation:
  sim_id: sales
  factor: 1
  logical_start_time: now
  timezone: UTC

# The ingress applies the rows of its parameter table that are not applied yet, every
# two seconds
ingress:
  - type: Postgres
    config:
      connection_dsn: "${PG_DSN:-postgresql://user:password@127.0.0.1:5432/odctl}"
      table_name: dashboard.params

# A few rows arrive a second
batching: {batch_size: 4, flush_interval: 1.0}

# One entry per table: an entry writes the events whose __table__ names its table and
# ignores the others. `envelope: false` writes the payload alone, so no task record
# reaches a table, and `when` drops the record of an order that leaves the picking
# queue, which the `cancelled` task writes as a row instead. `tables` makes the `dashboard` schema and the table at start when
# they do not exist. Orders and their items upsert on id, because their status changes.
egress:
  - type: Postgres
    when: &rows {expr: "record.stream_type == 'event' and record.value.status != 'reneged'"}
    envelope: false
    config:
      connection_dsn: "${PG_DSN:-postgresql://user:password@127.0.0.1:5432/odctl}"
      table_name: users
      server_settings: {search_path: dashboard}
      tables:
        dashboard.users:
          columns:
            id: TEXT
            age: INT
            gender: TEXT
            country: TEXT
            traffic_source: TEXT
            created_at: TEXT
          primary_key: id
  - type: Postgres
    when: *rows
    envelope: false
    config:
      connection_dsn: "${PG_DSN:-postgresql://user:password@127.0.0.1:5432/odctl}"
      table_name: orders
      server_settings: {search_path: dashboard}
      upsert_keys: [id]
      tables:
        dashboard.orders:
          columns:
            id: TEXT
            user_id: TEXT
            status: TEXT
            num_of_item: INT
            created_at: TEXT
          primary_key: id
  - type: Postgres
    when: *rows
    envelope: false
    config:
      connection_dsn: "${PG_DSN:-postgresql://user:password@127.0.0.1:5432/odctl}"
      table_name: order_items
      server_settings: {search_path: dashboard}
      upsert_keys: [id]
      tables:
        dashboard.order_items:
          columns:
            id: TEXT
            order_id: TEXT
            user_id: TEXT
            product_id: BIGINT
            status: TEXT
            sale_price: FLOAT8
            created_at: TEXT
          primary_key: id
  - type: Postgres
    when: *rows
    envelope: false
    config:
      connection_dsn: "${PG_DSN:-postgresql://user:password@127.0.0.1:5432/odctl}"
      table_name: products
      server_settings: {search_path: dashboard}
      tables:
        dashboard.products:
          columns:
            id: BIGINT
            name: TEXT
            category: TEXT
            department: TEXT
            retail_price: FLOAT8
            cost: FLOAT8
          primary_key: id

# Chances that a visitor is a registered user, buys, and returns a delivered order;
# `users` counts the users made so far
variables: {returning: 0.6, buy: 0.3, return: 0.1, users: 0}

# Mean and standard deviation in seconds
services:
  page_view: {dist: lognormal, mean: 4.0, std: 2.0}
  pick: {dist: lognormal, mean: 5.0, std: 2.0}
  transit: {dist: lognormal, mean: 60.0, std: 20.0}
  return_after: {dist: lognormal, mean: 60.0, std: 30.0}
  patience: {dist: lognormal, mean: 120.0, std: 60.0}

# Warehouse pickers packing orders at once
resources:
  pickers: {current_cap: 10, max_cap: 20}

arrivals:
  # The 260 products of products.csv, written in id order when the run starts
  catalogue: {initial: 260, spawn: product_row}
  # Visitors a second, exponential gaps
  visitor:
    dist: exponential
    rate: 4
    spawn: catalogue_check
    attributes:
      n: 0
      pages: {gen: integer, bounds: [2, 5]}

tasks:
  product_row:
    vars:
      p: {gen: row, file: products.csv, order: sequential}
    payload:
      __table__: products
      id: {gen: var, name: p, path: id}
      name: {gen: var, name: p, path: name}
      category: {gen: var, name: p, path: category}
      department: {gen: var, name: p, path: department}
      retail_price: {gen: var, name: p, path: retail_price}
      cost: {gen: var, name: p, path: cost}
  # A visitor is a returning user, chosen at the start of the visit from the users made
  # so far, with the chance `returning` once a user exists
  catalogue_check:
    payload: null
    next:
      weights:
        pick_user: "registry['sales.variables.returning'] if
          registry['sales.variables.users'] > 0 else 0"
        no_user: "1 - (registry['sales.variables.returning'] if
          registry['sales.variables.users'] > 0 else 0)"
  # An earlier user, each with the same chance; no visitor is sent here before a user
  # exists
  pick_user:
    payload: null
    set:
      user: {gen: lookup, task: new_user, path: id}
    next: pages
  no_user:
    payload: null
    set: {user: ""}
    next: pages
  # Two to five page views, a loop of `next`
  pages:
    service_time: {gen: sample, service: page_view}
    payload: null
    set:
      n: {gen: expr, expr: "attr.n + 1"}
    next:
      when:
        - {condition: "attr.n < attr.pages", task: pages}
      default: buy_choice
  # The chance to buy is a live variable, read for each visitor
  buy_choice:
    payload: null
    next:
      weights:
        buyer: "registry['sales.variables.buy']"
        walk_away: "1 - registry['sales.variables.buy']"
  walk_away:
    payload: null
  # A returning visitor orders for the user chosen at the start; a new user is made only
  # here
  buyer:
    payload: null
    next:
      when:
        - {condition: "attr.user != ''", task: returning}
      default: new_user
  returning:
    payload: null
    next: order
  new_user:
    on:
      - path: sales.variables.users
        value: {gen: expr, expr: "registry['sales.variables.users'] + 1"}
    vars:
      uid: {gen: uuid}
    # the order names its user in orders.user_id
    set:
      user: {gen: var, name: uid}
    payload:
      __table__: users
      id: {gen: var, name: uid}
      age: {gen: integer, bounds: [12, 70]}
      gender: {gen: one_of, choices: [F, M]}
      country:
        gen: weighted
        options:
          China: 7319934
          Brasil: 7294477
          South Korea: 1493470
          France: 1458801
          United States: 1157308
          United Kingdom: 1024009
      traffic_source:
        gen: weighted
        options:
          Search: 0.7
          Organic: 0.15
          Facebook: 0.06
          Email: 0.05
          Display: 0.04
      created_at: {gen: now}
    next: order
  # One to four items (70%, 20%, 5% and 5%), each a different product
  order:
    vars:
      # the order's row and every later row of it carry this id
      oid: {gen: uuid}
      created: {gen: now}
      n:
        gen: expr
        expr: "1 if u < 0.7 else 2 if u < 0.9 else 3 if u < 0.95 else 4"
        names:
          u: {gen: uniform, low: 0, high: 1}
      ids:
        gen: repeat
        times: {gen: var, name: n}
        value: {gen: uuid}
    set:
      order_id: {gen: var, name: oid}
      created_at: {gen: var, name: created}
      n: {gen: var, name: n}
      iids: {gen: var, name: ids}
      products:
        gen: repeat
        times: {gen: var, name: n}
        value: {gen: lookup, task: product_row, distinct: true}
    payload:
      __table__: orders
      id: {gen: var, name: oid}
      user_id: {gen: attr, name: user}
      status: Processing
      num_of_item: {gen: var, name: n}
      created_at: {gen: var, name: created}
    next: items
  items:
    wait:
      each: "range(attr.n)"
      branch:
        task: order_item
        args:
          i: {gen: expr, expr: each.value}
          status: Processing
    payload: null
    next: pick
  # one item row; a status change writes every item again with the same id
  order_item:
    vars:
      p: {gen: expr, expr: "attr.products[arg.i]"}
    payload:
      __table__: order_items
      id: {gen: expr, expr: "attr.iids[arg.i]"}
      order_id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user}
      product_id: {gen: var, name: p, path: id}
      status: {gen: expr, expr: arg.status}
      sale_price: {gen: var, name: p, path: retail_price}
      created_at: {gen: attr, name: created_at}
  # An order that waits longer than its patience for a picker is cancelled
  pick:
    resource: pickers
    service: pick
    patience: {gen: sample, service: patience}
    on_renege: cancelled
    payload:
      __table__: orders
      id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user}
      status: Shipped
      num_of_item: {gen: attr, name: n}
      created_at: {gen: attr, name: created_at}
    next: items_shipped
  items_shipped:
    wait:
      each: "range(attr.n)"
      branch:
        task: order_item
        args:
          i: {gen: expr, expr: each.value}
          status: Shipped
    payload: null
    next: transit
  cancelled:
    payload:
      __table__: orders
      id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user}
      status: Cancelled
      num_of_item: {gen: attr, name: n}
      created_at: {gen: attr, name: created_at}
    next: items_cancelled
  items_cancelled:
    wait:
      each: "range(attr.n)"
      branch:
        task: order_item
        args:
          i: {gen: expr, expr: each.value}
          status: Cancelled
    payload: null
  transit:
    service: transit
    payload:
      __table__: orders
      id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user}
      status: Complete
      num_of_item: {gen: attr, name: n}
      created_at: {gen: attr, name: created_at}
    next: items_complete
  items_complete:
    vars:
      sent_back:
        gen: boolean
        p: {gen: param, path: sales.variables.return}
    wait:
      each: "range(attr.n)"
      branch:
        task: order_item
        args:
          i: {gen: expr, expr: each.value}
          status: Complete
    payload: null
    next:
      when:
        - {condition: "sent_back", task: returned}
  returned:
    service: return_after
    payload:
      __table__: orders
      id: {gen: attr, name: order_id}
      user_id: {gen: attr, name: user}
      status: Returned
      num_of_item: {gen: attr, name: n}
      created_at: {gen: attr, name: created_at}
    next: items_returned
  items_returned:
    wait:
      each: "range(attr.n)"
      branch:
        task: order_item
        args:
          i: {gen: expr, expr: each.value}
          status: Returned
    payload: null

# `desflow test model.yaml` runs each test unpaced, with no ingress and no egress, and
# compares its statistics with these. `desflow test model.yaml --fix` writes new values
# after a deliberate change or a desflow upgrade.
tests:
  # One hour at the defaults: the whole catalogue is written, about 1.2 orders arrive a
  # second, and about four buyers in ten are new users
  - name: an hour at the defaults
    seed: 1
    until: 3600
    expect:
      tasks.product_row.finished: 260
      tasks.new_user.finished: 1795
      tasks.order.finished: 4375
      tasks.pick.finished: 4368
      tasks.transit.finished: 4307
      tasks.returned.finished: 441
```

In the following example, the simulation logs the seed it drew, starts and connects to each table.

```bash
(.venv) $ desflow run model.yaml
14:36:44 [INFO] desflow.builder.context: Building SimulationContext for 'sales'...
14:36:44 [INFO] desflow.builder.context: No random_seed was given, so this run uses 1842063416. Repeat it with: desflow run model.yaml --seed 1842063416
14:36:44 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:36:44 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:36:44 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:36:44 [INFO] desflow.core.environment: PostgresEgress has envelope: false, so it skips telemetry and the queued and started records, and writes each event's value alone.
14:36:44 [INFO] desflow.builder.context: Simulation engine started.
14:36:44 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to users
14:36:44 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to order_items
14:36:44 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to orders
14:36:44 [INFO] desflow.connectors.egress.postgres: PostgresEgress connected to products
```

When the data gets ingested into the database, we see the following tables are created in the *dashboard* schema.

| Table | One row per |
|---|---|
| `products` | product: 260, from 26 categories, 2 departments and 5 brands |
| `users` | customer, with age, gender, country and traffic source |
| `orders` | order, with its status and number of items |
| `order_items` | product in an order, with its status and sale price |

### WebSocket Server

This WebSocket server runs a FastAPI-based API using `uvicorn`, in its own terminal, on port 8000. It connects to the PostgreSQL database with the settings in `sales/core/config.py`. The service processes data with a 5-minute lookback window and refreshes every 5 seconds.

```bash
(.venv) $ uvicorn sales.api.server:app --host 127.0.0.1 --port 8000
```

#### WebSocket Server Source

This FastAPI WebSocket server streams real-time data from a PostgreSQL database. It connects using *asyncpg*, fetches order-related data with a configurable *lookback window*, and sends updates every few seconds as defined by *refresh seconds*. Each update is a JSON list of records. The app continuously queries the database, sending fresh data to the connected client until it disconnects. Logging ensures visibility into connections and queries.

```python
# live-dashboard/sales/api/server.py
"""Sends the recent order items to the dashboards over a WebSocket.

Every `REFRESH_SECONDS`, `/ws` sends the order items of the last `LOOKBACK_MINUTES`,
with their users and products, as a JSON list of records.

Run: uvicorn sales.api.server:app --host 127.0.0.1 --port 8000
"""

import asyncio
import logging

import asyncpg
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from sales.core.config import DSN, LOOKBACK_MINUTES, REFRESH_SECONDS
from sales.stores import postgres

logger = logging.getLogger("uvicorn.error")
app = FastAPI()


@app.websocket("/ws")
async def stream(websocket: WebSocket) -> None:
    """
    Sends the recent order items every `REFRESH_SECONDS`, until the client leaves.

    Args:
        websocket (WebSocket): The client.
    """
    await websocket.accept()
    conn = await asyncpg.connect(DSN)
    try:
        while True:
            records = await postgres.recent_items(conn, LOOKBACK_MINUTES)
            logger.info("Sending %d records", len(records))
            await websocket.send_json(records)
            await asyncio.sleep(REFRESH_SECONDS)
    except WebSocketDisconnect:
        logger.info("Client disconnected")
    finally:
        await conn.close()
```

The query and the function that runs it are in the store module.

```python
# live-dashboard/sales/stores/postgres.py
# The order items of the last $1 minutes, with their users and products.
# clock_timestamp() is the time now; current_timestamp would stay at the transaction's start.
RECENT_ITEMS = f"""
SELECT u.id AS user_id, u.age, u.gender, u.country, u.traffic_source,
    o.order_id, o.id AS item_id, p.category, p.cost, o.status AS item_status,
    o.sale_price, o.created_at
FROM {SCHEMA}.order_items AS o
JOIN {SCHEMA}.users AS u ON u.id = o.user_id
JOIN {SCHEMA}.products AS p ON p.id = o.product_id
WHERE o.created_at::timestamptz >= clock_timestamp() - make_interval(mins => $1)
"""
```

```python
# live-dashboard/sales/stores/postgres.py
async def recent_items(conn: asyncpg.Connection, minutes: int) -> list[dict]:
    """
    Reads the order items of the last `minutes`, with their users and products.

    Args:
        conn (asyncpg.Connection): An open connection.
        minutes (int): The lookback window.

    Returns:
        list[dict]: One record per order item.
    """
    return [dict(row) for row in await conn.fetch(RECENT_ITEMS, minutes)]
```

## Deploy Services

The services are started with the commands above: PostgreSQL first, then the data generator and the WebSocket server, each in its own terminal. Once started, the server can be checked with the WebSocket client of the [websockets](https://websockets.readthedocs.io/) package, which is installed with uvicorn, by executing `python -m websockets ws://127.0.0.1:8000/ws`, and its logs are printed in its terminal.  

The client prints each message the server sends: a list of the order items of the last five minutes, here 39 records in the first message.

```bash
python -m websockets ws://127.0.0.1:8000/ws
```

```text
Connected to ws://127.0.0.1:8000/ws.
< [{"user_id":"427f5544-f594-4127-826e-912dc0dd970e","age":40,"gender":"M","country":"China","traffic_source":"Search","order_id":"e8c140bd-087a-4dfe-ac01-29f40a36a27e","item_id":"40deff28-0310-49ed-b11b-fdf0a3dabb24","category":"Active","cost":24.7,"item_status":"Shipped","sale_price":55.04,"created_at":"2026-09-30T13:57:06.948553+00:00"}, ...]
```

The server logs how many records it sends every five seconds:

```text
INFO:     Started server process [...]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     127.0.0.1:54478 - "WebSocket /ws" [accepted]
INFO:     connection open
INFO:     Sending 39 records
INFO:     Sending 54 records
INFO:     Sending 67 records
```

## Related posts

* [Guide to Building Integrated Web Applications with FastAPI and NiceGUI](/blog/2025-11-19-fastapi-nicegui-template/) - serves a FastAPI backend and the web UI from one Python process, compared with React and with Streamlit
