---
title: Kafka Development with Docker - Part 2 Kafka Management App
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
description: The command utilities of Apache Kafka are not convenient and don't support key tools such as connectors and schemas. Development can be easier with a good management app and it is desirable to integrate AWS features/services - IAM access control and MSK Connect/Glue Schema Registry. In this post, I'll introduce several Kafka management apps for Kafka development on AWS.
---

In the previous post, I illustrated how to create a topic and to produce/consume messages using the command utilities provided by Apache Kafka. However, it is not convenient e.g. when you need to consume serialized messages where their schemas are stored in a schema registry. Also, the utilities doesn't support to browser or manage key tools such as connectors and schemas. Therefore, it will be easier if we use a good Kafka management application for Kafka development. Moreover, it is desirable that the management app supports additional features, which are [IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html) of [Amazon MSK](https://aws.amazon.com/msk/) and integration with [Amazon MSK Connect](https://aws.amazon.com/msk/features/msk-connect/) and [AWS Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html). In this post, I'll introduce several Kafka management apps for Kafka development on AWS.


...

* [Part 1 Kafka Cluster Setup](blog/2023-05-04-kafka-development-with-docker-part-1)
* [Part 2 Kafka Management App](#) (this post)
* Part 3 Kafka Connect without Schema Registry
* Part 4 Glue Schema Registry
* Part 5 Kafka Connect with Glue Schema Registry
* Part 6 SSL Encryption
* Part 7 SSL Authentication
* Part 8 SASL Authentication
* Part 9 Kafka Authorization
* (More topics related to MSK, MSK Connect...)

## TO DO


|Application|IAM Access Control|MSK Connect|Glue Schema Registry|Note|
|:------|:---:|:---:|:---:|:---|
|[UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme)|✔|[❌](https://github.com/provectus/kafka-ui/issues/1311)|[⚠](https://docs.kafka-ui.provectus.io/configuration/serialization-serde#custom-pluggable-serde-registration)|UI for Apache Kafka is a free, open-source web UI to monitor and manage Apache Kafka clusters. It will remain free and open-source, without any paid features or subscription plans to be added in the future.|
|[kpow](https://kpow.io/)|✔|✔|✔|Kpow CE allows you to manage one Kafka Cluster, one Schema Registry, and one Connect Cluster, with the UI supporting a single user session at a time.|
|[Conduktor Desktop](https://www.conduktor.io/desktop/)|✔|✔|✔|The Free plan is limited to integrating 1 unsecure cluster (of a single broker) and restricted to browse 10 viewable topics.|

Others

* [AKHQ](https://akhq.io/)
* [Redpanda Console formerly Kowl](https://github.com/redpanda-data/console)
* [Kafdrop](https://github.com/obsidiandynamics/kafdrop)
