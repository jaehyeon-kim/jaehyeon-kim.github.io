---
title: AWS Glue Local Development with Docker and Visual Studio Code
date: 2021-08-20
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
#   - API development with R
categories:
  - Data Engineering
tags: 
  - AWS
  - AWS Glue
  - Docker
  - Apache Spark
  - PySpark
  - Python
  - Visual Studio Code
authors:
  - JaehyeonKim
images: []
cevo: 2
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/aws-glue-local-development/).

As described in the product page, [AWS Glue](https://aws.amazon.com/glue) is a _serverless_ data integration service that makes it easy to discover, prepare, and combine data for analytics, machine learning, and application development. For development, a development endpoint is recommended, but it can be costly, inconvenient or [unavailable (for Glue 2.0)](https://docs.aws.amazon.com/glue/latest/dg/reduced-start-times-spark-etl-jobs.html). The [AWS Glue team published a Docker image](https://aws.amazon.com/blogs/big-data/developing-aws-glue-etl-jobs-locally-using-a-container/) that includes the AWS Glue binaries and all the dependencies packaged together. After inspecting it, I find some modifications are necessary in order to build a development environment on it. In this post, I'll demonstrate how to build development environments for AWS Glue 1.0 and 2.0 using the Docker image and the [Visual Studio Code Remote - Containers](https://code.visualstudio.com/docs/remote/containers) extension.


## Configuration

Although [AWS Glue 1.0 and 2.0 have different dependencies and versions](https://docs.aws.amazon.com/glue/latest/dg/release-notes.html), the Python library ([aws-glue-libs](https://github.com/awslabs/aws-glue-libs)) shares the same branch (_glue-1.0_) and Spark version. On the other hand, AWS Glue 2.0 supports Python 3.7 and has [different default python packages](https://docs.aws.amazon.com/glue/latest/dg/reduced-start-times-spark-etl-jobs.html). Therefore, in order to set up an AWS Glue 2.0 development environment, it would be necessary to install Python 3.7 and the default packages while sharing the same Spark-related dependencies.

The _[Visual Studio Code Remote - Containers](https://code.visualstudio.com/docs/remote/containers)_ extension lets you use a Docker container as a full-featured development environment. It allows you to open any folder or repository inside a container and take advantage of Visual Studio Code's full feature set. The [development container configuration](https://code.visualstudio.com/docs/remote/create-dev-container) (`devcontainer.json`) and associating files can be found in the `.devcontainer` folder of the [**GitHub repository** for this post](https://github.com/jaehyeon-kim/glue-vscode). Apart from the configuration file, the folder includes a Dockerfile, files to keep Python packages to install and a custom Pytest executable for AWS Glue 2.0 (_gluepytest2_) - this executable will be explained later.


```bash
.
├── .devcontainer
│   ├── 3.6
│   │   └── dev.txt
│   ├── 3.7
│   │   ├── default.txt
│   │   └── dev.txt
│   ├── Dockerfile
│   ├── bin
│   │   └── gluepytest2
│   └── devcontainer.json
├── .gitignore
├── README.md
├── example.py
├── execute.sh
├── src
│   └── utils.py
└── tests
    ├── __init__.py
    ├── conftest.py
    └── test_utils.py
```

### Dockerfile

The Docker image (`amazon/aws-glue-libs:glue_libs_1.0.0_image_01`) runs as the root user, and it is not convenient to write code with it. Therefore, a non-root user is created whose username corresponds to the logged-in user's username - the USERNAME argument will be set accordingly in `devcontainer.json`. Next the sudo program is added in order to install other programs if necessary. More importantly, the Python Glue library's executables are configured to run with the root user so that the sudo program is necessary to run those executables. Then the 3rd-party Python packages are installed for the Glue 1.0 and 2.0 development environments. Note that a virtual environment is created for the latter and the [default Python packages](https://docs.aws.amazon.com/glue/latest/dg/reduced-start-times-spark-etl-jobs.html) and additional development packages are installed in it. Finally, a Pytest executable is copied to the Python Glue library's executable path. It is because the Pytest path is hard-coded in the existing executable (`gluepytest`) and I just wanted to run test cases in the Glue 2.0 environment without touching existing ones - the Pytest path is set to `/root/venv/bin/pytest_ in _gluepytest2`.


```Dockerfile
## .devcontainer/Dockerfile
FROM amazon/aws-glue-libs:glue_libs_1.0.0_image_01

ARG USERNAME
ARG USER_UID
ARG USER_GID

## Create non-root user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

## Add sudo support in case we need to install software after connecting
## Jessie is not the latest stable Debian release - jessie-backports is not available
RUN rm -rf /etc/apt/sources.list.d/jessie-backports.list

RUN apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

## Install extra packages for python 3.6
COPY ./3.6 /tmp/3.6
RUN pip install -r /tmp/3.6/dev.txt

## Setup python 3.7 and install default and development packages to a virtual env
RUN apt-get update \
    && apt-get install -y python3.7 python3.7-venv

RUN python3.7 -m venv /root/venv

COPY ./3.7 /tmp/3.7
RUN /root/venv/bin/pip install -r /tmp/3.7/dev.txt

## Copy pytest execution script to /aws-glue-libs/bin
## in order to run pytest from the virtual env
COPY ./bin/gluepytest2 /home/aws-glue-libs/bin/gluepytest2
```

### Container Configuration

The development container will be created by building an image from the Dockerfile illustrated above. The logged-in user's username is provided to create a non-root user and the container is set to run as the user as well. And 2 Visual Studio Code extensions are installed - [Python](https://marketplace.visualstudio.com/items?itemName=ms-python.python) and [Prettier](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode). Also, the current folder is mounted to the container's workspace folder and 2 additional folders are mounted - they are to share AWS credentials and SSH keys. Note that AWS credentials are mounted to `/roo/.aws` because the Python Glue library's executables will be run as the root user. Then the port 4040 is set to be forwarded, which is used for the Spark UI. Finally, additional editor settings are added at the end.


```json
// .devcontainer/devcontainer.json
{
  "name": "glue",
  "build": {
    "dockerfile": "Dockerfile",
    "args": {
      "USERNAME": "${localEnv:USER}",
      "USER_UID": "1000",
      "USER_GID": "1000"
    }
  },
  "containerUser": "${localEnv:USER}",
  "extensions": [
    "ms-python.python",
    "esbenp.prettier-vscode"
  ],
  "workspaceMount": "source=${localWorkspaceFolder},target=${localEnv:HOME}/glue-vscode,type=bind,consistency=cached",
  "workspaceFolder": "${localEnv:HOME}/glue-vscode",
  "forwardPorts": [4040],
  "mounts": [ 
    "source=${localEnv:HOME}/.aws,target=/root/.aws,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.ssh,target=${localEnv:HOME}/.ssh,type=bind,consistency=cached"
  ],
  "settings": {
    "terminal.integrated.profiles.linux": {
      "bash": {
        "path": "/bin/bash"
      }
    },
    "terminal.integrated.defaultProfile.linux": "bash",
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.tabSize": 2,
    "python.testing.pytestEnabled": true,
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": false,
    "python.linting.flake8Enabled": false,
    "python.formatting.provider": "black",
    "python.formatting.blackPath": "black",
    "python.formatting.blackArgs": ["--line-length", "100"],
    "[python]": {
      "editor.tabSize": 4,
      "editor.defaultFormatter": "ms-python.python"
    }
  }
}
```

### Launch Container

The development container can be run by executing the following command in the command palette. 

* _Remote-Containers: Open Folder in Container..._

![](glue_config.png#center)


Once the development container is ready, the workspace folder will be open within the container. You will see 2 new images are created from the base Glue image and a container is run from the latest image.

![](glue_container.png#center)

## Examples

I've created a simple script (_execute.sh_) to run the executables easily. The main command indicates which executable to run and possible values are `pyspark`, `spark-submit` and `pytest`. Note that the IPython notebook is available, but it is not added because I don't think a notebook is good for development. However, you may try by just adding it. Below shows some example commands.

```bash
# pyspark
version=1 ./execute.sh pyspark OR version=2 ./execute.sh pyspark
# spark submit
version=1 ./execute.sh spark-submit example.py OR version=2 ./execute.sh spark-submit example.py
# pytest
version=1 ./execute.sh pytest -svv OR version=2 ./execute.sh pytest -svv
```

```bash
# ./execute.sh
#!/usr/bin/env bash

## configure python runtime
if [ "$version" == "1" ]; then
  pyspark_python=python
elif [ "$version" == "2" ]; then
  pyspark_python=/root/venv/bin/python
else
  echo "unsupported version - $version, only 1 or 2 is accepted"
  exit 1
fi
echo "pyspark python - $pyspark_python"

execution=$1
echo "execution type - $execution"

## remove first argument
shift 1
echo $@

## set up command
if [ $execution == 'pyspark' ]; then
  sudo su -c "PYSPARK_PYTHON=$pyspark_python /home/aws-glue-libs/bin/gluepyspark"
elif [ $execution == 'spark-submit' ]; then
  sudo su -c "PYSPARK_PYTHON=$pyspark_python /home/aws-glue-libs/bin/gluesparksubmit $@"
elif [ $execution == 'pytest' ]; then
  if [ $version == "1" ]; then
    sudo su -c "PYSPARK_PYTHON=$pyspark_python /home/aws-glue-libs/bin/gluepytest $@"
  else
    sudo su -c "PYSPARK_PYTHON=$pyspark_python /home/aws-glue-libs/bin/gluepytest2 $@"
  fi
else
  echo "unsupported execution type - $execution"
  exit 1
fi
```
### Pyspark 

Using the script above, we can launch the PySpark shells for each of the environments. Python 3.6.10 is associated with the AWS Glue 1.0 while Python 3.7.3 in a virtual environment is with the AWS Glue 2.0.

![](glue_pyspark.png#center)

### Spark Submit

Below shows [one of the Python samples](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-python-samples-legislators.html) in the Glue documentation. It pulls 3 data sets from a database called _legislators_. Then they are joined to create a history data set (_l_history_) and saved into S3.

```python
# ./example.py
from awsglue.dynamicframe import DynamicFrame
from awsglue.transforms import Join
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext

glueContext = GlueContext(SparkContext.getOrCreate())

DATABASE = "legislators"
OUTPUT_PATH = "s3://glue-python-samples-fbe445ee/output_dir"

## create dynamic frames from data catalog
persons: DynamicFrame = glueContext.create_dynamic_frame.from_catalog(
    database=DATABASE, table_name="persons_json"
)

memberships: DynamicFrame = glueContext.create_dynamic_frame.from_catalog(
    database=DATABASE, table_name="memberships_json"
)

orgs: DynamicFrame = glueContext.create_dynamic_frame.from_catalog(
    database=DATABASE, table_name="organizations_json"
)

## manipulate data
orgs = (
    orgs.drop_fields(["other_names", "identifiers"])
    .rename_field("id", "org_id")
    .rename_field("name", "org_name")
)

l_history: DynamicFrame = Join.apply(
    orgs, Join.apply(persons, memberships, "id", "person_id"), "org_id", "organization_id"
)
l_history = l_history.drop_fields(["person_id", "org_id"])

l_history.printSchema()

## write to s3
glueContext.write_dynamic_frame.from_options(
    frame=l_history,
    connection_type="s3",
    connection_options={"path": f"{OUTPUT_PATH}/legislator_history"},
    format="parquet",
)
```

When the execution completes, we can see the joined data set is stored as a parquet file in the output S3 bucket.

![](glue_spark-submit.png#center)


Note that we can monitor and inspect Spark job executions in the Spark UI on port 4040.

![](glue_spark-ui.png#center)

### Pytest

We can test a function that deals with a [DynamicFrame](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-api-crawler-pyspark-extensions-dynamic-frame.html). Below shows a test case for a simple function that filters a DynamicFrame based on a column value.


```python
# ./src/utils.py
from awsglue.dynamicframe import DynamicFrame

def filter_dynamic_frame(dyf: DynamicFrame, column_name: str, value: int):
    return dyf.filter(f=lambda x: x[column_name] > value)

# ./tests/conftest.py
from pyspark.context import SparkContext
from awsglue.context import GlueContext
import pytest

@pytest.fixture(scope="session")
def glueContext():
    sparkContext = SparkContext()
    glueContext = GlueContext(sparkContext)
    yield glueContext
    sparkContext.stop()


# ./tests/test_utils.py
from typing import List
from awsglue.dynamicframe import DynamicFrame
import pandas as pd
from src.utils import filter_dynamic_frame

def _get_sorted_data_frame(pdf: pd.DataFrame, columns_list: List[str] = None):
    if columns_list is None:
        columns_list = list(pdf.columns.values)
    return pdf.sort_values(columns_list).reset_index(drop=True)


def test_filter_dynamic_frame_by_value(glueContext):
    spark = glueContext.spark_session

    input = spark.createDataFrame(
        [("charly", 15), ("fabien", 18), ("sam", 21), ("sam", 25), ("nick", 19), ("nick", 40)],
        ["name", "age"],
    )

    expected_output = spark.createDataFrame(
        [("sam", 25), ("sam", 21), ("nick", 40)],
        ["name", "age"],
    )

    real_output = filter_dynamic_frame(DynamicFrame.fromDF(input, glueContext, "output"), "age", 20)

    pd.testing.assert_frame_equal(
        _get_sorted_data_frame(real_output.toDF().toPandas(), ["name", "age"]),
        _get_sorted_data_frame(expected_output.toPandas(), ["name", "age"]),
        check_like=True,
    )
```

![](glue_pytest.png#center)


## Conclusion

In this post, I demonstrated how to build local development environments for AWS Glue 1.0 and 2.0 using Docker and the Visual Studio Code Remote - Containers extension. Then examples of launching Pyspark shells, submitting an application and running a test are shown. I hope this post is useful to develop and test Glue ETL scripts locally.
