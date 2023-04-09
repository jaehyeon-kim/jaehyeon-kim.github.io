---
title: Data Build Tool (dbt) for Effective Data Transformation on AWS – Part 1 Redshift
date: 2022-09-28
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
  - Amazon Redshift
  - Data Build Tool (DBT)
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 18
---

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an effective data transformation tool and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In part 1 of the dbt on AWS series, we discuss data transformation pipelines using dbt on [Redshift Serverless](https://aws.amazon.com/redshift/redshift-serverless/). [Subsets of IMDb data](https://www.imdb.com/interfaces/) are used as source and data models are developed in multiple layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview).

* [Part 1 Redshift](#) (this post)
* [Part 2 Glue](/blog/2022-10-09-dbt-on-aws-part-2-glue)
* [Part 3 EMR on EC2](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2)
* [Part 4 EMR on EKS](/blog/2022-11-01-dbt-on-aws-part-4-emr-eks)
* [Part 5 Athena](/blog/2023-04-12-integrate-glue-schema-registry)


## Motivation

In our experience delivering data solutions for our customers, we have observed a desire to move away from a centralised team function, responsible for the data collection, analysis and reporting, towards shifting this responsibility to an organisation's lines of business (LOB) teams. The key driver for this comes from the recognition that LOBs retain the deep data knowledge and business understanding for their respective data domain; which improves the speed with which these teams can develop data solutions and gain customer insights. This shift away from centralised data engineering to LOBs exposed a skills and tooling gap.

Let's assume as a starting point that the central data engineering team has chosen a project that migrates an on-premise data warehouse into a data lake (spark + iceberg + redshift) on AWS, to provide a cost-effective way to serve data consumers thanks to iceberg's ACID transaction features. The LOB data engineers are new to spark, and they have a little bit of experience in python while the majority of their work is based on SQL. Thanks to their expertise in SQL, however, they are able to get started building data transformation logic on jupyter notebooks using Pyspark. However, they soon find the codebase gets quite bigger even during the minimum valuable product (MVP) phase, which would only amplify the issue as they extend it to cover the entire data warehouse. Additionally the use of notebooks makes development challenging mainly due to lack of modularity and fai,ling to incorporate testing. Upon contacting the central data engineering team for assistance they are advised that the team uses scala and many other tools (e.g. Metorikku) that are successful for them, however cannot be used directly by the engineers of the LOB. Moreover, the engineering team don't even have a suitable data transformation framework that supports iceberg. The LOB data engineering team understand that the data democratisation plan of the enterprise can be more effective if there is a tool or framework that:
* can be shared across LOBs although they can have different technology stack and practices,
* fits into various project types from traditional data warehousing to data lakehouse projects, and
* supports more than a notebook environment by facilitating code modularity and incorporating testing.

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an open-source command line tool, and it does the **T** in ELT (Extract, Load, Transform) processes well. It supports a wide range of [data platforms](https://docs.getdbt.com/docs/supported-data-platforms) and the following key AWS analytics services are covered - Redshift, Glue, EMR and Athena. It is one of the most popular tools in the [modern data stack](https://www.getdbt.com/blog/future-of-the-modern-data-stack/) that originally covers data warehousing projects. Its scope is extended to data lake projects by the addition of the [dbt-spark](https://github.com/dbt-labs/dbt-spark) and [dbt-glue](https://github.com/aws-samples/dbt-glue) adapter where we can develop data lakes with spark SQL. Recently the spark adapter added open source table formats (hudi, iceberg and delta lake) as the supported file formats, and it allows you to work on data lake house projects with it. As discussed in this [blog post](https://towardsdatascience.com/modern-data-stack-which-place-for-spark-8e10365a8772), dbt has clear advantages compared to spark in terms of
* low learning curve as SQL is easier than spark
* better code organisation as there is no correct way of organising transformation pipeline with spark

On the other hand, its weaknesses are 
* lack of expressiveness as [Jinja](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) is quite heavy and verbose, not very readable, and unit-testing is rather tedious
* limitation of SQL as some logic is much easier to implement with user defined functions rather than SQL

Those weaknesses can be overcome by [Python models](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/python-models) as it allows you to apply transformations as DataFrame operations. Unfortunately the beta feature is not available on any of the AWS services, however it is available on Snowflake, Databricks and BigQuery. Hopefully we can use this feature on Redshift, Glue and EMR in the near future.

Finally, the following areas are supported by spark, however not supported by DBT:
* E and L of ELT processes
* real time data processing

Overall dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse. Also it can be more powerful with spark by its Python models feature. Below shows an overview diagram of the scope of this dbt on AWS series. Redshift is highlighted as it is discussed in this post. 

![](featured.png#center)

## Infrastructure

A VPC with 3 public and private subnets is created using the [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest). The following Redshift serverless resources are deployed to work with the dbt project. As explained in the [Redshift user guide](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-workgroup-namespace.html), a namespace is a collection of database objects and users and a workgroup is a collection of compute resources. We also need a [Redshift-managed VPC endpoint](https://docs.aws.amazon.com/redshift/latest/mgmt/managing-cluster-cross-vpc.html) for a private connection from a client tool. The source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-on-aws) of this post.


```terraform
# redshift-sls/infra/redshift-sls.tf
resource "aws_redshiftserverless_namespace" "namespace" {
  namespace_name = "${local.name}-namespace"

  admin_username       = local.redshift.admin_username
  admin_user_password  = local.secrets.redshift_admin_password
  db_name              = local.redshift.db_name
  default_iam_role_arn = aws_iam_role.redshift_serverless_role.arn
  iam_roles            = [aws_iam_role.redshift_serverless_role.arn]

  tags = local.tags
}

resource "aws_redshiftserverless_workgroup" "workgroup" {
  namespace_name = aws_redshiftserverless_namespace.namespace.id
  workgroup_name = "${local.name}-workgroup"

  base_capacity      = local.redshift.base_capacity # 128 
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpn_redshift_serverless_access.id]

  tags = local.tags
}

resource "aws_redshiftserverless_endpoint_access" "endpoint_access" {
  endpoint_name = "${local.name}-endpoint"

  workgroup_name = aws_redshiftserverless_workgroup.workgroup.id
  subnet_ids     = module.vpc.private_subnets
}
```


As in the [previous post](/blog/2022-02-06-dev-infra-terraform), we connect to Redshift via [SoftEther VPN](https://www.softether.org/) to improve developer experience significantly by accessing the database directly from the developer machine. Instead of providing VPN related secrets as Terraform variables in the earlier post, they are created internally and stored to AWS Secrets Manager. Also, the Redshift admin username and password are included so that the secrets can be accessed securely. The details can be found in [redshift-sls/infra/secrets.tf](https://github.com/jaehyeon-kim/dbt-on-aws/blob/main/redshift-sls/infra/secrets.tf) and the secret string can be retrieved as shown below. 


```bash
$ aws secretsmanager get-secret-value --secret-id redshift-sls-all-secrets --query "SecretString" --output text
  {
    "vpn_pre_shared_key": "<vpn-pre-shared-key>",
    "vpn_admin_password": "<vpn-admin-password>",
    "redshift_admin_username": "master",
    "redshift_admin_password": "<redshift-admin-password>"
  }
```


The [previous post](/blog/2022-02-06-dev-infra-terraform) demonstrates how to create a VPN user and to establish connection in detail. An example of a successful connection is shown below.

![](vpn-connection.png#center)

## Project

We build a data transformation pipeline using [subsets of IMDb data](https://www.imdb.com/interfaces/) - seven titles and names related datasets are provided as gzipped, tab-separated-values (TSV) formatted files. This results in three tables that can be used for reporting and analysis.


### Create Database Objects

The majority of data transformation is performed in the _imdb_ schema, which is configured as the dbt target schema. We create the final three tables in a custom schema named _imdb_analytics_. Note that its name is according to the naming convention of the [dbt custom schema](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/using-custom-schemas), which is _&lt;target_schema>_&lt;custom_schema>_. After creating the database schemas, we create a development user (dbt) and a group that the user belongs to, followed by granting necessary permissions of the new schemas to the new group and reassigning schema ownership to the new user.


```sql
-- redshift-sls/setup-redshift.sql
-- // create db schemas
create schema if not exists imdb;
create schema if not exists imdb_analytics;

-- // create db user and group
create user dbt with password '<password>';
create group dbt with user dbt;

-- // grant permissions to new schemas
grant usage on schema imdb to group dbt;
grant create on schema imdb to group dbt;
grant all on all tables in schema imdb to group dbt;

grant usage on schema imdb_analytics to group dbt;
grant create on schema imdb_analytics to group dbt;
grant all on all tables in schema imdb_analytics to group dbt;

-- reassign schema ownership to dbt
alter schema imdb owner to dbt;
alter schema imdb_analytics owner to dbt;
```

### Save Data to S3

The [Axel download accelerator](https://github.com/axel-download-accelerator/axel) is used to download the data files locally followed by decompressing with the gzip utility. Note that simple retry logic is added as I see download failure from time to time. Finally the decompressed files are saved into the project S3 bucket using the [S3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command.,

 
```bash
# redshift-sls/upload-data.sh
#!/usr/bin/env bash

s3_bucket="<s3-bucket-name>"
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
  # download can fail, retry after removing temporary files if failed
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

### Copy Data

The data files in S3 are loaded into Redshift using the [COPY command](https://docs.aws.amazon.com/redshift/latest/dg/r_COPY.html) as shown below.


```sql
-- redshift-sls/setup-redshift.sql
-- // copy data to tables
-- name_basics
drop table if exists imdb.name_basics;
create table imdb.name_basics (
    nconst text,
    primary_name text,
    birth_year text,
    death_year text,
    primary_profession text,
    known_for_titles text
);

copy imdb.name_basics
from 's3://<s3-bucket-name>/name_basics'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_akas
drop table if exists imdb.title_akas;
create table imdb.title_akas (
    title_id text,
    ordering int,
    title varchar(max),
    region text,
    language text,
    types text,
    attributes text,
    is_original_title boolean
);

copy imdb.title_akas
from 's3://<s3-bucket-name>/title_akas'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_basics
drop table if exists imdb.title_basics;
create table imdb.title_basics (
    tconst text,
    title_type text,
    primary_title varchar(max),
    original_title varchar(max),
    is_adult boolean,
    start_year text,
    end_year text,
    runtime_minutes text,
    genres text
);

copy imdb.title_basics
from 's3://<s3-bucket-name>/title_basics'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_crews
drop table if exists imdb.title_crews;
create table imdb.title_crews (
    tconst text,
    directors varchar(max),
    writers varchar(max)
);

copy imdb.title_crews
from 's3://<s3-bucket-name>/title_crew'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_episodes
drop table if exists imdb.title_episodes;
create table imdb.title_episodes (
    tconst text,
    parent_tconst text,
    season_number int,
    episode_number int
);

copy imdb.title_episodes
from 's3://<s3-bucket-name>/title_episode'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_principals
drop table if exists imdb.title_principals;
create table imdb.title_principals (
    tconst text,
    ordering int,
    nconst text,
    category text,
    job varchar(max),
    characters varchar(max)
);

copy imdb.title_principals
from 's3://<s3-bucket-name>/title_principals'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;

-- title_ratings
drop table if exists imdb.title_ratings;
create table imdb.title_ratings (
    tconst text,
    average_rating float,
    num_votes int
);

copy imdb.title_ratings
from 's3://<s3-bucket-name>/title_ratings'
iam_role default
delimiter '\t'
region 'ap-southeast-2'
ignoreheader 1;
```

### Initialise dbt Project

We need the [dbt-core](https://pypi.org/project/dbt-core/) and [dbt-redshift](https://pypi.org/project/dbt-redshift/). Once installed, we can initialise a dbt project with the [dbt init command](https://docs.getdbt.com/reference/commands/init). We are required to specify project details such as project name, [database adapter](https://docs.getdbt.com/docs/supported-data-platforms#supported-data-platforms) and database connection info. Note dbt creates the [project profile](https://docs.getdbt.com/dbt-cli/configure-your-profile) to _.dbt/profile.yml_ of the user home directory by default.


```bash
$ dbt init
07:07:16  Running with dbt=1.2.1
Enter a name for your project (letters, digits, underscore): dbt_redshift_sls
Which database would you like to use?
[1] postgres
[2] redshift

(Don't see the one you want? https://docs.getdbt.com/docs/available-adapters)

Enter a number: 2
host (hostname.region.redshift.amazonaws.com): <redshift-endpoint-url>
port [5439]:
user (dev username): dbt
[1] password
[2] iam
Desired authentication method option (enter a number): 1
password (dev password):
dbname (default database that dbt will build objects in): main
schema (default schema that dbt will build objects in): gdelt
threads (1 or more) [1]: 4
07:08:13  Profile dbt_redshift_sls written to /home/<username>/.dbt/profiles.yml using target's profile_template.yml and your supplied values. Run 'dbt debug' to validate the connection.
07:08:13  
Your new dbt project "dbt_redshift_sls" was created!

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
$ tree dbt_redshift_sls/ -L 1
dbt_redshift_sls/
├── README.md
├── analyses
├── dbt_project.yml
├── macros
├── models
├── seeds
├── snapshots
└── tests
```


We can check the database connection with the [dbt debug command](https://docs.getdbt.com/reference/commands/debug). Do not forget to connect to VPN as mentioned earlier.


```bash
$ dbt debug
03:50:58  Running with dbt=1.2.1
dbt version: 1.2.1
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
  host: <redshift-endpoint-url>
  port: 5439
  user: dbt
  database: main
  schema: imdb
  search_path: None
  keepalives_idle: 240
  sslmode: None
  method: database
  cluster_id: None
  iam_profile: None
  iam_duration_seconds: 900
  Connection test: [OK connection ok]

All checks passed!
```


After initialisation, the model configuration is updated. The project [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations) is specified as view although it is the default materialisation. Also [tags](https://docs.getdbt.com/reference/resource-configs/tags) are added to the entire model folder as well as folders of specific layers - staging, intermediate and marts. As shown below, tags can simplify model execution.


```yaml
# redshift-sls/dbt_redshift_sls/dbt_project.yml
name: "dbt_redshift_sls"
...

models:
  dbt_redshift_sls:
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


Two [dbt packages](https://docs.getdbt.com/docs/building-a-dbt-project/package-management) are used in this project. The [dbt-labs/codegen](https://hub.getdbt.com/dbt-labs/codegen/latest/) is used to save typing when generating the source and base models while [dbt-labda/dbt_utils](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) for adding tests to the final marts models. The packages can be installed by the [dbt deps command](https://docs.getdbt.com/reference/commands/deps).


```yaml
# redshift-sls/dbt_redshift_sls/packages.yml
packages:
  - package: dbt-labs/codegen
    version: 0.8.0
  - package: dbt-labs/dbt_utils
    version: 0.9.2
```

### Create dbt Models

The models for this post are organised into three layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview) - staging, intermediate and marts.


#### Staging

The seven tables that are loaded from S3 are [dbt source](https://docs.getdbt.com/docs/building-a-dbt-project/using-sources) tables and their details are declared in a YAML file (__imdb_sources.yml_). By doing so, we are able to refer to the source tables with the `{{ source() }}` function. Also we can add tests to source tables. For example below two tests (unique, not_null) are added to the _tconst_ column of the _title_basics_ table below and these tests can be executed by the [dbt test command](https://docs.getdbt.com/reference/commands/test).


```yaml
# redshift-sls/dbt_redshift_sls/models/staging/imdb/_imdb__sources.yml
version: 2

sources:
  - name: imdb
    description: Subsets of IMDb data, which are available for access to customers for personal and non-commercial use
    tables:
      ...
      - name: title_basics
        description: Table that contains basic information of titles
        columns:
          - name: tconst
            description: alphanumeric unique identifier of the title
            tests:
              - unique
              - not_null
          - name: title_type
            description: the type/format of the title (e.g. movie, short, tvseries, tvepisode, video, etc)
          - name: primary_title
            description: the more popular title / the title used by the filmmakers on promotional materials at the point of release
          - name: original_title
            description: original title, in the original language
          - name: is_adult
            description: flag that indicates whether it is an adult title or not
          - name: start_year
            description: represents the release year of a title. In the case of TV Series, it is the series start year
          - name: end_year
            description: TV Series end year. NULL for all other title types
          - name: runtime_minutes
            description: primary runtime of the title, in minutes
          - name: genres
            description: includes up to three genres associated with the title
      ...
```


Based on the source tables, staging models are created. They are created as views, which is the project's default [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations). In the SQL statements, column names and data types are modified mainly. 


```sql
-- // redshift-sls/dbt_redshift_sls/models/staging/imdb/stg_imdb__title_basics.sql
with source as (

    select * from {{ source('imdb', 'title_basics') }}

),

renamed as (

    select
        tconst as title_id,
        title_type,
        primary_title,
        original_title,
        is_adult,
        start_year::int as start_year,
        end_year::int as end_year,
        runtime_minutes::int as runtime_minutes,
        genres
    from source

)

select * from renamed
```


Below shows the file tree of the staging models. The staging models can be executed using the [dbt run command](https://docs.getdbt.com/reference/commands/run). As we've added [tags](https://docs.getdbt.com/reference/resource-configs/tags) to the staging layer models, we can limit to execute only this layer by `dbt run --select staging`.


```bash
redshift-sls/dbt_redshift_sls/models/staging/
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

#### Intermediate

We can keep intermediate results in this layer so that the models of the final marts layer can be simplified. The source data includes columns where array values are kept as comma separated strings. For example, the genres column of the _stg_imdb__title_basics_ model includes up to 3 genre values as shown below. 

![](gnere-before.png#center)

A total of seven columns in three models are columns of comma-separated strings and it is better to flatten them in the intermediate layer. Also, in order to avoid repetition, a [dbt macro](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) (f_latten_fields_) is created to share the column-flattening logic. 


```sql
# redshift-sls/dbt_redshift_sls/macros/flatten_fields.sql
{% macro flatten_fields(model, field_name, id_field_name) %}
    with subset as (
        select
            {{ id_field_name }} as id,
            regexp_count({{ field_name }}, ',') + 1 AS num_fields,
            {{ field_name }} as fields
        from {{ model }}
    )
    select
        id,
        1 as idx,
        split_part(fields, ',', 1) as field
    from subset
    union all
    select
        s.id,
        idx + 1 as idx,
        split_part(s.fields, ',', idx + 1)
    from subset s
    join cte on s.id = cte.id
    where idx < num_fields
{% endmacro %}
```

The macro function can be added inside a [recursive cte](https://docs.aws.amazon.com/redshift/latest/dg/r_WITH_clause.html) by specifying the relevant model, field name to flatten and ID field name. 


```sql
-- dbt_redshift_sls/models/intermediate/title/int_genres_flattened_from_title_basics.sql
with recursive cte (id, idx, field) as (
    {{ flatten_fields(ref('stg_imdb__title_basics'), 'genres', 'title_id') }}
)

select
    id as title_id,
    field as genre
from cte
order by id
```

The intermediate models are also materialised as views, and we can check the array columns are flattened as expected.

![](gnere-after.png#center)

Below shows the file tree of the intermediate models. Similar to the staging models, the intermediate models can be executed by `dbt run --select intermediate`.


```bash
redshift-sls/dbt_redshift_sls/models/intermediate/
├── name
│   ├── _int_name__models.yml
│   ├── int_known_for_titles_flattened_from_name_basics.sql
│   └── int_primary_profession_flattened_from_name_basics.sql
└── title
    ├── _int_title__models.yml
    ├── int_directors_flattened_from_title_crews.sql
    ├── int_genres_flattened_from_title_basics.sql
    └── int_writers_flattened_from_title_crews.sql

redshift-sls/dbt_redshift_sls/macros/
└── flatten_fields.sql
```

#### Marts

The models in the marts layer are configured to be materialised as tables in a custom schema. Their materialisation is set to _table_ and the custom schema is specified as _analytics_. Note that the custom schema name becomes _imdb_analytics_ according to the naming convention of dbt custom schemas. Models of both the staging and intermediate layers are used to create final models to be used for reporting and analytics.


```sql
-- redshift-sls/dbt_redshift_sls/models/marts/analytics/titles.sql
{{
    config(
        schema='analytics',
        materialized='table',
        sort='title_id',
        dist='title_id'
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
# redshift-sls/dbt_redshift_sls/models/marts/analytics/_analytics__models.yml
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


Below shows the file tree of the marts models. As with the other layers, the marts models can be executed by <code>dbt run <em>--select marts</em></code>.


```bash
redshift-sls/dbt_redshift_sls/models/marts/
└── analytics
    ├── _analytics__models.yml
    ├── genre_titles.sql
    ├── names.sql
    └── titles.sql
```


Using the [Redshift query editor v2](https://docs.aws.amazon.com/redshift/latest/mgmt/query-editor-v2-using.html), we can quickly create charts with the final models. The example below shows a pie chart and we see about 50% of titles are from the top 5 genres.  

![](pie-chart.png#center)

### Generate dbt Documentation

A nice feature of dbt is [documentation](https://docs.getdbt.com/docs/building-a-dbt-project/documentation). It provides information about the project and the data warehouse, and it facilitates consumers as well as other developers to discover and understand the datasets better. We can generate the project documents and start a document server as shown below.


```bash
$ dbt docs generate
$ dbt docs serve
```

![](dbt-doc-01.png#center)

A very useful element of dbt documentation is [data lineage](https://docs.getdbt.com/terms/data-lineage), which provides an overall view about how data is transformed and consumed. Below we can see that the final titles model consumes all title-related stating models and an intermediate model from the name basics staging model. 

![](dbt-doc-02.png#center)


## Summary

In this post, we discussed how to build data transformation pipelines using dbt on Redshift Serverless. Subsets of IMDb data are used as source and data models are developed in multiple layers according to the dbt best practices. dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse, and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. More examples of using dbt will be discussed in subsequent posts.
