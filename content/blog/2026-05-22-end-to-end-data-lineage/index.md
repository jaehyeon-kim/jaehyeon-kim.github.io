---
title: "Current London 2026: Building End-to-End Data Lineage"
date: 2026-05-22
draft: false
featured: true
comment: true
toc: false
categories:
  - Data Engineering
tags:
  - Apache Kafka
  - Apache Flink
  - Apache Spark
  - OpenLineage
  - Data Lineage
description: |
  Tracking data across Kafka, Flink and Spark pipelines with OpenLineage, to show where each dataset came from and what reads it. Slides from my Current London 2026 session.
---

When a number in a report looks wrong, the first question is where it came from, and the next is what else a change will break. Answering both needs data lineage: a record of which jobs read and wrote which datasets, across every system the data passes through. At Current London 2026 I presented a session on this, [**Building End-to-End Data Lineage with Kafka, Flink, and Spark**](https://current.confluent.io/london/sessions#session-SESS-70), which captures that metadata across parallel pipelines using [OpenLineage](https://openlineage.io/).

## Presentation Slides

Below are the slides from my session, rendered natively here on the blog. 

{{< slide "/slides/2026-05-22-end-to-end-data-lineage/" >}}

*You can use your arrow keys to navigate the slides above, or click the "View Full Screen" button for the complete experience.*

## Session Breakdown: Tracking the Data Lifecycle

The presentation focused on tracking data from a single Kafka topic as it distributed across concurrent architectural paths. To demonstrate the lineage graph, we analyzed a standard production stack.

### 1. Real-Time & Archival Fan-Out

The architecture begins with a primary Kafka topic. From there, the data splits into distinct operational domains:
* **Archival:** A Kafka S3 Sink Connector handling raw data offloading to object storage.
* **Live Analytics:** A real-time Flink DataStream job consuming events for stateful processing.
* **Data Lakehouse:** A Flink Table API job ingesting the continuous stream into an Apache Iceberg table for query engines.

### 2. Completing the Picture with Spark

To demonstrate a complete end-to-end lifecycle, the session traced the lineage as a batch Apache Spark job consumed from the populated Iceberg table to generate downstream aggregations.

### 3. Instrumenting with OpenLineage

Visualizing this multi-path journey, including column-level details, was achieved using **Marquez** as the lineage repository and visualization layer. The metadata extraction was handled through **OpenLineage**. Integrating these systems to output a unified lineage graph requires specific strategies:

* **Kafka Connect:** Lineage is established at the connector level using a custom Single Message Transform (SMT) to capture operational state without altering the payload.
* **Apache Flink:** Two distinct patterns were evaluated: a low-overhead listener-based approach, and a manual orchestration method necessary for capturing application cancellations.
* **Apache Spark:** Spark's `extraListeners` were configured to auto-detect inputs and outputs, linking the batch jobs to upstream Flink outputs via aligned physical namespaces.

## Related posts

* [Setup Local Development Environment for Apache Flink and Spark Using EMR Container Images](/blog/2023-12-07-flink-spark-local-dev) - a local Flink and Spark environment of the kind this lineage work instruments.
* [Self-service Data Platform via a Multi-tenant SQL Gateway](/blog/2025-07-17-self-service-data-platform-via-sql-gateway) - Apache Kyuubi giving on-demand Spark, Flink and Trino engines with central governance.
* [Running Kafka, Flink, Spark, Trino and Iceberg Locally with One CLI](/blog/2026-07-16-odctl-open-data-stack) - a CLI that starts Kafka, Flink, Spark, Trino, Iceberg and observability tooling as one local stack.

## Moving Forward

By instrumenting event streams, streaming compute, and batch processing engines with a unified standard like OpenLineage, organizations can establish observable and reliable data architectures. 

Thank you to everyone who attended the session at Current London. For those unable to attend, the slides are provided above for reference.
