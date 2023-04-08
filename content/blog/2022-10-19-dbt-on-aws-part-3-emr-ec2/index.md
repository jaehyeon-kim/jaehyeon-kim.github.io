---
title: Data Build Tool (dbt) for Effective Data Transformation on AWS – Part 3 EMR on EC2
date: 2022-10-19
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
  - Amazon QuickSight
  - Data Build Tool (DBT)
  - Apache Spark
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 20
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/dbt-on-aws-part-3/).

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an effective data transformation tool and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In the previous posts, we discussed benefits of a common data transformation tool and the potential of dbt to cover a wide range of data projects from data warehousing to data lake to data lakehouse. Demo data projects that target Redshift Serverless and Glue are illustrated as well. In part 3 of the dbt on AWS series, we discuss data transformation pipelines using dbt on [Amazon EMR](https://aws.amazon.com/emr/). [Subsets of IMDb data](https://www.imdb.com/interfaces/) are used as source and data models are developed in multiple layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview). A list of posts of this series can be found below.

* [Part 1 Redshift](/blog/2022-09-28-dbt-on-aws-part-1-redshift)
* [Part 2 Glue](/blog/2022-10-09-dbt-on-aws-part-2-glue)
* [Part 3 EMR on EC2](#) (this post)
* [Part 4 EMR on EKS](/blog/2022-11-01-dbt-on-aws-part-4-emr-eks)
* [Part 5 Athena](/blog/2023-04-12-integrate-glue-schema-registry)

Below shows an overview diagram of the scope of this dbt on AWS series. EMR is highlighted as it is discussed in this post.

![](featured.png#center)


## Infrastructure

The infrastructure hosting this solution leverages an Amazon EMR cluster and a S3 bucket. We also need a VPN server so that a developer can connect to the EMR cluster in a private subnet. It is extended from a [previous post](/blog/2022-02-06-dev-infra-terraform) and the resources covered there (VPC, subnets, auto scaling group for VPN etc) are not repeated. All resources are deployed using Terraform and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-on-aws) of this post.


### EMR Cluster

The EMR 6.7.0 release is deployed with single master and core node instances. It is configured to use the AWS Glue Data Catalog as the metastore for [Hive](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hive-metastore-glue.html) and [Spark SQL](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-spark-glue.html) and it is done by adding the corresponding configuration classification. Also a managed scaling policy is created so that up to 4 additional task instances are added to the cluster. Note an additional security group is attached to the master and core groups for VPN access - the details of that security group is shown below.


```terraform
# dbt-on-aws/emr-ec2/infra/emr.tf
resource "aws_emr_cluster" "emr_cluster" {
  name                              = "${local.name}-emr-cluster"
  release_label                     = local.emr.release_label # emr-6.7.0
  service_role                      = aws_iam_role.emr_service_role.arn
  autoscaling_role                  = aws_iam_role.emr_autoscaling_role.arn
  applications                      = local.emr.applications # ["Spark", "Livy", "JupyterEnterpriseGateway", "Hive"]
  ebs_root_volume_size              = local.emr.ebs_root_volume_size
  log_uri                           = "s3n://${aws_s3_bucket.default_bucket[0].id}/elasticmapreduce/"
  step_concurrency_level            = 256
  keep_job_flow_alive_when_no_steps = true
  termination_protection            = false

  ec2_attributes {
    key_name                          = aws_key_pair.emr_key_pair.key_name
    instance_profile                  = aws_iam_instance_profile.emr_ec2_instance_profile.arn
    subnet_id                         = element(tolist(module.vpc.private_subnets), 0)
    emr_managed_master_security_group = aws_security_group.emr_master.id
    emr_managed_slave_security_group  = aws_security_group.emr_slave.id
    service_access_security_group     = aws_security_group.emr_service_access.id
    additional_master_security_groups = aws_security_group.emr_vpn_access.id # grant access to VPN server
    additional_slave_security_groups  = aws_security_group.emr_vpn_access.id # grant access to VPN server
  }

  master_instance_group {
    instance_type  = local.emr.instance_type # m5.xlarge
    instance_count = local.emr.instance_count # 1
  }
  core_instance_group {
    instance_type  = local.emr.instance_type # m5.xlarge
    instance_count = local.emr.instance_count # 1
  }

  configurations_json = <<EOF
    [
      {
          "Classification": "hive-site",
          "Properties": {
              "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
          }
      },
      {
          "Classification": "spark-hive-site",
          "Properties": {
              "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
          }
      }
    ]
  EOF

  tags = local.tags

  depends_on = [module.vpc]
}

resource "aws_emr_managed_scaling_policy" "emr_scaling_policy" {
  cluster_id = aws_emr_cluster.emr_cluster.id

  compute_limits {
    unit_type              = "Instances"
    minimum_capacity_units = 1
    maximum_capacity_units = 5
  }
}
```


The following security group is created to enable access from the VPN server to the EMR instances. Note that the inbound rule is created only when the _local.vpn.to_create_ variable value is true while the security group is created always - if the value is false, the security group has no inbound rule. 


```terraform
# dbt-on-aws/emr-ec2/infra/emr.tf
resource "aws_security_group" "emr_vpn_access" {
  name   = "${local.name}-emr-vpn-access"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_security_group_rule" "emr_vpn_inbound" {
  count                    = local.vpn.to_create ? 1 : 0
  type                     = "ingress"
  description              = "VPN access"
  security_group_id        = aws_security_group.emr_vpn_access.id
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = aws_security_group.vpn[0].id
}
```


As in the [previous post](/blog/2022-02-06-dev-infra-terraform), we connect to the EMR cluster via [SoftEther VPN](https://www.softether.org/). Instead of providing VPN related secrets as Terraform variables, they are created internally and stored to AWS Secrets Manager. The details can be found in [dbt-on-aws/emr-ec2/infra/secrets.tf](https://github.com/jaehyeon-kim/dbt-on-aws/blob/main/emr-ec2/infra/secrets.tf) and the secret string can be retrieved as shown below. 


```bash
$ aws secretsmanager get-secret-value --secret-id emr-ec2-all-secrets --query "SecretString" --output text
  {
    "vpn_pre_shared_key": "<vpn-pre-shared-key>",
    "vpn_admin_password": "<vpn-admin-password>"
  }
```

The [previous post](/blog/2022-02-06-dev-infra-terraform) demonstrates how to create a VPN user and to establish connection in detail. An example of a successful connection is shown below.

![](emr-ec2-vpn.png#center)

### Glue Databases

We have two Glue databases. The source tables and the tables of the staging and intermediate layers are kept in the _imdb_ database. The tables of the marts layer are stored in the _imdb_analytics _database.


```terraform
# glue databases
resource "aws_glue_catalog_database" "imdb_db" {
  name         = "imdb"
  location_uri = "s3://${local.default_bucket.name}/imdb"
  description  = "Database that contains IMDb staging/intermediate model datasets"
}

resource "aws_glue_catalog_database" "imdb_db_marts" {
  name         = "imdb_analytics"
  location_uri = "s3://${local.default_bucket.name}/imdb_analytics"
  description  = "Database that contains IMDb marts model datasets"
}
```

## Project

We build a data transformation pipeline using [subsets of IMDb data](https://www.imdb.com/interfaces/) - seven titles and names related datasets are provided as gzipped, tab-separated-values (TSV) formatted files. The project ends up creating three tables that can be used for reporting and analysis.


### Save Data to S3

The [Axel download accelerator](https://github.com/axel-download-accelerator/axel) is used to download the data files locally followed by decompressing with the gzip utility. Note that simple retry logic is added as I see download failure from time to time. Finally, the decompressed files are saved into the project S3 bucket using the [S3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command.


```bash
# dbt-on-aws/emr-ec2/upload-data.sh
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

### Start Thrift JDBC/ODBC Server

The connection from dbt to the EMR cluster is made by the [Thrift JDBC/ODBC server](https://spark.apache.org/docs/latest/sql-distributed-sql-engine.html) and it can be started by adding an EMR step as shown below.


```bash
$ cd emr-ec2
$ CLUSTER_ID=$(terraform -chdir=./infra output --raw emr_cluster_id)
$ aws emr add-steps \
  --cluster-id $CLUSTER_ID \
  --steps Type=CUSTOM_JAR,Name="spark thrift server",ActionOnFailure=CONTINUE,Jar=command-runner.jar,Args=[sudo,/usr/lib/spark/sbin/start-thriftserver.sh]
```


We can quickly check if the thrift server is started using the beeline JDBC client. The port is 10001 and, as connection is made in non-secure mode, we can simply enter the default username and a blank password. When we query databases, we see the Glue databases that are created earlier.


```bash
$ STACK_NAME=emr-ec2
$ EMR_CLUSTER_MASTER_DNS=$(terraform -chdir=./infra output --raw emr_cluster_master_dns)
$ ssh -i infra/key-pair/$STACK_NAME-emr-key.pem hadoop@$EMR_CLUSTER_MASTER_DNS
Last login: Thu Oct 13 08:59:51 2022 from ip-10-0-32-240.ap-southeast-2.compute.internal


...


[hadoop@ip-10-0-113-195 ~]$ beeline
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hive/lib/log4j-slf4j-impl-2.17.1.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.apache.logging.slf4j.Log4jLoggerFactory]
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hive/lib/log4j-slf4j-impl-2.17.1.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.apache.logging.slf4j.Log4jLoggerFactory]
Beeline version 3.1.3-amzn-0 by Apache Hive
beeline> !connect jdbc:hive2://localhost:10001
Connecting to jdbc:hive2://localhost:10001
Enter username for jdbc:hive2://localhost:10001: hadoop
Enter password for jdbc:hive2://localhost:10001:
Connected to: Spark SQL (version 3.2.1-amzn-0)
Driver: Hive JDBC (version 3.1.3-amzn-0)
Transaction isolation: TRANSACTION_REPEATABLE_READ
0: jdbc:hive2://localhost:10001> show databases;
+-------------------------------+
|           namespace           |
+-------------------------------+
| default                       |
| imdb                          |
| imdb_analytics                |
+-------------------------------+
3 rows selected (0.311 seconds)
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
21:00:16  Running with dbt=1.2.2
Enter a name for your project (letters, digits, underscore): emr_ec2
Which database would you like to use?
[1] spark

(Don't see the one you want? https://docs.getdbt.com/docs/available-adapters)

Enter a number: 1
host (yourorg.sparkhost.com): <hostname-or-ip-address-of-master-instance>
[1] odbc
[2] http
[3] thrift
Desired authentication method option (enter a number): 3
port [443]: 10001
schema (default schema that dbt will build objects in): imdb
threads (1 or more) [1]: 3
21:50:28  Profile emr_ec2 written to /home/<username>/.dbt/profiles.yml using target's profile_template.yml and your supplied values. Run 'dbt debug' to validate the connection.
21:50:28  
Your new dbt project "emr_ec2" was created!

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
$ tree emr-ec2/emr_ec2/ -L 1
emr-ec2/emr_ec2/
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
21:51:38  Running with dbt=1.2.2
dbt version: 1.2.2
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
  host: 10.0.113.195
  port: 10001
  cluster: None
  endpoint: None
  schema: imdb
  organization: 0
  Connection test: [OK connection ok]

All checks passed!
```


After initialisation, the model configuration is updated. The project [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations) is specified as view, although it is the default materialisation. Also, [tags](https://docs.getdbt.com/reference/resource-configs/tags) are added to the entire model folder as well as folders of specific layers - staging, intermediate and marts. As shown below, tags can simplify model execution.


```yaml
# emr-ec2/emr_ec2/dbt_project.yml
name: "emr_ec2"

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


While we created source tables using Glue crawlers in [part 2](/blog/2021-12-12-datalake-demo-part2), they are created directly from S3 by the [dbt_external_tables](https://hub.getdbt.com/dbt-labs/dbt_external_tables/latest/) package in this post. Also, the [dbt_utils](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) package is installed for adding tests to the final marts models. They can be installed by the [dbt deps command](https://docs.getdbt.com/reference/commands/deps).


```yaml
# emr-ec2/emr_ec2/packages.yml
packages:
  - package: dbt-labs/dbt_external_tables
    version: 0.8.2
  - package: dbt-labs/dbt_utils
    version: 0.9.2
```

### Create dbt Models

The models for this post are organised into three layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview) - staging, intermediate and marts.


#### External Source

The seven tables that are loaded from S3 are [dbt source](https://docs.getdbt.com/docs/building-a-dbt-project/using-sources) tables and their details are declared in a YAML file (__imdb_sources.yml_). [Macros](https://docs.getdbt.com/docs/build/jinja-macros) of the [dbt_external_tables](https://hub.getdbt.com/dbt-labs/dbt_external_tables/latest/) package parse properties of each table and execute SQL to create each of them. By doing so, we are able to refer to the source tables with the `{{ source() }}` function. Also we can add tests to source tables. For example two tests (unique, not_null) are added to the _tconst_ column of the _title_basics_ table below and these tests can be executed by the [dbt test command](https://docs.getdbt.com/reference/commands/test).


```yaml
# emr-ec2/emr_ec2/models/staging/imdb/_imdb__sources.yml
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


The source tables can be created by `dbt run-operation stage_external_sources`. Note that the following SQL is executed for the _title_basics _table under the hood. 


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

![](emr-ec2-source-show.png#center)

#### Staging

Based on the source tables, staging models are created. They are created as views, which is the project’s default [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations). In the SQL statements, column names and data types are modified mainly.


```sql
# emr-ec2/emr_ec2/models/staging/imdb/stg_imdb__title_basics.sql
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


Below shows the file tree of the staging models. The staging models can be executed using the [dbt run command](https://docs.getdbt.com/reference/commands/run). As we’ve added [tags](https://docs.getdbt.com/reference/resource-configs/tags) to the staging layer models, we can limit to execute only this layer by <code>dbt run <em>--select staging</em></code>.


```bash
$ tree emr-ec2/emr_ec2/models/staging/
emr-ec2/emr_ec2/models/staging/
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


Instead we can use spark sql to query the tables as shown below.

![](emr-ec2-staging-show.png#center)

#### Intermediate

We can keep intermediate results in this layer so that the models of the final marts layer can be simplified. The source data includes columns where array values are kept as comma separated strings. For example, the genres column of the _stg_imdb__title_basics_ model includes up to three genre values as shown in the previous screenshot. A total of seven columns in three models are columns of comma-separated strings and it is better to flatten them in the intermediate layer. Also, in order to avoid repetition, a [dbt macro](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) (f_latten_fields_) is created to share the column-flattening logic.


```sql
# emr-ec2/emr_ec2/macros/flatten_fields.sql
{% macro flatten_fields(model, field_name, id_field_name) %}
    select
        {{ id_field_name }} as id,
        explode(split({{ field_name }}, ',')) as field
    from {{ model }}
{% endmacro %}
```


The macro function can be added inside a [common table expression (CTE)](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html) by specifying the relevant model, field name to flatten and id field name.


```sql
-- emr-ec2/emr_ec2/models/intermediate/title/int_genres_flattened_from_title_basics.sql
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

![](emr-ec2-intremediate-show.png#center)

Below shows the file tree of the intermediate models. Similar to the staging models, the intermediate models can be executed by `dbt run --select intermediate`.


```bash
$ tree emr-ec2/emr_ec2/models/intermediate/ emr-ec2/emr_ec2/macros/
emr-ec2/emr_ec2/models/intermediate/
├── name
│   ├── _int_name__models.yml
│   ├── int_known_for_titles_flattened_from_name_basics.sql
│   └── int_primary_profession_flattened_from_name_basics.sql
└── title
    ├── _int_title__models.yml
    ├── int_directors_flattened_from_title_crews.sql
    ├── int_genres_flattened_from_title_basics.sql
    └── int_writers_flattened_from_title_crews.sql

emr-ec2/emr_ec2/macros/
└── flatten_fields.sql
```

#### Marts

The models in the marts layer are configured to be materialised as tables in a custom schema. Their materialisation is set to _table_ and the custom schema is specified as _analytics_ while taking _parquet _as the file format. Note that the custom schema name becomes _imdb_analytics_ according to the naming convention of [dbt custom schemas](https://docs.getdbt.com/docs/build/custom-schemas). Models of both the staging and intermediate layers are used to create final models to be used for reporting and analytics.


```sql
-- emr-ec2/emr_ec2/models/marts/analytics/titles.sql
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
# emr-ec2/emr_ec2/models/marts/analytics/_analytics__models.yml
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
19:29:31  Running with dbt=1.2.2
19:29:31  Found 15 models, 17 tests, 0 snapshots, 0 analyses, 533 macros, 0 operations, 0 seed files, 7 sources, 0 exposures, 0 metrics
19:29:31  
19:29:41  Concurrency: 3 threads (target='dev')
19:29:41  
19:29:41  1 of 2 START test dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .... [RUN]
19:29:41  2 of 2 START test dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ .. [RUN]
19:29:54  1 of 2 PASS dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .......... [PASS in 13.11s]
19:29:56  2 of 2 PASS dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ ........ [PASS in 15.14s]
19:29:56  
19:29:56  Finished running 2 tests in 0 hours 0 minutes and 25.54 seconds (25.54s).
19:29:56  
19:29:56  Completed successfully
19:29:56  
19:29:56  Done. PASS=2 WARN=0 ERROR=0 SKIP=0 TOTAL=2
```


Below shows the file tree of the marts models. As with the other layers, the marts models can be executed by `dbt run --select marts`.


```bash
$ tree emr-ec2/emr_ec2/models/marts/
emr-ec2/emr_ec2/models/marts/
└── analytics
    ├── _analytics__models.yml
    ├── genre_titles.sql
    ├── names.sql
    └── titles.sql
```

### Build Dashboard

The models of the marts layer can be consumed by external tools such as [Amazon QuickSight](https://aws.amazon.com/quicksight/). Below shows an example dashboard. The pie chart on the left shows the proportion of titles by genre while the box plot on the right shows the dispersion of average rating by title type.

![](emr-ec2-quicksight.png#center)

### Generate dbt Documentation

A nice feature of dbt is [documentation](https://docs.getdbt.com/docs/building-a-dbt-project/documentation). It provides information about the project and the data warehouse and it facilitates consumers as well as other developers to discover and understand the datasets better. We can generate the project documents and start a document server as shown below.


```bash
$ dbt docs generate
$ dbt docs serve
```

![](emr-ec2-doc-01.png#center)

A very useful element of dbt documentation is [data lineage](https://docs.getdbt.com/terms/data-lineage), which provides an overall view about how data is transformed and consumed. Below we can see that the final titles model consumes all title-related stating models and an intermediate model from the name basics staging model.

![](emr-ec2-doc-02.png#center)

## Summary

In this post, we discussed how to build data transformation pipelines using dbt on Amazon EMR. Subsets of IMDb data are used as source and data models are developed in multiple layers according to the dbt best practices. dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. More examples of using dbt will be discussed in subsequent posts.
