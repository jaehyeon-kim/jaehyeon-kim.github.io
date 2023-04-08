---
title: Data Lake Demo using Change Data Capture (CDC) on AWS – Part 2 Implement CDC
date: 2021-12-12
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Data Lake Demo Using Change Data Capture
categories:
  - Data Engineering
tags: 
  - AWS
  - Amazon EMR
  - Amazon MSK
  - Amazon MSK Connect
  - Apache Spark
  - Apache Hudi
  - Apache Kafka
  - Change Data Capture
  - Data Lake
  - Docker
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 6
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/data-lake-demo-using-cdc-part-2/).

In the [previous post](/blog/2021-12-05-datalake-demo-part1), we discussed a data lake solution where data ingestion is performed using [change data capture (CDC)](https://www.redhat.com/en/topics/integration/what-is-change-data-capture#what-is-cdc) and the output files are _upserted_ to an [Apache Hudi](https://hudi.apache.org/) table. Being registered to [Glue Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/populate-data-catalog.html), it can be used for ad-hoc queries and report/dashboard creation. The [Northwind database](https://docs.yugabyte.com/latest/sample-data/northwind/) is used as the source database and, following the [transactional outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html), order-related changes are _upserted _to an outbox table by triggers. The data ingestion is developed using Kafka connectors in the [local Confluent platform](https://docs.confluent.io/platform/current/quickstart/ce-docker-quickstart.html) where the [Debezium for PostgreSQL](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) is used as the source connector and the [Lenses S3 sink connector](https://lenses.io/blog/2020/11/new-kafka-to-S3-connector/) is used as the sink connector. We confirmed the order creation and update events are captured as expected, and it is ready for production deployment. In this post, we'll build the CDC part of the solution on AWS using [Amazon MSK](https://aws.amazon.com/msk/) and [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/).

* [Part 1 Local Development](/blog/2021-12-05-datalake-demo-part1)
* [Part 2 Implement CDC](#) (this post)
* [Part 3 Implement Data Lake](/blog/2021-12-19-datalake-demo-part3)

## Architecture

As described in a [Red Hat IT topics article](https://www.redhat.com/en/topics/integration/what-is-change-data-capture), _change data capture (CDC) is a proven data integration pattern to track when and what changes occur in data then alert other systems and services that must respond to those changes. Change data capture helps maintain consistency and functionality across all systems that rely on data_.

The primary use of CDC is to enable applications to respond almost immediately whenever data in databases change. Specifically its use cases cover microservices integration, data replication with up-to-date data, building time-sensitive analytics dashboards, auditing and compliance, cache invalidation, full-text search and so on. There are a number of approaches for CDC - polling, dual writes and log-based CDC. Among those, [log-based CDC has advantages](https://debezium.io/blog/2018/07/19/advantages-of-log-based-change-data-capture/) to other approaches.

Both [Amazon DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) and [Debezium](https://debezium.io/) implement log-based CDC. While the former is a managed service, the latter can be deployed to a Kafka cluster as a (source) connector. It uses [Apache Kafka](https://www.redhat.com/en/topics/integration/what-is-apache-kafka) as a messaging service to deliver database change notifications to the applicable systems and applications. Note that Kafka Connect is a tool for streaming data between Apache Kafka and other data systems by connectors in a scalable and reliable way. In AWS, we can use [Amazon MSK](https://aws.amazon.com/msk/) and [MSK Connect](https://aws.amazon.com/msk/features/msk-connect/) for building a Debezium based CDC solution.

Data replication to data lakes using CDC can be much more effective if [data is stored to a format](https://lakefs.io/hudi-iceberg-and-delta-lake-data-lake-table-formats-compared/) that supports atomic transactions and consistent updates. Popular choices are [Apache Hudi](https://hudi.apache.org/), [Apache Iceberg](https://iceberg.apache.org/) and [Delta Lake](https://delta.io/). Among those, Apache Hudi can be a good option as it is [well-integrated with AWS services](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hudi.html).

Below shows the architecture of the data lake solution that we will be building in this series of posts.

![](00-01-architecture.png#center)

1. Employing the [transactional outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html), the source database publishes change event records to the CDC event table. The event records are generated by triggers that listen to insert and update events on source tables. See the Source Database section of the [previous post](/blog/2021-12-05-datalake-demo-part1) for details.
2. CDC is implemented in a streaming environment and [Amazon MSK](https://aws.amazon.com/msk/) is used to build the streaming infrastructure. In order to process the real-time CDC event records, a source and sink connectors are set up in [Amazon MSK Connect](https://aws.amazon.com/msk/features/msk-connect/). The [Debezium connector for PostgreSQL](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) is used as the source connector and the [Lenses S3 connector](https://lenses.io/blog/2020/11/new-kafka-to-S3-connector/) is used as the sink connector. The sink connector pushes messages to a S3 bucket.
3. [Hudi DeltaStreamer](https://hudi.apache.org/docs/writing_data/#deltastreamer) is run on [Amazon EMR](https://aws.amazon.com/emr/). As a spark application, it reads files from the S3 bucket and upserts Hudi records to another S3 bucket. The Hudi table is created in the AWS Glue Data Catalog.
4. The Hudi table is queried in [Amazon Athena](https://aws.amazon.com/athena/) while the table is registered in the AWS Glue Data Catalog.
5. Dashboards are created in [Amazon Quicksight](https://aws.amazon.com/quicksight/) where the dataset is created using Amazon Athena.

In this post, we'll build the CDC part of the solution on AWS using Amazon MSK and MSK Connect.


## Infrastructure

### VPC

We'll build the data lake solution in a dedicated VPC. The VPC is created in the Sydney region, and it has private and public subnets in 2 availability zones. Note the source database, MSK cluster/connectors and EMR cluster will be deployed to the private subnets. The [CloudFormation template](https://s3-eu-west-1.amazonaws.com/widdix-aws-cf-templates-releases-eu-west-1/stable/vpc/vpc-2azs.yaml) can be found in the [Free Templates for AWS CloudFormation](https://templates.cloudonaut.io/en/stable/)- see the [VPC section](https://templates.cloudonaut.io/en/stable/vpc/) for details.

#### NAT Instances

NAT instances are created in each of the availability zone to forward outbound traffic to the internet. The [CloudFormation template](https://s3-eu-west-1.amazonaws.com/widdix-aws-cf-templates-releases-eu-west-1/stable/vpc/vpc-nat-instance.yaml) can be found in the VPC section of the site as well.


#### VPN Bastion Host

We can use a VPN bastion host to access resources in the private subnets. The free template site provides both SSH and VPN bastion host templates and I find the latter is more convenient. It can be used to access other resources via different ports as well as be used as an SSH bastion host. The [CloudFormation template](https://s3-eu-west-1.amazonaws.com/widdix-aws-cf-templates-releases-eu-west-1/stable/vpc/vpc-vpn-bastion.yaml) creates an EC2 instance in one of the public subnets and installs a [SoftEther VPN](https://www.softether.org/) server. The template requires you to add the [pre-shared key](https://en.wikipedia.org/wiki/Pre-shared_key) and the VPN admin password, which can be used to manage the server and create connection settings for the VPN server. After creating the CloudFormation stack, we need to download the server manager from the [download page](https://www.softether-download.com/en.aspx?product=softether) and to install the admin tools.

![](vpn-00.png#center)


After that, we can create connection settings for the VPN server by providing the necessary details as marked in red boxes below. We should add the public IP address of the EC2 instance and the VPN admin password.

![](vpn-01.png#center)

The template also has VPN username and password parameters and those are used to create a user account in the VPN bastion server. Using the credentials we can set up a VPN connection using the SoftEther VPN client program - it can be downloaded on the same download page. We should add the public IP address of the EC2 instance to the host name and select DEFAULT as the virtual hub name.

![](vpn-02.png#center)

After that, we can connect to the VPN bastion host and access resources in the private subnets.

### Aurora PostgreSQL

We create the source database with Aurora PostgreSQL. The [CloudFormation template](https://s3-eu-west-1.amazonaws.com/widdix-aws-cf-templates-releases-eu-west-1/stable/state/rds-postgres.yaml) from the [free template site](https://templates.cloudonaut.io/en/stable/state/) creates database instances in multiple availability zones. We can simplify it by creating only a single instance. Also, as we're going to use the `pgoutput` plugin for the Debezium source connector, we need to set `rds:logical_replication` value to "1" in the database cluster parameter group. Note to add the CloudFormation stack name of the VPN bastion host to the _ParentSSHBastionStack_ parameter value so that the database can be accessed by the VPN bastion host. Also note that the template doesn't include an inbound rule from the MSK cluster that'll be created below. For now, we need to add the inbound rule manually. The updated template can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/infra/state/rds-aurora.yaml).


#### Source Database

As with the local development, we can create the source database by executing the [db creation SQL scripts](https://github.com/jaehyeon-kim/data-lake-demo/tree/main/data/sql). A function is created in Python. After creating the _datalake_ schema and setting the search path of the database (_devdb_) to it, it executes the SQL scripts.


```python
# ./data/load/src.py
def create_northwind_db():
    """
    Create Northwind database by executing SQL scripts
    """
    try:
        global conn
        with conn:
            with conn.cursor() as curs:
                curs.execute("CREATE SCHEMA datalake;")
                curs.execute("SET search_path TO datalake;")
                curs.execute("ALTER database devdb SET search_path TO datalake;")
                curs.execute(set_script_path("01_northwind_ddl.sql").open("r").read())
                curs.execute(set_script_path("02_northwind_data.sql").open("r").read())
                curs.execute(set_script_path("03_cdc_events.sql").open("r").read())
                conn.commit()
                typer.echo("Northwind SQL scripts executed")
    except (psycopg2.OperationalError, psycopg2.DatabaseError, FileNotFoundError) as err:
        typer.echo(create_northwind_db.__name__, err)
        close_conn()
        exit(1)
```


In order to facilitate the db creation, a simple command line application is created using the [Typer library](https://typer.tiangolo.com/).


```python
# ./data/load/main.py
import typer
from src import set_connection, create_northwind_db

def main(
    host: str = typer.Option(..., "--host", "-h", help="Database host"),
    port: int = typer.Option(5432, "--port", "-p", help="Database port"),
    dbname: str = typer.Option(..., "--dbname", "-d", help="Database name"),
    user: str = typer.Option(..., "--user", "-u", help="Database user name"),
    password: str = typer.Option(..., prompt=True, hide_input=True, help="Database user password"),
):
    to_create = typer.confirm("To create database?")
    if to_create:
        params = {"host": host, "port": port, "dbname": dbname, "user": user, "password": password}
        set_connection(params)
        create_northwind_db()

if __name__ == "__main__":
    typer.run(main)
```


It has a set of options to specify - database host, post, database name and username. The database password is set to be prompted, and an additional confirmation is required. If all options are provided, the app runs and creates the source database.


```bash
(venv) jaehyeon@cevo:~/data-lake-demo$ python data/load/main.py --help
Usage: main.py [OPTIONS]

Options:
  -h, --host TEXT       Database host  [required]
  -p, --port INTEGER    Database port  [default: 5432]
  -d, --dbname TEXT     Database name  [required]
  -u, --user TEXT       Database user name  [required]
  --password TEXT       Database user password  [required]
  --install-completion  Install completion for the current shell.
  --show-completion     Show completion for the current shell, to copy it or
                        customize the installation.
  --help                Show this message and exit.

(venv) jaehyeon@cevo:~/data-lake-demo$ python data/load/main.py -h <db-host-name-or-ip> -d <dbname> -u <username>
Password:
To create database? [y/N]: y
Database connection created
Northwind SQL scripts executed
```


As illustrated thoroughly in the [previous post](/blog/2021-12-05-datalake-demo-part1), it inserts 829 order event records to the _cdc_events_ table. 


### MSK Cluster

We'll create an MSK cluster with 2 brokers (_[servers](https://kafka.apache.org/documentation/#intro_nutshell)_). The instance type of brokers is set to `kafka.m5.large`. Note that the smallest instance type of `kafka.t3.small` may look better for development, but we'll have a [failed authentication error](https://github.com/aws/aws-msk-iam-auth/issues/28) when IAM Authentication is used for access control and connectors are created on MSK Connect. It is because the T3 instance type is limited to [1 TCP connection per broker per second](https://docs.aws.amazon.com/msk/latest/developerguide/limits.html) and if the frequency is higher than the limit, that error is thrown. Note, while it's possible to avoid it by updating `reconnect.backoff.ms` to 1000, it is [not allowed on MSK Connect](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect-workers.html).

When it comes to inbound rules of the cluster security group, we need to configure that all inbound traffic is allowed from its own security group. This is because connectors on MSK Connect are deployed with the same security group of the MSK cluster, and they should have access to it. Also, we need to allow port 9098 from the security group of the VPN bastion host - 9098 is the port for establishing the initial connection to the cluster when IAM Authentication is used. 

Finally, a cluster configuration is created manually as it's not supported by CloudFormation and its ARN and revision number are added as parameters. The configuration is shown below.


```conf
auto.create.topics.enable = true
delete.topic.enable = true
```

The CloudFormation template can be found in the project [**GitHub repository**](https://github.com/jaehyeon-kim/data-lake-demo/blob/main/infra/main/msk.yaml). 


#### MSK Connect Role

As we use IAM Authentication for access control, the connectors need to have permission on the cluster, topic and group. Also, the sink connector should have access to put output files to the S3 bucket. For simplicity, a single connector role is created for both source and sink connectors in the same template.


## CDC Development

In order to create a connector on MSK Connect, we need to create a custom plugin and the connector itself. A custom plugin is a set of JAR files containing the implementation of one or more connectors, transforms, or converters and installed on the workers of the connect cluster where the connector is running. Both the resources are not supported by CloudFormation and can be created on AWS Console or using AWS SDK.


### Custom Plugins

We need plugins for the Debezium source and S3 sink connectors. Plugin objects can be saved to S3 in either JAR or ZIP file format. We can download them from the relevant release/download pages of [Debezium](https://debezium.io/releases/1.7/) and [Lenses Stream Reactor](https://github.com/lensesio/stream-reactor/releases/tag/3.0.0). Note to put contents at the root level of the zip archives. Once they are saved to S3, we can create them simply by specifying their S3 URIs. 


### MSK Connectors

#### Source Connector

_[Debezium's PostgreSQL connector](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) captures row-level changes in the schemas of a PostgreSQL database. PostgreSQL versions 9.6, 10, 11, 12 and 13 are supported. The first time it connects to a PostgreSQL server or cluster, the connector takes a consistent snapshot of all schemas. After that snapshot is complete, the connector continuously captures row-level changes that insert, update, and delete database content and that were committed to a PostgreSQL database. The connector generates data change event records and streams them to Kafka topics. For each table, the default behavior is that the connector streams all generated events to a separate Kafka topic for that table. Applications and services consume data change event records from that topic.

The connector has a number of connector properties including name, connector class, database connection details, key/value converter and so on - the full list of properties can be found in [this page](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-connector-properties). The properties that need explanation are listed below.

* `plugin.name` - Using the [logical decoding](https://www.postgresql.org/docs/current/logicaldecoding-explanation.html) feature, an output plug-in enables clients to consume changes to the transaction log in a user-friendly manner. Debezium supports `decoderbufs`, `wal2json` and `pgoutput` plug-ins. Both `wal2json` and `pgoutput` are available in Amazon RDS for PostgreSQL and Amazon Aurora PostgreSQL. `decoderbufs` requires a separate installation, and it is excluded from the option. Among the 2 supported plug-ins, `pgoutput` is selected because it is the standard logical decoding output plug-in in PostgreSQL 10+ and [ has better performance for large transactions](https://debezium.io/blog/2020/02/25/lessons-learned-running-debezium-with-postgresql-on-rds/).
* `publication.name` - With the `pgoutput` plug-in, the Debezium connector creates a publication (if not exists) and sets `publication.autocreate.mode` to _all_tables_. It can cause an issue to update a record to a table that doesn't have the primary key or replica identity. We can set the value to _filtered_ where the connector adjusts the applicable tables by other property values. Alternatively we can create a publication on our own and add the name to _publication.name_ property. I find creating a publication explicitly is easier to maintain. Note a publication alone is not sufficient to handle the issue. All affected tables by the publication should have the primary key or replica identity. In our example, the _orders _and _order_details _tables should meet the condition. In short, creating an explicit publication can prevent the event generation process from interrupting other processes by limiting the scope of CDC event generation.
* `key.converter/value.converter` - Although [Avro serialization](https://debezium.io/documentation/reference/stable/configuration/avro.html) is recommended, JSON is a format that can be generated without schema registry and can be read by DeltaStreamer.
* `transforms` - A Debezium event data has a complex structure that provides a wealth of information. It can be quite difficult to process such a structure using DeltaStreamer. Debezium's event flattening [single message transformation (SMT)](https://debezium.io/documentation/reference/stable/transformations/event-flattening.html) is configured to flatten the output payload.

Note once the connector is deployed, the CDC event records will be published to `msk.datalake.cdc_events` topic.


```conf
# ./connector/msk/source-debezium.properties
connector.class=io.debezium.connector.postgresql.PostgresConnector
tasks.max=1
plugin.name=pgoutput
publication.name=cdc_publication
database.hostname=<database-hostname-or-ip-address>
database.port=5432
database.user=<database-user>
database.password=<database-user-password>
database.dbname=devdb
database.server.name=msk
schema.include=datalake
table.include.list=datalake.cdc_events
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
transforms=unwrap
transforms.unwrap.type=io.debezium.transforms.ExtractNewRecordState
transforms.unwrap.drop.tombstones=false
transforms.unwrap.delete.handling.mode=rewrite
transforms.unwrap.add.fields=op,db,table,schema,lsn,source.ts_ms
```

The connector can be created in multiple steps. The first step is to select the relevant custom plugin from the custom plugins list.

![](connector-01.png#center)

In the second step, we can configure connector properties. Applicable properties are

* Connector name and description
* Apache Kafka cluster (MSK or self-managed) with an authentication method
* Connector configuration
* Connector capacity - Autoscaled or Provisioned
* Worker configuration
* IAM role of the connector - it is created in the CloudFormation template

![](connector-02-01.png#center)

![](connector-02-02.png#center)

![](connector-02-03.png#center)

![](connector-02-04.png#center)

![](connector-02-05.png#center)


In the third step, we configure cluster security. As we selected IAM Authentication, only TLS encryption is available.

![](connector-03.png#center)

Finally, we can configure logging. A log group is created in the CloudFormation, and we can add its ARN.

![](connector-04.png#center)

After reviewing, we can create the connector.

#### Sink Connector

[Lenses S3 Connector](https://lenses.io/blog/2020/11/new-kafka-to-S3-connector/) is a Kafka Connect sink connector for writing records from Kafka to AWS S3 Buckets. It extends the standard connect config adding a parameter for a SQL command (Lenses Kafka Connect Query Language or "KCQL"). This defines how to map data from the source (in this case Kafka) to the target (S3). Importantly, it also includes how data should be partitioned into S3, the bucket names and the serialization format (support includes JSON, Avro, Parquet, Text, CSV and binary).

I find the Lenses S3 connector is more straightforward to configure than the Confluent S3 sink connector for its [SQL-like syntax](https://docs.lenses.io/4.1/integrations/connectors/stream-reactor/sinks/s3sinkconnector/). The KCQL configuration indicates that object files are set to be


* moved from a Kafka topic (`msk.datalake.cdc_events`) to an S3 bucket (`data-lake-demo-cevo`) with object prefix of _`cdc-events-local`,
* partitioned by _customer_id_ and _order_id_ e.g. `customer_id=<customer-id>/order_id=<order-id>`,
* stored as the JSON format and,
* flushed every 60 seconds or when there are 50 records.

```conf
# ./connector/msk/sink-s3-lenses.properties
connector.class=io.lenses.streamreactor.connect.aws.s3.sink.S3SinkConnector
tasks.max=1
connect.s3.kcql=INSERT INTO data-lake-demo-cevo:cdc-events SELECT * FROM msk.datalake.cdc_events PARTITIONBY customer_id,order_id STOREAS `json` WITH_FLUSH_INTERVAL = 60 WITH_FLUSH_COUNT = 50
aws.region=ap-southeast-2
aws.custom.endpoint=https://s3.ap-southeast-2.amazonaws.com/
topics=msk.datalake.cdc_events
key.converter.schemas.enable=false
schema.enable=false
errors.log.enable=true
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
```

We can create the sink connector on AWS Console using the same steps to the source connector.

### Update/Insert Examples

#### Kafka UI

When we used the Confluent platform for local development in the previous post, we checked topics and messages on the control tower UI. For MSK, we can use [Kafka UI](https://github.com/provectus/kafka-ui). Below shows a docker-compose file for it. Note that the MSK cluster is secured by IAM Authentication so that _AWS_MSK_IAM _is specified as the SASL mechanism. Under the hood, it uses [Amazon MSK Library for AWS IAM](https://github.com/aws/aws-msk-iam-auth) for authentication and AWS credentials are provided via volume mapping. Also don't forget to connect the VPN bastion host using the SoftEther VPN client program. 


```yaml
# ./kafka-ui/docker-compose.yml
version: "2"
services:
  kafka-ui:
    image: provectuslabs/kafka-ui
    container_name: kafka-ui
    ports:
      - "8080:8080"
    # restart: always
    volumes:
      - $HOME/.aws:/root/.aws
    environment:
      KAFKA_CLUSTERS_0_NAME: msk
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: $BS_SERVERS
      KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: "SASL_SSL"
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_MECHANISM: "AWS_MSK_IAM"
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_CLIENT_CALLBACK_HANDLER_CLASS: "software.amazon.msk.auth.iam.IAMClientCallbackHandler"
      KAFKA_CLUSTERS_0_PROPERTIES_SASL_JAAS_CONFIG: "software.amazon.msk.auth.iam.IAMLoginModule required;"
```

Once started, the UI can be accessed via `http://localhost:8080`. We see that the CDC topic is found in the topics list. There are 829 messages in the topic, and it matches the number of records in the `cdc_events` table at creation. 


![](kafka-ui-01.png#center)

When we click the topic name, it shows further details of it. When clicking the messages tab, we can see individual messages within the topic. The UI also has some other options, and it can be convenient to manage topics and messages.

![](kafka-ui-02.png#center)

The message records can be expanded, and we can check a message's key, content and headers. Also, we can either copy the value to clipboard or save as a file.

![](kafka-ui-03.png#center)

#### Update Event

The order 11077 initially didn't have the _shipped_date _value. When the value is updated later, a new output file will be generated with the updated value.


```sql
BEGIN TRANSACTION;
    UPDATE orders
    SET shipped_date = '1998-06-15'::date
    WHERE order_id = 11077;
COMMIT TRANSACTION; 
END;
```


In S3, we see 2 JSON objects are included in the output file for the order entry and the shipped_date value is updated as expected. Note that the [Debezium connector converts the DATE type to the INT32 type](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-temporal-types), which represents the number of days since the epoch.

![](output-file-update.png#center)

#### Insert Event

When a new order is created, it'll insert a record to the _orders _table as well as one or more order items to the _order_details _table. Therefore, we expect multiple event records will be created when a new order is created. We can check it by inserting an order and related order details items.


```sql
BEGIN TRANSACTION;
    INSERT INTO orders VALUES (11075, 'RICSU', 8, '1998-05-06', '1998-06-03', NULL, 2, 6.19000006, 'Richter Supermarkt', 'Starenweg 5', 'Genève', NULL, '1204', 'Switzerland');
    INSERT INTO order_details VALUES (11075, 2, 19, 10, 0.150000006);
    INSERT INTO order_details VALUES (11075, 46, 12, 30, 0.150000006);
    INSERT INTO order_details VALUES (11075, 76, 18, 2, 0.150000006);
COMMIT TRANSACTION; 
END;
```

We can see the output file includes 4 JSON objects where the first object has NULL _order_items _and _products _value. We can also see that those values are expanded gradually in subsequent event records

![](output-file-insert.png#center)

## Conclusion

We created a VPC that has private and public subnets in 2 availability zones in order to build and deploy the data lake solution on AWS. NAT instances are created to forward outbound traffic to the internet and a VPN bastion host is set up to facilitate deployment. An Aurora PostgreSQL cluster is deployed to host the source database and a Python command line app is used to create the database. To develop data ingestion using CDC, an MSK cluster is deployed and the Debezium source and Lenses S3 sink connectors are created on MSK Connect. We also confirmed the order creation and update events are captured as expected with the scenarios used by local development. Using CDC event output files in S3, we are able to build an Apache Hudi table on EMR and use it for ad-hoc queries and report/dashboard generation. It'll be covered in the next post.
