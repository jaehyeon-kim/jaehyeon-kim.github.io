---
title: Data Lake Demo using Change Data Capture (CDC) on AWS – Part 3 Implement Data Lake
date: 2021-12-19
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Data Lake Demo Using Change Data Capture
categories:
  - Data Streaming
  - Data Engineering
  - Data Integration
tags: 
  - AWS
  - Amazon EMR
  - Amazon MSK
  - Apache Hudi
  - Apache Kafka
  - Kafka Connect
  - Change Data Capture (CDC)
  - Debezium
authors:
  - JaehyeonKim
images: []
cevo: 7
description: Change data capture (CDC) on Amazon MSK and ingesting data using Apache Hudi on Amazon EMR can be used to build an efficient data lake solution. In this post, we'll build a Hudi DeltaStramer app on Amazon EMR and use the resulting Hudi table with Athena and Quicksight to build a dashboard.
---

In the [previous post](/blog/2021-12-12-datalake-demo-part2), we created a VPC that has private and public subnets in 2 availability zones in order to build and deploy the data lake solution on AWS. NAT instances are created to forward outbound traffic to the internet and a VPN bastion host is set up to facilitate deployment. An [Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html) cluster is deployed to host the source database and a Python command line app is used to create the database. To develop data ingestion using CDC, an [Amazon MSK](https://aws.amazon.com/msk/) cluster is deployed and the [Debezium source](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) and [Lenses S3 sink](https://lenses.io/blog/2020/11/new-kafka-to-S3-connector/) connectors are created on [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/). We also confirmed the order creation and update events are captured as expected. As the last part of this series, we'll build an [Apache Hudi DeltaStreamer](https://hudi.apache.org/docs/writing_data/#deltastreamer) app on [Amazon EMR](https://aws.amazon.com/emr/) and use the resulting Hudi table with [Amazon Athena](https://aws.amazon.com/athena/) and [Amazon Quicksight](https://aws.amazon.com/quicksight/) to build a dashboard.

* [Part 1 Local Development](/blog/2021-12-05-datalake-demo-part1)
* [Part 2 Implement CDC](/blog/2021-12-12-datalake-demo-part2)
* [Part 3 Implement Data Lake](#) (this post)

## Architecture

As described in a [Red Hat IT topics article](https://www.redhat.com/en/topics/integration/what-is-change-data-capture), _change data capture (CDC) is a proven data integration pattern to track when and what changes occur in data then alert other systems and services that must respond to those changes. Change data capture helps maintain consistency and functionality across all systems that rely on data_.

The primary use of CDC is to enable applications to respond almost immediately whenever data in databases change. Specifically its use cases cover microservices integration, data replication with up-to-date data, building time-sensitive analytics dashboards, auditing and compliance, cache invalidation, full-text search and so on. There are a number of approaches for CDC - polling, dual writes and log-based CDC. Among those, [log-based CDC has advantages](https://debezium.io/blog/2018/07/19/advantages-of-log-based-change-data-capture/) to other approaches.

Both [Amazon DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) and [Debezium](https://debezium.io/) implement log-based CDC. While the former is a managed service, the latter can be deployed to a Kafka cluster as a (source) connector. It uses [Apache Kafka](https://www.redhat.com/en/topics/integration/what-is-apache-kafka) as a messaging service to deliver database change notifications to the applicable systems and applications. Note that Kafka Connect is a tool for streaming data between Apache Kafka and other data systems by connectors in a scalable and reliable way. In AWS, we can use [Amazon MSK](https://aws.amazon.com/msk/) and [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/) for building a Debezium based CDC solution.

Data replication to data lakes using CDC can be much more effective if [data is stored to a format](https://lakefs.io/hudi-iceberg-and-delta-lake-data-lake-table-formats-compared/) that supports atomic transactions and consistent updates. Popular choices are [Apache Hudi](https://hudi.apache.org/), [Apache Iceberg](https://iceberg.apache.org/) and [Delta Lake](https://delta.io/). Among those, Apache Hudi can be a good option as it is [well-integrated with AWS services](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hudi.html).

Below shows the architecture of the data lake solution that we will be building in this series of posts.

![](00-01-architecture.png#center)

1. Employing the [transactional outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html), the source database publishes change event records to the CDC event table. The event records are generated by triggers that listen to insert and update events on source tables. See the Source Database section of the [first post of this series](/blog/2021-12-05-datalake-demo-part1) for details.
2. CDC is implemented in a streaming environment and [Amazon MSK](https://aws.amazon.com/msk/) is used to build the streaming infrastructure. In order to process the real-time CDC event records, a source and sink connectors are set up in [Amazon MSK Connect](https://aws.amazon.com/msk/features/msk-connect/). The [Debezium connector for PostgreSQL](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) is used as the source connector and the [Lenses S3 connector](https://lenses.io/blog/2020/11/new-kafka-to-S3-connector/) is used as the sink connector. The sink connector pushes messages to a S3 bucket.
3. [Hudi DeltaStreamer](https://hudi.apache.org/docs/writing_data/#deltastreamer) is run on [Amazon EMR](https://aws.amazon.com/emr/). As a spark application, it reads files from the S3 bucket and upserts Hudi records to another S3 bucket. The Hudi table is created in the AWS Glue Data Catalog.
4. The Hudi table is queried in [Amazon Athena](https://aws.amazon.com/athena/) while the table is registered in the AWS Glue Data Catalog.
5. Dashboards are created in [Amazon Quicksight](https://aws.amazon.com/quicksight/) where the dataset is created using Amazon Athena.

In this post, we'll build a Hudi DeltaStreamer app on Amazon EMR and use the resulting Hudi table with Athena and Quicksight to build a dashboard.


## Infrastructure

In the [previous post](/blog/2021-12-12-datalake-demo-part2), we created a VPC in the Sydney region, which has private and public subnets in 2 availability zones. We also created NAT instances in each availability zone to forward outbound traffic to the internet and a VPN bastion host to access resources in the private subnets. An EMR cluster will be deployed to one of the private subnets of the VPC. 


### EMR Cluster

We'll create the EMR cluster with the following configurations.
* It is created with the latest EMR release - _semr-6.4.0_.
* It has 1 master and 2 core instance groups - their instance types are _m4.large_.
    * Both the instance groups have additional security groups that allow access from the VPN bastion host.
* It installs Hadoop, Hive, Spark, Presto, Hue and Livy. 
* It uses the AWS Glue Data Catalog as the metastore for Hive and Spark.

The last configuration is important to register the Hudi table to the Glue Data Catalog so that it can be accessed from other AWS services such as Athena and Quicksight. The cluster is created by CloudFormation and the template also creates a Glue database (_datalake_) in which the Hudi table will be created. The template can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/infra/main/emr.yaml).

Once the EMR cluster is ready, we can access the master instance as shown below. Note don't forget to connect the VPN bastion host using the SoftEther VPN client program.

![](ssh-bastion.png#center)

## Hudi Table

### Source Schema 

Kafka only transfers data in byte format and data verification is not performed at the cluster level. As producers and consumers do not communicate with each other, we need a schema registry that sits outside a Kafka cluster and handles distribution of schemas. Although [it is recommended](https://debezium.io/documentation/reference/stable/configuration/avro.html) to associate with a schema registry, we avoid using it because it requires either an [external service](https://docs.confluent.io/platform/current/schema-registry/index.html) or a [custom server](https://www.apicur.io/registry/) to host a schema registry. Ideally it'll be good if we're able to use the [AWS Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html), but unfortunately it doesn't support a REST interface and cannot be used at the moment.

In order to avoid having a schema registry, we use the built-in JSON converter (`org.apache.kafka.connect.json.JsonConverter`) as the key and value converters for the Debezium source and S3 sink connectors. The resulting value schema of our CDC event message is of the _struct_ type, and it can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/hudi/note/schema-demo.datalake.cdc_events.json). However, it is not supported by the DeltaStreamer utility that we'll be using to generate the Hudi table. A quick fix is replacing it with the Avro schema, and we can generate it with the local docker-compose environment that we discussed in the [first post of this series](/blog/2021-12-05-datalake-demo-part1). Once the local environment is up and running, we can create the Debezium source connector with the Avro converter (`io.confluent.connect.avro.AvroConverter`) as shown below.


```bash
curl -i -X POST -H "Accept:application/json" -H  "Content-Type:application/json" \
  http://localhost:8083/connectors/ -d @connector/local/source-debezium-avro.json
```


Then we can download the value schema in the Schema tab of the topic. 

![](avro-schema.png#center)


The schema file of the CDC event messages can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/hudi/config/schema-msk.datalake.cdc_events.avsc). Note that, although we use it as the source schema file for the DeltaStreamer app, we keep using the JSON converter for the Kafka connectors as we don't set up a schema registry


### DeltaStreamer

The [HoodieDeltaStreamer](https://hudi.apache.org/docs/writing_data#deltastreamer) utility (part of hudi-utilities-bundle) provides the way to ingest from different sources such as DFS or Kafka, with the following capabilities.
* _Exactly once ingestion of new events from Kafka, [incremental imports](https://sqoop.apache.org/docs/1.4.2/SqoopUserGuide#_incremental_imports) from Sqoop or output of HiveIncrementalPuller or files under a DFS folder_
* _Support JSON, AVRO or a custom record types for the incoming data_
* _Manage checkpoints, rollback & recovery_
* _Leverage AVRO schemas from DFS or Confluent [schema registry](https://github.com/confluentinc/schema-registry)._
* _Support for plugging in transformations_

As shown below, it runs as a Spark application. Some important options are illustrated below.
* Hudi-related jar files are specified directly because Amazon EMR release version 5.28.0 and later installs Hudi components by default.
    * [Hudi 0.8.0 is installed for EMR release 6.4.0](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hudi.html). 
* It is deployed by the [cluster deploy mode](https://spark.apache.org/docs/latest/cluster-overview.html) where the driver and executor have 2G and 4G of memory respectively.
* [Copy on Write (CoW)](https://hudi.apache.org/docs/concepts/#copy-on-write-table#what-is-the-difference-between-copy-on-write-cow-vs-merge-on-read-mor-storage-types) is configured as the storage type.
* Additional Hudi properties are saved in S3 (`cdc_events_deltastreamer_s3.properties`) - it'll be discussed below. 
* The JSON type is configured as the source file type - note we use the built-in JSON converter for the Kafka connectors.
* The S3 target base path indicates the place where the Hudi data is stored, and the target table configures the resulting table.
    * As we enable the AWS Glue Data Catalog as the Hive metastore, it can be accessed in Glue. 
* The file-based schema provider is configured.
    * The Avro schema file is referred to as the source schema file in the additional Hudi property file.
* Hive sync is enabled, and the minimum sync interval is set to 5 seconds.
* It is set to run continuously and the [default UPSERT operation](https://hudi.apache.org/docs/writing_data/#write-operations) is chosen.


```bash
spark-submit --jars /usr/lib/spark/external/lib/spark-avro.jar,/usr/lib/hudi/hudi-utilities-bundle.jar \
    --master yarn \
    --deploy-mode cluster \
    --driver-memory 2g \
    --executor-memory 4g \
    --conf spark.sql.catalogImplementation=hive \
    --conf spark.serializer=org.apache.spark.serializer.KryoSerializer \
    --class org.apache.hudi.utilities.deltastreamer.HoodieDeltaStreamer /usr/lib/hudi/hudi-utilities-bundle.jar \
    --table-type COPY_ON_WRITE \
    --source-ordering-field __source_ts_ms \
    --props "s3://data-lake-demo-cevo/hudi/config/cdc_events_deltastreamer_s3.properties" \
    --source-class org.apache.hudi.utilities.sources.JsonDFSSource \
    --target-base-path "s3://data-lake-demo-cevo/hudi/cdc-events/" \
    --target-table datalake.cdc_events \
    --schemaprovider-class org.apache.hudi.utilities.schema.FilebasedSchemaProvider \
    --enable-sync \
    --min-sync-interval-seconds 5 \
    --continuous \
    --op UPSERT
```

Below shows the additional Hudi properties. For Hive sync, the database, table, partition fields and JDBC URL are specified. Note that the private IP address of the master instance is added to the host of the JDBC URL. It is required when submitting the application by the cluster deploy mode. By default, the host is set to localhost and the connection failure error will be thrown if the app doesn't run in the master. The remaining Hudi datasource properties are to configure the [primary key of the Hudi table](https://hudi.apache.org/blog/2021/02/13/hudi-key-generators/) - every record in Hudi is uniquely identified by a pair of record key and partition path fields. The Hudi DeltaStreamer properties specify the source schema file and the S3 location where the source data files exist. More details about the configurations can be found in the [Hudi website](https://hudi.apache.org/docs/configurations/).


```properties
# ./hudi/config/cdc_events_deltastreamer_s3.properties
## base properties
hoodie.upsert.shuffle.parallelism=2
hoodie.insert.shuffle.parallelism=2
hoodie.delete.shuffle.parallelism=2
hoodie.bulkinsert.shuffle.parallelism=2

## datasource properties
hoodie.datasource.hive_sync.database=datalake
hoodie.datasource.hive_sync.table=cdc_events
hoodie.datasource.hive_sync.partition_fields=customer_id,order_id
hoodie.datasource.hive_sync.partition_extractor_class=org.apache.hudi.hive.MultiPartKeysValueExtractor
hoodie.datasource.hive_sync.jdbcurl=jdbc:hive2://10.100.22.160:10000
hoodie.datasource.write.recordkey.field=order_id
hoodie.datasource.write.partitionpath.field=customer_id,order_id
hoodie.datasource.write.keygenerator.class=org.apache.hudi.keygen.ComplexKeyGenerator
hoodie.datasource.write.hive_style_partitioning=true
# only supported in Hudi 0.9.0+
# hoodie.datasource.write.drop.partition.columns=true

## deltastreamer properties
hoodie.deltastreamer.schemaprovider.source.schema.file=s3://data-lake-demo-cevo/hudi/config/schema-msk.datalake.cdc_events.avsc
hoodie.deltastreamer.source.dfs.root=s3://data-lake-demo-cevo/cdc-events/

## file properties
# 1,024 * 1,024 * 128 = 134,217,728 (128 MB)
hoodie.parquet.small.file.limit=134217728
```

### EMR Steps

While it is possible to submit the application in the master instance, it can also be submitted as an EMR step. As an example, a simple version of the app is submitted as shown below. The JSON file that configures the step can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/hudi/steps/cdc-events-simple.json).


```bash
aws emr add-steps \
  --cluster-id <cluster-id> \
  --steps file://hudi/steps/cdc-events-simple.json
```

Once the step is added, we can see its details on the EMR console.

![](steps.png#center)

### Glue Table

Below shows the Glue tables that are generated by the DeltaStreamer apps. The main table (_cdc_events_) is by submitting the app on the master instance while the simple version is by the EMR step.

![](glue-tables-01.png#center)

We can check the details of the table in Athena. When we run the describe query, it shows column and partition information. As expected, it has 2 partition columns and additional Hudi table meta information is included as extra columns.

![](glue-tables-02.png#center)

## Dashboard

Using the Glue table, we can create dashboards in Quicksight. As an example, a dataset of order items is created using Athena as illustrated in the [Quicksight documentation](https://docs.aws.amazon.com/quicksight/latest/user/create-a-data-set-athena.html). As the order items column in the source table is JSON, custom SQL is chosen so that it can be preprocessed in a more flexible way. The following SQL statement is used to create the dataset. First it parses the order items column and then flattens the array elements into rows. Also, the revenue column is added as a calculated field.


```sql
WITH raw_data AS (
    SELECT
        customer_id,
        order_id,
        transform(
        CAST(json_parse(order_items) AS ARRAY(MAP(varchar, varchar))),
        x -> CAST(ROW(x['discount'], x['quantity'], x['unit_price']) 
                AS ROW(discount decimal(6,2), quantity decimal(6,2), unit_price decimal(6,2)))
        ) AS order_items
    from datalake.cdc_events
), flat_data AS (
	SELECT customer_id,
		  order_id,
		  item
	FROM raw_data
	CROSS JOIN UNNEST(order_items) AS t(item)
)
SELECT customer_id,
       order_id,
       item.discount,
       item.quantity,
       item.unit_price
FROM flat_data
```


A demo dashboard is created using the order items dataset as shown below. The pie chart on the left indicates there are 3 big customers and the majority of revenue is earned by the top 20 customers. The scatter plot on the right shows a more interesting story. It marks the average quantity and revenue by customers and the dots are scaled by the number of orders - the more orders, the larger the size of the dot. While the 3 big customers occupy the top right area, 5 potentially profitable customers are identified. They do not purchase frequently but tend to buy expensive items, resulting in the average revenue being higher. We may investigate them further if a promotional event may be appropriate to make them purchase more frequently in the future.


![](dashboard.png#center)

## Conclusion

In this post, we created an EMR cluster and developed a DeltaStreamer app that can be used to _upsert_ records to a Hudi table. Being sourced as an Athena dataset, the records of the table are used by a Quicksight dashboard. Over the series of posts we have built an effective end-to-end data lake solution while combining various AWS services and open source tools. The source database is hosted in an Aurora PostgreSQL cluster and a change data capture (CDC) solution is built on Amazon MSK and MSK Connect. With the CDC output files in S3, a DeltaStreamer app is developed on Amazon EMR to build a Hudi table. The resulting table is used to create a dashboard with Amazon Athena and Quicksight.
