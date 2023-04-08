---
title: Data Build Tool (dbt) for Effective Data Transformation on AWS – Part 2 Glue
date: 2022-10-09
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
  - AWS Glue
  - Amazon QuickSight
  - Data Build Tool (DBT)
  - Apache Spark
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 19
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/dbt-on-aws-part-2/).

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an effective data transformation tool and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In [part 1](/blog/2022-09-28-dbt-on-aws-part-1-redshift), we discussed benefits of a common data transformation tool and the potential of dbt to cover a wide range of data projects from data warehousing to data lake to data lakehouse. A demo data project that targets Redshift Serverless is illustrated as well. In part 2 of the dbt on AWS series, we discuss data transformation pipelines using dbt on [AWS Glue](https://aws.amazon.com/glue/). [Subsets of IMDb data](https://www.imdb.com/interfaces/) are used as source and data models are developed in multiple layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview). A list of posts of this series can be found below.

* [Part 1 Redshift](/blog/2022-09-28-dbt-on-aws-part-1-redshift)
* [Part 2 Glue](#) (this post)
* [Part 3 EMR on EC2](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2)
* [Part 4 EMR on EKS](/blog/2022-11-01-dbt-on-aws-part-4-emr-eks)
* [Part 5 Athena](/blog/2023-04-12-integrate-glue-schema-registry)

Below shows an overview diagram of the scope of this dbt on AWS series. Glue is highlighted as it is discussed in this post. 

![](featured.png#center)

## Infrastructure

The infrastructure hosting this solution leverages AWS Glue Data Catalog, AWS Glue Crawlers and a S3 bucket. We also need a runtime IAM role for AWS Glue interactive sessions for data transformation. They are deployed using Terraform and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-on-aws) of this post.


### Glue Databases

We have two Glue databases. The source tables and the tables of the staging and intermediate layers are kept in the _imdb_ database. The tables of the marts layer are stored in the _imdb_analytics _database.


```terraform
# dbt-on-aws/glue/infra/main.tf
resource "aws_glue_catalog_database" "imdb_db" {
  name        = "imdb"
  description = "Database that contains IMDb staging/intermediate model datasets"
}

resource "aws_glue_catalog_database" "imdb_db_marts" {
  name        = "imdb_analytics"
  description = "Database that contains IMDb marts model datasets"
}
```

### Glue Crawlers

We use Glue crawlers to create source tables in the _imdb_ database. We can create a single crawler for the seven source tables but it was not satisfactory, especially header detection. Instead, a dedicated crawler is created for each of the tables with its own custom classifier where it includes header columns specifically. The Terraform [count meta-argument](https://www.terraform.io/language/meta-arguments/count) is used to create the crawlers and classifiers recursively.


```terraform
# dbt-on-aws/glue/infra/main.tf
resource "aws_glue_crawler" "imdb_crawler" {
  count = length(local.glue.tables)

  name          = local.glue.tables[count.index].name
  database_name = aws_glue_catalog_database.imdb_db.name
  role          = aws_iam_role.imdb_crawler.arn
  classifiers   = [aws_glue_classifier.imdb_crawler[count.index].id]

  s3_target {
    path = "s3://${local.default_bucket.name}/${local.glue.tables[count.index].name}"
  }

  tags = local.tags
}

resource "aws_glue_classifier" "imdb_crawler" {
  count = length(local.glue.tables)

  name = local.glue.tables[count.index].name

  csv_classifier {
    contains_header = "PRESENT"
    delimiter       = "\t"
    header          = local.glue.tables[count.index].header
  }
}

# dbt-on-aws/glue/infra/variables.tf
locals {
  name        = basename(path.cwd) == "infra" ? basename(dirname(path.cwd)) : basename(path.cwd)
  region      = data.aws_region.current.name
  environment = "dev"

  default_bucket = {
    name = "${local.name}-${data.aws_caller_identity.current.account_id}-${local.region}"
  }

  glue = {
    tables = [
      { name = "name_basics", header = ["nconst", "primaryName", "birthYear", "deathYear", "primaryProfession", "knownForTitles"] },
      { name = "title_akas", header = ["titleId", "ordering", "title", "region", "language", "types", "attributes", "isOriginalTitle"] },
      { name = "title_basics", header = ["tconst", "titleType", "primaryTitle", "originalTitle", "isAdult", "startYear", "endYear", "runtimeMinutes", "genres"] },
      { name = "title_crew", header = ["tconst", "directors", "writers"] },
      { name = "title_episode", header = ["tconst", "parentTconst", "seasonNumber", "episodeNumber"] },
      { name = "title_principals", header = ["tconst", "ordering", "nconst", "category", "job", "characters"] },
      { name = "title_ratings", header = ["tconst", "averageRating", "numVotes"] }
    ]
  }

  tags = {
    Name        = local.name
    Environment = local.environment
  }
}
```

### Glue Runtime Role for Interactive Sessions

We need a [runtime (or service) role](https://docs.aws.amazon.com/glue/latest/dg/glue-is-security.html) for Glue interaction sessions. AWS Glue uses this role to run statements in a session, and it is required [to generate a profile](https://github.com/aws-samples/dbt-glue#example-config) by the dbt-glue adapter. Two policies are attached to the runtime role - the former is related to managing Glue interactive sessions while the latter is for actual data transformation by Glue.


```terraform
# dbt-on-aws/glue/infra/main.tf
resource "aws_iam_role" "glue_interactive_session" {
  name = "${local.name}-glue-interactive-session"

  assume_role_policy = data.aws_iam_policy_document.glue_interactive_session_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.glue_interactive_session.arn,
    aws_iam_policy.glue_dbt.arn
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "glue_interactive_session_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "lakeformation.amazonaws.com",
        "glue.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "glue_interactive_session" {
  name   = "${local.name}-glue-interactive-session"
  path   = "/"
  policy = data.aws_iam_policy_document.glue_interactive_session.json
  tags   = local.tags
}

resource "aws_iam_policy" "glue_dbt" {
  name   = "${local.name}-glue-dbt"
  path   = "/"
  policy = data.aws_iam_policy_document.glue_dbt.json
  tags   = local.tags
}

data "aws_iam_policy_document" "glue_interactive_session" {
  statement {
    sid = "AllowStatementInASessionToAUser"

    actions = [
      "glue:ListSessions",
      "glue:GetSession",
      "glue:ListStatements",
      "glue:GetStatement",
      "glue:RunStatement",
      "glue:CancelStatement",
      "glue:DeleteSession"
    ]

    resources = [
      "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:session/*",
    ]
  }

  statement {
    actions = ["glue:CreateSession"]

    resources = ["*"]
  }

  statement {
    actions = ["iam:PassRole"]

    resources = ["arn:aws:iam::*:role/${local.name}-glue-interactive-session*"]

    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"

      values = ["glue.amazonaws.com"]
    }
  }

  statement {
    actions = ["iam:PassRole"]

    resources = ["arn:aws:iam::*:role/service-role/${local.name}-glue-interactive-session*"]

    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"

      values = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_dbt" {
  statement {
    actions = [
      "glue:SearchTables",
      "glue:BatchCreatePartition",
      "glue:CreatePartitionIndex",
      "glue:DeleteDatabase",
      "glue:GetTableVersions",
      "glue:GetPartitions",
      "glue:DeleteTableVersion",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:DeletePartitionIndex",
      "glue:GetTableVersion",
      "glue:UpdateColumnStatisticsForTable",
      "glue:CreatePartition",
      "glue:UpdateDatabase",
      "glue:CreateTable",
      "glue:GetTables",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetDatabase",
      "glue:GetPartition",
      "glue:UpdateColumnStatisticsForPartition",
      "glue:CreateDatabase",
      "glue:BatchDeleteTableVersion",
      "glue:BatchDeleteTable",
      "glue:DeletePartition",
      "glue:GetUserDefinedFunctions"
    ]

    resources = [
      "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:table/*/*",
      "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:database/*",
    ]
  }

  statement {
    actions = [
      "lakeformation:UpdateResource",
      "lakeformation:ListResources",
      "lakeformation:BatchGrantPermissions",
      "lakeformation:GrantPermissions",
      "lakeformation:GetDataAccess",
      "lakeformation:GetTableObjects",
      "lakeformation:PutDataLakeSettings",
      "lakeformation:RevokePermissions",
      "lakeformation:ListPermissions",
      "lakeformation:BatchRevokePermissions",
      "lakeformation:UpdateTableObjects"
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = ["arn:aws:s3:::${local.default_bucket.name}"]
  }

  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:DeleteObject"
    ]

    resources = ["arn:aws:s3:::${local.default_bucket.name}/*"]
  }
}
```

## Project

We build a data transformation pipeline using [subsets of IMDb data](https://www.imdb.com/interfaces/) - seven titles and names related datasets are provided as gzipped, tab-separated-values (TSV) formatted files. This results in three tables that can be used for reporting and analysis.


### Save Data to S3

The [Axel download accelerator](https://github.com/axel-download-accelerator/axel) is used to download the data files locally followed by decompressing with the gzip utility. Note that simple retry logic is added as I see download failure from time to time. Finally, the decompressed files are saved into the project S3 bucket using the [S3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command.


```bash
# dbt-on-aws/glue/upload-data.sh
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

### Run Glue Crawlers

The Glue crawlers for the seven source tables are executed as shown below.


```bash
# dbt-on-aws/glue/start-crawlers.sh
#!/usr/bin/env bash

declare -a crawler_names=(
  "name_basics" \
  "title_akas" \
  "title_basics" \
  "title_crew" \
  "title_episode" \
  "title_principals" \
  "title_ratings"
  )

for cn in "${crawler_names[@]}"
do
  echo "start crawler $cn ..."
  aws glue start-crawler --name $cn
done
```


Note that the header rows of the source tables are not detected properly by the Glue crawlers, and they have to be filtered out in the stage models of the dbt project.

![](source-view.png#center)

### Setup dbt Project

We need the [dbt-core](https://pypi.org/project/dbt-core/) and [dbt-glue](https://github.com/aws-samples/dbt-glue) packages for the main data transformation project. Also the boto3 and [aws-glue-sessions](https://docs.aws.amazon.com/glue/latest/dg/interactive-sessions.html) packages are necessary for setting up interactive sessions locally. The dbt Glue adapter doesn’t support creating a profile with the [dbt init command](https://docs.getdbt.com/reference/commands/init) so that profile creation is skipped when initialising the project.


```bash
$ pip install --no-cache-dir --upgrade boto3 aws-glue-sessions dbt-core dbt-glue
$ dbt init --skip-profile-setup
10:04:00  Running with dbt=1.2.1
Enter a name for your project (letters, digits, underscore): dbt_glue_proj
```


The project profile is manually created as shown below. The attributes are self-explanatory and their details can be checked further in the [GitHub repository](https://github.com/aws-samples/dbt-glue#example-config) of the dbt-glue adapter.


```bash
# dbt-on-aws/glue/set-profile.sh
#!/usr/bin/env bash

dbt_role_arn=$(terraform -chdir=./infra output --raw glue_interactive_session_role_arn)
dbt_s3_location=$(terraform -chdir=./infra output --raw default_bucket_name)

cat << EOF > ~/.dbt/profiles.yml
dbt_glue_proj:
  outputs:
    dev:
      type: glue
      role_arn: "${dbt_role_arn}"
      region: ap-southeast-2
      workers: 3
      worker_type: G.1X
      schema: imdb
      database: imdb
      session_provisioning_timeout_in_seconds: 240
      location: "s3://${dbt_s3_location}"
      query_timeout_in_seconds: 300
      idle_timeout: 60
      glue_version: "3.0"
  target: dev
EOF
```

dbt initialises a project in a folder that matches to the project name and generates project boilerplate as shown below. Some of the main objects are _[dbt_project.yml](https://docs.getdbt.com/reference/dbt_project.yml)_, and the [model](https://docs.getdbt.com/docs/building-a-dbt-project/building-models) folder. The former is required because dbt doesn't know if a folder is a dbt project without it. Also, it contains information that tells dbt how to operate on the project. The latter is for including dbt models, which is basically a set of SQL select statements. See [dbt documentation](https://docs.getdbt.com/docs/introduction) for more details.


```bash
$ tree glue/dbt_glue_proj/ -L 1
glue/dbt_glue_proj/
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


We can check Glue interactive session connection with the [dbt debug command](https://docs.getdbt.com/reference/commands/debug) as shown below.


```bash
$ dbt debug
08:50:58  Running with dbt=1.2.1
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
  role_arn: <glue-interactive-session-role-arn>
  region: ap-southeast-2
  session_id: None
  workers: 3
  worker_type: G.1X
  session_provisioning_timeout_in_seconds: 240
  database: imdb
  schema: imdb
  location: s3://<s3-bucket-name>
  extra_jars: None
  idle_timeout: 60
  query_timeout_in_seconds: 300
  glue_version: 3.0
  security_configuration: None
  connections: None
  conf: None
  extra_py_files: None
  delta_athena_prefix: None
  tags: None
  Connection test: [OK connection ok]

All checks passed!
```


After initialisation, the model configuration is updated. The project [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations) is specified as view although it is the default materialisation. Also [tags](https://docs.getdbt.com/reference/resource-configs/tags) are added to the entire model folder as well as folders of specific layers - staging, intermediate and marts. As shown below, tags can simplify model execution.


```yaml
# glue/dbt_glue_proj/dbt_project.yml
name: "dbt_glue_proj"

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


The [dbt_utils](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/) package is installed for adding tests to the final marts models. The packages can be installed by the [dbt deps command](https://docs.getdbt.com/reference/commands/deps).


```yaml
# glue/dbt_glue_proj/packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 0.9.2
```

### Create dbt Models

The models for this post are organised into three layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview) - staging, intermediate and marts.


#### Staging

The seven tables that are loaded from S3 are [dbt source](https://docs.getdbt.com/docs/building-a-dbt-project/using-sources) tables and their details are declared in a YAML file (__imdb_sources.yml_). By doing so, we are able to refer to the source tables with the `{{ source() }}` function. Also we can add tests to source tables. For example below two tests (unique, not_null) are added to the _tconst_ column of the _title_basics_ table below and these tests can be executed by the [dbt test command](https://docs.getdbt.com/reference/commands/test).


```yaml
# glue/dbt_glue_proj/models/staging/imdb/_imdb__sources.yml
version: 2

sources:
  - name: imdb
    description: Subsets of IMDb data, which are available for access to customers for personal and non-commercial use
    tables:
      - name: title_basics
        description: Table that contains basic information of titles
        columns:
          - name: tconst
            description: alphanumeric unique identifier of the title
            tests:
              - unique
              - not_null
          - name: titletype
            description: the type/format of the title (e.g. movie, short, tvseries, tvepisode, video, etc)
          - name: primarytitle
            description: the more popular title / the title used by the filmmakers on promotional materials at the point of release
          - name: originaltitle
            description: original title, in the original language
          - name: isadult
            description: flag that indicates whether it is an adult title or not
          - name: startyear
            description: represents the release year of a title. In the case of TV Series, it is the series start year
          - name: endyear
            description: TV Series end year. NULL for all other title types
          - name: runtime minutes
            description: primary runtime of the title, in minutes
          - name: genres
            description: includes up to three genres associated with the title
      ...
```


Based on the source tables, staging models are created. They are created as views, which is the project’s default [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations). In the SQL statements, column names and data types are modified mainly.


```sql
# glue/dbt_glue_proj/models/staging/imdb/stg_imdb__title_basics.sql
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
        genres
    from source
    where tconst <> 'tconst'

)

select * from renamed
```


Below shows the file tree of the staging models. The staging models can be executed using the [dbt run command](https://docs.getdbt.com/reference/commands/run). As we’ve added [tags](https://docs.getdbt.com/reference/resource-configs/tags) to the staging layer models, we can limit to execute only this layer by `dbt run --select staging`.


```bash
$ tree glue/dbt_glue_proj/models/staging/
glue/dbt_glue_proj/models/staging/
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


Instead we can use [Glue Studio notebooks](https://docs.aws.amazon.com/glue/latest/ug/notebook-getting-started.html) to query the tables, which is a bit inconvenient.

![](query-view.png#center)

#### Intermediate

We can keep intermediate results in this layer so that the models of the final marts layer can be simplified. The source data includes columns where array values are kept as comma separated strings. For example, the genres column of the _stg_imdb__title_basics_ model includes up to three genre values as shown in the previous screenshot. A total of seven columns in three models are columns of comma-separated strings and it is better to flatten them in the intermediate layer. Also, in order to avoid repetition, a [dbt macro](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) (f_latten_fields_) is created to share the column-flattening logic.


```sql
# glue/dbt_glue_proj/macros/flatten_fields.sql
{% macro flatten_fields(model, field_name, id_field_name) %}
    select
        {{ id_field_name }} as id,
        explode(split({{ field_name }}, ',')) as field
    from {{ model }}
{% endmacro %}
```


The macro function can be added inside a [common table expression (CTE)](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html) by specifying the relevant model, field name to flatten and id field name.


```sql
-- glue/dbt_glue_proj/models/intermediate/title/int_genres_flattened_from_title_basics.sql
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

![](query-view-flattened.png#center)

Below shows the file tree of the intermediate models. Similar to the staging models, the intermediate models can be executed by `dbt run --select intermediate`.


```bash
$ tree glue/dbt_glue_proj/models/intermediate/ glue/dbt_glue_proj/macros/
glue/dbt_glue_proj/models/intermediate/
├── name
│   ├── _int_name__models.yml
│   ├── int_known_for_titles_flattened_from_name_basics.sql
│   └── int_primary_profession_flattened_from_name_basics.sql
└── title
    ├── _int_title__models.yml
    ├── int_directors_flattened_from_title_crews.sql
    ├── int_genres_flattened_from_title_basics.sql
    └── int_writers_flattened_from_title_crews.sql

glue/dbt_glue_proj/macros/
└── flatten_fields.sql
```

#### Marts

The models in the marts layer are configured to be materialised as tables in a custom schema. Their materialisation is set to _table_ and the custom schema is specified as _analytics_ while taking _parquet _as the file format. Note that the custom schema name becomes _imdb_analytics_ according to the naming convention of dbt custom schemas. Models of both the staging and intermediate layers are used to create final models to be used for reporting and analytics.


```sql
-- glue/dbt_glue_proj/models/marts/analytics/titles.sql
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
# glue/dbt_glue_proj/models/marts/analytics/_analytics__models.yml
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
09:11:51  Running with dbt=1.2.1
09:11:51  Found 15 models, 17 tests, 0 snapshots, 0 analyses, 521 macros, 0 operations, 0 seed files, 7 sources, 0 exposures, 0 metrics
09:11:51  
09:12:28  Concurrency: 1 threads (target='dev')
09:12:28  
09:12:28  1 of 2 START test dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .... [RUN]
09:12:53  1 of 2 PASS dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .......... [PASS in 24.94s]
09:12:53  2 of 2 START test dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ .. [RUN]
09:13:04  2 of 2 PASS dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ ........ [PASS in 11.63s]
09:13:07  
09:13:07  Finished running 2 tests in 0 hours 1 minutes and 15.74 seconds (75.74s).
09:13:07  
09:13:07  Completed successfully
09:13:07  
09:13:07  Done. PASS=2 WARN=0 ERROR=0 SKIP=0 TOTAL=2
```


Below shows the file tree of the marts models. As with the other layers, the marts models can be executed by <code>dbt run <em>--select marts</em></code>.


```
$ tree glue/dbt_glue_proj/models/marts/
glue/dbt_glue_proj/models/marts/
└── analytics
    ├── _analytics__models.yml
    ├── genre_titles.sql
    ├── names.sql
    └── titles.sql
```



### Build Dashboard

The models of the marts layer can be consumed by external tools such as [Amazon QuickSight](https://aws.amazon.com/quicksight/). Below shows an example dashboard. The two pie charts on top show proportions of genre and title type. The box plots at the bottom show dispersion of the number of votes and average rating by title type.

![](imdb-dashboard.png#center)

### Generate dbt Documentation

A nice feature of dbt is [documentation](https://docs.getdbt.com/docs/building-a-dbt-project/documentation). It provides information about the project and the data warehouse, and it facilitates consumers as well as other developers to discover and understand the datasets better. We can generate the project documents and start a document server as shown below.


```bash
$ dbt docs generate
$ dbt docs serve
```

![](doc-01.png#center)

A very useful element of dbt documentation is [data lineage](https://docs.getdbt.com/terms/data-lineage), which provides an overall view about how data is transformed and consumed. Below we can see that the final titles model consumes all title-related stating models and an intermediate model from the name basics staging model. 

![](doc-02.png#center)

## Summary

In this post, we discussed how to build data transformation pipelines using dbt on AWS Glue. Subsets of IMDb data are used as source and data models are developed in multiple layers according to the dbt best practices. dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. More examples of using dbt will be discussed in subsequent posts.
