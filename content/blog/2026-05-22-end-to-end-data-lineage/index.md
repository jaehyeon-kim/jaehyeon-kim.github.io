---
title: "Current London 2026: Building End-to-End Data Lineage"
date: 2026-05-22
draft: false
featured: false
comment: true
toc: false
reward: false
pinned: false
carousel: false
featuredImage: false
categories:
  - Data Engineering
  - Conference
tags:
  - Apache Kafka
  - Apache Flink
  - Apache Spark
  - OpenLineage
  - Data Lineage
  - Streaming
authors:
  - JaehyeonKim
images: []
description: "A comprehensive walkthrough from my session at Current London 2026 on capturing and visualizing data lineage across a production-style data stack."
---

This week, I traveled to London to speak at Current 2026. In addition to connecting with fellow data practitioners, I presented a session on a common architectural challenge: tracking the complete lifecycle of data.

In modern data ecosystems, understanding data provenance, transformation steps, and final destinations is necessary for governance and root-cause analysis. My session, [**Building End-to-End Data Lineage with Kafka, Flink, and Spark**](https://current.confluent.io/london/sessions#session-SESS-70), detailed a way to capture this metadata across parallel pipelines using [OpenLineage](https://openlineage.io/).

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

## Moving Forward

By instrumenting event streams, streaming compute, and batch processing engines with a unified standard like OpenLineage, organizations can establish observable and reliable data architectures. 

Thank you to everyone who attended the session at Current London. For those unable to attend, the slides are provided above for reference.
