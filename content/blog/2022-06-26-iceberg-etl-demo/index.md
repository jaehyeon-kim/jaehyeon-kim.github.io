---
title: Data Warehousing ETL Demo with Apache Iceberg on EMR Local Environment
date: 2022-06-26
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Integrate Schema Registry with MSK Connect
categories:
  - Data Engineering
tags: 
  - AWS
  - Amazon EMR
  - Apache Spark
  - Pyspark
  - Apache Iceberg
  - ETL
  - SCD
  - Slowly Changing Dimension
  - Docker
  - Docker Compose
  - Visual Studio Code
authors:
  - JaehyeonKim
images: []
cevo: 13
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/iceberg-etl-demo/).

Unlike traditional Data Lake, new table formats ([Iceberg](https://iceberg.apache.org/), [Hudi](https://hudi.apache.org/) and [Delta Lake](https://delta.io/)) support [features](https://iceberg.apache.org/docs/latest/spark-writes/) that can be used to apply data warehousing patterns, which can bring a way to be rescued from [Data Swamp](https://www.gartner.com/en/newsroom/press-releases/2014-07-28-gartner-says-beware-of-the-data-lake-fallacy). In this post, we'll discuss how to implement ETL using retail analytics data. It has two dimension data (user and product) and a single fact data (order). The dimension data sets have different ETL strategies depending on whether to track historical changes. For the fact data, the primary keys of the dimension data are added to facilitate later queries. We'll use Iceberg for data storage/management and Spark for data processing. Instead of provisioning an EMR cluster, a local development environment will be used. Finally, the ETL results will be queried by Athena for verification.


## EMR Local Environment

In [one of my earlier posts](/blog/2022-05-08-emr-local-dev), we discussed how to develop and test Apache Spark apps for EMR locally using Docker (and/or VSCode). Instead of provisioning an EMR cluster, we can quickly build an ETL app using the local environment. For this post, a new local environment is created based on the Docker image of the latest EMR 6.6.0 release. Check the [**GitHub repository**](https://github.com/jaehyeon-kim/iceberg-etl-demo) for this post for further details.

Apache Iceberg is [supported by EMR 6.5.0 or later](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-iceberg.html), and it requires _[iceberg-defaults configuration classification](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-iceberg-use-cluster.html)_ that enables Iceberg. The latest EMR Docker release ([emr-6.6.0-20220411](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks-6.6.0.html)), however, doesn't support that configuration classification and I didn't find the _iceberg _folder (`/usr/share/aws/iceberg`) within the Docker container. Therefore, the project's [AWS integration example](https://iceberg.apache.org/docs/latest/aws/#spark) is used instead and the following script ([run.sh](https://github.com/jaehyeon-kim/iceberg-etl-demo/blob/main/run.sh)) is an update of the example script that allows to launch the Pyspark shell or to submit a Spark application.


```bash
# run.sh
#!/usr/bin/env bash

# add Iceberg dependency
ICEBERG_VERSION=0.13.2
DEPENDENCIES="org.apache.iceberg:iceberg-spark3-runtime:$ICEBERG_VERSION"

# add AWS dependency
AWS_SDK_VERSION=2.17.131
AWS_MAVEN_GROUP=software.amazon.awssdk
AWS_PACKAGES=(
    "bundle"
    "url-connection-client"
)
for pkg in "${AWS_PACKAGES[@]}"; do
    DEPENDENCIES+=",$AWS_MAVEN_GROUP:$pkg:$AWS_SDK_VERSION"
done

# execute pyspark or spark-submit
execution=$1
app_path=$2
if [ -z $execution ]; then
    echo "missing execution type. specify either pyspark or spark-submit"
    exit 1
fi

if [ $execution == "pyspark" ]; then
    pyspark --packages $DEPENDENCIES \
        --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
        --conf spark.sql.catalog.demo=org.apache.iceberg.spark.SparkCatalog \
        --conf spark.sql.catalog.demo.warehouse=s3://iceberg-etl-demo \
        --conf spark.sql.catalog.demo.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog \
        --conf spark.sql.catalog.demo.io-impl=org.apache.iceberg.aws.s3.S3FileIO
elif [ $execution == "spark-submit" ]; then
    if [ -z $app_path ]; then
        echo "pyspark application is mandatory"
        exit 1
    else
        spark-submit --packages $DEPENDENCIES \
            --deploy-mode client \
            --master local[*] \
            --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
            --conf spark.sql.catalog.demo=org.apache.iceberg.spark.SparkCatalog \
            --conf spark.sql.catalog.demo.warehouse=s3://iceberg-etl-demo \
            --conf spark.sql.catalog.demo.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog \
            --conf spark.sql.catalog.demo.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
            $app_path
    fi
fi
```

Here is an example of using the script.

```bash
# launch pyspark shell
$ ./run.sh pyspark

# execute spark-submit, requires pyspark application (etl.py) as the second argument
$ ./run.sh spark-submit path-to-app.py
```

## ETL Strategy

### Sample Data

We use the [retail analytics sample database](https://docs.yugabyte.com/preview/sample-data/retail-analytics/) from YugaByteDB to get the ETL sample data. Records from the following 3 tables are used to run ETL on its own ETL strategy.

![](03_data_diagram.png#center)

The main focus of the demo ETL application is to show how to track product price changes over time and to apply those changes to the order data. Normally ETL is performed daily, but it'll be time-consuming to execute daily incremental ETL with the order data because it includes records spanning for 5 calendar years. Moreover, as it is related to the user and product data, splitting the corresponding dimension records will be quite difficult. Instead, I chose to run yearly incremental ETL. I first grouped orders in 4 groups where the first group (year 0) includes orders in 2016 and 2017. And each of the remaining groups (year 1 to 3) keeps records of a whole year from 2018 to 2020. Then I created 4 product groups in order to match the order groups and to execute incremental ETL together with the order data. The first group (year 0) keeps the original data and the product price is set to be increased by 5% in the following years until the last group (year 3). Note, with this setup, it is expected that orders for a given product tend to be mapped to a higher product price over time. On the other hand, the ETL strategy of the user data is not to track historical data so that it is used as it is. The sample data files used for the ETL app are listed below, and they can be found in the [data folder](https://github.com/jaehyeon-kim/iceberg-etl-demo/tree/main/data) of the **GitHub repository**.


```bash
$ tree data
data
├── orders_year_0.csv
├── orders_year_1.csv
├── orders_year_2.csv
├── orders_year_3.csv
├── products_year_0.csv
├── products_year_1.csv
├── products_year_2.csv
├── products_year_3.csv
└── users.csv
```

### Users

[Slowly changing dimension (SCD) type 1](https://en.wikipedia.org/wiki/Slowly_changing_dimension) is implemented for the user data. This method basically _upsert_s records by comparing the primary key values and therefore doesn't track historical data. The data has the [natural key](https://en.wikipedia.org/wiki/Natural_key) of _id _and its [md5 hash](https://en.wikipedia.org/wiki/MD5) is used as the [surrogate key](https://en.wikipedia.org/wiki/Surrogate_key) named _user_sk_ - this column is used as the primary key of the table. The table is configured to be partitioned by its surrogate key in 20 buckets. The table creation statement can be found below.


```sql
CREATE TABLE demo.dwh.users (
	user_sk     string,
	id          bigint,
	name        string,
	email       string,
	address     string,
	city        string,
	state       string,
	zip         string,
	birth_date  date,
	source      string,
	created_at  timestamp)
USING iceberg
PARTITIONED BY (bucket(20, user_sk))
```

### Products

[Slowly changing dimension (SCD) type 2](https://en.wikipedia.org/wiki/Slowly_changing_dimension) is taken for product data. This method tracks historical data by adding multiple records for a given natural key. Same as the user data, the _id_ column is the natural key. Each record for the same natural key will be given a different surrogate key and the md5 hash of a combination of the _id_ and _created_at _columns is used as the surrogate key named _prod_sk_. Each record has its own effect period and it is determined by the _eff_from_ and _eff_to _columns and the latest record is marked as 1 for its _curr_flag_ value. The table is also configured to be partitioned by its surrogate key in 20 buckets. The table creation statement is shown below.


```sql
CREATE TABLE demo.dwh.products (
	prod_sk     string,
	id          bigint,
	category    string,
	price       decimal(6,3),
	title       string,
	vendor      string,
	curr_flag   int,
	eff_from    timestamp,
	eff_to      timestamp,
	created_at  timestamp)
USING iceberg
PARTITIONED BY (bucket(20, prod_sk))
```

### Orders

The orders table has a composite primary key of the surrogate keys of the dimension tables - _users_sk_ and _prod_sk_. Those columns don't exist in the source data and are added during transformation. The table is configured to be partitioned by the date part of the _created_at_ column. The table creation statement can be found below.


```sql
CREATE TABLE demo.dwh.orders (
	user_sk     string,
	prod_sk     string,
	id          bigint,
	discount    decimal(4,2),
	quantity    integer,
	created_at  timestamp)
USING iceberg
PARTITIONED BY (days(created_at))
```

## ETL Implementation

### Users

In the transformation phase, a source dataframe is created by creating the surrogate key (_user_sk_), changing data types of relevant columns and selecting columns in the same order as the table is created. Then a view (_users_tbl_) is created from the source dataframe and it is used to execute MERGE operation by comparing the surrogate key values of the source view with those of the target users table. 


```python
# src.py
def etl_users(file_path: str, spark_session: SparkSession):
    print("users - transform records...")
    src_df = (
        spark_session.read.option("header", "true")
        .csv(file_path)
        .withColumn("user_sk", md5("id"))
        .withColumn("id", expr("CAST(id AS bigint)"))
        .withColumn("created_at", to_timestamp("created_at"))
        .withColumn("birth_date", to_date("birth_date"))
        .select(
            "user_sk",
            "id",
            "name",
            "email",
            "address",
            "city",
            "state",
            "zip",
            "birth_date",
            "source",
            "created_at",
        )
    )
    print("users - upsert records...")
    src_df.createOrReplaceTempView("users_tbl")
    spark_session.sql(
        """
        MERGE INTO demo.dwh.users t
        USING (SELECT * FROM users_tbl ORDER BY user_sk) s
        ON s.user_sk = t.user_sk
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )
```

### Products

The source dataframe is created by adding the surrogate key while concatenating the _id_ and _created_at _columns, followed by changing data types of relevant columns and selecting columns in the same order as the table is created. The view (_products_tbl_) that is created from the source dataframe is used to query all the records that have the product ids in the source table - see _products_to_update_. Note we need data from the products table in order to update _eff_from_, _eff_to _and _current_flag _column values. Then _eff_lead_ is added to the result set, which is the next record's created_at value for a given product id - see _products_updated_. The final result set is created by determining the _curr_flag _and _eff_to _column value. Note that the _eff_to _value of the last record for a product is set to ‘_9999-12-31 00:00:00_' in order to make it easy to query the relevant records. The updated records are updated/inserted by executing MERGE operation by comparing the surrogate key values to those of the target products table


```python
# src.py
def etl_products(file_path: str, spark_session: SparkSession):
    print("products - transform records...")
    src_df = (
        spark_session.read.option("header", "true")
        .csv(file_path)
        .withColumn("prod_sk", md5(concat("id", "created_at")))
        .withColumn("id", expr("CAST(id AS bigint)"))
        .withColumn("price", expr("CAST(price AS decimal(6,3))"))
        .withColumn("created_at", to_timestamp("created_at"))
        .withColumn("curr_flag", expr("CAST(NULL AS int)"))
        .withColumn("eff_from", col("created_at"))
        .withColumn("eff_to", expr("CAST(NULL AS timestamp)"))
        .select(
            "prod_sk",
            "id",
            "category",
            "price",
            "title",
            "vendor",
            "curr_flag",
            "eff_from",
            "eff_to",
            "created_at",
        )
    )
    print("products - upsert records...")
    src_df.createOrReplaceTempView("products_tbl")
    products_update_qry = """
    WITH products_to_update AS (
        SELECT l.*
        FROM demo.dwh.products AS l
        JOIN products_tbl AS r ON l.id = r.id
        UNION
        SELECT *
        FROM products_tbl
    ), products_updated AS (
        SELECT *,
                LEAD(created_at) OVER (PARTITION BY id ORDER BY created_at) AS eff_lead
        FROM products_to_update
    )
    SELECT prod_sk,
            id,
            category,
            price,
            title,
            vendor,
            (CASE WHEN eff_lead IS NULL THEN 1 ELSE 0 END) AS curr_flag,
            eff_from,
            COALESCE(eff_lead, to_timestamp('9999-12-31 00:00:00')) AS eff_to,
            created_at
    FROM products_updated
    ORDER BY prod_sk
    """
    spark_session.sql(
        f"""
        MERGE INTO demo.dwh.products t
        USING ({products_update_qry}) s
        ON s.prod_sk = t.prod_sk
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )
```

### Orders

After transformation, a view (_orders_tbl_) is created from the source dataframe. The relevant user (_user_sk_) and product (_prod_sk_) surrogate keys are added to source data by joining the users and products dimension tables. The users table is SCD type 1 so matching the _user_id _alone is enough for the join condition. On the other hand, additional join condition based on the _eff_from _and _eff_to _columns is necessary for the products table as it is SCD type 2 and records in that table have their own effective periods. Note that ideally we should be able to apply INNER JOIN but the sample data is not clean and some product records are not matched by that operation. For example, an order whose id is 15 is made at 2018-06-26 02:24:38 with a product whose id is 116. However the earliest record of that product is created at 2018-09-12 15:23:05 and it'll be missed by INNER JOIN. Therefore LEFT JOIN is applied to create the initial result set (_orders_updated_) and, for those products that are not matched, the surrogate keys of the earliest records are added instead. Finally the updated order records are appended using the [DataFrameWriterV2 API](https://iceberg.apache.org/docs/latest/spark-writes/#appending-data).


```python
# src.py
def etl_orders(file_path: str, spark_session: SparkSession):
    print("orders - transform records...")
    src_df = (
        spark_session.read.option("header", "true")
        .csv(file_path)
        .withColumn("id", expr("CAST(id AS bigint)"))
        .withColumn("user_id", expr("CAST(user_id AS bigint)"))
        .withColumn("product_id", expr("CAST(product_id AS bigint)"))
        .withColumn("discount", expr("CAST(discount AS decimal(4,2))"))
        .withColumn("quantity", expr("CAST(quantity AS int)"))
        .withColumn("created_at", to_timestamp("created_at"))
    )
    print("orders - append records...")
    src_df.createOrReplaceTempView("orders_tbl")
    spark_session.sql(
        """
        WITH src_products AS (
            SELECT * FROM demo.dwh.products
        ), orders_updated AS (
            SELECT o.*, u.user_sk, p.prod_sk
            FROM orders_tbl o
            LEFT JOIN demo.dwh.users u
                ON o.user_id = u.id
            LEFT JOIN src_products p
                ON o.product_id = p.id
                AND o.created_at >= p.eff_from
                AND o.created_at < p.eff_to
        ), products_tbl AS (
            SELECT prod_sk,
                   id,
                   ROW_NUMBER() OVER (PARTITION BY id ORDER BY eff_from) AS rn
            FROM src_products
        )
        SELECT o.user_sk,
               COALESCE(o.prod_sk, p.prod_sk) AS prod_sk,
               o.id,
               o.discount,
               o.quantity,
               o.created_at
        FROM orders_updated AS o
        JOIN products_tbl AS p ON o.product_id = p.id
        WHERE p.rn = 1
        ORDER BY o.created_at
        """
    ).writeTo("demo.dwh.orders").append()
```

### Run ETL

The ETL script begins with creating all the tables - users, products and orders. Then the ETL for the users table is executed. Note that, although it is executed as initial loading, the code can also be applied to incremental ETL. Finally, incremental ETL is executed for the products and orders tables. The application can be submitted by `./run.sh spark-submit etl.py`. Note to create the following environment variables before submitting the application.
* _AWS_ACCESS_KEY_ID_
* _AWS_SECRET_ACCESS_KEY_
* _AWS_SESSION_TOKEN_
    * Note it is optional and required if authentication is made via assume role
* _AWS_REGION_
    * Note it is NOT _AWS_DEFAULT_REGION_

```python
# etl.py
from pyspark.sql import SparkSession
from src import create_tables, etl_users, etl_products, etl_orders

spark = SparkSession.builder.appName("Iceberg ETL Demo").getOrCreate()

## create all tables - demo.dwh.users, demo.dwh.products and demo.dwh.orders
create_tables(spark_session=spark)

## users etl - assuming SCD type 1
etl_users("./data/users.csv", spark)

## incremental ETL
for yr in range(0, 4):
    print(f"processing year {yr}")
    ## products etl - assuming SCD type 2
    etl_products(f"./data/products_year_{yr}.csv", spark)
    ## orders etl - relevant user_sk and prod_sk are added during transformation
    etl_orders(f"./data/orders_year_{yr}.csv", spark)
```

Once the application completes, we're able to query the iceberg tables on Athena. The following query returns all products whose id is 1. It is shown that the price increases over time and the relevant columns (_curr_flag, eff_from and eff_to_) for SCD type 2 are created as expected.


```sql
SELECT *
FROM dwh.products
WHERE id = 1
ORDER BY eff_from
```

![](01_products.png#center)


The following query returns sample order records that bought the product. It can be checked that the product surrogate key matches the products dimension records.


```sql
WITH src_orders AS (
    SELECT o.user_sk, o.prod_sk, o.id, p.title, p.price, o.discount, o.quantity, o.created_at,
           ROW_NUMBER() OVER (PARTITION BY p.price ORDER BY o.created_at) AS rn
    FROM dwh.orders AS o
    JOIN dwh.products AS p ON o.prod_sk = p.prod_sk
    WHERE p.id = 1
)
SELECT *
FROM src_orders
WHERE rn = 1
ORDER BY created_at
```

![](02_orders.png#center)

## Summary

In this post, we discussed how to implement ETL using retail analytics data. In transformation, SCD type 1 and SCD type 2 are applied to the user and product data respectively. For the order data, the corresponding surrogate keys of the user and product data are added. A Pyspark application that implements ETL against Iceberg tables is used for demonstration in an EMR location environment. Finally, the ETL results will be queried by Athena for verification.
