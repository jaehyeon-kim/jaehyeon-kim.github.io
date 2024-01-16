---
title: Data Build Tool (dbt) Pizza Shop Demo - Part 2 ETL on PostgreSQL via Airflow
date: 2024-01-25
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - DBT Pizza Shop Demo
categories:
  - Data Engineering
tags: 
  - Data Build Tool (DBT)
  - PostgreSQL
  - Docker
  - Docker Compose
  - Apache Airflow
  - Python
authors:
  - JaehyeonKim
images: []
description: In this series of posts, we discuss data warehouse/lakehouse examples using data build tool (dbt) including ETL orchestration with Apache Airflow. In Part 1, we developed a dbt project on PostgreSQL with fictional pizza shop data. Two dimension tables that keep product and user records are created as Type 2 slowly changing dimension (SCD Type 2) tables, and one transactional fact table are built to keep pizza orders. In this post, we discuss how to set up an ETL process on the project using Airflow.
---

In this series of posts, we discuss data warehouse/lakehouse examples using [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) including ETL orchestration with Apache Airflow. In Part 1, we developed a *dbt* project on PostgreSQL with fictional pizza shop data. Two dimension tables that keep product and user records are created as [Type 2 slowly changing dimension (SCD Type 2)](https://en.wikipedia.org/wiki/Slowly_changing_dimension) tables, and one transactional fact table are built to keep pizza orders. In this post, we discuss how to set up an ETL process on the project using Airflow.

* [Part 1 Modelling on PostgreSQL](/blog/2024-01-18-dbt-pizza-shop-1)
* [Part 2 ETL on PostgreSQL via Airflow](#) (this post)
* Part 3 Modelling on Amazon Athena
* Part 4 ETL on Amazon Athena via Airflow
* Part 5 Modelling on Apache Spark
* Part 6 ETL on Apache Spark via Airflow

## Infrastructure

Apache Airflow and PostgreSQL are used in this post, and they are deployed locally using Docker Compose. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/general-demos/tree/master/dbt-postgres-demo) of this post.

### Database

As [Part 1](/blog/2024-01-18-dbt-pizza-shop-1), a PostgreSQL server is deployed using Docker Compose. See the previous post for details about (1) how fictional pizza shop data sets are made available, and (2) how the database is bootstrapped using a script (*bootstrap.sql*), which creates necessary schemas/tables as well as loads initial records to the tables. Note that the database cluster is shared with Airflow and thus a database and role named *airflow* are created for it - see below for details.

```yaml
# compose-orchestration.yml
...
services:
  postgres:
    image: postgres:13
    container_name: postgres
    ports:
      - 5432:5432
    networks:
      - appnet
    environment:
      POSTGRES_USER: devuser
      POSTGRES_PASSWORD: password
      POSTGRES_DB: devdb
      TZ: Australia/Sydney
    volumes:
      - ./initdb/scripts:/docker-entrypoint-initdb.d
      - ./initdb/data:/tmp
      - postgres_data:/var/lib/postgresql/data
...
```

```sql
-- initdb/scripts/bootstrap.sql

...

CREATE DATABASE airflow;
CREATE ROLE airflow 
LOGIN 
PASSWORD 'airflow';
GRANT ALL ON DATABASE airflow TO airflow;
```

### Airflow

For development, Airflow can be simplified by using the Local Executor where both scheduling and task execution are handled by the airflow scheduler service - i.e. *AIRFLOW__CORE__EXECUTOR: LocalExecutor*. Also, it is configured to be able to run the *dbt* project (see [Part 1](/blog/2024-01-18-dbt-pizza-shop-1) for details) within the scheduler service by 

- installing the *dbt-postgre* package, and
- volume-mapping folders that keep the *dbt* project and *dbt* project profile

```yaml
# compose-orchestration.yml
version: "3"
x-airflow-common: &airflow-common
  image: ${AIRFLOW_IMAGE_NAME:-apache/airflow:2.8.0}
  networks:
    - appnet
  environment: &airflow-common-env
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    # For backward compatibility, with Airflow <2.3
    AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    AIRFLOW__CORE__FERNET_KEY: ""
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: "true"
    AIRFLOW__CORE__LOAD_EXAMPLES: "false"
    AIRFLOW__API__AUTH_BACKENDS: "airflow.api.auth.backend.basic_auth"
    # install dbt-postgres==1.7.4
    _PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:- dbt-postgres==1.7.4 pendulum}
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/plugins:/opt/airflow/plugins
    - ./airflow/logs:/opt/airflow/logs
    - ./pizza_shop:/tmp/pizza_shop                     # dbt project
    - ./airflow/dbt-profiles:/opt/airflow/dbt-profiles # dbt profiles
  user: "${AIRFLOW_UID:-50000}:0"
  depends_on: &airflow-common-depends-on
    postgres:
      condition: service_healthy

services:
  postgres:
    image: postgres:13
    container_name: postgres
    ports:
      - 5432:5432
    networks:
      - appnet
    environment:
      POSTGRES_USER: devuser
      POSTGRES_PASSWORD: password
      POSTGRES_DB: devdb
      TZ: Australia/Sydney
    volumes:
      - ./initdb/scripts:/docker-entrypoint-initdb.d
      - ./initdb/data:/tmp
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 5s
      retries: 5

  airflow-webserver:
    <<: *airflow-common
    container_name: webserver
    command: webserver
    ports:
      - 8080:8080
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    container_name: scheduler
    environment:
      <<: *airflow-common-env
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-init:
    <<: *airflow-common
    container_name: init
    entrypoint: /bin/bash
    command:
      - -c
      - |
        mkdir -p /sources/logs /sources/dags /sources/plugins
        chown -R "${AIRFLOW_UID}:0" /sources/{logs,dags,plugins}
        exec /entrypoint airflow version
    environment:
      <<: *airflow-common-env
      _AIRFLOW_DB_UPGRADE: "true"
      _AIRFLOW_WWW_USER_CREATE: "true"
      _AIRFLOW_WWW_USER_USERNAME: ${_AIRFLOW_WWW_USER_USERNAME:-airflow}
      _AIRFLOW_WWW_USER_PASSWORD: ${_AIRFLOW_WWW_USER_PASSWORD:-airflow}
      _PIP_ADDITIONAL_REQUIREMENTS: ""
    user: "0:0"
    volumes:
      - .:/sources

volumes:
  airflow_log_volume:
    driver: local
    name: airflow_log_volume
  postgres_data:
    driver: local
    name: postgres_data

networks:
  appnet:
    name: app-network
```

The Airflow and PostgreSQL services can be deployed as shown below. Note that it is recommended to specify the host user's ID as the *AIRFLOW_UID* value. Otherwise, Airflow can fail to launch due to insufficient permission to write logs.

```bash
$ AIRFLOW_UID=1000 docker-compose -f compose-orchestration.yml up -d
```

Once started, we can visit the Airflow web server on *http://localhost:8080*.

![](airflow-home.png#center)

## ETL Job

A simple ETL job (*demo_etl*) is created, which updates source records (*update_records*) followed by running and testing the *dbt* project. Note that the *dbt* project and profile are accessible as they are volume-mapped to the Airflow scheduler container.

```python
# airflow/dags/operators.py
import pendulum
from airflow.models.dag import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

import update_records

with DAG(
    dag_id="demo_etl",
    schedule=None,
    start_date=pendulum.datetime(2024, 1, 1, tz="Australia/Sydney"),
    catchup=False,
    tags=["pizza"],
):
    task_records_update = PythonOperator(
        task_id="update_records", python_callable=update_records.main
    )

    task_dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command="dbt run --profiles-dir /opt/airflow/dbt-profiles --project-dir /tmp/pizza_shop",
    )

    task_dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command="dbt test --profiles-dir /opt/airflow/dbt-profiles --project-dir /tmp/pizza_shop",
    )

    task_records_update >> task_dbt_run >> task_dbt_test
```

### Update Records

As *dbt* takes care of data transformation only, we should create a task that updates source records. As shown below, the task updates as many as a half of records of the dimension tables (*products* and *users*) and appends 5,000 *order* records in a single run.

```python
# airflow/dags/update_records.py
import os
import json
import dataclasses
import random
import string

import psycopg2
import psycopg2.extras


class DbHelper:
    def __init__(self) -> None:
        self.conn = self.connect_db()

    def connect_db(self):
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST", "postgres"),
            database=os.getenv("DB_NAME", "devdb"),
            user=os.getenv("DB_USER", "devuser"),
            password=os.getenv("DB_PASSWORD", "password"),
        )
        conn.autocommit = False
        return conn

    def get_connection(self):
        if (self.conn is None) or (self.conn.closed):
            self.conn = self.connect_db()

    def fetch_records(self, stmt: str):
        self.get_connection()
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(stmt)
            return cur.fetchall()

    def update_records(self, stmt: str, records: list, to_fetch: bool = True):
        self.get_connection()
        with self.conn.cursor() as cur:
            values = psycopg2.extras.execute_values(cur, stmt, records, fetch=to_fetch)
            self.conn.commit()
            if to_fetch:
                return values

    def commit(self):
        if not self.connection.closed:
            self.connection.commit()

    def close(self):
        if self.connection and (not self.connection.closed):
            self.connection.close()


@dataclasses.dataclass
class Product:
    id: int
    name: int
    description: int
    price: float
    category: str
    image: str

    def __hash__(self) -> int:
        return self.id

    @classmethod
    def from_json(cls, r: dict):
        return cls(**r)

    @staticmethod
    def load(db: DbHelper):
        stmt = """
        WITH windowed AS (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
            FROM staging.products
        )
        SELECT id, name, description, price, category, image
        FROM windowed
        WHERE rn = 1;
        """
        return [Product.from_json(r) for r in db.fetch_records(stmt)]

    @staticmethod
    def update(db: DbHelper, percent: float = 0.5):
        stmt = "INSERT INTO staging.products(id, name, description, price, category, image) VALUES %s RETURNING id, price"
        products = Product.load(db)
        records = set(random.choices(products, k=int(len(products) * percent)))
        for r in records:
            r.price = r.price + 10
        values = db.update_records(
            stmt, [list(dataclasses.asdict(r).values()) for r in records], True
        )
        return values


@dataclasses.dataclass
class User:
    id: int
    first_name: str
    last_name: str
    email: str
    residence: str
    lat: float
    lon: float

    def __hash__(self) -> int:
        return self.id

    @classmethod
    def from_json(cls, r: dict):
        return cls(**r)

    @staticmethod
    def load(db: DbHelper):
        stmt = """
        WITH windowed AS (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
            FROM staging.users
        )
        SELECT id, first_name, last_name, email, residence, lat, lon
        FROM windowed
        WHERE rn = 1;
        """
        return [User.from_json(r) for r in db.fetch_records(stmt)]

    @staticmethod
    def update(db: DbHelper, percent: float = 0.5):
        stmt = "INSERT INTO staging.users(id, first_name, last_name, email, residence, lat, lon) VALUES %s RETURNING id, email"
        users = User.load(db)
        records = set(random.choices(users, k=int(len(users) * percent)))
        for r in records:
            r.email = f"{''.join(random.choices(string.ascii_letters, k=5)).lower()}@email.com"
        values = db.update_records(
            stmt, [list(dataclasses.asdict(r).values()) for r in records], True
        )
        return values


@dataclasses.dataclass
class Order:
    user_id: int
    items: str

    @classmethod
    def create(self):
        order_items = [
            {"product_id": id, "quantity": random.randint(1, 5)}
            for id in set(random.choices(range(1, 82), k=random.randint(1, 10)))
        ]
        return Order(
            user_id=random.randint(1, 10000),
            items=json.dumps([item for item in order_items]),
        )

    @staticmethod
    def append(db: DbHelper, num_orders: int = 5000):
        stmt = "INSERT INTO staging.orders(user_id, items) VALUES %s RETURNING id"
        records = [Order.create() for _ in range(num_orders)]
        values = db.update_records(
            stmt, [list(dataclasses.asdict(r).values()) for r in records], True
        )
        return values


def main():
    db = DbHelper()
    ## update product and user records
    print(f"{len(Product.update(db))} product records updated")
    print(f"{len(User.update(db))} user records updated")
    ## created order records
    print(f"{len(Order.append(db))} order records created")
```

The details of the ETL job can be found on the Airflow web server as shown below.

![](airflow-dag.png#center)

## Run ETL

Below shows an example product dimension records after the ETL job is completed twice. The product is updated in the second job and a new surrogate key is assigned as well as the *value_from* and *valid_to* column values are updated accordingly.

```sql
SELECT product_key, price, created_at, valid_from, valid_to 
FROM dev.dim_products
WHERE product_id = 61

product_key                     |price|created_at         |valid_from         |valid_to           |
--------------------------------+-----+-------------------+-------------------+-------------------+
6a326183ce19f0db7f4af2ab779cc2dd|185.0|2024-01-16 18:18:12|2024-01-16 18:18:12|2024-01-16 18:22:19|
d2e27002c0f474d507c60772161673aa|195.0|2024-01-16 18:22:19|2024-01-16 18:22:19|2199-12-31 00:00:00|
```

When I query the fact table for orders with the same product ID, I can check correct product key values are mapped - note *value_to* is not inclusive.

```sql
SELECT o.order_key, o.product_key, o.product_id, p.price, o.created_at
FROM dev.fct_orders o
JOIN dev.dim_products p ON o.product_key = p.product_key 
WHERE o.product_id = 61 AND order_id IN (5938, 28146)

order_key                       |product_key                     |product_id|price|created_at         |
--------------------------------+--------------------------------+----------+-----+-------------------+
cb650e3bb22e3be1d112d59a44482560|6a326183ce19f0db7f4af2ab779cc2dd|        61|185.0|2024-01-16 18:18:12|
470c2fa24f97a2a8dfac2510cc49f942|d2e27002c0f474d507c60772161673aa|        61|195.0|2024-01-16 18:22:19|
```

## Summary

In this series of posts, we discuss data warehouse/lakehouse examples using data build tool (dbt) including ETL orchestration with Apache Airflow. In this post, we discussed how to set up an ETL process on the *dbt* project from Part 1 using Airflow. A demo ETL job was created that updates records followed by running and testing the *dbt* project. Finally, the result of ETL job was validated by checking sample records.
