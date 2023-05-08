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
description: The command utilities of Apache Kafka are not convenient when developing Kafka. A Kafka management app can be a good companion. On top of helping monitor/manage Kafka-related resources, additional features are desirable for Kafka development on AWS, which covers IAM access control and integration with MSK Connect and Glue Schema Registry. In this post, I'll introduce several management apps for Kafka development on AWS.
---

In the previous post, I illustrated how to create a topic and to produce/consume messages using the command utilities provided by Apache Kafka. It is not convenient, however, for example, when you consume serialised messages where their schemas are stored in a schema registry. Also, the utilities don't support to browse or manage related resources such as connectors and schemas. Therefore, a Kafka management app can be a good companion, which helps manage Kafka-related resources as well as produce/consume messages easily. Moreover, additional features are desirable for developing Kafka on AWS, which covers [IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html) of [Amazon MSK](https://aws.amazon.com/msk/) and integration with [Amazon MSK Connect](https://aws.amazon.com/msk/features/msk-connect/) and [AWS Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html). In this post, I'll introduce several effective management apps for Kafka development on AWS.

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

## Overview of Kafka Management App

Generally good Kafka management apps support to monitor and manage one or more Kafka clusters. They also allow you to view and/or manage Kafka-related resources such as brokers, topics, consumer groups, connectors, schemas etc. Furthermore, they help produce/consume/search messages with default/custom serialisation and deserialisation methods. 

While the majority of Kafka management apps share the features mentioned above, we need additional features for developing Kafka on AWS. They cover IAM access control of Amazon MSK and integration with Amazon MSK Connect and AWS Glue Schema Registry. As far as I've searched, there are 3 management apps that support these features.

[UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme) is free and open-source, and multiple clusters can be registered to it. It supports IAM access control by default and Glue Schema registry integration is partially implementation, which means it doesn't seem to allow you to view/manage schemas while message deserialisation is implemented by [custom serde registration](https://docs.kafka-ui.provectus.io/configuration/serialization-serde#custom-pluggable-serde-registration). Besides, MSK Connect integration is yet to be in their roadmap. Note that the limited features wouldn't be critical as we can manage schemas/connectors on the associating AWS Console anyway.

Both [Kpow](https://kpow.io/) and [Conduktor Desktop](https://www.conduktor.io/desktop/) support all the features out-of-box. However, their free editions are limited to a single cluster, and the latter has a more strict restriction so that even we are not able to link our local Kafka cluster as it has 3 brokers. However, I find its paid edition is most intuitive and feature-rich, and it should be taken seriously when deciding an app for your team. 

Below shows a comparison of the 3 apps in terms of the features for Kafka development on AWS.

|Application|IAM Access Control|MSK Connect|Glue Schema Registry|Note|
|:------|:---:|:---:|:---:|:---|
|[UI for Apache Kafka (kafka-ui)](https://docs.kafka-ui.provectus.io/overview/readme)|✔|[❌](https://github.com/provectus/kafka-ui/issues/1311)|[⚠](https://docs.kafka-ui.provectus.io/configuration/serialization-serde#custom-pluggable-serde-registration)|UI for Apache Kafka is a free, open-source web UI to monitor and manage Apache Kafka clusters. It will remain free and open-source, without any paid features or subscription plans to be added in the future.|
|[Kpow](https://kpow.io/)|✔|✔|✔|[Kpow CE](https://docs.kpow.io/ce/) allows you to manage one Kafka Cluster, one Schema Registry, and one Connect Cluster, with the UI supporting a single user session at a time.|
|[Conduktor Desktop](https://www.conduktor.io/desktop/)|✔|✔|✔|The Free plan is limited to integrating 1 unsecure cluster (of a single broker) and restricted to browse 10 viewable topics.|

There are other popular Kafka management apps, and they are listed below for your information.

* [AKHQ](https://akhq.io/)
* [Redpanda Console formerly Kowl](https://github.com/redpanda-data/console)
* [Kafdrop](https://github.com/obsidiandynamics/kafdrop)

In the subsequent sections, I will introduce UI for Apache Kafka (kafka-ui) and Kpow. I assume the local Kafka cluster demonstrated in [Part 1]((blog/2023-05-04-kafka-development-with-docker-part-1)) is up and running.

## UI for Apache Kafka (kafka-ui)


## Kpow


## Summary