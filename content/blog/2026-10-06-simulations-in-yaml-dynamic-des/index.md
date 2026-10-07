---
title: "Defining Data-Streaming Simulations in YAML, Without Writing Python"
date: 2026-10-06
draft: false
featured: true
comment: true
toc: true
series:
  - Building Real-Time Digital Twins with dynamic-des
categories:
  - Data Engineering
  - Open Source
tags:
  - Discrete Event Simulation
  - dynamic-des
  - SimPy
  - YAML
  - Apache Kafka
  - Apache Iceberg
  - PostgreSQL
  - Python
description: |
  Test data for a streaming pipeline, from a settings file rather than a program: a plain YAML file describes a simulation, and one command runs it and sends its events to Kafka, PostgreSQL, Parquet or Iceberg.
---

A pipeline is easier to test when its input behaves like production: orders arrive at random, queues grow, a machine slows down. A simulation can produce that data, but when the simulation is a Python program, every change is a code change. Someone who only wants to double an arrival rate has to read and edit code, and a reviewer has to check that nothing else moved. A file that holds only settings is easier to read, to compare in a pull request and to run in CI.

[dynamic-des](https://github.com/jaehyeon-kim/dynamic-des) 0.16.0 adds that file. A YAML blueprint describes the whole simulation, and the `ddes` command runs it. Each of the seven examples in the repository now has a YAML version in plain YAML. The documentation was rebuilt around the three ways to write a simulation.

<!--more-->

The project started as a way to change a running SimPy model from Kafka ([Building an Event-Driven Hybrid Digital Twin with dynamic-des](/blog/2026-04-28-digital-twin-dynamic-des/)). It then learned to write Parquet for model training ([One Simulation, Two Pipelines](/blog/2026-05-25-dynamic-des-parquet-support/)) and gained a declarative Python API with PostgreSQL and Redis connectors ([A Declarative API with Postgres and Redis Connectors](/blog/2026-07-17-dynamic-des-declarative-connectors/)). This release removes the need for Python in most simulations.

## A Complete Blueprint

This file is `examples/yaml/local.yaml`. It needs no containers and prints events and telemetry to the terminal:

```yaml
simulation:
  sim_id: Factory_A
  factor: 1.0

egress:
  - type: Console

resources:
  lathe: {current_cap: 2, max_cap: 5}

services:
  milling: {dist: normal, mean: 3.0, std: 0.5}

arrivals:
  # Each arrival spawns one process_part task.
  standard: {dist: exponential, rate: 1.0, spawn: process_part}

tasks:
  process_part:
    service: milling
    resource: lathe
    # The value of the task's finished event. id_field adds the task id as part_id.
    payload: {event_type: part_produced, quality: A}
    id_field: part_id

telemetry:
  # Samples the lathe every 2 simulation seconds.
  - interval: 2.0
    publish:
      utilization: lathe.utilization
      queue_length: lathe.queue_length

run:
  until: 60
```

Install the package from [PyPI](https://pypi.org/project/dynamic-des/), download the file and run it:

```bash
pip install dynamic-des
curl -O https://raw.githubusercontent.com/jaehyeon-kim/dynamic-des/main/examples/yaml/local.yaml
ddes run local.yaml

# Override run.until, in seconds or as a duration such as "2 min"
ddes run local.yaml --until 30
```

![Downloading local.yaml, printing it and running it with ddes, with events and telemetry streaming until the run is stopped](local-yaml-run.gif)

The [documentation](https://jaehyeon.me/dynamic-des/) has the full reference. The `ddes` command comes with the core package. Typer and PyYAML are now core dependencies, so no extra is needed to run a blueprint. From Python, `SimulationContext.from_yaml("local.yaml")` returns the same simulation as a builder you can extend.

The file is checked before the run starts. An unknown key, a task that names a missing service, or a scenario path that does not exist is reported with the file name and the line number.

## What a Blueprint Can Express

Each section of a blueprint maps to one call of the declarative API. Beyond the sections above, a blueprint supports:

* **Environment variables.** `${VAR}` and `${VAR:-default}` are replaced in string values, with a default when a variable is not set. The same file then runs on your machine and in a test pipeline, with no edits.
* **Relative times.** `logical_start_time` and `go_live_at` take `now` or a signed duration such as `-10m`.
* **Backfill then live in one run.** Each egress entry takes `when: history` or `when: live`. Records stamped before `go_live_at` go to one sink, and later records go to the other.
* **Scenarios on simulation time.** A `scenario` list sets parameters at given simulation times, such as a capacity change at 30 seconds. The steps wait on the simulation clock, so they repeat exactly and also work at `factor: 0`.
* **Tasks without a service or a resource.** Such a task emits its payload as soon as it is spawned, which suits order or click events that do not queue.
* **Connectors that prepare their target.** Kafka creates its event and telemetry topics at start. PostgreSQL creates the tables listed under `tables`. Parquet and JSONL create the destination folder and take a `filesystem` mapping for local disk or S3. Iceberg takes its catalog properties and table schemas as plain mappings.

This excerpt from `examples/yaml/backfill_live.yaml` uses three of them. It writes ten minutes of history to Parquet as fast as the machine allows, then sends the same events to Kafka in real time:

```yaml
simulation:
  sim_id: Line_A
  factor: 0.0
  random_seed: 42
  logical_start_time: -10m
  go_live_at: now

egress:
  - type: Parquet
    config:
      default_path: data/backfill/events.parquet
    when: history
  - type: Kafka
    config:
      event_topic: sim-events
      telemetry_topic: sim-telemetry
      bootstrap_servers: ${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}
    when: live
```

## Python for Logic YAML Cannot Express

Some logic is not configuration, for example an order with a random number of line items. A blueprint references such code with the `!python` tag, and the module sits beside the file. The repository has one example of this, `examples/yaml/advanced/postgres_orders.yaml`. Everything else in that file is still plain YAML:

```yaml
processes:
  # Called as order_generator(context, arrival="customer_order", max_items=5).
  - function: !python postgres_orders_logic.order_generator
    kwargs: {arrival: customer_order, max_items: 5}
```

`!python` also works for a task payload, a telemetry function, an egress `when`, a connector class and any value under `config`, `simulation` or `run.until`. A file without it is read with PyYAML's safe loader and imports only the connector modules it names.

## Three Ways to Write the Same Simulation

A simulation can now be written in three ways, and all three build the same parameters and run on the same environment:

* **Low-level API:** `DynamicRealtimeEnvironment` used directly, with SimPy processes you write yourself.
* **Declarative API:** the `SimulationContext` builder and its decorators.
* **YAML blueprint:** the file above, run with `ddes`.

The registry paths, the records and the connectors are the same whichever you choose, so a team can start in YAML and move one part to Python when it needs to.

## Documentation Rebuilt

The [documentation](https://jaehyeon.me/dynamic-des/) was reorganised around those three ways:

* **Tutorials in three parts.** One small factory is built three times: [with the low-level API](https://jaehyeon.me/dynamic-des/latest/tutorials/low-level/), [with the declarative API](https://jaehyeon.me/dynamic-des/latest/tutorials/declarative/) and [as a YAML blueprint](https://jaehyeon.me/dynamic-des/latest/tutorials/yaml/).
* **Core Architecture in two groups.** Writing a simulation has a page per way, starting from the [overview](https://jaehyeon.me/dynamic-des/latest/architecture/overview/). The runtime pages cover the environment, the [registry and live parameters](https://jaehyeon.me/dynamic-des/latest/architecture/registry/), time, resources, connectors, records and batching.
* **Examples with a tab per way.** Each example page shows its versions side by side in tabs, low-level, declarative and YAML where all three exist, starting with the [local example](https://jaehyeon.me/dynamic-des/latest/examples/local/).
* **Guides grouped by topic.** Connectors, features such as [backfill then live](https://jaehyeon.me/dynamic-des/latest/guides/backfill-then-live/), and YAML, from [a first blueprint to connectors](https://jaehyeon.me/dynamic-des/latest/guides/yaml-blueprints/) to [custom logic with `!python`](https://jaehyeon.me/dynamic-des/latest/guides/yaml-advanced/). Modelling patterns such as preemptive breakdowns moved into an Advanced section.

## Other Changes in This Release

* **Fractional container capacity.** A capacity change on a `DynamicContainer` was rounded down to a whole number. A tank set to 62.5 now holds 62.5, also when it started at a whole number.
* **`DynamicContainer` and `DynamicStore` exported.** Both now import from `dynamic_des`, like `DynamicResource`.
* **Live `max_cap` changes.** A change to `max_cap` used to have no effect on a running resource. It now applies at once, and a lower limit shrinks the capacity.
* **Flat rows for files and tables.** Parquet, JSONL and Iceberg sinks with no router now write each event's value as columns and leave telemetry out. A router keeps the earlier behaviour.
* **Time strings in time columns.** Iceberg and PostgreSQL convert ISO time strings for timestamp and date columns, using the column types of the table.
* **Stricter blueprint checks.** A zero interval, batch size or `until` is rejected, because an interval of zero made a run hang. A `go_live_at` and a start time where only one has a time zone are rejected with the line. A connector that rejects its settings is reported with the line instead of a Python error.
* **`add_arrival` takes `std`,** so normal and lognormal arrivals can set a standard deviation.
* **CI checks.** The docs are built in strict mode on every pull request, and the core package alone, with no extra, must run a YAML blueprint.

## Related Posts

* [Change Data Capture on a Simulated Online Shop with Debezium and Kafka Connect](/blog/2026-10-01-ecommerce-cdc-debezium-kafka-connect/) - a simulated shop feeding a change data capture pipeline
* [Keeping Game Leaderboards Up to Date in Real Time with Kafka and Flink SQL](/blog/2026-10-02-game-leaderboard-flink-sql/) - a simulated mobile game feeding Flink SQL leaderboards
* [Why Digital Twins Are Rewiring Industry 4.0](/blog/2026-04-23-digital-twin-industry-4-0/) - where a simulation like this fits in a digital twin
* [Building an Agentic Analytics System over an Iceberg Lakehouse](/blog/2026-07-18-agentic-analytics-system/) - dynamic-des filling an Iceberg lakehouse with the data an agent queries

## Try It Out

```bash
# Core library and the ddes command
pip install dynamic-des

# Every connector: Kafka, Redis, PostgreSQL, Avro, Parquet and Iceberg
pip install "dynamic-des[all]"
```

* **GitHub:** [jaehyeon-kim/dynamic-des](https://github.com/jaehyeon-kim/dynamic-des), with the YAML examples in [`examples/yaml/`](https://github.com/jaehyeon-kim/dynamic-des/tree/main/examples/yaml)
* **PyPI:** [pypi.org/project/dynamic-des](https://pypi.org/project/dynamic-des/)
* **Documentation:** [jaehyeon.me/dynamic-des](https://jaehyeon.me/dynamic-des/)
