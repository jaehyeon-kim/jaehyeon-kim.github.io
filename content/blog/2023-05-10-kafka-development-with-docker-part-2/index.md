---
title: Kafka Development with Docker - Part 2 Kafka Management UI
date: 2023-05-10
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Kafka Development with Docker
categories:
  - Apache Kafka
tags: 
  - Apache Kafka
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: Apache Kafka is one of the key technologies for modern data streaming architectures on AWS. Developing and testing Kafka-related applications can be easier using Docker and Docker Compose. In this series of posts, I will demonstrate reference implementations of those applications in Dockerized environments.
---

...

* [Part 1 Kafka Cluster Setup](blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Kafka Management UI](#) (this post)
* Part 3 Kafka Connect without Schema Registry
* Part 4 Glue Schema Registry
* Part 5 Kafka Connect with Glue Schema Registry
* Part 6 SSL Encryption
* Part 7 SSL Authentication
* Part 8 SASL Authentication
* Part 9 Kafka Authorization
* (More topics related to MSK, MSK Connect...)

## TO DO

IAM Authentication
MSK Connect
Glue Schema Registry





|Application|IAM Auth|MSK Connect|Glue Schema Registry|Note|
|:------|:---:|:---:|:---:|:---|
|[UI for Apache Kafka (kafka-ui)](https://github.com/provectus/kafka-ui)|✔|[❌](https://github.com/provectus/kafka-ui/issues/1311)|✔|Support multiple clusters|
|[kpow](https://kpow.io/)|✔|✔|✔|Single cluster if community edition|
|[Conduktor Desktop](https://www.conduktor.io/desktop/)|✔|✔|✔|Single cluster single broker|

Others

* [AKHQ](https://akhq.io/)
* [Redpanda Console formerly Kowl](https://github.com/redpanda-data/console)
* [Kafdrop](https://github.com/obsidiandynamics/kafdrop)
