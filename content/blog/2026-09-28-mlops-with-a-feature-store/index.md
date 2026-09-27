---
title: "Learning MLOps with a Feature Store: A New Series"
date: 2026-09-28
draft: false
featured: true
comment: true
toc: true
series:
  - MLOps with a Feature Store
categories:
  - Machine Learning
  - Open Source
tags:
  - MLOps
  - Feature Store
  - Feast
  - MLflow
  - Apache Airflow
  - Apache Iceberg
  - odctl
  - dynamic-des
description: |
  I am teaching myself MLOps with Jim Dowling's book on feature stores, and rebuilding its three hands-on projects with open-source tools on a local odctl stack.
---

I am teaching myself MLOps with Jim Dowling's [*Building Machine Learning Systems with a Feature Store*](https://www.oreilly.com/library/view/building-machine-learning/9781098165222/). This series follows that work: I rebuild the book's hands-on projects with open-source tools, running on my laptop.

<!--more-->

## Why This Book

Rather than teaching one tool, this book teaches one way to build any ML system, and applies it to classic machine learning and to systems built on large language models alike: batch predictions, real-time predictions and agents.

It rests on one architecture, split into three kinds of pipeline, known as FTI pipelines:

- a **feature pipeline** turns raw data into features, the inputs a model learns from;
- a **training pipeline** turns features and labels into a model;
- an **inference pipeline** turns features and a model into predictions.

The pipelines never call each other. They share only two stores: a **feature store**, which keeps features so that training and prediction read exactly the same values, and a **model registry**, which keeps every trained model as a numbered version and marks the one in use. So each pipeline can be built, tested, scheduled and changed on its own.

## Three Projects

The book teaches through three systems, each adding something new:

1. **Air quality forecasting:** a batch system that predicts daily air pollution for the week ahead from weather forecasts.
2. **Credit card fraud detection:** a real-time system, with features computed from a stream of transactions.
3. **A personalised video recommender:** a real-time system modelled on TikTok, which retrieves and ranks videos for each user.

## Rebuilding on Open Source

The book builds its projects on Hopsworks, a platform from the author's company that bundles a feature store, a model registry and model serving. I am rebuilding each one with open-source tools instead:

| What the system needs | Open-source tool |
|---|---|
| Feature storage | Apache Iceberg tables |
| Feature store | Feast, with an online store in Valkey |
| Model registry and experiment tracking | MLflow |
| Scheduling the pipelines | Apache Airflow |
| Streaming features | Apache Kafka and Apache Flink |

All of them run locally with [odctl](https://github.com/jaehyeon-kim/odctl), a command-line tool I built that starts an open data stack with Docker Compose, as introduced in an [earlier post](/blog/2026-07-16-odctl-open-data-stack/). The data comes from simulations built with [dynamic-des](https://github.com/jaehyeon-kim/dynamic-des), a Python library I built for discrete-event simulations that stream their output to Kafka, files and Iceberg. So every project runs offline, and nothing needs a cloud account.

## What Comes Next

Each project gets its own post in this series, covering how the design maps onto open-source tools, what worked, and what broke along the way. I will share them as each one is ready.
