---
title: Data Build Tool (dbt) Pizza Shop Demo - Part 6 ETL on Amazon Athena via Airflow
date: 2024-03-14
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
  - AWS
  - Amazon Athena
  - Apache Iceberg
  - Docker
  - Docker Compose
  - Apache Airflow
  - Python
authors:
  - JaehyeonKim
images: []
description: In Part 3, we developed a dbt project that targets Google BigQuery with fictional pizza shop data. Two dimension tables that keep product and user records are created as Type 2 slowly changing dimension (SCD Type 2) tables, and one transactional fact table is built to keep pizza orders. The fact table is denormalized using nested and repeated fields for improving query performance. In this post, we discuss how to set up an ETL process on the project using Apache Airflow.
---

In [Part 3](/blog/2024-02-08-dbt-pizza-shop-3), we developed a [dbt](https://docs.getdbt.com/docs/introduction) project that targets Google BigQuery with fictional pizza shop data. Two dimension tables that keep product and user records are created as [Type 2 slowly changing dimension (SCD Type 2)](https://en.wikipedia.org/wiki/Slowly_changing_dimension) tables, and one transactional fact table is built to keep pizza orders. The fact table is denormalized using [nested and repeated fields](https://cloud.google.com/bigquery/docs/best-practices-performance-nested) for improving query performance. In this post, we discuss how to set up an ETL process on the project using Apache Airflow.

* [Part 1 Modelling on PostgreSQL](/blog/2024-01-18-dbt-pizza-shop-1)
* [Part 2 ETL on PostgreSQL via Airflow](/blog/2024-01-25-dbt-pizza-shop-2)
* [Part 3 Modelling on BigQuery](/blog/2024-02-08-dbt-pizza-shop-3)
* [Part 4 ETL on BigQuery via Airflow](/blog/2024-02-22-dbt-pizza-shop-4)
* [Part 5 Modelling on Amazon Athena](/blog/2024-03-07-dbt-pizza-shop-5)
* Part 6 ETL on Amazon Athena via Airflow

## Infrastructure

Apache Airflow and Google BigQuery are used in this post, and the former is deployed locally using Docker Compose. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/general-demos/tree/master/dbt-bigquery-demo) of this post.

### Airflow

Airflow is simplified by using the [Local Executor](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/local.html) where both scheduling and task execution are handled by the airflow scheduler service - i.e. *AIRFLOW__CORE__EXECUTOR: LocalExecutor*. Also, it is configured to be able to run the *dbt* project (see [Part 3](/blog/2024-02-08-dbt-pizza-shop-3) for details) within the scheduler service by 

- installing the *dbt-bigquery* package as an additional pip package,
- volume-mapping folders that keep the *dbt* project and *dbt* project profile, and
- specifying environment variables for the *dbt* project profile (*GCP_PROJECT* and *SA_KEYFILE*)

```yaml
# docker-compose.yml
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
    _PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:- dbt-athena-community==1.7.1 awswrangler pendulum}
    AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
    AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
    TZ: Australia/Sydney
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/plugins:/opt/airflow/plugins
    - ./airflow/logs:/opt/airflow/logs
    - ./pizza_shop:/tmp/pizza_shop
    - ./airflow/dbt-profiles:/opt/airflow/dbt-profiles
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
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
      TZ: Australia/Sydney
    volumes:
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
        mkdir -p /sources/logs /sources/dags /sources/plugins /sources/scheduler
        chown -R "${AIRFLOW_UID}:0" /sources/{logs,dags,plugins,scheduler}
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
      - ./airflow:/sources

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

Before we deploy the Airflow services, we need to create the BigQuery dataset and staging tables, followed by inserting initial records - see [Part 3](/blog/2024-02-08-dbt-pizza-shop-3) for details about the prerequsite steps. Then the services can be started using the *docker-compose up* command. Note that it is recommended to specify the host user's ID as the *AIRFLOW_UID* value. Otherwise, Airflow can fail to launch due to insufficient permission to write logs. Note also that the relevant GCP project ID should be included as it is read in the compose file.

```bash
## prerequisite
## create staging tables and insert records - python setup/insert_records.py 

## start airflow services
$ AIRFLOW_UID=$(id -u) docker-compose up -d
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
import datetime
import dataclasses
import json
import random
import string

import boto3
import pandas as pd
import awswrangler as wr


class QueryHelper:
    def __init__(self, db_name: str, bucket_name: str):
        self.db_name = db_name
        self.bucket_name = bucket_name

    def read_sql_query(self, stmt: str):
        return wr.athena.read_sql_query(
            stmt,
            database=self.db_name,
            boto3_session=boto3.Session(
                region_name=os.getenv("AWS_REGION", "ap-southeast-2")
            ),
        )

    def load_source(self, df: pd.DataFrame, obj_name: str):
        if obj_name not in ["users", "products", "orders"]:
            raise ValueError("object name should be one of users, products, orders")
        wr.s3.to_parquet(
            df=df,
            path=f"s3://{self.bucket_name}/staging/{obj_name}/",
            dataset=True,
            database=self.db_name,
            table=f"staging_{obj_name}",
            boto3_session=boto3.Session(
                region_name=os.getenv("AWS_REGION", "ap-southeast-2")
            ),
        )


def update_products(
    query_helper: QueryHelper,
    percent: float = 0.5,
    created_at: datetime.datetime = datetime.datetime.now(),
):
    stmt = """
    WITH windowed AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
        FROM pizza_shop.staging_products
    )
    SELECT id, name, description, price, category, image
    FROM windowed
    WHERE rn = 1;
    """
    products = query_helper.read_sql_query(stmt)
    products.insert(products.shape[1], "created_at", created_at)
    records = products.sample(n=int(products.shape[0] * percent))
    records["price"] = records["price"] + 10
    query_helper.load_source(records, "products")
    return records


def update_users(
    query_helper: QueryHelper,
    percent: float = 0.5,
    created_at: datetime.datetime = datetime.datetime.now(),
):
    stmt = """
    WITH windowed AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
        FROM pizza_shop.staging_users
    )
    SELECT id, first_name, last_name, email, residence, lat, lon
    FROM windowed
    WHERE rn = 1;
    """
    users = query_helper.read_sql_query(stmt)
    users.insert(users.shape[1], "created_at", created_at)
    records = users.sample(n=int(users.shape[0] * percent))
    records[
        "email"
    ] = f"{''.join(random.choices(string.ascii_letters, k=5)).lower()}@email.com"
    query_helper.load_source(records, "users")
    return records


@dataclasses.dataclass
class Order:
    id: int
    user_id: int
    items: str
    created_at: datetime.datetime

    def to_json(self):
        return dataclasses.asdict(self)

    @classmethod
    def create(cls, id: int, created_at: datetime.datetime):
        order_items = [
            {"product_id": id, "quantity": random.randint(1, 5)}
            for id in set(random.choices(range(1, 82), k=random.randint(1, 10)))
        ]
        return cls(
            id=id,
            user_id=random.randint(1, 10000),
            items=json.dumps([item for item in order_items]),
            created_at=created_at,
        )

    @staticmethod
    def insert(
        query_helper: QueryHelper,
        max_id: int,
        num_orders: int = 5000,
        created_at: datetime.datetime = datetime.datetime.now(),
    ):
        records = []
        for _ in range(num_orders):
            records.append(Order.create(max_id + 1, created_at).to_json())
            max_id += 1
        query_helper.load_source(pd.DataFrame.from_records(records), "orders")
        return records

    @staticmethod
    def get_max_id(query_helper: QueryHelper):
        stmt = "SELECT max(id) AS mx FROM pizza_shop.staging_orders"
        df = query_helper.read_sql_query(stmt)
        return next(iter(df.mx))


def main():
    query_helper = QueryHelper(db_name="pizza_shop", bucket_name="dbt-pizza-shop-demo")
    created_at = datetime.datetime.now()
    # update product and user records
    updated_products = update_products(query_helper, created_at=created_at)
    print(f"{len(updated_products)} product records updated")
    updated_users = update_users(query_helper, created_at=created_at)
    print(f"{len(updated_users)} user records updated")
    # create order records
    max_order_id = Order.get_max_id(query_helper)
    new_orders = Order.insert(query_helper, max_order_id, created_at=created_at)
    print(f"{len(new_orders)} order records created")
```

The details of the ETL job can be found on the Airflow web server as shown below.

![](airflow-dag.png#center)

## Run ETL

Below shows example product dimension records after the ETL job is completed. It is shown that the product 1 is updated, and a new surrogate key is assigned to the new record as well as the *valid_from* and *valid_to* column values are updated to it.

```sql
SELECT product_key, product_id AS id, price, valid_from, valid_to 
FROM pizza_shop.dim_products
WHERE product_id IN (1, 2)
ORDER BY product_id, valid_from;

# product_key                        id  price  valid_from                  valid_to
1 b8c187845db8b7e55626659cfbb8aea1    1  335.0  2024-03-01 10:16:36.481000  2199-12-31 00:00:00.000000
2 * 8311b52111a924582c0fe5cb566cfa9a  2   60.0  2024-03-01 10:16:36.481000  2024-03-01 10:16:50.932000
3 * 0f4df52917ddff1bcf618b798c8aff43  2   70.0  2024-03-01 10:16:50.932000  2199-12-31 00:00:00.000000
```

When I query the fact table for orders with the same product ID, I can check correct product key values are mapped - note *value_to* is not inclusive.

```sql
SELECT o.order_id, p.key, p.id, p.price, p.quantity, o.created_at
FROM pizza_shop.fct_orders AS o
CROSS JOIN UNNEST(product) AS t(p)
WHERE o.order_id IN (11146, 20398) AND p.id IN (1, 2)
ORDER BY o.order_id, p.id;

# order_id  key                                 id  price  quantity  created_at
1    11146  b8c187845db8b7e55626659cfbb8aea1     1  335.0         1  2024-03-01 10:16:37.981000
2    11146  * 8311b52111a924582c0fe5cb566cfa9a   2   60.0         2  2024-03-01 10:16:37.981000
3    20398  b8c187845db8b7e55626659cfbb8aea1     1  335.0         5  2024-03-01 10:16:50.932000
4    20398  * 0f4df52917ddff1bcf618b798c8aff43   2   70.0         3  2024-03-01 10:16:50.932000
```

## Summary

In this series of posts, we discuss data warehouse/lakehouse examples using data build tool (dbt) including ETL orchestration with Apache Airflow. In this post, we discussed how to set up an ETL process on the *dbt* project developed in Part 3 using Airflow. A demo ETL job was created that updates records followed by running and testing the *dbt* project. Finally, the result of ETL job was validated by checking sample records.
