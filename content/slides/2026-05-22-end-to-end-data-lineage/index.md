---
title: "Building End-to-End Data Lineage with Kafka, Flink, and Spark"
date: 2026-05-22
reveal_theme: "black"
layout: "single"
description: "A deep dive into capturing runtime metadata and building an operational, cross-platform lineage graph across streaming and batch environments."
---

<style>
  /* Global text sizing and layout tuning */
  .reveal section {
    padding: 20px !important;
  }
  .reveal p, .reveal li {
    font-size: 0.65em; 
    line-height: 1.4;
    margin-bottom: 0.4em;
    text-align: left;
  }
  .reveal h2 {
    font-size: 1.5em;
    margin-bottom: 0.5em;
  }
  .reveal h3 {
    font-size: 1.1em;
    margin-top: 0.6em;
    margin-bottom: 0.2em;
    color: #42affa;
    text-align: left;
  }
  .columns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
    text-align: left;
    align-items: center;
  }
  .columns h3 {
    margin-top: 0;
  }
  .center {
    text-align: center;
  }
  /* Ensure images fit the viewport */
  .reveal img {
    max-height: 45vh !important;
    max-width: 100%;
    margin: 10px auto !important;
    display: block;
    border: 1px solid #333;
    border-radius: 4px;
    object-fit: contain;
  }
  /* Fix for wide bullet margins */
  .reveal ul {
    display: block;
    margin-left: 0 !important;
    padding-left: 1.2em !important; /* Pulls bullets much closer to the left edge */
  }
</style>

## Building End-to-End Data Lineage
#### With Kafka, Flink, and Spark

---

## What is Data Lineage?

The journey of data - where it comes from, how it’s transformed, and where it ends up.

### Why Data Lineage Matters

- **Debugging & Root Cause Analysis:** Quickly trace production bugs back to the source.
- **Impact Analysis & Governance:** See downstream dependencies before changing schemas.
- **Compliance & Audit:** Document data provenance for strict regulatory requirements.
- **Trust & Reliability:** Increase stakeholder confidence in data products.

---

## What is OpenLineage?

An open standard for capturing lineage metadata from jobs in execution.

<div class="columns">
  <div>
    <p>Supports seamless collection across popular tools:</p>
    <ul>
      <li><strong>Orchestration:</strong> Airflow, dbt</li>
      <li><strong>Compute Engines:</strong> Flink, Spark, Trino</li>
      <li><strong>Backend:</strong> Marquez (visualization)</li>
      <li>⚠️ <strong>Gap:</strong> Kafka is not an official, out-of-the-box source.</li>
    </ul>
  </div>
  <div class="center">
    <img src="openlineage-model.png" alt="OpenLineage Model">
  </div>
</div>

---

## Two Lineage Paradigms

<div class="columns" style="align-items: start;">
  <div>

### Batch Lineage (Retrospective)

- **Data:** Bounded Sets
- **Lifecycle:** Finite, Scheduled
- **Capture:** At Job Completion
- **Result:** Historical Audit Trail
  </div>
  <div>

### Streaming Lineage (Operational)

- **Challenge:** Unbounded Streams
- **Challenge:** Continuous Jobs
- **Opportunity:** Capture **During** Execution
- **Opportunity:** A **Live, Observable System**
  </div>
</div>

---

## Kafka: Lineage with Connect

Use a custom **Single Message Transform (SMT)** as a "pass-through" lineage agent.

- **Lifecycle Hook:** Intercepts connector states (`RUNNING`, `FAIL`, `COMPLETE`) without altering records.
- **Column-Level Depth:** Resolves fields via Avro schemas in the Schema Registry.
- **Consistent Namespacing:** Normalizes physical dataset naming (e.g., `kafka://...`, `s3://...`) for job linking.

---

## Kafka Pipeline Mapping

One lineage job tracking data flow per active connector.

<img src="data-lineage-kafka.gif" alt="Kafka Lineage Flow">

---

## Flink: Integration Patterns

<div class="columns" style="align-items: start;">
  <div>

### Native `JobListener`<br>*(DataStream API)*

- **Method:** `OpenLineageFlinkJobListener`.
- **Pros:** Simple, out-of-the-box.
- **Cons:** Fails to capture final `ABORT` transition.
  </div>
  <div>

### Manual Orchestration<br>*(Table API / SQL)*

- **Method:** OpenLineage Java client.
- **Pros:** Full lifecycle event tracking.
- **Cons:** Requires custom wrapper code.
  </div>
</div>

---

## Flink Pipeline Mapping

One lineage job mapped directly per active Flink application cluster.

<img src="data-lineage-flink.gif" alt="Flink Lineage Flow">

---

## Spark: Final Picture

Batch Spark job reading from Flink-written Iceberg tables.

- **Agent:** Tracked via OpenLineage Java agent in `spark.extraListeners`.
- **Query Plan:** Auto-detects inputs/outputs from Logical/Physical plans.
- **Granular Actions:** Parent job with child jobs per Spark action.
- 💡 **Namespace Alignment:** Engines must agree on the same physical root namespace (e.g., `s3://warehouse`).

---

## Spark Pipeline Mapping

One lineage job registered for each execution action block.

<img src="data-lineage-spark.gif" alt="Spark Lineage Flow">

---

## Conclusion: Key Takeaways

Bridging real-time events and historical batch processing.

- **Choose the Right Pattern**
  - **Trade-off:** Simplicity vs. Tracing Durability.
  - **Standard:** Use Native Listeners.
  - **Critical:** Use Manual Orchestration for strict lifecycle tracking.
- **Align Namespaces**
  - Essential for cross-tech lineage.
- **Start Small**
  - Instrument one critical pipeline first.
  - Establish metadata visibility, then scale outward.

---

## Project Repositories & Guides

- [OpenLineage Project](https://openlineage.io/)
- [Data Linage Lab](https://github.com/factorhouse/examples/tree/main/projects/data-lineage-labs)
