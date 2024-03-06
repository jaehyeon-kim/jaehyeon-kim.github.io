---
title: Data Build Tool (dbt) Pizza Shop Demo - Part 4 ETL on BigQuery via Airflow
date: 2024-02-22
draft: false
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
  - GCP
  - BigQuery
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
* [Part 4 ETL on BigQuery via Airflow](#) (this post)
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
    _PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:- dbt-bigquery==1.7.4 pendulum}
    SA_KEYFILE: /tmp/sa_key/key.json  # service account key file, required for dbt profile and airflow python operator
    GCP_PROJECT: ${GCP_PROJECT}       # GCP project id, required for dbt profile
    TZ: Australia/Sydney
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/plugins:/opt/airflow/plugins
    - ./airflow/logs:/opt/airflow/logs
    - ./pizza_shop:/tmp/pizza_shop                      # dbt project
    - ./sa_key:/tmp/sa_key                              # service account key file
    - ./airflow/dbt-profiles:/opt/airflow/dbt-profiles  # dbt profiles
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

Before we deploy the Airflow services, we need to create the BigQuery dataset and staging tables, followed by inserting initial records - see [Part 3](/blog/2024-02-08-dbt-pizza-shop-3) for details about the prerequisite steps. Then the services can be started using the *docker-compose up* command. Note that it is recommended to specify the host user's ID as the *AIRFLOW_UID* value. Otherwise, Airflow can fail to launch due to insufficient permission to write logs. Note also that the relevant GCP project ID should be included as it is read in the compose file.

```bash
## prerequisite
## 1. create BigQuery dataset and staging tables
## 2. insert initial records i.e. python setup/insert_records.py 

## start airflow services
$ AIRFLOW_UID=$(id -u) GCP_PROJECT=<gcp-project-id> docker-compose up -d
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

from google.cloud import bigquery
from google.oauth2 import service_account


class QueryHelper:
    def __init__(self, sa_keyfile: str):
        self.sa_keyfile = sa_keyfile
        self.credentials = self.get_credentials()
        self.client = bigquery.Client(
            credentials=self.credentials, project=self.credentials.project_id
        )

    def get_credentials(self):
        # https://cloud.google.com/bigquery/docs/samples/bigquery-client-json-credentials#bigquery_client_json_credentials-python
        return service_account.Credentials.from_service_account_file(
            self.sa_keyfile, scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )

    def get_table(self, dataset_name: str, table_name: str):
        return self.client.get_table(
            f"{self.credentials.project_id}.{dataset_name}.{table_name}"
        )

    def fetch_rows(self, stmt: str):
        query_job = self.client.query(stmt)
        rows = query_job.result()
        return rows

    def insert_rows(self, dataset_name: str, table_name: str, records: list):
        table = self.get_table(dataset_name, table_name)
        errors = self.client.insert_rows_json(table, records)
        if len(errors) > 0:
            print(errors)
            raise RuntimeError("fails to insert records")


@dataclasses.dataclass
class Product:
    id: int
    name: int
    description: int
    price: float
    category: str
    image: str
    created_at: str = datetime.datetime.now().isoformat(timespec="seconds")

    def __hash__(self) -> int:
        return self.id

    def to_json(self):
        return dataclasses.asdict(self)

    @classmethod
    def from_row(cls, row: bigquery.Row):
        return cls(**dict(row.items()))

    @staticmethod
    def fetch(query_helper: QueryHelper):
        stmt = """
        WITH windowed AS (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
            FROM `pizza_shop.staging_products`
        )
        SELECT id, name, description, price, category, image
        FROM windowed
        WHERE rn = 1;
        """
        return [Product.from_row(row) for row in query_helper.fetch_rows(stmt)]

    @staticmethod
    def insert(query_helper: QueryHelper, percent: float = 0.5):
        products = Product.fetch(query_helper)
        records = set(random.choices(products, k=int(len(products) * percent)))
        for r in records:
            r.price = r.price + 10
        query_helper.insert_rows(
            "pizza_shop",
            "staging_products",
            [r.to_json() for r in records],
        )
        return records


@dataclasses.dataclass
class User:
    id: int
    first_name: str
    last_name: str
    email: str
    residence: str
    lat: float
    lon: float
    created_at: str = datetime.datetime.now().isoformat(timespec="seconds")

    def __hash__(self) -> int:
        return self.id

    def to_json(self):
        return {
            k: v if k not in ["lat", "lon"] else str(v)
            for k, v in dataclasses.asdict(self).items()
        }

    @classmethod
    def from_row(cls, row: bigquery.Row):
        return cls(**dict(row.items()))

    @staticmethod
    def fetch(query_helper: QueryHelper):
        stmt = """
        WITH windowed AS (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
            FROM `pizza_shop.staging_users`
        )
        SELECT id, first_name, last_name, email, residence, lat, lon
        FROM windowed
        WHERE rn = 1;
        """
        return [User.from_row(row) for row in query_helper.fetch_rows(stmt)]

    @staticmethod
    def insert(query_helper: QueryHelper, percent: float = 0.5):
        users = User.fetch(query_helper)
        records = set(random.choices(users, k=int(len(users) * percent)))
        for r in records:
            r.email = f"{''.join(random.choices(string.ascii_letters, k=5)).lower()}@email.com"
        query_helper.insert_rows(
            "pizza_shop",
            "staging_users",
            [r.to_json() for r in records],
        )
        return records


@dataclasses.dataclass
class Order:
    id: int
    user_id: int
    items: str
    created_at: str = datetime.datetime.now().isoformat(timespec="seconds")

    def to_json(self):
        return dataclasses.asdict(self)

    @classmethod
    def create(cls, id: int):
        order_items = [
            {"product_id": id, "quantity": random.randint(1, 5)}
            for id in set(random.choices(range(1, 82), k=random.randint(1, 10)))
        ]
        return cls(
            id=id,
            user_id=random.randint(1, 10000),
            items=json.dumps([item for item in order_items]),
        )

    @staticmethod
    def insert(query_helper: QueryHelper, max_id: int, num_orders: int = 5000):
        records = []
        for _ in range(num_orders):
            records.append(Order.create(max_id + 1))
            max_id += 1
        query_helper.insert_rows(
            "pizza_shop",
            "staging_orders",
            [r.to_json() for r in records],
        )
        return records

    @staticmethod
    def get_max_id(query_helper: QueryHelper):
        stmt = "SELECT max(id) AS max FROM `pizza_shop.staging_orders`"
        return next(iter(query_helper.fetch_rows(stmt))).max


def main():
    query_helper = QueryHelper(os.environ["SA_KEYFILE"])
    ## update product and user records
    updated_products = Product.insert(query_helper)
    print(f"{len(updated_products)} product records updated")
    updated_users = User.insert(query_helper)
    print(f"{len(updated_users)} user records updated")
    ## create order records
    max_order_id = Order.get_max_id(query_helper)
    new_orders = Order.insert(query_helper, max_order_id)
    print(f"{len(new_orders)} order records created")
```

The details of the ETL job can be found on the Airflow web server as shown below.

![](airflow-dag.png#center)

## Run ETL

Below shows example product dimension records after the ETL job is completed. It is shown that the product 1 is updated, and a new surrogate key is assigned to the new record as well as the *valid_from* and *valid_to* column values are updated accordingly.

```sql
SELECT product_key, product_id AS id, price, valid_from, valid_to 
FROM `pizza_shop.dim_products`
WHERE product_id IN (1, 2)

product_key                         id price valid_from          valid_to
8dd51b3981692c787baa9d4335f15345     2  60.0 2024-02-16T22:07:19 2199-12-31T00:00:00
* a8c5f8c082bcf52a164f2eccf2b493f6   1 335.0 2024-02-16T22:07:19 2024-02-16T22:09:37
* c995d7e1ec035da116c0f37e6284d1d5   1 345.0 2024-02-16T22:09:37 2199-12-31T00:00:00
```

When we query the fact table for orders with the same product ID, we can check correct product key values are mapped - note *value_to* is not inclusive.

```sql
SELECT o.order_id, p.key, p.id, p.price, p.quantity, o.created_at
FROM `pizza_shop.fct_orders` AS o,
  UNNEST(o.product) AS p
WHERE o.order_id IN (11146, 23296) AND p.id IN (1, 2)
ORDER BY o.order_id, p.id

order_id  key                                id price quantity created_at
   11146  * a8c5f8c082bcf52a164f2eccf2b493f6  1 335.0        1 2024-02-16T22:07:23
   11146  8dd51b3981692c787baa9d4335f15345    2  60.0        2 2024-02-16T22:07:23
   23296  * c995d7e1ec035da116c0f37e6284d1d5  1 345.0        4 2024-02-16T22:09:37
   23296  8dd51b3981692c787baa9d4335f15345    2  60.0        4 2024-02-16T22:09:37
```

## Summary

In this series of posts, we discuss data warehouse/lakehouse examples using data build tool (dbt) including ETL orchestration with Apache Airflow. In this post, we discussed how to set up an ETL process on the *dbt* project developed in Part 3 using Airflow. A demo ETL job was created that updates records followed by running and testing the *dbt* project. Finally, the result of ETL job was validated by checking sample records.
