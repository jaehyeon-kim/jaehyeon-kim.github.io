---
title: "Building an Event-Driven Hybrid Digital Twin with dynamic-des"
date: 2026-04-29
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Building Real-Time Digital Twins with dynamic-des
categories:
  - System Architecture
  - Data Engineering
tags:
  - Digital Twin
  - Discrete Event Simulation
  - IoT
  - Kafka
  - dynamic-des
  - SimPy
  - Python
authors:
  - JaehyeonKim
images: []
description: |
  In Part 2 of our series, we dive into the code and architecture of dynamic-des. Learn how to use the Switchboard pattern, mutable resources, and dynamic topic routing to transform a static model into a synchronized forecasting engine.
---

## Asynchronous Gap

In [Part 1](/blog/2026-04-23-digital-twin-industry-4-0/), we established that a true Hybrid Digital Twin does more than just mirror reality. It actively forecasts the future by running a simulation against live operational states.

If you have ever tried to build one of these systems from scratch, you immediately hit a fundamental architectural clash.

Standard simulation clocks (like those in traditional SimPy implementations) are logically synchronous and not designed to handle high-frequency asynchronous I/O without explicit decoupling. They step through logical time deterministically. Real-world telemetry (like a Kafka stream or a Redis Pub/Sub channel) is asynchronous and non-deterministic in arrival timing and ordering at the system level. If you naively wire a live data feed directly into a standard simulation loop, you will stall the simulation loop while awaiting network I/O. The simulation drifts from real-world time, making your live twin useless.

To solve this, the compute layer must be explicitly decoupled from the network layer. This is the exact design problem the open-source [**`dynamic-des`**](https://github.com/jaehyeon-kim/dynamic-des) package addresses.

# Core Architecture: Switchboard Pattern

`dynamic-des` operates as a real-time control plane wrapped around a discrete-event simulation core. It bridges the asynchronous gap using the Switchboard Pattern, which isolates the network from the math:

1. **Connectors (I/O Layer):** Background async I/O workers handle heavy network traffic (Kafka, Redis, Postgres) entirely independently of the simulation clock.
2. **Simulation Registry (Switchboard):** This is the central state manager. It intercepts incoming network data, safely casts types, and flattens complex system schemas into addressable paths that act as reactive state bindings, allowing any component in the simulation to subscribe to and react to state transitions.
3. **Simulation Objects:** The actual mathematical models and resources that consume these state transitions.

Because the background I/O workers and the simulation clock communicate through thread-safe queues, network latency does not block your forecasting logic. However, decoupling is not a magic bullet. If ingestion rates exceed processing rates, drift can still occur, which is why system observability is critical.

## Physics of Change: Mutable Resources

With the data flowing safely, the simulation objects themselves must be able to react. In a traditional DES model, resources are static. If you initialize `simpy.Resource(capacity=5)`, it stays 5 forever. In the real world, machines break, operators go on break, and routing logic shifts dynamically.

Instead of polling the network, `dynamic-des` introduces mutable resources (`DynamicResource`, `DynamicContainer`, `DynamicStore`) that adapt safely:

  * **Growing is easy:** If capacity increases from 5 to 10, new tokens are immediately added to the pool, instantly unblocking pending requests.
  * **Shrinking is complex:** If capacity drops from 5 to 2 while 4 tasks are actively being processed, what happens? Work-In-Progress (WIP) is never destroyed. The resource enters a temporary over-capacity state. It waits for the active tasks to naturally finish, intercepting their returned tokens until the physical pool matches the new, smaller capacity limit.

## System Observability

When running a real-time simulation, your biggest operational risk is simulation drift. If your compute layer cannot process the incoming event stream fast enough, the simulation clock will fall behind relative to event time or wall-clock time.

To solve this, `dynamic-des` includes built-in observability. The egress layer automatically calculates this drift and continuously streams a `system.simulation.lag_seconds` telemetry metric. This makes it easy to set up Grafana dashboards and trigger alerts if the forecasting engine begins lagging behind reality.

## Designing for Failure Modes

Moving from a static offline script to a live, event-driven twin introduces distributed systems problems. A production-grade deployment must account for specific failure modes:

  * **Backlog Growth:** Queues prevent the network from blocking the simulation loop, but if your computational logic is too heavy, the event backlog will grow and cause severe simulation drift.
  * **Event Ordering:** In distributed systems, events can arrive out of order. You must implement proper Kafka partitioning strategies to ensure causal events are processed sequentially within a partition; cross-partition ordering must be handled at the application level.
  * **State Recovery:** If a simulation node crashes, it must be able to restart, rebuild its state tree from the Registry or by replaying the event log, and resume processing from the correct Kafka offsets without losing WIP logic.

## Developer Journey: From Laptop to Cluster

A good digital twin framework must be portable. You should be able to validate your business logic locally before introducing the complexity of enterprise message brokers. `dynamic-des` achieves this by making the I/O layer entirely pluggable.

### Phase 1: Local Deterministic Testing

Before touching Kafka, you can use `LocalIngress` to schedule mutations deterministically. This allows you to unit-test exactly how your factory floor reacts to a breakdown at a specific timestamp.

```python
from dynamic_des import (
    DynamicRealtimeEnvironment, DynamicResource, 
    LocalIngress, ConsoleEgress, SimParameter, CapacityConfig
)

# 1. Define the initial state
params = SimParameter(
    sim_id="Line_A",
    resources={"lathe": CapacityConfig(current_cap=1, max_cap=5)},
)

# 2. Schedule a deterministic capacity jump (1 -> 3) at t=5.0s
ingress = LocalIngress([
    (5.0, "Line_A.resources.lathe.current_cap", 3)
])
egress = ConsoleEgress()

# 3. Initialize Environment & Registry
env = DynamicRealtimeEnvironment(factor=1.0)
env.registry.register_sim_parameter(params)
env.setup_ingress([ingress])
env.setup_egress([egress])

res = DynamicResource(env, "Line_A", "lathe")

env.run(until=10)
```

Notice the `factor` parameter in the environment setup. The environment can run in real-time or accelerated logical time, depending on the configured factor. A factor of 1.0 syncs the simulation strictly to the wall-clock, while lower factors accelerate it for rapid scenario testing.

### Phase 2: Live Kafka Integration

Once your logic is sound, transitioning to an operational digital twin requires changing exactly two lines of code. You swap the local connectors for Kafka connectors.

While this example is kept clean for readability, real production deployments will naturally require additional configurations for retries, authentication, and backpressure handling.

```python
from dynamic_des import KafkaIngress, KafkaEgress

# Swap connectors: no changes needed to business logic
ingress = KafkaIngress(
    topic="factory-config", 
    bootstrap_servers="broker.internal:9092"
)

egress = KafkaEgress(
    telemetry_topic="sim-vitals", 
    event_topic="sim-events", 
    bootstrap_servers="broker.internal:9092"
)

env.setup_ingress([ingress])
env.setup_egress([egress])

env.run()
```

## Evolution into a State-Machine Engine

Traditional Discrete-Event Simulation is strictly quantitative, focusing mostly on queue lengths, processing times, and resource capacities. However, `dynamic-des` has evolved beyond this to blend DES with reactive programming, behaving much like a state-machine engine.

By utilizing the `variables` registry and the `wait_for_change()` observer pattern, developers can track arbitrary logical states. Instead of just yielding on time delays, simulation processes can yield on external network events. A Kafka payload no longer just updates a number. It acts as a state-transition trigger that dictates the logical flow of the entire application.

This flexibility means digital twins can incorporate sophisticated modeling well beyond tracking discrete items in a queue. You can map real-time telemetry directly to custom mathematical logic. For a practical example, you can view the [**OML Digital Twin Hot Rolling**](https://github.com/jaehyeon-kim/oml-digital-twin-hotrolling) project, which demonstrates how to build a real-time tracking dashboard for steel manufacturing using advanced physical simulations.

### 💡 Domain-Agnostic Applications

Because it behaves as a reactive state engine, `dynamic-des` is not restricted to factory floors. I am currently building out additional demo projects to highlight its versatility across entirely different domains:

  * **Continuous-Time Crypto Trading Bot:** This demo proves the package can handle high-velocity financial simulations. It utilizes the variables registry to track live BTC prices and portfolio balances, while using dynamic resources to model exchange API rate limits. Concurrent processes simulate the market maker (random walk price updates), strategy monitor (moving average crossovers), and order execution (yielding realistic network latency delays).
  * **RPG Adventure Game State Machine:** This demo highlights the stochastic and time-delay strengths of the engine by modeling complex entity interactions over continuous time. Primitive game states (player HP, enemy HP, current room) live in the variables registry. Continuous processes handle room exploration with travel time delays and active combat loops. The combat process yields attack cooldown timeouts and uses the global `Sampler` for randomized damage, tracking causality back to the root encounter event.

## Enforcing Data Contracts and Routing

A hybrid twin is only as useful as the data it outputs. To ensure downstream analytics systems do not break, `dynamic-des` natively enforces strict data contracts and provides granular control over serialization.

### Type Safety and Pydantic Integration

Data hygiene works in both directions. On the ingress side, the framework performs dynamic type casting to prevent malformed sensor data from crashing your active simulation.

On the egress side, you can yield strongly typed Pydantic models directly from your simulation logic. You do not need to manually convert objects to dictionaries. The egress layer automatically detects, extracts, and serializes your models:

```python
from pydantic import BaseModel
from dynamic_des import DynamicRealtimeEnvironment

class TaskEvent(BaseModel):
    path_id: str
    status: str

def work_task(env: DynamicRealtimeEnvironment, task_id: int):
    # Pass the Pydantic model directly to the framework
    event = TaskEvent(path_id="Line_A.lathe", status="queued")
    env.publish_event(f"task-{task_id}", event)
```

### Pluggable Routing and Avro Schemas

In an enterprise architecture, you rarely dump all events into a single Kafka topic. You might want standard telemetry routed as lightweight JSON, while high-velocity machine learning payloads are serialized as binary Avro.

`dynamic-des` handles this through pluggable topic routers and serializers. You can map specific topics to a `ConfluentAvroSerializer` or a `GlueAvroSerializer`, and any unmapped topics will safely fall back to default JSON.

Because hardcoding Avro schemas is prone to drift, the framework natively supports `dataclasses-avroschema`. This allows you to auto-generate your schema directly from your Pydantic model and route it seamlessly:

```python
from pydantic import Field
from dataclasses_avroschema.pydantic import AvroBaseModel
from dynamic_des import KafkaEgress
from dynamic_des.connectors.egress.kafka import ConfluentAvroSerializer

# 1. Define your model and auto-generate the schema
class MLPrediction(AvroBaseModel):
    """High-velocity ML payload"""
    task_id: str = Field(...)
    confidence: float = Field(...)

    class Meta:
        namespace = "com.dynamic_des.ml"
        schema_name = "PredictionEvent"

# 2. Define a topic router to separate standard events from ML events
def ml_topic_router(data: dict) -> str:
    if data.get("value", {}).get("event_type") == "prediction":
        return "ml-predictions"
    return "sim-lifecycle"

# 3. Configure the Egress Connector
egress = KafkaEgress(
    bootstrap_servers="localhost:9092",
    topic_router=ml_topic_router,
    topic_serializers={
        # Map the auto-generated Avro serializer to the ML topic
        "ml-predictions": ConfluentAvroSerializer(
            registry_url="http://localhost:8081",
            schema_str=MLPrediction.avro_schema() 
        ),
    }
)
```

## Moving to Production

By decoupling network I/O from the simulation clock, enforcing strict data schemas, and blending DES with reactive programming, `dynamic-des` provides a clean architectural pattern for modern event-driven systems.

This enables a new class of systems beyond static models and passive dashboards. You can build resilient, synchronized forecasting engines that adapt to reality the moment it changes.

To explore the source code, view the full API documentation, or test out the zero-setup Docker examples, check out the [**`dynamic-des` repository on GitHub**](https://github.com/jaehyeon-kim/dynamic-des).
