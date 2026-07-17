---
title: "Dynamic DES v0.11.1: A Declarative API with Postgres and Redis Connectors"
date: 2026-07-17
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
  - Discrete Event Simulation
  - dynamic-des
  - Digital Twin
  - SimPy
  - Kafka
  - Redis
  - PostgreSQL
  - Python
authors:
  - JaehyeonKim
images: []
description: |
  Since the v0.8.1 release, Dynamic DES has gained a declarative SimulationContext API, native Postgres and Redis ingress and egress connectors, and broader object storage support. This post walks through what changed and why the new builder pattern makes real-time digital twins far easier to write.
---

A while back I wrote about [Dynamic DES v0.8.1](/blog/2026-05-25-dynamic-des-parquet-support/) and its native Data Lake integration, using one SimPy codebase for both batch training and live inference. Several releases later, the project has grown in two directions that matter for anyone building event-driven digital twins: a cleaner authoring experience, and more places to send and receive data.

Here is what changed on the way to **v0.11.1**.

<!--more-->

## A Declarative SimulationContext API

The biggest change is how you write a simulation. Earlier versions exposed a low-level, imperative API where you wired up the environment, registry, connectors, and processes by hand. That is still available and fully supported for advanced control flows, but it is now the low-level paradigm rather than the default one.

The new **Standard API** is built around `SimulationContext`, a declarative builder that describes the whole simulation in one readable block:

```python
from dynamic_des import SimulationContext, ConsoleEgress, LocalIngress

# Schedule capacity to jump to 3 at t=10s, then drop to 2 at t=20s
app = (
    SimulationContext(sim_id="Line_A", factor=1.0, random_seed=42)
    .add_resource("lathe", current_cap=1, max_cap=5)
    .add_arrival("standard", dist="exponential", rate=1.0)
    .add_service("milling", dist="normal", mean=3.0, std=0.5)
    .add_ingress(LocalIngress(
        schedule=[
            (10.0, "Line_A.resources.lathe.current_cap", 3),
            (20.0, "Line_A.resources.lathe.current_cap", 2),
        ]
    ))
    .add_egress(ConsoleEgress())
)
```

Simulation logic is then attached with decorators, so the mechanics of queuing, resource locking, duration sampling, and telemetry emission are handled for you:

```python
@app.arrival_loop("standard")
def arrival_process(context: SimulationContext):
    task_id = 0
    while True:
        yield context.wait_for_arrival("standard")
        context.spawn(work_task(task_id))
        task_id += 1

@app.task(service_id="milling", resource_id="lathe")
def work_task(task_id: int):
    return {"part_id": task_id}

app.run(until=25.0)
```

The value here is separation of concerns. The builder declares parameters, connectors, and configuration, while the decorators express only the behavior that is unique to your model. Swapping a console for Kafka, or a fast-forward clock for a real-time one, does not touch the simulation logic at all.

## Postgres and Redis Connectors

Dynamic DES uses a **Switchboard Pattern** that decouples data sourcing from simulation logic. Background threads handle heavy I/O, a central registry flattens incoming data into dot-notation paths, and SimPy resources wake up only when the registry signals a change. Because that boundary is clean, adding a new backend is mostly a connector implementation.

Recent releases added two important ones, each with matching ingress and egress:

* **PostgreSQL:** stream telemetry and lifecycle events into a relational store, or drive simulation parameters from a table. Useful when your control plane or your analytics already live in Postgres.
* **Redis:** a low-latency, in-memory option for pushing state out to dashboards or reading live parameter updates, alongside the existing Kafka path.

These sit next to the connectors that were already there, so a single simulation can now ingest from and emit to Kafka, Redis, or PostgreSQL, and export historical data to local disk, AWS S3, Google Cloud Storage, Azure Blob, or SeaweedFS through PyArrow's virtual filesystem, all with strict schema drift prevention.

<div align="center">
  <img src="dashboard-preview.gif" alt="Dynamic DES live control dashboard" width="800" />
</div>

## Strict Data Contracts

Regardless of the backend, outbound payloads are validated with Pydantic, so external consumers receive a predictable shape. There are two stream types. Telemetry carries scalar metrics such as utilization and queue length:

```json
{
  "stream_type": "telemetry",
  "path_id": "Line_A.resources.lathe.utilization",
  "value": 85.5,
  "sim_ts": 120.5,
  "timestamp": "2023-10-25T14:30:00.000Z"
}
```

Events carry discrete lifecycle transitions such as a task arriving, queuing, or finishing:

```json
{
  "stream_type": "event",
  "key": "task-001",
  "value": {
    "status": "finished",
    "duration": 45.2,
    "path_id": "Line_A.service.lathe"
  },
  "sim_ts": 125.0,
  "timestamp": "2023-10-25T14:30:04.500Z"
}
```

## Stability

The v0.11.1 patch closed out threading race conditions in the egress providers during environment teardown. When a simulation shuts down, the background I/O threads now drain and stop cleanly instead of racing the main thread, which matters for both test suites and long-running twins.

## Try It Out

Everything above is available now:

```bash
# Core library
pip install dynamic-des

# Everything: Kafka, Redis, Postgres, dashboard, Avro, Parquet
pip install "dynamic-des[all]"
```

The repository ships zero-setup demos for the local, Kafka, Postgres, and Redis paths in both the declarative and imperative styles.

* **PyPI:** [pypi.org/project/dynamic-des](https://pypi.org/project/dynamic-des/)
* **GitHub:** [jaehyeon-kim/dynamic-des](https://github.com/jaehyeon-kim/dynamic-des)
* **Documentation:** [jaehyeon.me/dynamic-des](https://jaehyeon.me/dynamic-des/)
