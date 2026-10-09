---
title: "odctl 1.0: Kafka, Flink, Spark, Iceberg, Trino and MLflow on Your Laptop with One Command"
date: 2026-10-12
draft: false
featured: true
comment: true
toc: true
categories:
  - Data Engineering
  - Open Source
tags:
  - Open Data Stack
  - odctl
  - Apache Kafka
  - Apache Flink
  - Apache Spark
  - Apache Iceberg
  - MLflow
  - Python
description: |
  odctl is a command-line tool that runs an open-source data platform on your laptop: Kafka, Flink, Spark, Iceberg, ClickHouse, Trino, Airflow, MLflow, Feast and more, started with one command and wired together. Version 1.0 adds a documentation site with a guide for every service.
---

Trying a modern data tool on your own machine is rarely about the tool. Writing Iceberg tables from Flink needs a catalog, the catalog needs a database and object storage, Avro on Kafka needs a schema registry, and every piece needs the right connector jars, ports and network settings. Most of an afternoon goes into making them talk to each other before you write a line of your own code.

`odctl` removes that work. It is a command-line tool that runs a set of open-source data and machine learning services on your laptop with Docker, already connected to each other. You say what you want, for example Kafka and Flink, and it starts them together with everything they depend on. It has now reached 1.0, with a documentation site that has a guide for every service.

<!--more-->

![Installing odctl, previewing what flink-lite starts, starting kafka-lite, listing the containers and stopping them](odctl-1-0.gif)

## What It Runs

odctl groups the services into profiles, and you start the profiles you need. Each profile brings its dependencies with it, so `odctl up flink-lite` also starts the Iceberg REST catalog, with PostgreSQL and SeaweedFS (S3 storage) behind it, ready for Flink to write Iceberg tables.

| Area | Technologies | Profiles |
| --- | --- | --- |
| Messaging | Kafka, Karapace schema registry, Kafka Connect, Kafka UI | `kafka-lite`, `kafka-full` |
| Stream and batch processing | Apache Flink, Apache Spark | `flink-lite`, `flink-full`, `spark-lite`, `spark-full` |
| Analytics | ClickHouse, Trino, Metabase | `ch-lite`, `ch-full`, `trino`, `metabase` |
| Orchestration | Apache Airflow, Temporal | `airflow`, `temporal` |
| MLOps | MLflow, Feast, Evidently | `mlflow`, `feast`, `evidently` |
| Metadata and lineage | OpenMetadata, Marquez | `metadata`, `lineage` |
| Observability | OpenTelemetry Collector, Prometheus, Tempo, Loki, Grafana | `telemetry` |
| Storage and catalog | PostgreSQL 18 with pgvector, pg_textsearch and PostGIS, SeaweedFS, Iceberg REST catalog, Valkey, Apache Fluss | `postgres`, `storage`, `catalog`, `valkey`, `fluss` |

The `-lite` profiles run one broker or worker and fit on a laptop. The `-full` profiles run a small cluster, three Kafka brokers or three Flink TaskManagers, when you want to see how a tool behaves with more than one node.

The services are already wired together. Kafka Connect ships with the Iceberg sink, the Debezium PostgreSQL source and the JDBC and S3 sinks. Flink, Spark and Trino use the same Iceberg catalog, so a table one engine writes is a table the others read. Every service reports metrics, and Grafana has a dashboard for each one.

## What You Can Use It For

* **Learning a tool with a realistic setup.** Write Flink SQL against a real Kafka topic with Avro schemas, or query Iceberg tables from Spark and Trino, without assembling the setup yourself.
* **Building a pipeline end to end.** Change data capture from PostgreSQL with Debezium, Kafka to Iceberg with Flink, then ClickHouse or Trino on top, all on one machine. The [Debezium](/blog/2026-10-01-ecommerce-cdc-debezium-kafka-connect/) and [Flink SQL leaderboard](/blog/2026-10-02-game-leaderboard-flink-sql/) posts are complete examples.
* **Machine learning workflows.** Features in Feast, training and model serving in MLflow, scheduling in Airflow and drift reports in Evidently. The [air quality forecast](/blog/2026-09-28-mlops-with-a-feature-store/) series uses Feast, MLflow and Airflow together. For online learning, the [product recommender](/blog/2026-02-23-productionize-recommender-with-eda/) updates a model in Flink as clicks arrive on Kafka and serves it from Valkey.
* **AI applications.** Hybrid search with pgvector and BM25 in PostgreSQL, vector search in Valkey, and Temporal for workflows that wait for a person to approve an agent's action. The [agentic analytics system](/blog/2026-07-18-agentic-analytics-system/) runs its lakehouse on odctl.
* **Demos and tests that run anywhere.** A project can say which profiles it needs, and anyone can run it from a fresh clone. The [Benchtop](https://github.com/jaehyeon-kim/benchtop) projects and the integration tests of [dynamic-des](https://github.com/jaehyeon-kim/dynamic-des) work this way.

## Getting Started

You need Docker with 8 to 16 GB of memory, and Python 3.10 or later.

```bash
uv tool install odctl              # or: pipx install odctl

odctl list                         # every profile and what it runs
odctl up flink-lite --dry-run      # what would start, in which order
odctl up kafka-lite flink-lite     # start Kafka and Flink with their dependencies
odctl ps --all                     # the running containers and their ports
odctl down --all                   # stop everything
```

Each service is on `127.0.0.1` at a fixed port, for example Kafka UI at `http://127.0.0.1:8086` and the Flink UI at `http://127.0.0.1:8082`. `odctl explain <profile>` prints the addresses for a profile.

To change a memory limit, a port or the Python packages a container installs, run `odctl init`. It copies the configuration into a `.odctl` folder in your project, and odctl uses that copy from then on.

## A Guide for Every Service

The documentation at [jaehyeon.me/odctl](https://jaehyeon.me/odctl/) has 18 guides, from producing to Kafka and running Flink SQL to serving a model from MLflow and cataloguing a database in OpenMetadata. Each guide uses the commands odctl's own tests run before every release, and shows what you should see.

![Kafka UI listing the topics of a running kafka-lite profile](kafka-ui.png#center "Kafka UI from the Kafka guide")

The site also explains how a profile starts and where its data lives, and has a page for each area with every profile's images, ports and memory limits.

## New in 1.0

Since the [first post](/blog/2026-07-16-odctl-open-data-stack/) in July, odctl has gained Feast, Evidently and Temporal, MLflow model serving, a dashboard for every service, and a PostgreSQL with keyword and geospatial search. Version 1.0 adds the documentation site, and fixes the commands, profile names and ports for the whole of 1.x, so a project that depends on `odctl>=1.0,<2` keeps working as odctl is updated.

## Related Posts

* [Data Streaming and Machine Learning Projects That Run on Your Laptop](/blog/2026-09-30-introducing-benchtop/) - the Benchtop projects, each run on odctl from a fresh clone
* [Defining Data-Streaming Simulations in YAML, Without Writing Python](/blog/2026-10-06-simulations-in-yaml-dynamic-des/) - generating the test data these services process
* [Productionizing an Online Product Recommender using Event Driven Architecture](/blog/2026-02-23-productionize-recommender-with-eda/) - a recommender that learns from clicks, with Kafka, Flink and Valkey started by odctl
* [Building an Agentic Analytics System over an Iceberg Lakehouse](/blog/2026-07-18-agentic-analytics-system/) - an agent answering questions over Iceberg tables, with Trino, the catalog, object storage and Valkey started by odctl

## Try It Out

* **Documentation:** [jaehyeon.me/odctl](https://jaehyeon.me/odctl/)
* **GitHub:** [jaehyeon-kim/odctl](https://github.com/jaehyeon-kim/odctl)
* **PyPI:** [pypi.org/project/odctl](https://pypi.org/project/odctl/)

It is licensed under Apache 2.0, and contributions are welcome.
