---
title: Data Build Tool (dbt) for Effective Data Transformation on AWS – Part 5 Athena
date: 2022-12-06
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
  - Amazon Athena
  - Amazon QuickSight
  - Data Build Tool (DBT)
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 22
---

The [data build tool (dbt)](https://docs.getdbt.com/docs/introduction) is an effective data transformation tool and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In the previous posts, we discussed benefits of a common data transformation tool and the potential of dbt to cover a wide range of data projects from data warehousing to data lake to data lakehouse. Demo data projects that target Redshift Serverless, Glue, EMR on EC2 and EMR on EKS are illustrated as well. In the last part of the dbt on AWS series, we discuss data transformation pipelines using dbt on [Amazon Athena](https://aws.amazon.com/athena). [Subsets of IMDb data](https://www.imdb.com/interfaces/) are used as source and data models are developed in multiple layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview). A list of posts of this series can be found below.

* [Part 1 Redshift](/blog/2022-09-28-dbt-on-aws-part-1-redshift)
* [Part 2 Glue](/blog/2022-10-09-dbt-on-aws-part-2-glue)
* [Part 3 EMR on EC2](/blog/2022-10-19-dbt-on-aws-part-3-emr-ec2)
* [Part 4 EMR on EKS](/blog/2022-11-01-dbt-on-aws-part-4-emr-eks)
* [Part 5 Athena](#) (this post)

Below shows an overview diagram of the scope of this dbt on AWS series. Athena is highlighted as it is discussed in this post.

![](featured.png#center)

## Infrastructure

The infrastructure hosting this solution leverages Athena Workgroup, AWS Glue Data Catalog, AWS Glue Crawlers and a S3 bucket. They are deployed using Terraform and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-on-aws) of this post.


### Athena Workgroup

The [dbt athena](https://github.com/Tomme/dbt-athena) adapter requires an Athena workgroup and it only supports the Athena engine version 2. The workgroup used in the dbt project is created as shown below. 


```terraform
resource "aws_athena_workgroup" "imdb" {
  name = "${local.name}-imdb"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    engine_version {
      selected_engine_version = "Athena engine version 2"
    }

    result_configuration {
      output_location = "s3://${local.default_bucket.name}/athena/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = true

  tags = local.tags
}
```

### Glue Databases

We have two Glue databases. The source tables and the tables of the staging and intermediate layers are kept in the _imdb_ database. The tables of the marts layer are stored in the _imdb_analytics _database.


```terraform
# athena/infra/main.tf
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

We use Glue crawlers to create source tables in the _imdb_ database. We can create a single crawler for the seven source tables but it was not satisfactory, especially header detection. Instead a dedicated crawler is created for each of the tables with its own custom classifier where it includes header columns specifically. The Terraform [count meta-argument](https://www.terraform.io/language/meta-arguments/count) is used to create the crawlers and classifiers recursively.


```terraform
# athena/infra/main.tf
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

# athena/infra/variables.tf
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

## Project

We build a data transformation pipeline using [subsets of IMDb data](https://www.imdb.com/interfaces/) - seven titles and names related datasets are provided as gzipped, tab-separated-values (TSV) formatted files. This results in three tables that can be used for reporting and analysis.


### Save Data to S3

The [Axel download accelerator](https://github.com/axel-download-accelerator/axel) is used to download the data files locally followed by decompressing with the gzip utility. Note that simple retry logic is added as I see download failure from time to time. Finally, the decompressed files are saved into the project S3 bucket using the [S3 sync](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html) command.


```bash
# athena/upload-data.sh
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
# athena/start-crawlers.sh
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


After the crawlers run successfully, we are able to check the seven source tables. Below shows a query example of one of the source tables in Athena.

![](athena-source-show.png#center)

### Setup dbt Project

We need the [dbt-core](https://pypi.org/project/dbt-core/) and [dbt-athena-adapter](https://github.com/Tomme/dbt-athena) packages for the main data transformation project - the former can be installed as dependency of the latter. The dbt project is initialised while skipping the [connection profile](https://docs.getdbt.com/docs/get-started/connection-profiles) as it does not allow to select key connection details such as _aws_profile_name_ and _threads_. Instead the profile is created manually as shown below. Note that, after this post was complete, it announced a new project repository called [dbt-athena-community](https://github.com/Tomme/dbt-athena/issues/144) and new features are planned to be supported in the new project. Those new features cover the Athena engine version 3 and Apache Iceberg support and a new dbt targeting Athena is encouraged to use it.  


```bash
$ pip install dbt-athena-adapter
$ dbt init --skip-profile-setup
# 09:32:09  Running with dbt=1.3.1
# Enter a name for your project (letters, digits, underscore): athena_proj
```


The attributes are self-explanatory, and their details can be checked further in the [GitHub repository](https://github.com/Tomme/dbt-athena) of the dbt-athena adapter.


```bash
# athena/set-profile.sh
#!/usr/bin/env bash

aws_region=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
dbt_s3_location=$(terraform -chdir=./infra output --raw default_bucket_name)
dbt_work_group=$(terraform -chdir=./infra output --raw aws_athena_workgroup_name)

cat << EOF > ~/.dbt/profiles.yml
athena_proj:
  outputs:
    dev:
      type: athena
      region_name: ${aws_region}
      s3_staging_dir: "s3://${dbt_s3_location}/dbt/"
      schema: imdb
      database: awsdatacatalog
      work_group: ${dbt_work_group}
      threads: 3
      aws_profile_name: <aws-profile>
  target: dev
EOF
```


dbt initialises a project in a folder that matches to the project name and generates project boilerplate as shown below. Some of the main objects are _[dbt_project.yml](https://docs.getdbt.com/reference/dbt_project.yml)_, and the [model](https://docs.getdbt.com/docs/building-a-dbt-project/building-models) folder. The former is required because dbt doesn't know if a folder is a dbt project without it. Also it contains information that tells dbt how to operate on the project. The latter is for including dbt models, which is basically a set of SQL select statements. See [dbt documentation](https://docs.getdbt.com/docs/introduction) for more details.


```bash
$ tree athena/athena_proj/ -L 1
athena/athena_proj/
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


We can check Athena connection with the [dbt debug command](https://docs.getdbt.com/reference/commands/debug) as shown below.


```bash
$ dbt debug
09:33:53  Running with dbt=1.3.1
dbt version: 1.3.1
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
  s3_staging_dir: s3://<s3-bucket-name>/dbt/
  work_group: athena-imdb
  region_name: ap-southeast-2
  database: imdb
  schema: imdb
  poll_interval: 1.0
  aws_profile_name: <aws-profile>
  Connection test: [OK connection ok]

All checks passed!
```


After initialisation, the model configuration is updated. The project [materialisation](https://docs.getdbt.com/docs/building-a-dbt-project/building-models/materializations) is specified as view, although it is the default materialisation. Also [tags](https://docs.getdbt.com/reference/resource-configs/tags) are added to the entire model folder as well as folders of specific layers - staging, intermediate and marts. As shown below, tags can simplify model execution.


```yaml
# athena/athena_proj/dbt_project.yml
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
# athena/athena_proj/packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 0.9.5
```

### Create dbt Models

The models for this post are organised into three layers according to the [dbt best practices](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview) - staging, intermediate and marts.


#### Staging

The seven tables that are loaded from S3 are [dbt source](https://docs.getdbt.com/docs/building-a-dbt-project/using-sources) tables and their details are declared in a YAML file (__imdb_sources.yml_). By doing so, we are able to refer to the source tables with the `{{ source() }}` function. Also we can add tests to source tables. For example below two tests (unique, not_null) are added to the _tconst_ column of the _title_basics_ table below and these tests can be executed by the [dbt test command](https://docs.getdbt.com/reference/commands/test).


```yaml
# athena/athena_proj/models/staging/imdb/_imdb__sources.yml
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
# athena/athena_proj/models/staging/imdb/stg_imdb__title_basics.sql
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

)

select * from renamed
```


Below shows the file tree of the staging models. The staging models can be executed using the [dbt run command](https://docs.getdbt.com/reference/commands/run). As we’ve added [tags](https://docs.getdbt.com/reference/resource-configs/tags) to the staging layer models, we can limit to execute only this layer by `dbt run --select staging`.


```bash
$ tree athena/athena_proj/models/staging/
athena/athena_proj/models/staging/
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

![](athena-virtual-views.png#center)

The views in the staging layer can be queried in Athena as shown below.

![](athena-staging-show.png#center)

#### Intermediate

We can keep intermediate results in this layer so that the models of the final marts layer can be simplified. The source data includes columns where array values are kept as comma separated strings. For example, the genres column of the _stg_imdb__title_basics_ model includes up to three genre values as shown in the previous screenshot. A total of seven columns in three models are columns of comma-separated strings and it is better to flatten them in the intermediate layer. Also, in order to avoid repetition, a [dbt macro](https://docs.getdbt.com/docs/building-a-dbt-project/jinja-macros) (f_latten_fields_) is created to share the column-flattening logic.


```sql
# athena/athena_proj/macros/flatten_fields.sql
{% macro flatten_fields(model, field_name, id_field_name) %}
    select
        {{ id_field_name }} as id,
        field
    from {{ model }}
    cross join unnest(split({{ field_name }}, ',')) as x(field)
{% endmacro %}
```


The macro function can be added inside a [common table expression (CTE)](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html) by specifying the relevant model, field name to flatten and ID field name.


```sql
-- athena/athena_proj/models/intermediate/title/int_genres_flattened_from_title_basics.sql
with flattened as (
    {{ flatten_fields(ref('stg_imdb__title_basics'), 'genres', 'title_id') }}
)

select
    id as title_id,
    field as genre
from flattened
order by id
```

The intermediate models are also materialised as views, and we can check the array columns are flattened as expected.

![](athena-intermediate-show.png#center)

Below shows the file tree of the intermediate models. Similar to the staging models, the intermediate models can be executed by `dbt run --select intermediate`.


```bash
$ tree athena/athena_proj/models/intermediate/ athena/athena_proj/macros/
athena/athena_proj/models/intermediate/
├── name
│   ├── _int_name__models.yml
│   ├── int_known_for_titles_flattened_from_name_basics.sql
│   └── int_primary_profession_flattened_from_name_basics.sql
└── title
    ├── _int_title__models.yml
    ├── int_directors_flattened_from_title_crews.sql
    ├── int_genres_flattened_from_title_basics.sql
    └── int_writers_flattened_from_title_crews.sql

athena/athena_proj/macros/
└── flatten_fields.sql
```

#### Marts

The models in the marts layer are configured to be materialised as tables in a custom schema. Their materialisation is set to _table_ and the custom schema is specified as _analytics_ while taking _parquet _as the file format. Note that the custom schema name becomes _imdb_analytics_ according to the naming convention of dbt custom schemas. Models of both the staging and intermediate layers are used to create final models to be used for reporting and analytics.


```sql
-- athena/athena_proj/models/marts/analytics/titles.sql
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
# athena/athena_proj/models/marts/analytics/_analytics__models.yml
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
07:18:42  Running with dbt=1.3.1
07:18:43  Found 15 models, 17 tests, 0 snapshots, 0 analyses, 473 macros, 0 operations, 0 seed files, 7 sources, 0 exposures, 0 metrics
07:18:43  
07:18:48  Concurrency: 3 threads (target='dev')
07:18:48  
07:18:48  1 of 2 START test dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .... [RUN]
07:18:48  2 of 2 START test dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ .. [RUN]
07:18:51  2 of 2 PASS dbt_utils_equal_rowcount_titles_ref_stg_imdb__title_basics_ ........ [PASS in 2.76s]
07:18:52  1 of 2 PASS dbt_utils_equal_rowcount_names_ref_stg_imdb__name_basics_ .......... [PASS in 3.80s]
07:18:52  
07:18:52  Finished running 2 tests in 0 hours 0 minutes and 9.17 seconds (9.17s).
07:18:52  
07:18:52  Completed successfully
07:18:52  
07:18:52  Done. PASS=2 WARN=0 ERROR=0 SKIP=0 TOTAL=2
```


Below shows the file tree of the marts models. As with the other layers, the marts models can be executed by `dbt run --select marts`.


```bash
$ tree athena/athena_proj/models/marts/
athena/athena_proj/models/marts/
└── analytics
    ├── _analytics__models.yml
    ├── genre_titles.sql
    ├── names.sql
    └── titles.sql
```

### Build Dashboard

The models of the marts layer can be consumed by external tools such as [Amazon QuickSight](https://aws.amazon.com/quicksight/). Below shows an example dashboard. The pie chart on the left shows the proportion of titles by genre while the box plot on the right shows the dispersion of average rating by start year.

![](athena-quicksight.png#center)

### Generate dbt Documentation

A nice feature of dbt is [documentation](https://docs.getdbt.com/docs/building-a-dbt-project/documentation). It provides information about the project and the data warehouse, and it facilitates consumers as well as other developers to discover and understand the datasets better. We can generate the project documents and start a document server as shown below.


```bash
$ dbt docs generate
$ dbt docs serve
```

![](athena-doc-01.png#center)

A very useful element of dbt documentation is [data lineage](https://docs.getdbt.com/terms/data-lineage), which provides an overall view about how data is transformed and consumed. Below we can see that the final titles model consumes all title-related stating models and an intermediate model from the name basics staging model.

![](athena-doc-02.png#center)

## Summary

In this post, we discussed how to build data transformation pipelines using dbt on AWS Athena. Subsets of IMDb data are used as source and data models are developed in multiple layers according to the dbt best practices. dbt can be used as an effective tool for data transformation in a wide range of data projects from data warehousing to data lake to data lakehouse and it supports key AWS analytics services - Redshift, Glue, EMR and Athena. In this series, we mainly focus on how to develop a data project with dbt targeting variable AWS analytics services. It is quite an effective framework for data transformation and advanced features will be covered in a new series of posts. 
