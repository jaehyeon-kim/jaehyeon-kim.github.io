---
title: "Introducing odctl: One CLI for a Local Open Data Stack"
date: 2026-07-16
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
categories:
  - Data Engineering
  - Open Source
tags:
  - Open Data Stack
  - odctl
  - Kafka
  - Flink
  - Spark
  - Trino
  - Iceberg
  - Docker
  - Python
authors:
  - JaehyeonKim
images: []
description: |
  Provisioning a local data platform usually means fighting dependency conflicts, port clashes, and brittle Docker Compose files. odctl is a small CLI that turns Kafka, Flink, Spark, Trino, Iceberg, Airflow, and a full MLOps and observability suite into a cohesive stack you can launch with a single command. Now available on PyPI.
---

Anyone who has tried to stand up a realistic data platform on their laptop knows the pain. You want Kafka talking to Flink, Spark writing to Iceberg, Trino querying the result, and maybe a catalog and a lineage tool watching over all of it. What you actually get is an afternoon lost to dependency conflicts, port clashes, and a Docker Compose file that grows a new bug every time you touch it.

I built `odctl` to make that afternoon disappear. It is a curated collection of open-source data technologies wrapped in a small CLI, and it is now available on PyPI.

<!--more-->

## What odctl Is

`odctl` provides a cohesive, Docker-based blueprint for experimenting with modern data architecture and MLOps locally. Instead of hand-writing Compose files, you describe what you want in terms of profiles, and the CLI resolves the dependency graph, network routing, and configuration for you.

Install it as an isolated CLI tool:

```bash
uv tool install odctl
# or
pipx install odctl
```

## Bundled Technologies

Rather than shipping one monolithic cluster, the stack is organized into profiles you can launch independently or together:

* **Messaging:** Kafka (KRaft), Schema Registry (Karapace), Kafka Connect
* **Stream Processing:** Apache Flink
* **Data Processing:** Apache Spark
* **Analytics:** ClickHouse, Trino, Metabase
* **Orchestration:** Apache Airflow
* **MLOps:** MLflow, Ray Serve
* **Metadata:** OpenMetadata
* **Observability:** Prometheus, Alertmanager, Grafana
* **Lineage:** OpenLineage, Marquez
* **Foundational storage and catalog:** PostgreSQL (pgvector), SeaweedFS (S3), Iceberg REST Catalog, Valkey, Apache Fluss

That covers ingestion, streaming, batch, OLAP, orchestration, machine learning, governance, and observability, all from a single tool.

## Dependencies Resolve Themselves

Manual Compose setups fall apart because the interesting engines depend on foundational infrastructure that you have to remember to start first. `odctl` treats those dependencies as a graph and walks it for you.

Getting a full data engineering environment running takes three steps:

```bash
# 1. Copy the default Compose files and configs into a local .odctl workspace
odctl init

# 2. See what you can launch
odctl list

# 3. Launch the streaming and batch engines
odctl up kafka-lite flink1-lite spark-lite
```

You do not need to memorize what depends on what. When you ask for Kafka, Flink, and Spark, the CLI detects that they require foundational infrastructure and quietly launches PostgreSQL, SeaweedFS (S3), and the Iceberg REST Catalog before starting the compute engines.

## A Small, Predictable Command Surface

Commands are grouped by intent, and every one accepts `--help`:

* **Inspect:** `odctl list`, `odctl explain <profile>`, `odctl ps`, `odctl info`
* **Lifecycle:** `odctl pull`, `odctl up`, `odctl down`
* **Manage:** `odctl logs`, `odctl restart`

A few examples:

```bash
# View all profiles and exposed ports
odctl list -d

# See exactly what the kafka profile provisions
odctl explain kafka-lite

# Complete teardown and wipe all data
odctl down --all --volumes
```

## Hackable by Design

`odctl` does not hide the underlying configuration from you. Running `odctl init` generates a local `./.odctl/` workspace containing everything that powers the stack:

* `compose-*.yml`: the actual Docker Compose definitions. Edit these to change exposed ports, adjust memory limits, or inject environment variables.
* `registry.yml`: the internal dependency graph.
* `.env`: shared environment variables such as default credentials and timezones.

The CLI always prioritizes the files in your local workspace, so you can tweak freely. If you break something, `odctl init --force` restores the pristine defaults.

## Try It Out

`odctl` is on PyPI now. If you build demos, write technical content, or just want a realistic data platform to experiment with, it removes the setup tax so you can get to the interesting part.

* **PyPI:** [pypi.org/project/odctl](https://pypi.org/project/odctl/)
* **GitHub:** [jaehyeon-kim/odctl](https://github.com/jaehyeon-kim/odctl)

It is licensed under Apache 2.0, and contributions are welcome.
