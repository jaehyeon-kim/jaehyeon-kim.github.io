---
title: "Data Streaming and Machine Learning Projects That Run on Your Laptop"
date: 2026-09-30
draft: false
featured: false
comment: true
toc: true
categories:
  - Data Engineering
  - Machine Learning
  - Open Source
tags:
  - Apache Kafka
  - Apache Flink
  - MLOps
  - odctl
  - dynamic-des
  - Benchtop
description: |
  Small data engineering, stream processing, machine learning and MLOps projects that run on a laptop from a fresh clone, each explaining the system it builds.
---

Reading about a data tool only goes so far. The hard part is getting several tools to run together and seeing how data moves between them. [Benchtop](https://github.com/jaehyeon-kim/benchtop) is a collection of small, hands-on demos for data engineering, stream processing, machine learning, AI engineering and MLOps. Each demo runs locally on the odctl stack, and works from a fresh clone of the repository, with nothing to install beforehand but Docker and uv. Each one builds a working system from open-source tools and explains the ideas behind it, so you learn a tool by running it rather than only reading about it.

<!--more-->

## Why One Repository

My earlier examples were spread across several repositories, each with its own setup. Some needed a cloud account, and some had drifted out of date with the tools they used. Benchtop brings them together under one set of rules:

- **Each project stands on its own.** It has its own folder, its own README and its own dependencies, and you can read and run it without the others.
- **Everything runs locally.** No step calls a cloud service, so a project costs nothing to run and works offline.
- **Each project teaches.** Its README walks through the steps, and says what to run and what to look at. A `docs` folder explains the concepts behind it from the start, for readers who are new to the tools.
- **Each project is tested.** Its unit tests need none of the services, and GitHub runs them for every project on every push.

## What Every Project Shares

Two tools of mine sit underneath every project.

[odctl](https://github.com/jaehyeon-kim/odctl) starts an open data stack with Docker Compose, as introduced in an [earlier post](/blog/2026-07-16-odctl-open-data-stack/). Each project starts only the services it needs, such as PostgreSQL, Kafka, Flink or Valkey, with one command like `odctl up kafka-lite flink-lite postgres`. The same addresses and credentials work in every project, so there is nothing to configure.

[dynamic-des](https://github.com/jaehyeon-kim/dynamic-des) ([documentation](https://jaehyeon.me/dynamic-des/)) is a Python library for discrete-event simulations that stream their output to Kafka, PostgreSQL and Iceberg. Most projects use it to produce their data: a shop where visitors arrive, browse and buy, or a game where players join teams and score. Its parameters can change while it runs, so you can double the visitors or send the warehouse pickers home, and watch the rest of the system respond.

## Projects

The projects are listed from the fewest services to the most, and each adds one new idea, so reading them in order is the gentlest path:

1. **[live-dashboard](https://github.com/jaehyeon-kim/benchtop/tree/main/live-dashboard):** two dashboards that update themselves as a simulated shop takes orders. You learn how a server pushes new data to a web page as it arrives, with WebSockets, and build the same dashboard in Streamlit and in Next.js. A series of three posts starts with the [data producer](/blog/2025-02-18-realtime-dashboard-1/).
2. **[ecommerce-cdc](https://github.com/jaehyeon-kim/benchtop/tree/main/ecommerce-cdc):** every change to a shop's database, captured as it happens and saved as files. You learn change data capture: reading a database's own log of changes with Debezium, rather than querying its tables. The [post](/blog/2026-10-01-ecommerce-cdc-debezium-kafka-connect/) walks through it.
3. **[order-streams](https://github.com/jaehyeon-kim/benchtop/tree/main/order-streams):** a stream of orders, first sent and read by small programs, then summarised every few seconds. You learn how Kafka moves messages, and two ways to process a stream as it flows, Kafka Streams and Flink, all in Kotlin. A series of five posts starts with [Kafka clients with JSON](/blog/2025-05-20-kotlin-getting-started-kafka-json-clients/).
4. **[game-leaderboard](https://github.com/jaehyeon-kim/benchtop/tree/main/game-leaderboard):** live leaderboards for a simulated mobile game. You learn to write Flink SQL queries that never finish and keep their answer up to date as scores arrive, including late scores and top 10 rankings. The [post](/blog/2026-10-02-game-leaderboard-flink-sql/) walks through it.
5. **[product-recommender](https://github.com/jaehyeon-kim/benchtop/tree/main/product-recommender):** a shop that learns which products to show each visitor from what they click. You learn contextual bandits, first in plain Python, then split into a live service and a Flink job that trains the models. The [prototype](/blog/2026-01-29-prototype-recommender-with-python/) and [production](/blog/2026-02-23-productionize-recommender-with-eda/) posts explain it.
6. **[MLOps with a Feature Store](/blog/2026-09-28-mlops-with-a-feature-store/):** a series that rebuilds the three projects in Jim Dowling's book on feature stores with open-source tools. The first, [air-quality](https://github.com/jaehyeon-kim/benchtop/tree/main/air-quality), forecasts daily air pollution for the week ahead. Fraud detection and a video recommender will follow.

Three of these, live-dashboard, order-streams and product-recommender, first appeared in an older repository. They now run on odctl, and their posts are updated to match.

## Getting Started

You need Docker, [uv](https://docs.astral.sh/uv/) for Python, and a copy of the repository:

```bash
git clone https://github.com/jaehyeon-kim/benchtop.git
```

Each project is one folder, and the root holds only the checks they share:

```
benchtop/
├── live-dashboard/
├── ecommerce-cdc/
├── order-streams/
├── game-leaderboard/
├── product-recommender/
├── air-quality/
├── ...
```

Inside, every Python project has the same core. game-leaderboard, for example:

```
game-leaderboard/
├── README.md          the steps: what to run and what to look at
├── docs/              the concepts behind it, and its data
├── images/            the architecture diagram and screenshots
├── leaderboard/       the code, one folder per part
├── tests/             unit tests that need none of the services
└── requirements.txt
```

Some projects add a folder for one more part: `nextjs/` for live-dashboard's Next.js dashboard, `dags/` for air-quality's Airflow pipelines, and `recsys-trainer/` for product-recommender's Flink job, written in Kotlin. order-streams is written in Kotlin throughout and built with Gradle, so it has one folder per application in place of a Python package.

Pick a project, open its folder, and follow its README from the top. Each README ends with a clean-up command that removes what the project created and keeps the services running, so you can move on to the next project without starting again.
