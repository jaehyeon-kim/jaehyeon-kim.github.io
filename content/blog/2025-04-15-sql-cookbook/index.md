---
title: Run Flink SQL Cookbook in Docker
date: 2025-04-15
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
  - Data Streaming
tags: 
  - Apache Flink
  - Docker
  - Docker Compose
  - Flink SQL
  - Flink SQL Client
authors:
  - JaehyeonKim
images: []
description:
---

The [Flink SQL Cookbook](https://github.com/ververica/flink-sql-cookbook) by Ververica is a hands-on, example-rich guide to mastering [Apache Flink SQL](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sql/overview/) for real-time stream processing. It offers a wide range of self-contained recipes, from basic queries and table operations to more advanced use cases like windowed aggregations, complex joins, user-defined functions (UDFs), and pattern detection. These examples are designed to be run on the Ververica Platform, and as such, the cookbook doesn't include instructions for setting up a Flink cluster.

To help you run these recipes locally and explore Flink SQL without external dependencies, this post walks through setting up a fully functional local Flink cluster using Docker Compose. With this setup, you can experiment with the cookbook examples right on your machine.

<!--more-->

## Flink Cluster on Docker

The cookbook generates sample data using the [Flink SQL Faker Connector](https://github.com/knaufk/flink-faker), which allows for realistic, randomized record generation. To streamline the setup, we use a custom Docker image where the connector's JAR file is downloaded into the `/opt/flink/lib/` directory. This approach eliminates the need to manually register the connector each time we launch the [Flink SQL client](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sqlclient/), making it easier to jump straight into experimenting with the cookbook's examples. The source for this post is available in this [**GitHub repository**](https://github.com/jaehyeon-kim/flink-demos/tree/master/flink-sql-cookbook).

```Dockerfile
FROM flink:1.20.1

# add faker connector
RUN wget -P /opt/flink/lib/ \
  https://github.com/knaufk/flink-faker/releases/download/v0.5.3/flink-faker-0.5.3.jar
```

We deploy a local Apache Flink cluster using Docker Compose. It defines one `JobManager` and three `TaskManagers`, all using the custom image. The `JobManager` handles coordination and exposes the Flink web UI on port 8081, while each `TaskManager` provides 10 task slots for parallel processing. All components share a custom network and use a filesystem-based state backend with checkpointing and savepoint directories configured for local testing. A health check ensures the `JobManager` is ready before `TaskManagers` start.

```yaml
version: "3"

services:
  jobmanager:
    image: flink-sql-cookbook
    build: .
    command: jobmanager
    container_name: jobmanager
    ports:
      - "8081:8081"
    networks:
      - cookbook
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        state.savepoints.dir: file:///tmp/flink-savepoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000
        rest.flamegraph.enabled: true
        web.backpressure.refresh-interval: 10000
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/config"]
      interval: 5s
      timeout: 5s
      retries: 5

  taskmanager-1:
    image: flink-sql-cookbook
    build: .
    command: taskmanager
    container_name: taskmanager-1
    networks:
      - cookbook
    depends_on:
      jobmanager:
        condition: service_healthy
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 10
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        state.savepoints.dir: file:///tmp/flink-savepoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000

  taskmanager-2:
    image: flink-sql-cookbook
    build: .
    command: taskmanager
    container_name: taskmanager-2
    networks:
      - cookbook
    depends_on:
      jobmanager:
        condition: service_healthy
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 10
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        state.savepoints.dir: file:///tmp/flink-savepoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000

  taskmanager-3:
    image: flink-sql-cookbook
    build: .
    command: taskmanager
    container_name: taskmanager-3
    networks:
      - cookbook
    depends_on:
      jobmanager:
        condition: service_healthy
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: jobmanager
        taskmanager.numberOfTaskSlots: 10
        state.backend: filesystem
        state.checkpoints.dir: file:///tmp/flink-checkpoints
        state.savepoints.dir: file:///tmp/flink-savepoints
        heartbeat.interval: 1000
        heartbeat.timeout: 5000

networks:
  cookbook:
    name: flink-sql-cookbook
```

The Flink cluster can be deployed as follows.

```bash
# start containers
$ docker compose up -d

# list containers
$ docker-compose ps
# NAME                COMMAND                  SERVICE             STATUS              PORTS
# jobmanager          "/docker-entrypoint.…"   jobmanager          running (healthy)   6123/tcp, 0.0.0.0:8081->8081/tcp, :::8081->8081/tcp
# taskmanager-1       "/docker-entrypoint.…"   taskmanager-1       running             6123/tcp, 8081/tcp
# taskmanager-2       "/docker-entrypoint.…"   taskmanager-2       running             6123/tcp, 8081/tcp
# taskmanager-3       "/docker-entrypoint.…"   taskmanager-3       running             6123/tcp, 8081/tcp
```

## Flink SQL Client

We can start the SQL client from the `JobManager` container as shown below.

```bash
$ docker exec -it jobmanager /opt/flink/bin/sql-client.sh
```

On the SQL shell, we can execute Flink SQL statements.

```sql
-- // create a temporary table
CREATE TEMPORARY TABLE heros (
  `name` STRING,
  `power` STRING,
  `age` INT
) WITH (
  'connector' = 'faker',
  'fields.name.expression' = '#{superhero.name}',
  'fields.power.expression' = '#{superhero.power}',
  'fields.power.null-rate' = '0.05',
  'fields.age.expression' = '#{number.numberBetween ''0'',''1000''}'
);
-- [INFO] Execute statement succeeded.

-- list tables
SHOW TABLES;
-- +------------+
-- | table name |
-- +------------+
-- |      heros |
-- +------------+
-- 1 row in set

-- query records from the heros table
-- hit 'q' to exit the record view
SELECT * FROM heros;

-- quit sql shell
quit;
```

![](featured.gif#center)

The associating Flink job of the SELECT query can be found on the Flink Web UI at `http://localhost:8081`.

![](web-ui.png#center)

## Caveat

Some examples in the cookbook rely on an older version of the Faker connector, and as a result, certain directives used in the queries are no longer supported in the latest version—leading to runtime errors. For instance, the following query fails because the `#{Internet.userAgentAny}` directive has been removed. To resolve this, you can either remove the `user_agent` field from the query or replace the outdated directive with a supported one, such as using `regexify` to generate similar values.

```sql
CREATE TABLE server_logs ( 
    client_ip STRING,
    client_identity STRING, 
    userid STRING, 
    user_agent STRING,
    log_time TIMESTAMP(3),
    request_line STRING, 
    status_code STRING, 
    size INT
) WITH (
  'connector' = 'faker', 
  'fields.client_ip.expression' = '#{Internet.publicIpV4Address}',
  'fields.client_identity.expression' =  '-',
  'fields.userid.expression' =  '-',
  'fields.user_agent.expression' = '#{Internet.userAgentAny}',
  'fields.log_time.expression' =  '#{date.past ''15'',''5'',''SECONDS''}',
  'fields.request_line.expression' = '#{regexify ''(GET|POST|PUT|PATCH){1}''} #{regexify ''(/search\.html|/login\.html|/prod\.html|cart\.html|/order\.html){1}''} #{regexify ''(HTTP/1\.1|HTTP/2|/HTTP/1\.0){1}''}',
  'fields.status_code.expression' = '#{regexify ''(200|201|204|400|401|403|301){1}''}',
  'fields.size.expression' = '#{number.numberBetween ''100'',''10000000''}'
);
```

![](sql-error.gif#center)