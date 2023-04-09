---
title: Data Build Tool (dbt) for Effective Data Transformation on AWS – Part 4 EMR on EKS
date: 2022-11-01
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
  - DBT for Effective Data Transformation on AWS
categories:
  - Data Engineering
tags: 
  - AWS
  - Amazon EMR
  - Amazon EKS
  - Amazon QuickSight
  - Data Build Tool (DBT)
  - Apache Spark
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 21
---

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an effective data transformation tool and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In the previous posts, we discussed benefits of a common data transformation tool and the potential of dbt to cover a wide range of data projects from data warehousing to data lake to data lakehouse. Demo data projects that target Redshift Serverless, Glue and EMR on EC2 are illustrated as well. In part 4 of the dbt on AWS series, we discuss data transformation pipelines using dbt on [Amazon EMR on EKS](https://aws.amazon.com/emr/features/eks/). As Spark Submit does not allow the spark thrift server to run in cluster mode on Kubernetes, a simple wrapper class is created to overcome the limitation and it makes the thrift server run indefinitely. [Subsets of IMDb data](https://www.imdb.com/interfaces/) are used as source and data models are developed in multiple layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview). A list of posts of this series can be found below.

* [Part 1 Redshift](/blog/2022-09-28-dbt-on-aws-part-1-redshift)
* [Part 2 Glue](/blog/2022-10-09-dbt-on-aws-part-2-glue)
* [Part 3 EMR on EC2](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2)
* [Part 4 EMR on EKS](#) (this post)
* [Part 5 Athena](/blog/2023-04-12-integrate-glue-schema-registry)

Below shows an overview diagram of the scope of this dbt on AWS series. EMR is highlighted as it is discussed in this post.

![](featured.png#center)

## Infrastructure

The main infrastructure hosting this solution leverages an Amazon EKS cluster and EMR virtual cluster. As discussed in [one of the earlier posts](/blog/2022-02-06-dev-infra-terraform), EMR job pods (controller, driver and executors) can be configured to be managed by [Karpenter](https://karpenter.sh/), which simplifies autoscaling by provisioning just-in-time capacity as well as reduces scheduling latency. While the infrastructure elements are discussed in depth in the [earlier post](/blog/2022-08-26-emr-on-eks-with-terraform) and [part 3](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2), this section focuses on how to set up a long-running Thrift JDBC/ODBC server on EMR on EKS, which is a critical part of using the [dbt-spark](https://github.com/dbt-labs/dbt-spark) adapter. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-on-aws) of this post.


### Thrift JDBC/ODBC Server

The [Spark Submit](https://spark.apache.org/docs/latest/submitting-applications.html) does not allow the spark thrift server to run in cluster mode on Kubernetes. I have found a number of implementations that handle this issue. The [first one](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator/issues/1116) is executing the thrift server start script in the container command, but [it is not allowed in pod templates](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/pod-templates.html) of EMR on EKS. Besides, it creates the driver and executors in a single pod, which is not scalable. The [second example](https://www.youtube.com/watch?v=iLKCuchzQso&list=PL0QYlrC86xQlj9UDGiEwhXQuSjuSyPJHl) relies on [Apache Kyuubi](https://kyuubi.apache.org/) that manages Spark applications while providing JDBC connectivity. However, there is no dbt adapter that supports Kyuubi as well as I am concerned it could make dbt transformations more complicated. The [last one](https://itnext.io/hive-on-spark-in-kubernetes-115c8e9fa5c1) is creating a wrapper class that makes the thrift server run indefinitely. It is an interesting approach to deploy the thrift server on EMR on EKS (and the spark kubernetes operator in general) with minimal effort. Following that example, a wrapper class is created in this post.


#### Spark Thrift Server Runner

The wrapper class (`SparkThriftServerRunner`) is created as shown below, and it makes the HiveThriftServer2 class run indefinitely. In this way, we are able to use the runner class as the entry point for a spark application.


```java
// emr-eks/hive-on-spark-in-kubernetes/examples/spark-thrift-server/src/main/java/io/jaehyeon/hive/SparkThriftServerRunner.java
package io.jaehyeon.hive;

public class SparkThriftServerRunner {

    public static void main(String[] args) {
        org.apache.spark.sql.hive.thriftserver.HiveThriftServer2.main(args);

        while (true) {
            try {
                Thread.sleep(Long.MAX_VALUE);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}
```

While the reference implementation includes all of its dependent libraries when building the class, only the runner class itself is built for this post. It is because we do not have to include those as they are available in the EMR on EKS container image. To do so, the Project Object Model (POM) file is updated so that all the _provided_ dependency scopes are changed into _runtime_ except for _spark-hive-thriftserver_2.12_ - see [pom.xml](https://github.com/jaehyeon-kim/dbt-on-aws/blob/main/emr-eks/hive-on-spark-in-kubernetes/examples/spark-thrift-server/pom.xml) for details. The runner class can be built as shown below.


```bash
cd emr-eks/hive-on-spark-in-kubernetes/examples/spark-thrift-server
mvn -e -DskipTests=true clean install;
```


Once completed, the JAR file of the runner class can be found in the _target_ folder - _spark-thrift-server-1.0.0-SNAPSHOT.jar_.


```bash
$ tree target/ -L 1
target/
├── classes
├── generated-sources
├── maven-archiver
├── maven-status
├── spark-thrift-server-1.0.0-SNAPSHOT-sources.jar
├── spark-thrift-server-1.0.0-SNAPSHOT.jar
└── test-classes

5 directories, 2 files
```

#### Driver Template

We can expose the spark driver pod by a [service](https://kubernetes.io/docs/concepts/services-networking/service/). A [label](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) (app) is added to the driver pod template so that it can be selected by the service.


```yaml
# emr-eks/resources/driver-template.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: spark-thrift-server-driver
spec:
  nodeSelector:
    type: karpenter
    provisioner: spark-driver
  tolerations:
    - key: spark-driver
      operator: Exists
      effect: NoSchedule
  containers:
    - name: spark-kubernetes-driver
```

#### Spark Job Run

The wrapper class and (driver and executor) pod templates are referred from the default S3 bucket of this post. The runner class is specified as the entry point of the spark application and three executor instances with 2G of memory are configured to run. In the application configuration, the dynamic resource allocation is disabled and the AWS Glue Data Catalog is set to be used as the metastore for [Spark SQL](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-spark-glue.html).


```bash
# emr-eks/job-run.sh
export VIRTUAL_CLUSTER_ID=$(terraform -chdir=./infra output --raw emrcontainers_virtual_cluster_id)
export EMR_ROLE_ARN=$(terraform -chdir=./infra output --json emr_on_eks_role_arn | jq '.[0]' -r)
export DEFAULT_BUCKET_NAME=$(terraform -chdir=./infra output --raw default_bucket_name)
export AWS_REGION=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].[RegionName]' --output text)

aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name thrift-server \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.8.0-latest \
--region $AWS_REGION \
--job-driver '{
    "sparkSubmitJobDriver": {
        "entryPoint": "s3://'${DEFAULT_BUCKET_NAME}'/resources/jars/spark-thrift-server-1.0.0-SNAPSHOT.jar",
        "sparkSubmitParameters": "--class io.jaehyeon.hive.SparkThriftServerRunner --jars s3://'${DEFAULT_BUCKET_NAME}'/resources/jars/spark-thrift-server-1.0.0-SNAPSHOT.jar --conf spark.executor.instances=3 --conf spark.executor.memory=2G --conf spark.executor.cores=1 --conf spark.driver.cores=1 --conf spark.driver.memory=2G"
        }
    }' \
--configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.dynamicAllocation.enabled":"false",
          "spark.kubernetes.executor.deleteOnTermination": "true",
          "spark.kubernetes.driver.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/resources/templates/driver-template.yaml",
          "spark.kubernetes.executor.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/resources/templates/executor-template.yaml",
          "spark.hadoop.hive.metastore.client.factory.class":"com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
         }
      }
    ]
}'
```


Once it is started, we can check the spark job pods as shown below. A single driver and three executor pods are deployed as expected.


```bash
$ kubectl get pod -n analytics
NAME                                                READY   STATUS    RESTARTS   AGE
0000000310t0tkbcftg-nmzfh                           2/2     Running   0          5m39s
spark-0000000310t0tkbcftg-6385c0841d09d389-exec-1   1/1     Running   0          3m2s
spark-0000000310t0tkbcftg-6385c0841d09d389-exec-2   1/1     Running   0          3m1s
spark-0000000310t0tkbcftg-6385c0841d09d389-exec-3   1/1     Running   0          3m1s
spark-0000000310t0tkbcftg-driver                    2/2     Running   0          5m26s
```



#### Spark Thrift Server Service

As mentioned earlier, the driver pod is exposed by a service. The service manifest file uses a [label selector](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors) to identify the spark driver pod. As EMR on EC2, the thrift server is mapped to port 10001 by default. Note that the container port is not allowed in the pod templates of EMR on EKS but the service can still access it.


```yaml
# emr-eks/resources/spark-thrift-server-service.yaml
kind: Service
apiVersion: v1
metadata:
  name: spark-thrift-server-service
  namespace: analytics
spec:
  type: LoadBalancer
  selector:
    app: spark-thrift-server-driver
  ports:
    - name: jdbc-port
      protocol: TCP
      port: 10001
      targetPort: 10001
```


The service can be deployed by `kubectl apply -f resources/spark-thrift-server-service.yaml`, and we can check the service details as shown below - we will use the hostname of the service (EXTERNAL-IP) later.

![](thrift-server-svc.png#center)

Similar to beeline, we can check the connection using the _pyhive_ package.


```python
# emr-eks/resources/test_conn.py
from pyhive import hive
import pandas as pd

conn = hive.connect(
    host="<hostname-of-spark-thrift-server-service>",
    port=10001,
    username="hadoop",
    auth=None
    )
print(pd.read_sql(con=conn, sql="show databases"))
conn.close()
```

```bash
$ python resources/test_conn.py
  print(pd.read_sql(con=conn, sql="show databases"))
                       namespace
0                        default
1                           imdb
2                 imdb_analytics
```

## Project

We build a data transformation pipeline using [subsets of IMDb data](https://www.imdb.com/interfaces/) - seven titles and names related datasets are provided as gzipped, tab-separated-values (TSV) formatted files. The project ends up creating three tables that can be used for reporting and analysis.


### Save Data to S3

The [Axel download accelerator](https://github.com/axel-download-accelerator/axel) is used to download the data files locally followed by decompressing with the gzip utility. Note that simple retry logic is added as I see download failure from time to time. Finally, the decompressed files are saved into the project S3 bucket using the [S3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command.


```bash
# dbt-on-aws/emr-eks/upload-data.sh
#!/usr/bin/env bash

s3_bucket=$(terraform -chdir=./infra output --raw default_bucket_name)
hostname="datasets.imdbws.com"
declare -a file_names=(
  "name.basics.tsv.gz" \
  "title.akas.tsv.gz" \
  "title.basics.tsv.gz" \
  "title.crew.tsv.gz" \
  "title.episode.tsv.gz" \
  "title.principals.tsv.gz" \
  "title.ratings.tsv.gz"
  )

rm -rf imdb-data

for fn in "${file_names[@]}"
do
  download_url="https://$hostname/$fn"
  prefix=$(echo ${fn::-7} | tr '.' '_')
  echo "download imdb-data/$prefix/$fn from $download_url"
  while true;
  do
    mkdir -p imdb-data/$prefix
    axel -n 32 -a -o imdb-data/$prefix/$fn $download_url
    gzip -d imdb-data/$prefix/$fn
    num_files=$(ls imdb-data/$prefix | wc -l)
    if [ $num_files == 1 ]; then
      break
    fi
    rm -rf imdb-data/$prefix
  done
done

aws s3 sync ./imdb-data s3://$s3_bucket
```

### Setup dbt Project

We use the [dbt-spark](https://docs.getdbt.com/reference/warehouse-setups/spark-setup) adapter to work with the EMR cluster. As connection is made by the [Thrift JDBC/ODBC server](https://spark.apache.org/docs/latest/sql-distributed-sql-engine.html), it is necessary to install the adapter with the PyHive package. I use Ubuntu 20.04 in WSL 2 and it needs to install the [libsasl2-dev](https://packages.debian.org/sid/libsasl2-dev) apt package, which is required for one of the dependent packages of PyHive (pure-sasl). After installing it, we can install the dbt packages as usual.


```bash
$ sudo apt-get install libsasl2-dev
$ python3 -m venv venv
$ source venv/bin/activate
$ pip install --upgrade pip
$ pip install dbt-core "dbt-spark[PyHive]"
```


We can initialise a dbt project with the [dbt init command](https://docs.getdbt.com/reference/commands/init). We are required to specify project details - project name, host, connection method, port, schema and the number of threads. Note dbt creates the [project profile](https://docs.getdbt.com/dbt-cli/configure-your-profile) to _.dbt/profile.yml_ of the user home directory by default.


```bash
$ dbt init
05:29:39  Running with dbt=1.3.0
Enter a name for your project (letters, digits, underscore): emr_eks
Which database would you like to use?
[1] spark

(Don't see the one you want? https://docs.getdbt.com/docs/available-adapters)

Enter a number: 1
host (yourorg.sparkhost.com): <hostname-of-spark-thrift-server-service>
[1] odbc
[2] http
[3] thrift
Desired authentication method option (enter a number): 3
port [443]: 10001
schema (default schema that dbt will build objects in): imdb
threads (1 or more) [1]: 3
05:30:13  Profile emr_eks written to /home/<username>/.dbt/profiles.yml using target's profile_template.yml and your supplied values. Run 'dbt debug' to validate the connection.
05:30:13  
Your new dbt project "emr_eks" was created!

For more information on how to configure the profiles.yml file,
please consult the dbt documentation here:

  https://docs.getdbt.com/docs/configure-your-profile

One more thing:

Need help? Don't hesitate to reach out to us via GitHub issues or on Slack:

  https://community.getdbt.com/

Happy modeling!
```


dbt initialises a project in a folder that matches to the project name and generates project boilerplate as shown below. Some of the main objects are _[dbt_project.yml](https://docs.getdbt.com/reference/dbt_project.yml)_, and the [model](https://docs.getdbt.com/docs/building-a-dbt-project/building-models) folder. The former is required because dbt doesn't know if a folder is a dbt project without it. Also it contains information that tells dbt how to operate on the project. The latter is for including dbt models, which is basically a set of SQL select statements. See [dbt documentation](https://docs.getdbt.com/docs/introduction) for more details.


```bash
$ tree emr-eks/emr_eks/ -L 1
emr-eks/emr_eks/
├── README.md
├── analyses
├── dbt_packages
├── dbt_project.yml
├── logs
├── macros
├── models
├── packages.yml
├── seeds
├── snapshots
├── target
└── tests
```


We can check connection to the EMR cluster with the [dbt debug command](https://docs.getdbt.com/reference/commands/debug) as shown below.


```bash
$ dbt debug
05:31:22  Running with dbt=1.3.0
dbt version: 1.3.0
python version: 3.8.10
python path: <path-to-python-path>
os info: Linux-5.4.72-microsoft-standard-WSL2-x86_64-with-glibc2.29
Using profiles.yml file at /home/<username>/.dbt/profiles.yml
Using dbt_project.yml file at <path-to-dbt-project>/dbt_project.yml

Configuration:
  profiles.yml file [OK found and valid]
  dbt_project.yml file [OK found and valid]

Required dependencies:
 - git [OK found]

Connection:
  host: <hostname-of-spark-thrift-server-service>
  port: 10001
  cluster: None
  endpoint: None
  schema: imdb
  organization: 0
  Connection test: [OK connection ok]

All checks passed!
```


After initialisation, the model configuration is updated. The project [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations) is specified as view although it is the default materialisation. Also [tags](https://docs.getdbt.com/reference/resource-configs/tags) are added to the entire model folder as well as folders of specific layers - staging, intermediate and marts. As shown below, tags can simplify model execution.


```yaml
# emr-eks/emr_eks/dbt_project.yml
name: "emr_eks"

...

models:
  dbt_glue_proj:
    +materialized: view
    +tags:
      - "imdb"
    staging:
      +tags:
        - "staging"
    intermediate:
      +tags:
        - "intermediate"
    marts:
      +tags:
        - "marts"
```


While we created source tables using Glue crawlers in [part 2](/blog/2022-10-09-dbt-on-aws-part-2-glue), they are created directly from S3 by the [dbt_external_tables](https://hub.getdbt.com/dbt-labs/dbt_external_tables/latest/) package in this post. Also the [dbt_utils](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) package is installed for adding tests to the final marts models. They can be installed by the [dbt deps command](https://docs.getdbt.com/reference/commands/deps).


```yaml
# emr-eks/emr_eks/packages.yml
packages:
  - package: dbt-labs/dbt_external_tables
    version: 0.8.2
  - package: dbt-labs/dbt_utils
    version: 0.9.2
```

### Create dbt Models

The models for this post are organised into three layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview) - staging, intermediate and marts.


#### External Source

The seven tables that are loaded from S3 are [dbt source](https://docs.getdbt.com/docs/building-a-dbt-project/using-sources) tables and their details are declared in a YAML file (__imdb_sources.yml_). [Macros](https://docs.getdbt.com/docs/build/jinja-macros) of the [dbt_external_tables](https://hub.getdbt.com/dbt-labs/dbt_external_tables/latest/) package parse properties of each table and execute SQL to create each of them. By doing so, we are able to refer to the source tables with the `{{ source() }}` function. Also, we can add tests to source tables. For example two tests (unique, not_null) are added to the _tconst_ column of the _title_basics_ table below and these tests can be executed by the [dbt test command](https://docs.getdbt.com/reference/commands/test).


```yaml
# emr-eks/emr_eks/models/staging/imdb/_imdb__sources.yml
version: 2

sources:
  - name: imdb
    description: Subsets of IMDb data, which are available for access to customers for personal and non-commercial use
    tables:
      - name: title_basics
        description: Table that contains basic information of titles
        external:
          location: "s3://<s3-bucket-name>/title_basics/"
          row_format: >
            serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
            with serdeproperties (
              'separatorChar'='\t'
            )
          table_properties: "('skip.header.line.count'='1')"
        columns:
          - name: tconst
            data_type: string
            description: alphanumeric unique identifier of the title
            tests:
              - unique
              - not_null
          - name: titletype
            data_type: string
            description: the type/format of the title (e.g. movie, short, tvseries, tvepisode, video, etc)
          - name: primarytitle
            data_type: string
            description: the more popular title / the title used by the filmmakers on promotional materials at the point of release
          - name: originaltitle
            data_type: string
            description: original title, in the original language
          - name: isadult
            data_type: string
            description: flag that indicates whether it is an adult title or not
          - name: startyear
            data_type: string
            description: represents the release year of a title. In the case of TV Series, it is the series start year
          - name: endyear
            data_type: string
            description: TV Series end year. NULL for all other title types
          - name: runtimeminutes
            data_type: string
            description: primary runtime of the title, in minutes
          - name: genres
            data_type: string
            description: includes up to three genres associated with the title
```


The source tables can be created  by `dbt run-operation stage_external_sources`. Note that the following SQL is executed for the _title_basics _table under the hood. 


```sql
create table imdb.title_basics (
    tconst string,
    titletype string,
    primarytitle string,
    originaltitle string,
    isadult string,
    startyear string,
    endyear string,
    runtimeminutes string,
    genres string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde' with serdeproperties (
'separatorChar'='\t'
)
location 's3://<s3-bucket-name>/title_basics/'
tblproperties ('skip.header.line.count'='1')
```


Interestingly the header rows of the source tables are not skipped when they are queried by spark while they are skipped by Athena. They have to be filtered out in the stage models of the dbt project as spark is the query engine.

![](emr-eks-source-show.png#center)

#### Staging

Based on the source tables, staging models are created. They are created as views, which is the project’s default [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations). In the SQL statements, column names and data types are modified mainly.


```sql
# emr-eks/emr_eks/models/staging/imdb/stg_imdb__title_basics.sql
with source as (

    select * from {{ source('imdb', 'title_basics') }}

),

renamed as (

    select
        tconst as title_id,
        titletype as title_type,
        primarytitle as primary_title,
        originaltitle as original_title,
        cast(isadult as boolean) as is_adult,
        cast(startyear as int) as start_year,
        cast(endyear as int) as end_year,
        cast(runtimeminutes as int) as runtime_minutes,
        case when genres = 'N' then null else genres end as genres
    from source
    where tconst <> 'tconst'

)

select * from renamed
```


Below shows the file tree of the staging models. The staging models can be executed using the [dbt run command](https://docs.getdbt.com/reference/commands/run). As we’ve added [tags](https://docs.getdbt.com/reference/resource-configs/tags) to the staging layer models, we can limit to execute only this layer by `dbt run --select staging`.


```bash
$ tree emr-eks/emr_eks/models/staging/
emr-eks/emr_eks/models/staging/
└── imdb
    ├── _imdb__models.yml
    ├── _imdb__sources.yml
    ├── stg_imdb__name_basics.sql
    ├── stg_imdb__title_akas.sql
    ├── stg_imdb__title_basics.sql
    ├── stg_imdb__title_crews.sql
    ├── stg_imdb__title_episodes.sql
    ├── stg_imdb__title_principals.sql
    └── stg_imdb__title_ratings.sql
```


Note that the model materialisation of the staging and intermediate models is _view_ and the dbt project creates _VIRTUAL_VIEW_ tables. Although we are able to reference those tables in other models, they cannot be queried by Athena. 


```bash
$ aws glue get-tables --database imdb \
 --query "TableList[?Name=='stg_imdb__title_basics'].[Name, TableType, StorageDescriptor.Columns]" --output yaml
- - stg_imdb__title_basics
  - VIRTUAL_VIEW
  - - Name: title_id
      Type: string
    - Name: title_type
      Type: string
    - Name: primary_title
      Type: string
    - Name: original_title
      Type: string
    - Name: is_adult
      Type: boolean
    - Name: start_year
      Type: int
    - Name: end_year
      Type: int
    - Name: runtime_minutes
      Type: int
    - Name: genres
      Type: string
```


Instead we can use spark sql to query the tables. Below shows a query result of the title basics staging table in Glue Studio notebook.

![](emr-eks-staging-show.png#center)

#### Intermediate

We can keep intermediate results in this layer so that the models of the final marts layer can be simplified. The source data includes columns where array values are kept as comma separated strings. For example, the genres column of the _stg_imdb__title_basics_ model includes up to three genre values as shown in the previous screenshot. A total of seven columns in three models are columns of comma-separated strings, and it is better to flatten them in the intermediate layer. Also, in order to avoid repetition, a [dbt macro](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) (f_latten_fields_) is created to share the column-flattening logic.


```sql
# emr-eks/emr_eks/macros/flatten_fields.sql
{% macro flatten_fields(model, field_name, id_field_name) %}
    select
        {{ id_field_name }} as id,
        explode(split({{ field_name }}, ',')) as field
    from {{ model }}
{% endmacro %}
```


The macro function can be added inside a [common table expression (CTE)](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html) by specifying the relevant model, field name to flatten and ID field name.


```sql
-- emr-eks/emr_eks/models/intermediate/title/int_genres_flattened_from_title_basics.sql
with flattened as (
    {{ flatten_fields(ref('stg_imdb__title_basics'), 'genres', 'title_id') }}
)

select
    id as title_id,
    field as genre
from flattened
order by id
```


The intermediate models are also materialised as views and we can check the array columns are flattened as expected.

![](emr-eks-intremediate-show.png#center)

Below shows the file tree of the intermediate models. Similar to the staging models, the intermediate models can be executed by `dbt run --select intermediate`.


```bash
$ tree emr-eks/emr_eks/models/intermediate/ emr-eks/emr_eks/macros/
emr-eks/emr_eks/models/intermediate/
├── name
│   ├── _int_name__models.yml
│   ├── int_known_for_titles_flattened_from_name_basics.sql
│   └── int_primary_profession_flattened_from_name_basics.sql
└── title
    ├── _int_title__models.yml
    ├── int_directors_flattened_from_title_crews.sql
    ├── int_genres_flattened_from_title_basics.sql
    └── int_writers_flattened_from_title_crews.sql

emr-eks/emr_eks/macros/
└── flatten_fields.sql
```

#### Marts

The models in the marts layer are configured to be materialised as tables in a custom schema. Their materialisation is set to _table_ and the custom schema is specified as _analytics_ while taking _parquet _as the file format. Note that the custom schema name becomes _imdb_analytics_ according to the naming convention of [dbt custom schemas](https://docs.getdbt.com/docs/build/custom-schemas). Models of both the staging and intermediate layers are used to create final models to be used for reporting and analytics.


```sql
-- emr-eks/emr_eks/models/marts/analytics/titles.sql
{{
    config(
        schema='analytics',
        materialized='table',
        file_format='parquet'
    )
}}

with titles as (

    select * from {{ ref('stg_imdb__title_basics') }}

),

principals as (

    select
        title_id,
        count(name_id) as num_principals
    from {{ ref('stg_imdb__title_principals') }}
    group by title_id

),

names as (

    select
        title_id,
        count(name_id) as num_names
    from {{ ref('int_known_for_titles_flattened_from_name_basics') }}
    group by title_id

),

ratings as (

    select
        title_id,
        average_rating,
        num_votes
    from {{ ref('stg_imdb__title_ratings') }}

),

episodes as (

    select
        parent_title_id,
        count(title_id) as num_episodes
    from {{ ref('stg_imdb__title_episodes') }}
    group by parent_title_id

),

distributions as (

    select
        title_id,
        count(title) as num_distributions
    from {{ ref('stg_imdb__title_akas') }}
    group by title_id

),

final as (

    select
        t.title_id,
        t.title_type,
        t.primary_title,
        t.original_title,
        t.is_adult,
        t.start_year,
        t.end_year,
        t.runtime_minutes,
        t.genres,
        p.num_principals,
        n.num_names,
        r.average_rating,
        r.num_votes,
        e.num_episodes,
        d.num_distributions
    from titles as t
    left join principals as p on t.title_id = p.title_id
    left join names as n on t.title_id = n.title_id
    left join ratings as r on t.title_id = r.title_id
    left join episodes as e on t.title_id = e.parent_title_id
    left join distributions as d on t.title_id = d.title_id

)

select * from final
```


The details of the three models can be found in a YAML file (__analytics__models.yml_). We can add tests to models and below we see tests of row count matching to their corresponding staging models.


```yaml
# emr-eks/emr_eks/models/marts/analytics/_analytics__models.yml
version: 2

models:
  - name: names
    description: Table that contains all names with additional details
    tests:
      - dbt_utils.equal_rowcount:
          compare_model: ref('stg_imdb__name_basics')
  - name: titles
    description: Table that contains all titles with additional details
    tests:
      - dbt_utils.equal_rowcount:
          compare_model: ref('stg_imdb__title_basics')
  - name: genre_titles
    description: Table that contains basic title details after flattening genres
```


The models of the marts layer can be tested using the [dbt test command](https://docs.getdbt.com/reference/commands/test) as shown below.


```bash
$ dbt test --select marts
06:05:30  Running with dbt=1.3.0
06:05:30  Found 15 models, 17 tests, 0 snapshots, 0 analyses, 569 macros, 0 operations, 0 seed files, 7 sources, 0 exposures, 0 metrics
06:05:30  
06:06:03  Concurrency: 3 threads (target='dev')
06:06:03  
06:06:03  1 of 2 START test dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .... [RUN]
06:06:03  2 of 2 START test dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ .. [RUN]
06:06:57  1 of 2 PASS dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .......... [PASS in 53.54s]
06:06:59  2 of 2 PASS dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ ........ [PASS in 56.40s]
06:07:02  
06:07:02  Finished running 2 tests in 0 hours 1 minutes and 31.75 seconds (91.75s).
06:07:02  
06:07:02  Completed successfully
06:07:02  
06:07:02  Done. PASS=2 WARN=0 ERROR=0 SKIP=0 TOTAL=2
```


As with the other layers, the marts models can be executed by `dbt run --select marts`. While the transformation is performed, we can check the details from the spark history server. The SQL tab shows the three transformations in the marts layer.

![](spark-history-server.png#center)

The file tree of the marts models can be found below.


```bash
$ tree emr-eks/emr_eks/models/marts/
emr-eks/emr_eks/models/marts/
└── analytics
    ├── _analytics__models.yml
    ├── genre_titles.sql
    ├── names.sql
    └── titles.sql
```

### Build Dashboard

The models of the marts layer can be consumed by external tools such as [Amazon QuickSight](https://aws.amazon.com/quicksight/). Below shows an example dashboard. The pie chart on the left shows the proportion of titles by genre while the box plot on the right shows the dispersion of average rating by start year.

![](emr-eks-quicksight.png#center)

### Generate dbt Documentation

A nice feature of dbt is [documentation](https://docs.getdbt.com/docs/building-a-dbt-project/documentation). It provides information about the project and the data warehouse, and it facilitates consumers as well as other developers to discover and understand the datasets better. We can generate the project documents and start a document server as shown below.


```bash
$ dbt docs generate
$ dbt docs serve
```

![](emr-eks-doc-01.png#center)

A very useful element of dbt documentation is [data lineage](https://docs.getdbt.com/terms/data-lineage), which provides an overall view about how data is transformed and consumed. Below we can see that the final titles model consumes all title-related stating models and an intermediate model from the name basics staging model.

![](emr-eks-doc-02.png#center)

## Summary

In this post, we discussed how to build data transformation pipelines using dbt on Amazon EMR on EKS. As Spark Submit does not allow the spark thrift server to run in cluster mode on Kubernetes, a simple wrapper class was created that makes the thrift server run indefinitely. Subsets of IMDb data are used as source and data models are developed in multiple layers according to the dbt best practices. dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse, and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. More examples of using dbt will be discussed in subsequent posts.
