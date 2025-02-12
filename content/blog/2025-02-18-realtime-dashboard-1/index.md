---
title: Realtime Dashboard with Streamlit and Next.js - Part 1 Data Producer
date: 2025-02-18
draft: true
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
categories:
  - Data Product
tags: 
  - Python
  - FastAPI
  - Websocket
  - PostgreSQL
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description:
---

to be updated!!!!!!!!

<!--more-->

* [Part 1 Data Producer](#) (this post)
* Part 2 Streamlit Frontend
* Part 3 Next.js Frontend

<!--more-->

## Docker Compose Services

We have three docker-compose services, and each service is illustrated separately. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/product-demos).

### PostgreSQL

A PostgreSQL database server is configured so that it enables logical replication (`wal_level=logical`) at startup. It is necessary because we will be using the standard logical decoding output plug-in in PostgreSQL 10+ - see [this page](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-overview) for details.

```yaml
# producer/docker-compose.yml
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
-- producer/config/postgres/bootstrap.sql
CREATE SCHEMA ecommerce;
GRANT ALL ON SCHEMA ecommerce TO develop;

-- change search_path on a connection-level
SET search_path TO ecommerce;

-- change search_path on a database-level
ALTER database "develop" SET search_path TO ecommerce;
```

### Data Generator

```yaml
# producer/docker-compose.yml
services:
...
  datagen:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: datagen
    environment:
      DB_USER: develop
      DB_PASS: password
      DB_HOST: postgres
      DB_NAME: develop
    command:
      - python
      - generator.py
      - --wait_for
      - "0.5"
      - --max_iter
      - "-1"
    volumes:
      - .:/home/app
    depends_on:
      postgres:
        condition: service_healthy
...
```

#### Data Generator Source

The *theLook eCommerce* dataset has seven entities and five of them are generated dynamically. In each iteration, a *user* record is created, and it has zero or more orders. An *order* record creates zero or more order items in turn. Finally, an *order item* record creates zero or more *event* and *inventory item* objects. Once all records are generated, they are ingested into the relevant tables using pandas' `to_sql` method.

```python
# producer/generator.py
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

### Backend API

```yaml
# producer/docker-compose.yml
services:
...
  producer:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: producer
    ports:
      - "8000:8000"
    environment:
      DB_USER: develop
      DB_PASS: password
      DB_HOST: postgres
      DB_NAME: develop
      LOOKBACK_MINUTES: "5"
      REFRESH_SECONDS: "5"
    command:
      - uvicorn
      - api:app
      - --host
      - "0.0.0.0"
      - --port
      - "8000"
    volumes:
      - .:/home/app
    depends_on:
      postgres:
        condition: service_healthy
...
```

#### Backend API Source

```python
# producer/api.py
import os
import logging
import asyncio

import sqlalchemy
from sqlalchemy import Engine, Connection
import pandas as pd
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

logging.getLogger().setLevel(logging.INFO)

try:
    LOOKBACK_MINUTES = int(os.getenv("LOOKBACK_MINUTES", "5"))
    REFRESH_SECONDS = int(os.getenv("REFRESH_SECONDS", "5"))
except ValueError:
    LOOKBACK_MINUTES = 5
    REFRESH_SECONDS = 5


def create_engine(
    user: str = os.getenv("DB_USER", "develop"),
    password: str = os.getenv("DB_PASS", "password"),
    host: str = os.getenv("DB_HOST", "localhost"),
    db_name: str = os.getenv("DB_NAME", "develop"),
    echo: bool = True,
) -> Engine:
    return sqlalchemy.create_engine(
        f"postgresql+psycopg2://{user}:{password}@{host}/{db_name}", echo=echo
    )


def read_from_db(conn: Connection, minutes: int = 0):
    sql = """
    SELECT
        u.id AS user_id
        , u.age
        , u.gender
        , u.country
        , u.traffic_source
        , o.order_id
        , o.id AS item_id
        , p.category
        , p.cost
        , o.status AS item_status
        , o.sale_price
        , o.created_at
    FROM users AS u
    JOIN order_items AS o ON u.id = o.user_id
    JOIN products AS p ON p.id = o.product_id
    """
    if minutes > 0:
        sql = f"{sql} WHERE o.created_at >= current_timestamp - interval '{minutes} minute'"
    else:
        sql = f"{sql} LIMIT 1"
    return pd.read_sql(sql=sql, con=conn)


app = FastAPI()


class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def send_records(self, df: pd.DataFrame, websocket: WebSocket):
        records = df.to_json(orient="records")
        await websocket.send_json(records)


manager = ConnectionManager()


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    engine = create_engine()
    conn = engine.connect()
    try:
        while True:
            df = read_from_db(conn=conn, minutes=LOOKBACK_MINUTES)
            logging.info(f"{df.shape[0]} records are fetched...")
            await manager.send_records(df, websocket)
            await asyncio.sleep(REFRESH_SECONDS)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    finally:
        conn.close()
        engine.dispose()
```

## Start Services
