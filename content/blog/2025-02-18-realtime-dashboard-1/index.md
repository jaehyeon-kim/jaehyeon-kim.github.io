---
title: Realtime Dashboard with FastAPI, Streamlit and Next.js - Part 1 Data Producer
date: 2025-02-18
draft: false
featured: true
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
description: A Python generator loads theLook eCommerce data into PostgreSQL, and a FastAPI WebSocket server queries it on a timer to serve live dashboards.
---

A data generating app is created with Python, and it ingests the [theLook eCommerce](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce) data continuously into a PostgreSQL database. A WebSocket server, built by [FastAPI](https://fastapi.tiangolo.com/), periodically queries the data to serve its clients. In this series, we develop real-time monitoring dashboard applications, and this post walks through the data generation app and backend API. The monitoring dashboards will be developed using [Streamlit](https://streamlit.io/) and [Next.js](https://nextjs.org/), with [Apache ECharts](https://echarts.apache.org/en/index.html) for visualization. They will be discussed in later posts.

<!--more-->

* [Part 1 Data Producer](#) (this post)
* [Part 2 Streamlit Dashboard](/blog/2025-02-25-realtime-dashboard-2)
* [Part 3 Next.js Dashboard](/blog/2025-03-04-realtime-dashboard-3)

<!--more-->

## Services

![The simulation writes to PostgreSQL, the WebSocket server sends the recent order items on /ws, and a terminal client prints them](part-1.png#center "Architecture")

We have three services, and they are illustrated separately below. The source of this post can be found in the **live-dashboard** folder of the [**benchtop**](https://github.com/jaehyeon-kim/benchtop/tree/main/live-dashboard) GitHub repository. The development environment can be constructed as follows:

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

The data generator creates a dedicated schema named *dashboard* and its tables when it starts.

```python
# live-dashboard/sales/stores/postgres.py
TABLES = ("products", "users", "orders", "order_items")
UPSERT_KEYS = {"orders": ["id"], "order_items": ["id"]}  # rows whose status changes

_DDL = f"""
CREATE SCHEMA IF NOT EXISTS {SCHEMA};
CREATE TABLE IF NOT EXISTS {SCHEMA}.products (id BIGINT PRIMARY KEY, name TEXT,
    category TEXT, department TEXT, retail_price FLOAT8, cost FLOAT8);
CREATE TABLE IF NOT EXISTS {SCHEMA}.users (id TEXT PRIMARY KEY, age INT, gender TEXT,
    country TEXT, traffic_source TEXT, created_at TEXT);
CREATE TABLE IF NOT EXISTS {SCHEMA}.orders (id TEXT PRIMARY KEY, user_id TEXT,
    status TEXT, num_of_item INT, created_at TEXT);
CREATE TABLE IF NOT EXISTS {SCHEMA}.order_items (id TEXT PRIMARY KEY, order_id TEXT,
    user_id TEXT, product_id BIGINT, status TEXT, sale_price FLOAT8, created_at TEXT);
CREATE TABLE IF NOT EXISTS {PARAMS_TABLE} (id SERIAL PRIMARY KEY,
    param_path VARCHAR(255) NOT NULL, param_value TEXT NOT NULL,
    is_applied BOOLEAN DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
"""
```

### Data Generator

The data generator is a [dynamic-des](https://github.com/jaehyeon-kim/dynamic-des) simulation of the shop, and it runs in its own terminal. It connects to the PostgreSQL database with the settings in `sales/core/config.py`, and runs until it is stopped (`--minutes` stops it after that many minutes).

```bash
(.venv) $ python -m sales.simulation.run
```

#### Data Generator Source

The *theLook eCommerce* dataset is reduced to four entities, three of which are dynamically generated. Visitors arrive at random, view a few pages, and some buy. A buyer is a new or a returning *user*, and each purchase creates an *order* with one or more *order items*. Each order waits for a warehouse picker, then ships and completes, or is cancelled when no picker comes in time. Every change of status updates the order and its items. dynamic-des's `PostgresEgress` writes each row to its table, and `PostgresIngress` applies parameter changes while the simulation runs.

```python
# live-dashboard/sales/simulation/run.py
"""The shop as a discrete-event model in dynamic-des, run in real time into PostgreSQL.

Visitors arrive and browse, and some buy. Each order waits for a picker, ships and
completes, or is cancelled when no picker comes in time. Every rate, time and chance is
a registry parameter, so `sales.simulation.control` can change it while the model runs.
"""

import argparse
import asyncio
import logging
from datetime import UTC, datetime, timedelta

from dynamic_des import PostgresEgress, PostgresIngress, SimulationContext

from sales.core.config import (
    ARRIVALS,
    CHANCES,
    DSN,
    MAX_PICKERS,
    PARAMS_TABLE,
    PICKERS,
    SCHEMA,
    SERVICES,
    SIM_ID,
)
from sales.core.models import User
from sales.simulation.catalogue import products
from sales.simulation.shop import basket, new_user, with_status
from sales.stores import postgres


def _wait(app: SimulationContext, service: str):
    """Returns a timeout drawn from a service's live distribution."""
    config = app.env.registry.get_config(f"{SIM_ID}.service.{service}")
    return app.env.timeout(app.sampler.sample(config))


def _chance(app: SimulationContext, name: str) -> bool:
    """Returns True with the probability of a chance variable's live value."""
    return (
        app.sampler.rng.random()
        < app.env.registry.get(f"{SIM_ID}.variables.{name}").value
    )


def build(seed: int | None = None, start: datetime | None = None) -> SimulationContext:
    """
    Builds the shop's model: its parameters, its pickers and its processes.

    Args:
        seed (int, optional): The seed for every random choice. None varies them.
        start (datetime, optional): The simulated start time, in UTC. Defaults to now.

    Returns:
        SimulationContext: The model, ready for egress, ingress and `run`.
    """
    start = start or datetime.now(UTC)
    app = SimulationContext(
        SIM_ID,
        factor=1.0,
        random_seed=seed,
        logical_start_time=start.replace(tzinfo=None),
    )
    for name, rate in ARRIVALS.items():
        app.add_arrival(name, dist="exponential", rate=rate)
    for name, (mean, std) in SERVICES.items():
        app.add_service(name, dist="lognormal", mean=mean, std=std)
    app.add_resource("pickers", current_cap=PICKERS, max_cap=MAX_PICKERS)
    for name, chance in CHANCES.items():
        app.add_variable(name, chance)
    catalogue, users = products(), list[User]()

    def now() -> str:
        """Returns the simulated time, in UTC, as ISO 8601 text."""
        return (start + timedelta(seconds=app.env.now)).isoformat()

    def publish(rows) -> None:
        """Writes rows to their tables."""
        for row in rows:
            app.env.publish_event(row.table, row.model_dump())

    @app.arrival_loop("visitor")
    def visitors(ctx):
        """Writes the catalogue, then starts a visit at each visitor arrival."""
        publish(catalogue)
        while True:
            yield ctx.wait_for_arrival("visitor")
            ctx.spawn(visit())

    def visit():
        """One visitor: a few page views, then possibly an order."""
        rng = app.sampler.rng
        user = (
            users[int(rng.integers(len(users)))]
            if users and _chance(app, "returning")
            else None
        )
        for _ in range(int(rng.integers(2, 6))):
            yield _wait(app, "page_view")
        if not _chance(app, "buy"):
            return
        if user is None:
            user = new_user(rng, now())
            users.append(user)
            publish([user])
        order, items = basket(rng, user, catalogue, now())
        publish([order, *items])
        app.spawn(fulfil([order, *items]))

    def fulfil(rows):
        """One order: wait for a picker or give up, then pack, ship and complete."""
        with app.get_resource("pickers").request() as picker:
            waited = yield picker | _wait(app, "patience")
            if picker not in waited:
                publish(with_status(rows, "Cancelled"))
                return
            yield _wait(app, "pick")
        publish(with_status(rows, "Shipped"))
        yield _wait(app, "transit")
        publish(with_status(rows, "Complete"))
        if _chance(app, "return"):
            yield _wait(app, "return_after")
            publish(with_status(rows, "Returned"))

    return app


def run(minutes: float | None = None, seed: int | None = None) -> None:
    """
    Runs the shop in real time, writing every row to PostgreSQL.

    Args:
        minutes (float, optional): How long to run. None runs until interrupted.
        seed (int, optional): The seed for every random choice.
    """
    asyncio.run(postgres.create_tables())
    app = build(seed)
    app.add_ingress(PostgresIngress(DSN, table_name=PARAMS_TABLE))
    app.with_batching(batch_size=4, flush_interval=1.0)  # a few rows arrive a second
    for table in postgres.TABLES:
        # Bare table names, found through the connection's search path.
        egress = PostgresEgress(
            DSN,
            table_name=table,
            upsert_keys=postgres.UPSERT_KEYS.get(table),
            server_settings={"search_path": SCHEMA},
        )
        app.add_egress(egress, when=lambda r, t=table: r.get("key") == t)
    app.run(until=minutes * 60 if minutes else None)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    parser = argparse.ArgumentParser(description="Runs the shop in real time.")
    parser.add_argument(
        "--minutes", type=float, help="how long to run (default: forever)"
    )
    parser.add_argument("--seed", type=int, help="seed for the random choices")
    args = parser.parse_args()
    run(args.minutes, args.seed)
```

In the following example, the simulation starts and connects to each table.

```bash
(.venv) $ python -m sales.simulation.run
2026-09-30 22:44:19,294 dynamic_des.core.context Building SimulationContext for 'sales'...
2026-09-30 22:44:19,295 dynamic_des.core.context Simulation engine started.
2026-09-30 22:44:19,627 dynamic_des.connectors.egress.postgres PostgresEgress connected to order_items
2026-09-30 22:44:19,627 dynamic_des.connectors.egress.postgres PostgresEgress connected to users
2026-09-30 22:44:19,627 dynamic_des.connectors.egress.postgres PostgresEgress connected to orders
2026-09-30 22:44:19,627 dynamic_des.connectors.egress.postgres PostgresEgress connected to products
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

* [Guide to Building Integrated Web Applications with FastAPI and NiceGUI](/blog/2025-11-19-fastapi-nicegui-template) - serves a FastAPI backend and the web UI from one Python process, compared with React and with Streamlit
