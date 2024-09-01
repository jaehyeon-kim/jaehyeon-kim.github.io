---
title: DBT CI/CD Demo with BigQuery and GitHub Actions
date: 2024-09-05
draft: true
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Apache Beam Python Examples
categories:
  - Data Engineering
tags: 
  - Data Build Tool (DBT)
  - GCP
  - BigQuery
  - Continuous Integration
  - Continuous Delivery
  - GitHub Actions
authors:
  - JaehyeonKim
images: []
description:
---

Continuous integration (CI) is the process of ensuring new code integrates with the larger code base, and it puts a great emphasis on testing automation to check that the application is not broken whenever new commits are integrated into the main branch. Continuous delivery (CD) is an extension of continuous integration since it automatically deploys all code changes to a testing and/or production environment after the build stage. CI/CD helps development teams avoid bugs and code failures while maintaining a continuous cycle of software development and updates. In this post, we discuss how to set up a CI/CD pipeline for a [data build tool (*dbt*)](https://www.getdbt.com/) project using [GitHub Actions](https://github.com/features/actions) where [BigQuery](https://cloud.google.com/bigquery?hl=en) is used as the target data warehouse.

<!--more-->

The CI/CD process has two workflows - `slim-ci` and `deploy`. When a pull request is created to the main branch, the `slim-ci` workflow is triggered, and it aims to perform tests after building only modified models and its first-order children in *ci* datasets. Thanks to the [defer feature](https://docs.getdbt.com/reference/node-selection/defer) and [state method](https://docs.getdbt.com/reference/node-selection/methods#the-state-method), it saves time and computational resources for testing a few models in a *dbt* project. When a pull request is merged to the main branch, the `deploy` workflow is triggered. It begins with performing [unit tests](https://docs.getdbt.com/docs/build/unit-tests) to validate key SQL modelling logic on a small set of static inputs. Once the tests are complete successfully, two jobs are triggered concurrently. The first job builds a Docker container that packages the *dbt* model and pushes into *Artifact Registry* while the second one publishes the project documentation into *GitHub Pages*.

## DBT Project

A *dbt* project is created using fictional pizza shop data. There are three stating data sets (*staging_orders*, *staging_products*, and *staging_users*), and they are loaded as *dbt* seeds. The project ends up building two *SCD Type 2* dimension tables (*dim_products* and *dim_users*) and one fact table (*fct_orders*). The structure of the project is listed below, and the source can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/dbt-cicd-demo) of this post.

```text
pizza_shop
├── analyses
├── dbt_project.yml
├── macros
├── models
│   ├── dim
│   │   ├── dim_products.sql
│   │   └── dim_users.sql
│   ├── fct
│   │   └── fct_orders.sql
│   ├── schema.yml
│   ├── sources.yml
│   ├── src
│   │   ├── src_orders.sql
│   │   ├── src_products.sql
│   │   └── src_users.sql
│   └── unit_tests.yml
├── seeds
│   ├── properties.yml
│   ├── staging_orders.csv
│   ├── staging_products.csv
│   └── staging_users.csv
├── snapshots
└── tests
```

We use two *dbt* profiles. The *dev* target is used to manage the *dbt* models in the main dataset named *pizza_shop* while the *ci* target is used by the GitHub Actions Runner. Note that the dataset of the *ci* target is specified by an environment variable named *CI_DATASET*, and the value is dynamically determined.

```yaml
# dbt_profiles/profiles.yml
pizza_shop:
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: pizza_shop
      threads: 4
      keyfile: "{{ env_var('SA_KEYFILE') }}"
      job_execution_timeout_seconds: 300
      job_retries: 1
      priority: interactive
      location: australia-southeast1
    ci:
      type: bigquery
      method: service-account
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: "{{ env_var('CI_DATASET') }}"
      threads: 4
      keyfile: "{{ env_var('SA_KEYFILE') }}"
      job_execution_timeout_seconds: 300
      job_retries: 1
      priority: interactive
      location: australia-southeast1
  target: dev
```

We first need to load the *dbt* seed data sets, and it can be achieved using the `dbt seed` command as shown below.

```bash
$ dbt seed --profiles-dir=dbt_profiles --project-dir=pizza_shop --target dev
10:42:18  Running with dbt=1.8.6
10:42:19  Registered adapter: bigquery=1.8.2
10:42:19  Unable to do partial parsing because saved manifest not found. Starting full parse.
10:42:20  [WARNING]: Deprecated functionality
The `tests` config has been renamed to `data_tests`. Please see
https://docs.getdbt.com/docs/build/data-tests#new-data_tests-syntax for more
information.
10:42:20  Found 6 models, 3 seeds, 4 data tests, 3 sources, 587 macros, 1 unit test
10:42:20  
10:42:27  Concurrency: 4 threads (target='dev')
10:42:27  
10:42:27  1 of 3 START seed file pizza_shop.staging_orders ............................... [RUN]
10:42:27  2 of 3 START seed file pizza_shop.staging_products ............................. [RUN]
10:42:27  3 of 3 START seed file pizza_shop.staging_users ................................ [RUN]
10:42:34  2 of 3 OK loaded seed file pizza_shop.staging_products ......................... [INSERT 81 in 6.73s]
10:42:34  3 of 3 OK loaded seed file pizza_shop.staging_users ............................ [INSERT 10000 in 7.30s]
10:42:36  1 of 3 OK loaded seed file pizza_shop.staging_orders ........................... [INSERT 20000 in 8.97s]
10:42:36  
10:42:36  Finished running 3 seeds in 0 hours 0 minutes and 15.34 seconds (15.34s).
10:42:36  
10:42:36  Completed successfully
10:42:36  
10:42:36  Done. PASS=3 WARN=0 ERROR=0 SKIP=0 TOTAL=3
```

Then, we can build the *dbt* models using the `dbt run` command. It creates three view models, two table models for the dimension tables, and one incremental model for the fact table.

```bash
$ dbt run --profiles-dir=dbt_profiles --project-dir=pizza_shop --target dev
10:43:18  Running with dbt=1.8.6
10:43:19  Registered adapter: bigquery=1.8.2
10:43:19  Found 6 models, 3 seeds, 4 data tests, 3 sources, 587 macros, 1 unit test
10:43:19  
10:43:21  Concurrency: 4 threads (target='dev')
10:43:21  
10:43:21  1 of 6 START sql view model pizza_shop.src_orders .............................. [RUN]
10:43:21  2 of 6 START sql view model pizza_shop.src_products ............................ [RUN]
10:43:21  3 of 6 START sql view model pizza_shop.src_users ............................... [RUN]
10:43:22  3 of 6 OK created sql view model pizza_shop.src_users .......................... [CREATE VIEW (0 processed) in 1.19s]
10:43:22  4 of 6 START sql table model pizza_shop.dim_users .............................. [RUN]
10:43:22  1 of 6 OK created sql view model pizza_shop.src_orders ......................... [CREATE VIEW (0 processed) in 1.35s]
10:43:22  2 of 6 OK created sql view model pizza_shop.src_products ....................... [CREATE VIEW (0 processed) in 1.35s]
10:43:22  5 of 6 START sql table model pizza_shop.dim_products ........................... [RUN]
10:43:25  5 of 6 OK created sql table model pizza_shop.dim_products ...................... [CREATE TABLE (81.0 rows, 13.7 KiB processed) in 2.77s]
10:43:25  4 of 6 OK created sql table model pizza_shop.dim_users ......................... [CREATE TABLE (10.0k rows, 880.9 KiB processed) in 3.49s]
10:43:25  6 of 6 START sql incremental model pizza_shop.fct_orders ....................... [RUN]
10:43:31  6 of 6 OK created sql incremental model pizza_shop.fct_orders .................. [INSERT (20.0k rows, 5.0 MiB processed) in 6.13s]
10:43:31  
10:43:31  Finished running 3 view models, 2 table models, 1 incremental model in 0 hours 0 minutes and 12.10 seconds (12.10s).
10:43:31  
10:43:31  Completed successfully
10:43:31  
10:43:31  Done. PASS=6 WARN=0 ERROR=0 SKIP=0 TOTAL=6
```

We can check the models are created in the *pizza_shop* dataset.

![](initial-data.png#center)

## CI/CD Process

The CI/CD process has two workflows - `slim-ci` and `deploy`. When a pull request is created to the main branch, the `slim-ci` workflow is triggered, and it aims to perform tests after building only modified models and its first-order children in *ci* datasets. When a pull request is merged to the main branch, the `deploy` workflow is triggered, and it begins with performing *unit tests*. Upon successful testing, two jobs are triggered subsequently, which builds/pushes the *dbt* project as a Docker container and publishes the project documentation.

### Prerequisites

#### Create Repository Variable and Secret

The workflows require a variable that keeps the GCP project ID, and it is accessed by `${{ vars.GCP_PROJECT_ID }}`. Also, the service account key is stored as a secret, and it can be retrieved by `${{ secrets.GCP_SA_KEY }}`. They can be created on the repository settings as shown below.

![](variable-secret.png#center)

#### Create GCP Resources and Store DBT Artifact

```bash
$ gsutil mb gs://dbt-cicd-demo

$ gcloud artifacts repositories create dbt-cicd-demo \
  --repository-format=docker --location=australia-southeast1
```

```bash
$ gsutil cp pizza_shop/target/manifest.json gs://dbt-cicd-demo/artifact/manifest.json
# Copying file://pizza_shop/target/manifest.json [Content-Type=application/json]...
# - [1 files][608.8 KiB/608.8 KiB]                                                
# Operation completed over 1 objects/608.8 KiB. 
```

#### Configure GitHub Pages

![](gh-pages-config-1.png#center)

![](gh-pages-config-2.png#center)

### DBT Slim CI

![](slim-ci-workflow.png#center)

```yaml
# .github/workflows/slim-ci.yml
name: slim-ci

on:
  pull_request:
    branches: ["main"]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

env:
  GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
  DBT_PROFILES_DIR: ${{github.workspace}}/dbt_profiles
  DBT_ARTIFACT_PATH: gs://dbt-cicd-demo/artifact/manifest.json

jobs:
  dbt-slim-ci:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v1
        with:
          python-version: "3.10"

      - name: Create and start virtual environment
        run: |
          python -m venv venv
          source venv/bin/activate

      - name: Install dependencies
        run: |
          pip install -r requirements.txt

      - name: Set up service account key file
        env:
          GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
        run: |
          echo ${GCP_SA_KEY} > ${{github.workspace}}/.github/key.json
          echo SA_KEYFILE=${{github.workspace}}/.github/key.json >> $GITHUB_ENV

      - name: Set up ci dataset
        run: |
          echo CI_DATASET=ci_$(date +'%y%m%d_%S')_$(git rev-parse --short "$GITHUB_SHA") >> $GITHUB_ENV

      - name: Authenticate to GCP
        run: |
          gcloud auth activate-service-account \
            dbt-cicd@${{ env.GCP_PROJECT_ID }}.iam.gserviceaccount.com \
            --key-file $SA_KEYFILE --project ${{ env.GCP_PROJECT_ID }}

      - name: Download dbt manifest
        run: gsutil cp ${{ env.DBT_ARTIFACT_PATH }} ${{github.workspace}}

      - name: Install dbt dependencies
        run: |
          dbt deps --project-dir=pizza_shop

      - name: Build modified dbt models and its first-order children
        run: |
          dbt build --profiles-dir=${{ env.DBT_PROFILES_DIR }} --project-dir=pizza_shop --target ci \
            --select state:modified+ --defer --state ${{github.workspace}}

      # Hacky way of getting around the bq outputting annoying welcome stuff on first run which breaks jq
      - name: Check existing CI datasets
        if: always()
        shell: bash -l {0}
        run: bq ls --project_id=${{ env.GCP_PROJECT_ID }} --quiet=true --headless=true --format=json

      - name: Clean up CI datasets
        if: always()
        shell: bash -l {0}
        run: |
          for dataset in $(bq ls --project_id=${{ env.GCP_PROJECT_ID }} --quiet=true --headless=true --format=json | jq -r '.[].datasetReference.datasetId')
          do
            # If the dataset starts with the prefix, delete it
            if [[ $dataset == $CI_DATASET* ]]; then
              echo "Deleting $dataset"
              bq rm -r -f $dataset
            fi
          done
```

```sql
-- pizza_shot/models/fct/fct_orders.sql
...
SELECT
  o.order_id,
  'foo' AS bar -- add new column
...
```

![](slim-ci-log.png#center)

![](slim-ci-output.png#center)


### DBT Deployment

![](deployment-workflow.png#center)

#### DBT Unit Tests

```sql
-- pizza_shot/models/dim/dim_users.sql
WITH src_users AS (
  SELECT * FROM {{ ref('src_users') }}
)
SELECT
    *, 
    created_at AS valid_from,
    COALESCE(
      LEAD(created_at, 1) OVER (PARTITION BY user_id ORDER BY created_at), 
      CAST('2199-12-31' AS DATETIME)
    ) AS valid_to
FROM src_users
```

```yaml
# pizza_shop/models/unit_tests
unit_tests:
  - name: test_is_valid_date_ranges
    model: dim_users
    given:
      - input: ref('src_users')
        rows:
          - { created_at: 2024-08-29T10:29:49 }
          - { created_at: 2024-08-30T10:29:49 }
    expect:
      rows:
        - {
            created_at: 2024-08-29T10:29:49,
            valid_from: 2024-08-29T10:29:49,
            valid_to: 2024-08-30T10:29:49,
          }
        - {
            created_at: 2024-08-30T10:29:49,
            valid_from: 2024-08-30T10:29:49,
            valid_to: 2199-12-31T00:00:00,
          }
```

```yaml
# .github/workflows/deploy.yml
name: deploy

on:
  push:
    branches: ["main"]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

...

env:
  GCP_LOCATION: australia-southeast1
  GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
  GCS_TARGET_PATH: gs://dbt-cicd-demo/artifact
  DBT_PROFILES_DIR: ${{github.workspace}}/dbt_profiles

jobs:
  dbt-unit-tests:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v1
        with:
          python-version: "3.10"

      - name: Create and start virtual environment
        run: |
          python -m venv venv
          source venv/bin/activate

      - name: Install dependencies
        run: |
          pip install -r requirements.txt

      - name: Set up service account key file
        env:
          GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
        run: |
          echo ${GCP_SA_KEY} > ${{github.workspace}}/.github/key.json
          echo SA_KEYFILE=${{github.workspace}}/.github/key.json >> $GITHUB_ENV

      - name: Set up ci dataset
        run: |
          echo CI_DATASET=ci_$(date +'%y%m%d_%S')_$(git rev-parse --short "$GITHUB_SHA") >> $GITHUB_ENV

      - name: Authenticate to GCP
        run: |
          gcloud auth activate-service-account \
            dbt-cicd@${{ env.GCP_PROJECT_ID }}.iam.gserviceaccount.com \
            --key-file $SA_KEYFILE --project ${{ env.GCP_PROJECT_ID }}

      - name: Install dbt dependencies
        run: |
          dbt deps --project-dir=pizza_shop

      - name: Run dbt unit tests
        run: |
          # build all the models that the unit tests need to run, but empty
          dbt run --profiles-dir=${{ env.DBT_PROFILES_DIR }} --project-dir=pizza_shop --target ci \
            --select +test_type:unit --empty
          # perform the actual unit tests
          dbt test --profiles-dir=${{ env.DBT_PROFILES_DIR }} --project-dir=pizza_shop --target ci \
            --select test_type:unit

      # Hacky way of getting around the bq outputting annoying welcome stuff on first run which breaks jq
      - name: Check existing CI datasets
        if: always()
        shell: bash -l {0}
        run: bq ls --project_id=${{ env.GCP_PROJECT_ID }} --quiet=true --headless=true --format=json

      - name: Clean up CI datasets
        if: always()
        shell: bash -l {0}
        run: |
          for dataset in $(bq ls --project_id=${{ env.GCP_PROJECT_ID }} --quiet=true --headless=true --format=json | jq -r '.[].datasetReference.datasetId')
          do
            # If the dataset starts with the prefix, delete it
            if [[ $dataset == $CI_DATASET* ]]; then
              echo "Deleting $dataset"
              bq rm -r -f $dataset
            fi
          done
```


![](unit-test-log.png#center)

#### DBT Image Build and Push

```dockerfile
FROM ghcr.io/dbt-labs/dbt-bigquery:1.8.2

ARG GCP_PROJECT_ID
ARG GCS_TARGET_PATH

ENV GCP_PROJECT_ID=${GCP_PROJECT_ID}
ENV GCS_TARGET_PATH=${GCS_TARGET_PATH}
ENV SA_KEYFILE=/usr/app/dbt/key.json
ENV DBT_ARTIFACT=/usr/app/dbt/pizza_shop/target/manifest.json

## set up gcloud
RUN apt-get update \
  && apt-get install -y curl \
  && curl -sSL https://sdk.cloud.google.com | bash

ENV PATH $PATH:/root/google-cloud-sdk/bin
COPY key.json key.json

## copy dbt source
COPY dbt_profiles dbt_profiles
COPY pizza_shop pizza_shop
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

RUN dbt deps --project-dir=pizza_shop

ENTRYPOINT ["./entrypoint.sh"]
```

```bash
#!/bin/bash
set -e

# authenticate to GCP
gcloud auth activate-service-account \
  dbt-cicd@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --key-file $SA_KEYFILE --project $GCP_PROJECT_ID

# execute DBT with arguments from container launch
dbt "$@"

if [ -n "$GCS_TARGET_PATH" ]; then
    echo "source: $DBT_ARTIFACT, target: $GCS_TARGET_PATH"
    echo "Copying file..."
    gsutil --quiet cp $DBT_ARTIFACT $GCS_TARGET_PATH
fi
```

```bash
docker build \
  --build-arg GCP_PROJECT_ID=$GCP_PROJECT_ID \
  --build-arg GCS_TARGET_PATH=gs://dbt-cicd-demo/artifact \
  -t dbt:test .
```

```bash
$ docker run --rm -it dbt:test \
    test --profiles-dir=dbt_profiles --project-dir=pizza_shop --target dev
Activated service account credentials for: [dbt-cicd@GCP_PROJECT_ID.iam.gserviceaccount.com]
11:53:20  Running with dbt=1.8.3
11:53:21  Registered adapter: bigquery=1.8.2
11:53:21  Unable to do partial parsing because saved manifest not found. Starting full parse.
11:53:22  [WARNING]: Deprecated functionality
The `tests` config has been renamed to `data_tests`. Please see
https://docs.getdbt.com/docs/build/data-tests#new-data_tests-syntax for more
information.
11:53:22  Found 6 models, 3 seeds, 4 data tests, 3 sources, 585 macros, 1 unit test
11:53:22  
11:53:23  Concurrency: 4 threads (target='dev')
11:53:23  
11:53:23  1 of 5 START test not_null_dim_products_product_key ............................ [RUN]
11:53:23  2 of 5 START test not_null_dim_users_user_key .................................. [RUN]
11:53:23  3 of 5 START test unique_dim_products_product_key .............................. [RUN]
11:53:23  4 of 5 START test unique_dim_users_user_key .................................... [RUN]
11:53:24  3 of 5 PASS unique_dim_products_product_key .................................... [PASS in 1.44s]
11:53:24  5 of 5 START unit_test dim_users::test_is_valid_date_ranges .................... [RUN]
11:53:24  1 of 5 PASS not_null_dim_products_product_key .................................. [PASS in 1.50s]
11:53:24  4 of 5 PASS unique_dim_users_user_key .......................................... [PASS in 1.54s]
11:53:25  2 of 5 PASS not_null_dim_users_user_key ........................................ [PASS in 1.59s]
11:53:28  5 of 5 PASS dim_users::test_is_valid_date_ranges ............................... [PASS in 3.66s]
11:53:28  
11:53:28  Finished running 4 data tests, 1 unit test in 0 hours 0 minutes and 5.77 seconds (5.77s).
11:53:28  
11:53:28  Completed successfully
11:53:28  
11:53:28  Done. PASS=5 WARN=0 ERROR=0 SKIP=0 TOTAL=5
source: /usr/app/dbt/pizza_shop/target/manifest.json, target: gs://dbt-cicd-demo/artifact
Copying file...
```

```yaml
# .github/workflows/deploy.yml
name: deploy

on:
  push:
    branches: ["main"]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

...

env:
  GCP_LOCATION: australia-southeast1
  GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
  GCS_TARGET_PATH: gs://dbt-cicd-demo/artifact
  DBT_PROFILES_DIR: ${{github.workspace}}/dbt_profiles

jobs:
  dbt-unit-tests:
    ...

  dbt-deploy:
    runs-on: ubuntu-latest

    needs: dbt-unit-tests

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up service account key file
        env:
          GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
        run: |
          echo ${GCP_SA_KEY} > ${{github.workspace}}/.github/key.json
          echo SA_KEYFILE=${{github.workspace}}/.github/key.json >> $GITHUB_ENV

      - name: Authenticate to GCP
        run: |
          gcloud auth activate-service-account \
            dbt-cicd@${{ env.GCP_PROJECT_ID }}.iam.gserviceaccount.com \
            --key-file $SA_KEYFILE --project ${{ env.GCP_PROJECT_ID }}

      - name: Configure docker
        run: |
          gcloud auth configure-docker ${{ env.GCP_LOCATION }}-docker.pkg.dev --quiet

      - name: Docker build and push
        run: |
          cp ${{github.workspace}}/.github/key.json ${{github.workspace}}/key.json
          export DOCKER_TAG=${{ env.GCP_LOCATION }}-docker.pkg.dev/${{ env.GCP_PROJECT_ID }}/dbt-cicd-demo/dbt:$(git rev-parse --short "$GITHUB_SHA")
          docker build \
            --build-arg GCP_PROJECT_ID=${{ env.GCP_PROJECT_ID }} \
            --build-arg GCS_TARGET_PATH=${{ env.GCS_TARGET_PATH }} \
            -t ${DOCKER_TAG} ./
          docker push ${DOCKER_TAG}
```

#### DBT Document on GitHub Pages

```yaml
# .github/workflows/deploy.yml
name: deploy

on:
  push:
    branches: ["main"]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

...

env:
  GCP_LOCATION: australia-southeast1
  GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
  GCS_TARGET_PATH: gs://dbt-cicd-demo/artifact
  DBT_PROFILES_DIR: ${{github.workspace}}/dbt_profiles

jobs:
  dbt-unit-tests:
    ...

  dbt-docs:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest

    needs: dbt-unit-tests

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v1
        with:
          python-version: "3.10"

      - name: Create and start virtual environment
        run: |
          python -m venv venv
          source venv/bin/activate

      - name: Install dependencies
        run: |
          pip install -r requirements.txt

      - name: Set up service account key file
        env:
          GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
        run: |
          echo ${GCP_SA_KEY} > ${{github.workspace}}/.github/key.json
          echo SA_KEYFILE=${{github.workspace}}/.github/key.json >> $GITHUB_ENV

      - name: Authenticate to GCP
        run: |
          gcloud auth activate-service-account \
            dbt-cicd@${{ env.GCP_PROJECT_ID }}.iam.gserviceaccount.com \
            --key-file $SA_KEYFILE --project ${{ env.GCP_PROJECT_ID }}

      - name: Generate dbt docs
        id: docs
        shell: bash -l {0}
        run: |
          dbt deps --project-dir=pizza_shop
          dbt docs generate --profiles-dir=${{ env.DBT_PROFILES_DIR }} --project-dir=pizza_shop \
            --target dev --target-path dbt-docs

      - name: Upload DBT docs Pages artifact
        id: build
        uses: actions/upload-pages-artifact@v2
        with:
          path: pizza_shop/dbt-docs
          name: dbt-docs

      - name: Publish DBT docs to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v2
        with:
          artifact_name: dbt-docs
```

![](gh-pages-output.png#center)