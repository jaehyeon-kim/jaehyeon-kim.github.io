---
title: How I Prepared for Confluent Certified Developer for Apache Kafka as a Non-Java Developer
date: 2023-05-11
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Kafka Development with Docker
categories:
  - General
tags: 
  - Apache Kafka
  - Confluent
authors:
  - JaehyeonKim
images: []
description: I recently obtained the Confluent Certified Developer for Apache Kafka (CCDAK) certification. It focuses on knowledge of developing applications that work with Kafka, and is targeted to developers and solutions architects. As it assumes Java APIs for development and testing, I am contacted to share how I prepared for it as a non-Java developer from time to time. I thought it would be better to write a post to summarise how I did it rather than answering to them individually. 
---

I recently obtained the [Confluent Certified Developer for Apache Kafka (CCDAK)](https://www.confluent.io/certification/) certification. It focuses on knowledge of developing applications that work with Kafka, and is targeted to developers and solutions architects. As it assumes Java APIs for development and testing, I am contacted to share how I prepared for it as a non-Java developer from time to time. I thought it would be better to write a post to summarise how I did it rather than answering to them individually. 

Before I decided to take the exam, I had some exposure to Kafka. One of them is building a data pipeline using *Change Data Capture (CDC)*, and it aimed to ingest data from a PostgreSQL DB into S3 using MSK Connect. Another project is developing a Kafka consumer that upserts into/deletes from multiple database tables. Although I was not sure if I would work on the Confluent platform, I decided to take the exam as I thought it would be a good chance to learn more on Apache Kafka and related technologies.

I searched online courses and found [Confluent Certified Developer for Apache Kafka (CCDAK)](https://acloudguru.com/course/confluent-certified-developer-for-apache-kafka-ccdak) from *A Cloud Grue*. I chose it as it (1) seems to cover all exam topics, (2) gives chances to apply course contents to real world scenarios on lab sessions, and (3) provides a practice test. It covers the following topics - *Kafka fundamentals, application design concepts, Kafka producer/consumer, Kafka Streams, Kafka Connect, Confluent Schema Registry, REST Proxy, ksqlDB, testing, security and monitoring*. The lectures are well-organised and mostly easy to follow. It is based on a Kafka cluster on 3 VMs, but I used a cluster on Docker instead. Using Docker made me confused on Kafka security (SSL authentication and ACL). I couldn't complete that chapter fully, but moved on as security is not covered in depth. 

Also, as I don't develop in Java, I couldn't follow some chapters on its own, and I had to convert them in Python. For Kafka producer and consumer, it was not difficult to do so using the [kafka-python](https://kafka-python.readthedocs.io/en/master/index.html) package as I used it on earlier projects. *Kafka Streams* is a bit tricky as there doesn't seem to be a Python package that matches it tightly. Although hands-on implementation is not required for the exam, I'd like to try on my own. After some investigation, I found several candidates for streams processing in Python - [Faust](https://faust-streaming.github.io/faust/), [Bytewax](https://bytewax.io/), and [PyFlink](https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/python/overview/). Among those, I chose *PyFlink* and implemented all examples and labs with it. If you don't use the *Kafka Streams* API in Java, I recommend you to try *Flink*. Recently [Confluent announced to acquire Immerok](https://www.confluent.io/blog/cloud-kafka-meets-cloud-flink-with-confluent-and-immerok/), a startup offering a fully managed service for Apache Flink. Maybe Flink questions will start to come up in the future.

After finishing the lectures, I did the practice test. The questions much simpler than the [sample questions](https://assets.confluent.io/m/1eb934ef619a0ccc/original/20200331-Developer_Certification_Sample_Questions.pdf) from Confluent. Then I bought a [practice test course](https://www.udemy.com/course/confluent-certified-developer-for-apache-kafka/) from Udemy. It provides 3 practice tests, and I was able to gain additional knowledge while going through those. I think you would be okay if you pass the practice exams.

I hope you find this post useful and good luck with your exam!
