---
title: "One Simulation, Two Pipelines: Batch Training and Live Inference with Dynamic DES v0.8.1"
date: 2026-05-21
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
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
  Dynamic DES v0.8.1 introduces native Data Lake integration. Learn how to use a single SimPy codebase to generate batch Parquet data for ML training, and seamlessly transition to streaming live Kafka events for production inference.
---

Training a machine learning model on simulated data is straightforward until you try to deploy it. The disconnect usually happens at the pipeline level: training requires massive, historical batch data (like Parquet files in an S3 bucket), but production inference requires real-time, event-driven streams (like Kafka or Redis). 

Maintaining two separate simulation codebases, _one for generating training data and another for streaming live events_, introduces friction, schema mismatches, and duplicated engineering effort.

Dynamic DES was originally designed to solve the real-time problem by acting as a control plane for SimPy models. With the release of **v0.8.1**, it now natively handles high-performance historical data generation, allowing you to use the **exact same simulation code** for both batch training and live inference.

### Step 1: Batch Training (Historical Fast-Forward)

To generate training data efficiently, the simulation must be decoupled from the real-world clock. By setting the environment's `factor` to `0.0`, the engine initiates a "fast-forward," executing logical events as fast as the CPU allows.

To capture this massive data throughput without exhausting memory or fragmenting storage, v0.8.1 introduces **`ParquetStorageEgress`** and **`JsonlStorageEgress`**. Built on PyArrow, these connectors handle the complexities of Data Lake ingestion natively:

* **Schema Drift Protection:** The engine infers the schema from the initial data batch and strictly casts all subsequent records. This guarantees deterministic data types, preventing downstream ML pipelines from failing due to unexpected schema mutations.
* **Native Data Lake Integration:** Data is automatically chunked, compressed, and written directly to local disk, AWS S3, or SeaweedFS clusters via PyArrow's virtual filesystem.

You can simulate months of system operations in seconds, outputting optimized Parquet chunks ready for model training.

![Data Generation Example](parquet-example.gif#center)

### Step 2: Live Inference (Production Streaming)

Once the model is trained on the historical Parquet data, transitioning to production testing requires zero changes to your core simulation logic. 

By changing the environment's `factor` from `0.0` to `1.0`, logical time synchronizes with wall-clock time. You simply swap the `ParquetStorageEgress` for a `KafkaEgress`. The simulation now runs in real-time, streaming the exact same schema to your message broker, providing a live data feed for your deployed ML model to consume.

This provides an end-to-end data engineering toolkit for simulation-based Machine Learning, from historical batch generation to live streaming pipelines.

### Try it out

The v0.8.1 release and the new storage connectors are available now. You can view the source code and run the historical data generation example below.

* **GitHub Repository:** [jaehyeon-kim/dynamic-des](https://github.com/jaehyeon-kim/dynamic-des)
* **Documentation & Examples:** [Historical Data Generation Guide](https://jaehyeon.me/dynamic-des/latest/examples/history/)
