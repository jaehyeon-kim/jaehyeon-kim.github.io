---
title: "Building an Agentic Analytics System over an Iceberg Lakehouse"
date: 2026-07-18
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
  - Artificial Intelligence
  - Open Source
tags:
  - Agentic AI
  - Semantic Layer
  - WrenAI
  - Strands
  - Trino
  - Apache Iceberg
  - Text-to-SQL
  - Mem0
  - dynamic-des
  - odctl
authors:
  - JaehyeonKim
images: []
description: |
  Direct text-to-SQL is hard to trust in production because raw schemas do not capture governed metrics or business meaning. This post walks through a local, open-source proof of concept that puts a semantic layer between the language model and the lakehouse, combining Strands, WrenAI, Trino, Iceberg, and long-term agent memory.
---

Generative AI has made conversational analytics feel within reach, yet direct text-to-SQL systems remain hard to operate reliably. A database schema tells you the tables, columns, and types, but it says nothing about which datasets are canonical, which join paths are approved, how a governed metric is calculated, or what the business actually means by "revenue" or "active customer". Ask a language model to infer all of that from raw tables and, sooner or later, it will confidently invent an answer.

I built a proof of concept to explore a more disciplined approach: put a semantic layer between the model and the data, and let the agent reason over governed business concepts instead of guessing at raw schemas. It runs entirely locally on an open-source stack, and it happens to tie together two of my other projects along the way.

<!--more-->

## Why a Semantic Layer

A semantic layer defines models, relationships, reusable metrics, business rules, and approved query patterns independently of the language model. That separation is the whole point. When the definition of a metric lives in a governed contract rather than in a prompt, the agent cannot quietly redefine it, and the same question produces the same number every time.

I evaluated several options (WrenAI, Vanna AI, Nao, and MetricFlow) and selected [WrenAI](https://www.getwren.ai/). It uses a Modeling Definition Language (MDL) to define models, relationships, views, calculated fields, and cubes as a structured, executable contract, and critically it generates SQL without executing it. That last property lets the orchestrator own authorization, validation, and controlled execution as a separate concern, which is exactly the boundary you want when adapting a system for enterprise governance.

## Architecture

The stack is fully decoupled. An AI orchestrator interprets requests and talks to the semantic engine over the Model Context Protocol (MCP). The semantic engine plans deterministic queries from its business models and vector memory, and those queries execute against the physical lakehouse.

![Agentic Analytics System architecture: a Strands orchestrator coordinates the WrenAI semantic engine, LanceDB retrieval, and Mem0 memory over MCP, with queries executing against Trino, Iceberg, and SeaweedFS.](featured.png#center)

The diagram above traces a request end to end, and the table below maps each component to its role.

| Component | Technology | Role |
|:---|:---|:---|
| Agent Orchestrator | Strands SDK | Interprets natural language, plans multi-step tool calls, coordinates the pipeline over MCP |
| Semantic Engine | WrenAI | Governed semantic compiler: defines business logic as MDL, plans physical SQL, validates before execution |
| Retrieval Index | LanceDB | Local vector store for RAG-based table discovery over MDL descriptions |
| Agent Memory | Mem0 v3 over Valkey | Long-term user and conversational memory with hybrid retrieval |
| Historical Data | Trino / Apache Iceberg | Distributed SQL over an open table format |
| Object Storage | SeaweedFS | Local S3-compatible backend for Iceberg data |

The infrastructure is launched with [`odctl`](https://github.com/jaehyeon-kim/odctl), and the sample e-commerce dataset (customers, products, orders, order items, payments, returns) is generated with [`dynamic-des`](https://github.com/jaehyeon-kim/dynamic-des) running a fast-forward clock and writing Parquet straight to SeaweedFS. Both projects earn their keep here: one stands up the platform, the other fills it with realistic data in seconds.

## Two Layers That Keep the Model Honest

A major failure point for generative AI in data work is raw SQL hallucination. If you hand a model raw tables and ask it to join them on the fly, it will eventually produce a plausible but wrong metric. This system separates the problem into two layers so the model never sees a raw table.

**Layer 1, the semantic compiler (WrenAI):** supplies governed context (models, relationships, cubes, metrics), expands modeled SQL through MDL with `dry_plan`, validates against the live backend with `dry_run`, and executes through Trino with `run_sql`.

**Layer 2, the autonomous agent (Strands):** interprets the question, calls tools such as `get_context` and `recall_queries`, selects a cube or constructs modeled SQL, decides which execution tool to invoke, and maintains conversational context. Strands spawns WrenAI's native MCP server as a subprocess and discovers the semantic tools automatically, so there is no hardcoded database wiring.

Because the agent only ever interacts with WrenAI's governed semantic API, the set of available models and joins is constrained by design, which is what reduces the hallucination risk.

## A Query, End to End

1. **Context check:** the orchestrator queries Mem0 on Valkey to pull long-term preferences.
2. **Semantic translation:** the request goes to WrenAI, which uses its MDL and LanceDB memory to map intent to accurate SQL.
3. **Validation and execution:** the agent validates the physical schema against live metadata, then executes against Iceberg through Trino and returns structured data.

For a governed question like "what is the revenue for delivered orders?", the agent discovers the `daily_revenue` cube and maps "revenue" to `gross_revenue`. It never writes the `SUM()` or `GROUP BY` itself, because WrenAI compiles the deterministic SQL defined in the cube.

## Memory That Turns Usage into Learning

Two forms of memory make the system better over time.

WrenAI builds a local LanceDB index over schema items, seed queries, and approved SQL examples, so it can retrieve only the relevant models for a question and offer proven queries as few-shot context. Most text-to-SQL systems treat every question as the first one. Adding a retrieval layer means successful work improves future work as the knowledge base grows.

On top of that, Mem0 gives the agent long-term memory for subjective business logic. Ask "how many high-value orders did we have yesterday?" with no memory, and the model will invent a threshold. Teach it once that high-value means a total amount greater than $1,000, and that definition is stored in Valkey and applied consistently from then on, without editing the underlying semantic model.

## Evaluation

Measuring an agent means judging both its decision-making and its safety. The repository includes a golden test suite and an automated harness that spins up an isolated agent per case and grades the output with an LLM-as-a-judge, covering three things: cube discovery (does it route governed questions to governed metrics), raw table navigation (can it handle joins and aggregations when no cube fits), and hallucination prevention (does it refuse gracefully when asked for data that does not exist, such as a missing `return_reason` column, rather than fabricating it).

## Where This Is Going

This is a foundational phase, deliberately scoped to batch data over cold storage. Real-time integration and dynamic routing between hot and cold storage are natural next steps, and the decoupled architecture is designed to absorb them.

The interesting takeaway for me is that a reliable data assistant is less about a smarter model and more about the boundaries you draw around it. A governed semantic layer, a clear split between generation and execution, and a memory that learns do far more for trustworthiness than any single prompt.

The full walkthrough, including infrastructure setup, semantic modeling, the orchestrator, and the evaluation harness, is on GitHub.

* **GitHub:** [jaehyeon-kim/agentic-analytics-system](https://github.com/jaehyeon-kim/agentic-analytics-system)
