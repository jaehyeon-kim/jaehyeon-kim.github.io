---
title: Revisit AWS Lambda Invoke Function Operator of Apache Airflow
date: 2022-08-06
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
  - AWS Lambda
  - Apache Airflow
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
cevo: 15
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/revisit-airflow-lambda-operator/).

[Apache Airflow](https://airflow.apache.org/) is a popular workflow management platform. A wide range of AWS services are integrated with the platform by [Amazon AWS Operators](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/operators/index.html). AWS Lambda is one of the integrated services, and it can be used to develop workflows efficiently. The current [Lambda Operator](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/operators/lambda.html), however, just invokes a Lambda function, and it can fail to report the invocation result of a function correctly and to record the exact error message from failure. In this post, we’ll discuss a custom Lambda operator that handles those limitations.


## Architecture

We’ll discuss a custom Lambda operator, and it extends the Lambda operator provided by AWS. When a DAG creates a task that invokes a Lambda function, it updates the Lambda payload with a _correlation ID_ that uniquely identifies the task. The correlation ID is added to every log message that the Lambda function generates. Finally, the custom operator filters the associating CloudWatch log events, prints the log messages and raises a runtime error when an error message is found. In this setup, we are able to correctly identify the function invocation result and to point to the exact error message if it fails. The source of this post can be found in a [**GitHub repository**](https://github.com/jaehyeon-kim/revisit-lambda-operator).

![](featured.png#center)

## Lambda Setup

### Lambda Function

The [Logger utility](https://awslabs.github.io/aws-lambda-powertools-python/latest/core/logger/) of the [Lambda Powertools Python](https://awslabs.github.io/aws-lambda-powertools-python/latest/) package is used to record log messages. The correlation ID is added to the event payload, and it is set to be injected with log messages by the _logger.inject_lambda_context_ decorator. Note the Lambda Context would be a better place to add a correlation ID as we can add a custom client context object. However, it is not recognised when an invocation is made asynchronously, and we have to add it to the event payload. We use another decorator (_middleware_before_after_) and it logs messages before and after the function invocation. The latter message that indicates the end of a function is important as we can rely on it in order to identify whether a function is completed without an error. If a function finishes with an error, the last log message won’t be recorded. Also, we can check if a function fails by checking a log message where its level is ERROR, and it is created by the _logger.exception_ method. The Lambda event payload has two extra attributes - _n_ for setting-up the number of iteration and _to_fail_ for determining whether to raise an error.


```python
# lambda/src/lambda_function.py
import time
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.middleware_factory import lambda_handler_decorator

logger = Logger(log_record_order=["correlation_id", "level", "message", "location"])


@lambda_handler_decorator
def middleware_before_after(handler, event, context):
    logger.info("Function started")
    response = handler(event, context)
    logger.info("Function ended")
    return response


@logger.inject_lambda_context(correlation_id_path="correlation_id")
@middleware_before_after
def lambda_handler(event: dict, context: LambdaContext):
    num_iter = event.get("n", 10)
    to_fail = event.get("to_fail", False)
    logger.info(f"num_iter - {num_iter}, fail - {to_fail}")
    try:
        for n in range(num_iter):
            logger.info(f"iter - {n + 1}...")
            time.sleep(1)
        if to_fail:
            raise Exception
    except Exception as e:
        logger.exception("Function invocation failed...")
        raise RuntimeError("Unable to finish loop") from e
```



### SAM Template

The [Serverless Application Model (SAM) framework](https://aws.amazon.com/serverless/sam/) is used to deploy the Lambda function. The Lambda Powertools Python package is added as a Lambda layer. The Lambda log group is configured so that messages are kept only for 1 day, and it can help reduce time to filter log events. By default, a Lambda function is invoked twice more on error when it is invoked asynchronously - the default retry attempts equals to 2. It is set to 0 as retry behaviour can be controlled by Airflow if necessary, and it can make it easier to track function invocation status.


```yaml
# lambda/template.yml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Description: Lambda functions used to demonstrate Lambda invoke operator with S3 log extension

Globals:
  Function:
    MemorySize: 128
    Timeout: 30
    Runtime: python3.8
    Tracing: Active
    Environment:
      Variables:
        POWERTOOLS_SERVICE_NAME: airflow
        LOG_LEVEL: INFO
    Tags:
      Application: LambdaInvokeOperatorDemo
Resources:
  ExampleFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: example-lambda-function
      Description: Example lambda function
      CodeUri: src/
      Handler: lambda_function.lambda_handler
      Layers:
        - !Sub arn:aws:lambda:${AWS::Region}:017000801446:layer:AWSLambdaPowertoolsPython:26
  ExampleFunctionAsyncConfig:
    Type: AWS::Lambda::EventInvokeConfig
    Properties:
      FunctionName: !Ref ExampleFunction
      MaximumRetryAttempts: 0
      Qualifier: "$LATEST"
  LogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub "/aws/lambda/${ExampleFunction}"
      RetentionInDays: 1

Outputs:
  ExampleFunction:
    Value: !Ref ExampleFunction
    Description: Example lambda function ARN
```

## Lambda Operator

### Lambda Invoke Function Operator

Below shows the source of the [Lambda invoke function operator](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/operators/lambda.html). After invoking a Lambda function, the _execute _method checks if the response status code indicates success and whether _[FunctionError](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html#API_Invoke_ResponseSyntax) _is found in the response payload. When an invocation is made synchronously (_RequestResponse_ invocation type), it can identify whether the invocation is successful or not because the response is returned after it finishes. However it reports a generic error message when it fails and we have to visit CloudWatch Logs if we want to check the exact error. It gets worse when it is invoked asynchronously (_Event_ invocation type) because the response is made before the invocation finishes. In this case it is not even possible to check whether the invocation is successful.  


```python
...

class AwsLambdaInvokeFunctionOperator(BaseOperator):
    def __init__(
        self,
        *,
        function_name: str,
        log_type: Optional[str] = None,
        qualifier: Optional[str] = None,
        invocation_type: Optional[str] = None,
        client_context: Optional[str] = None,
        payload: Optional[str] = None,
        aws_conn_id: str = 'aws_default',
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.function_name = function_name
        self.payload = payload
        self.log_type = log_type
        self.qualifier = qualifier
        self.invocation_type = invocation_type
        self.client_context = client_context
        self.aws_conn_id = aws_conn_id

    def execute(self, context: 'Context'):
        hook = LambdaHook(aws_conn_id=self.aws_conn_id)
        success_status_codes = [200, 202, 204]
        self.log.info("Invoking AWS Lambda function: %s with payload: %s", self.function_name, self.payload)
        response = hook.invoke_lambda(
            function_name=self.function_name,
            invocation_type=self.invocation_type,
            log_type=self.log_type,
            client_context=self.client_context,
            payload=self.payload,
            qualifier=self.qualifier,
        )
        self.log.info("Lambda response metadata: %r", response.get("ResponseMetadata"))
        if response.get("StatusCode") not in success_status_codes:
            raise ValueError('Lambda function did not execute', json.dumps(response.get("ResponseMetadata")))
        payload_stream = response.get("Payload")
        payload = payload_stream.read().decode()
        if "FunctionError" in response:
            raise ValueError(
                'Lambda function execution resulted in error',
                {"ResponseMetadata": response.get("ResponseMetadata"), "Payload": payload},
            )
        self.log.info('Lambda function invocation succeeded: %r', response.get("ResponseMetadata"))
        return payload
```

### Custom Lambda Operator

The custom Lambda operator extends the Lambda invoke function operator. It updates the Lambda payload by adding a correlation ID. The _execute _method is extended by the _log_processor _decorator function. As the name suggests, the decorator function filters all log messages that include the correlation ID and print them. This process loops over the lifetime of the invocation. While processing log events, it raises an error if an error message is found. And log event processing gets stopped when a message that indicates the end of the invocation is encountered. Finally, in order to handle the case where an invocation doesn’t finish within the timeout seconds, it raises an error at the end of the loop. 

The main benefits of this approach are

* we don’t have to rewrite Lambda invocation logic as we extend the Lambda invoke function operator,
* we can track a lambda invocation status regardless of its invocation type, and
* we are able to record all relevant log messages of an invocation

```python
# airflow/dags/lambda_operator.py
...

class CustomLambdaFunctionOperator(AwsLambdaInvokeFunctionOperator):
    def __init__(
        self,
        *,
        function_name: str,
        log_type: Optional[str] = None,
        qualifier: Optional[str] = None,
        invocation_type: Optional[str] = None,
        client_context: Optional[str] = None,
        payload: Optional[str] = None,
        aws_conn_id: str = "aws_default",
        correlation_id: str = str(uuid4()),
        **kwargs,
    ):
        super().__init__(
            function_name=function_name,
            log_type=log_type,
            qualifier=qualifier,
            invocation_type=invocation_type,
            client_context=client_context,
            payload=json.dumps(
                {**json.loads((payload or "{}")), **{"correlation_id": correlation_id}}
            ),
            aws_conn_id=aws_conn_id,
            **kwargs,
        )
        self.correlation_id = correlation_id

    def log_processor(func):
        @functools.wraps(func)
        def wrapper_decorator(self, *args, **kwargs):
            payload = func(self, *args, **kwargs)
            function_timeout = self.get_function_timeout()
            self.process_log_events(function_timeout)
            return payload

        return wrapper_decorator

    @log_processor
    def execute(self, context: "Context"):
        return super().execute(context)

    def get_function_timeout(self):
        resp = boto3.client("lambda").get_function_configuration(FunctionName=self.function_name)
        return resp["Timeout"]

    def process_log_events(self, function_timeout: int):
        start_time = 0
        for _ in range(function_timeout):
            response_iterator = self.get_response_iterator(
                self.function_name, self.correlation_id, start_time
            )
            for page in response_iterator:
                for event in page["events"]:
                    start_time = event["timestamp"]
                    message = json.loads(event["message"])
                    print(message)
                    if message["level"] == "ERROR":
                        raise RuntimeError("ERROR found in log")
                    if message["message"] == "Function ended":
                        return
            time.sleep(1)
        raise RuntimeError("Lambda function end message not found after function timeout")

    @staticmethod
    def get_response_iterator(function_name: str, correlation_id: str, start_time: int):
        paginator = boto3.client("logs").get_paginator("filter_log_events")
        return paginator.paginate(
            logGroupName=f"/aws/lambda/{function_name}",
            filterPattern=f'"{correlation_id}"',
            startTime=start_time + 1,
        )
```

### Unit Testing

Unit testing is performed for the main log processing function (_process_log_events_). Log events fixture is created by a closure function. Depending on the case argument, it returns a log events list that covers success, error or timeout error. It is used as the mock response of the _get_response_iterator _method. The 3 testing cases cover each of the possible scenarios.


```python
# airflow/tests/test_lambda_operator.py
import json
import pytest
from unittest.mock import MagicMock
from dags.lambda_operator import CustomLambdaFunctionOperator


@pytest.fixture
def log_events():
    def _(case):
        events = [
            {
                "timestamp": 1659296879605,
                "message": '{"correlation_id":"2850fda4-9005-4375-aca8-88dfdda222ba","level":"INFO","message":"Function started","location":"middleware_before_after:12","timestamp":"2022-07-31 19:47:59,605+0000","service":"airflow", ...}\n',
            },
            {
                "timestamp": 1659296879605,
                "message": '{"correlation_id":"2850fda4-9005-4375-aca8-88dfdda222ba","level":"INFO","message":"num_iter - 10, fail - False","location":"lambda_handler:23","timestamp":"2022-07-31 19:47:59,605+0000","service":"airflow", ...}\n',
            },
            {
                "timestamp": 1659296879605,
                "message": '{"correlation_id":"2850fda4-9005-4375-aca8-88dfdda222ba","level":"INFO","message":"iter - 1...","location":"lambda_handler:26","timestamp":"2022-07-31 19:47:59,605+0000","service":"airflow", ...}\n',
            },
        ]
        if case == "success":
            events.append(
                {
                    "timestamp": 1659296889620,
                    "message": '{"correlation_id":"2850fda4-9005-4375-aca8-88dfdda222ba","level":"INFO","message":"Function ended","location":"middleware_before_after:14","timestamp":"2022-07-31 19:48:09,619+0000","service":"airflow", ...}\n',
                }
            )
        elif case == "error":
            events.append(
                {
                    "timestamp": 1659296889629,
                    "message": '{"correlation_id":"2850fda4-9005-4375-aca8-88dfdda222ba","level":"ERROR","message":"Function invocation failed...","location":"lambda_handler:31","timestamp":"2022-07-31 19:48:09,628+0000","service":"airflow", ..., "exception":"Traceback (most recent call last):\\n  File \\"/var/task/lambda_function.py\\", line 29, in lambda_handler\\n    raise Exception\\nException","exception_name":"Exception","xray_trace_id":"1-62e6dc6f-30b8e51d000de0ee5a22086b"}\n',
                },
            )
        return [{"events": events}]

    return _


def test_process_log_events_success(log_events):
    success_resp = log_events("success")
    operator = CustomLambdaFunctionOperator(
        task_id="sync_w_error",
        function_name="",
        invocation_type="RequestResponse",
        payload=json.dumps({"n": 1, "to_fail": True}),
        aws_conn_id=None,
    )
    operator.get_response_iterator = MagicMock(return_value=success_resp)
    assert operator.process_log_events(1) == None


def test_process_log_events_fail_with_error(log_events):
    fail_resp = log_events("error")
    operator = CustomLambdaFunctionOperator(
        task_id="sync_w_error",
        function_name="",
        invocation_type="RequestResponse",
        payload=json.dumps({"n": 1, "to_fail": True}),
        aws_conn_id=None,
    )
    operator.get_response_iterator = MagicMock(return_value=fail_resp)
    with pytest.raises(RuntimeError) as e:
        operator.process_log_events(1)
    assert "ERROR found in log" == str(e.value)


def test_process_log_events_fail_by_timeout(log_events):
    fail_resp = log_events(None)
    operator = CustomLambdaFunctionOperator(
        task_id="sync_w_error",
        function_name="",
        invocation_type="RequestResponse",
        payload=json.dumps({"n": 1, "to_fail": True}),
        aws_conn_id=None,
    )
    operator.get_response_iterator = MagicMock(return_value=fail_resp)
    with pytest.raises(RuntimeError) as e:
        operator.process_log_events(1)
    assert "Lambda function end message not found after function timeout" == str(e.value)
```


Below shows the results of the testing.


```bash
$ pytest airflow/tests/test_lambda_operator.py -v
============================================ test session starts =============================================
platform linux -- Python 3.8.10, pytest-7.1.2, pluggy-1.0.0 -- /home/jaehyeon/personal/revisit-lambda-operator/venv/bin/python3
cachedir: .pytest_cache
rootdir: /home/jaehyeon/personal/revisit-lambda-operator
plugins: anyio-3.6.1
collected 3 items                                                                                            

airflow/tests/test_lambda_operator.py::test_process_log_events_success PASSED                          [ 33%]
airflow/tests/test_lambda_operator.py::test_process_log_events_fail_with_error PASSED                  [ 66%]
airflow/tests/test_lambda_operator.py::test_process_log_events_fail_by_timeout PASSED                  [100%]

============================================= 3 passed in 1.34s ==============================================
```

## Compare Operators

### Docker Compose

In order to compare the two operators, the [Airflow Docker quick start guide](https://airflow.apache.org/docs/apache-airflow/stable/start/docker.html) is simplified into using the [Local Executor](https://airflow.apache.org/docs/apache-airflow/stable/executor/local.html). In this setup, both scheduling and task execution are handled by the airflow scheduler service. Instead of creating an [AWS connection](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/connections/aws.html) for invoking Lambda functions, the host AWS configuration is shared by volume-mapping (_${HOME}/.aws to /home/airflow/.aws_). Also, as I don’t use the default AWS profile but a profile named _cevo_, it is added to the scheduler service as an environment variable (_AWS_PROFILE: "cevo"_). 


```yaml
# airflow/docker-compose.yaml
---
version: "3"
x-airflow-common: &airflow-common
  image: ${AIRFLOW_IMAGE_NAME:-apache/airflow:2.3.3}
  environment: airflow-common-env
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    # For backward compatibility, with Airflow <2.3
    AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    AIRFLOW__CORE__FERNET_KEY: ""
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: "true"
    AIRFLOW__CORE__LOAD_EXAMPLES: "false"
    AIRFLOW__API__AUTH_BACKENDS: "airflow.api.auth.backend.basic_auth"
    _PIP_ADDITIONAL_REQUIREMENTS: ${_PIP_ADDITIONAL_REQUIREMENTS:-}
  volumes:
    - ./dags:/opt/airflow/dags
    - ./logs:/opt/airflow/logs
    - ./plugins:/opt/airflow/plugins
    - ${HOME}/.aws:/home/airflow/.aws
  user: "${AIRFLOW_UID:-50000}:0"
  depends_on: &airflow-common-depends-on
    postgres:
      condition: service_healthy

services:
  postgres:
    image: postgres:13
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - postgres-db-volume:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 5s
      retries: 5

  airflow-webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - 8080:8080
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    environment:
      <<: *airflow-common-env
      AWS_PROFILE: "cevo"
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-init:
    <<: *airflow-common
    entrypoint: /bin/bash
    # yamllint disable rule:line-length
    command:
      - -c
      - |
        if [[ -z "${AIRFLOW_UID}" ]]; then
          echo
          echo -e "\033[1;33mWARNING!!!: AIRFLOW_UID not set!\e[0m"
          echo "If you are on Linux, you SHOULD follow the instructions below to set "
          echo "AIRFLOW_UID environment variable, otherwise files will be owned by root."
          echo "For other operating systems you can get rid of the warning with manually created .env file:"
          echo "    See: https://airflow.apache.org/docs/apache-airflow/stable/start/docker.html#setting-the-right-airflow-user"
          echo
        fi
        mkdir -p /sources/logs /sources/dags /sources/plugins
        chown -R "${AIRFLOW_UID}:0" /sources/{logs,dags,plugins}
        exec /entrypoint airflow version
    # yamllint enable rule:line-length
    environment:
      <<: *airflow-common-env
      _AIRFLOW_DB_UPGRADE: "true"
      _AIRFLOW_WWW_USER_CREATE: "true"
      _AIRFLOW_WWW_USER_USERNAME: ${_AIRFLOW_WWW_USER_USERNAME:-airflow}
      _AIRFLOW_WWW_USER_PASSWORD: ${_AIRFLOW_WWW_USER_PASSWORD:-airflow}
      _PIP_ADDITIONAL_REQUIREMENTS: ""
    user: "0:0"
    volumes:
      - .:/sources

volumes:
  postgres-db-volume:
```


The quick start guide requires a number of steps to [initialise an environment](https://airflow.apache.org/docs/apache-airflow/stable/start/docker.html#initializing-environment) before starting the services and they are added to a single shell script shown below.


```bash
# airflow/init.sh
#!/usr/bin/env bash

## initialising environment
# remove docker-compose services
docker-compose down --volumes
# create folders to mount
rm -rf ./logs
mkdir -p ./dags ./logs ./plugins ./tests
# setting the right airflow user
echo -e "AIRFLOW_UID=$(id -u)" > .env
# initialise database
docker-compose up airflow-init
```

After finishing the initialisation steps, the docker compose services can be started by `docker-compose up -d`.


### Lambda Invoke Function Operator

Two tasks are created with the Lambda invoke function operator. The first is invoked synchronously (_RequestResponse_) while the latter is asynchronously (_Event_). Both are configured to raise an error after 10 seconds.


```python
# airflow/dags/example_without_logging.py
import os
import json
from datetime import datetime

from airflow import DAG
from airflow.providers.amazon.aws.operators.aws_lambda import AwsLambdaInvokeFunctionOperator

LAMBDA_FUNCTION_NAME = os.getenv("LAMBDA_FUNCTION_NAME", "example-lambda-function")


def _set_payload(n: int = 10, to_fail: bool = True):
    return json.dumps({"n": n, "to_fail": to_fail})


with DAG(
    dag_id="example_without_logging",
    schedule_interval=None,
    start_date=datetime(2022, 1, 1),
    max_active_runs=2,
    concurrency=2,
    tags=["logging"],
    catchup=False,
) as dag:
    [
        AwsLambdaInvokeFunctionOperator(
            task_id="sync_w_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="RequestResponse",
            payload=_set_payload(),
            aws_conn_id=None,
        ),
        AwsLambdaInvokeFunctionOperator(
            task_id="async_w_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="Event",
            payload=_set_payload(),
            aws_conn_id=None,
        ),
    ]
```


As shown below the task by asynchronous invocation is incorrectly marked as _success_. It is because practically only the response status code is checked as it doesn't wait until the invocation finishes. On the other hand, the task by synchronous invocation is indicated as _failed_. However, it doesn’t show the exact error that fails the invocation - see below for further details.

![](dag-without-logging.png#center)


The error message is _Lambda function execution resulted in error_, and it is the generic message constructed by the Lambda invoke function operator.


![](dag-without-logging-fail.png#center)


### Custom Lambda Operator

Five tasks are created with the custom Lambda operator The first four tasks cover success and failure by synchronous and asynchronous invocations. The last task is to check failure due to timeout.


```python
# airflow/dags/example_with_logging.py
import os
import json
from datetime import datetime

from airflow import DAG
from lambda_operator import CustomLambdaFunctionOperator

LAMBDA_FUNCTION_NAME = os.getenv("LAMBDA_FUNCTION_NAME", "example-lambda-function")


def _set_payload(n: int = 10, to_fail: bool = True):
    return json.dumps({"n": n, "to_fail": to_fail})


with DAG(
    dag_id="example_with_logging",
    schedule_interval=None,
    start_date=datetime(2022, 1, 1),
    max_active_runs=2,
    concurrency=5,
    tags=["logging"],
    catchup=False,
) as dag:
    [
        CustomLambdaFunctionOperator(
            task_id="sync_w_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="RequestResponse",
            payload=_set_payload(),
            aws_conn_id=None,
        ),
        CustomLambdaFunctionOperator(
            task_id="async_w_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="Event",
            payload=_set_payload(),
            aws_conn_id=None,
        ),
        CustomLambdaFunctionOperator(
            task_id="sync_wo_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="RequestResponse",
            payload=_set_payload(to_fail=False),
            aws_conn_id=None,
        ),
        CustomLambdaFunctionOperator(
            task_id="async_wo_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="Event",
            payload=_set_payload(to_fail=False),
            aws_conn_id=None,
        ),
        CustomLambdaFunctionOperator(
            task_id="async_timeout_error",
            function_name=LAMBDA_FUNCTION_NAME,
            invocation_type="Event",
            payload=_set_payload(n=40, to_fail=False),
            aws_conn_id=None,
        ),
    ]
```


As expected we see two success tasks and three failure tasks. The custom Lambda operator tracks Lambda function invocation status correctly.

![](dag-with-logging.png#center)


Below shows log messages of the success task by asynchronous invocation. Each message includes the same correlation ID and the last message from the Lambda function is _Function ended_.

![](dag-with-logging-success.png#center)


The failed task by asynchronous invocation also shows all log messages, and it is possible to check what caused the invocation to fail.

![](dag-with-logging-fail.png#center)


The case of failure due to timeout doesn’t show an error message from the Lambda invocation. However, we can treat it as failure because we don’t see the message of the function invocation ended within the function timeout.

![](dag-with-logging-timeout.png#center)


Still the failure by synchronous invocation doesn’t show the exact error message, and it is because an error is raised before the process log events function is executed. Because of this, I advise to invoke a Lambda function asynchronously.

![](dag-with-logging-fail-sync.png#center)

## Summary

In this post, we discussed limitations of the Lambda invoke function operator and created a custom Lambda operator. The custom operator reports the invocation result of a function correctly and records the exact error message from failure. A number of tasks are created to compare the results between the two operators, and it is shown that the custom operator handles those limitations successfully.
