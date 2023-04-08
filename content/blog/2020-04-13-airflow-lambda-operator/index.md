---
title: Thoughts on Apache Airflow AWS Lambda Operator
date: 2020-04-13
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
  - AWS Lambda
  - Apache Airflow
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
---

[Apache Airflow](https://airflow.apache.org/) is a popular open-source workflow management platform. Typically tasks run remotely by [Celery](http://www.celeryproject.org/) workers for scalability. In AWS, however, scalability can also be achieved using serverless computing services in a simpler way. For example, the [ECS Operator](https://airflow.apache.org/docs/stable/_api/airflow/contrib/operators/ecs_operator/index.html) allows to run _dockerized_ tasks and, with the _Fargate_ launch type, they can run in a serverless environment.

The ECS Operator alone is not sufficent because it can take up to several minutes to pull a Docker image and to set up network interface (for the case of _Fargate_ launch type). Due to its latency, it is not suitable for frequently-running tasks. On the other hand, the latency of a Lambda function is negligible so that it's more suitable for managing such tasks.

In this post, it is demonstrated how AWS Lambda can be integrated with Apache Airflow using a custom operator inspired by the ECS Operator.

## How it works

The following shows steps when an Airflow task is executed by the ECS Operator.

* Running the associating ECS task
* Waiting for the task ended
* Checking the task status

The status of a task is checked by searching a [stopped reason](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-errors.html) and raises `AirflowException` if the reason is considered to be failure. While checking the status, the associating CloudWatch log events are pulled and printed so that the ECS task's container logs can be found in Airflow web server.

The key difference between ECS and Lambda is that the former sends log events to a dedicated CloudWatch Log Stream while the latter may reuse an existing Log Stream due to [container reuse](https://aws.amazon.com/blogs/compute/container-reuse-in-lambda/). Therefore it is not straightforward to pull execution logs for a specific Lambda invocation. It can be handled by creating a custom CloudWatch Log Group and sending log events to a CloudWatch Log Stream within the custom Log Group. For example, let say there is a Lambda function named as *airflow-test*. In order to pull log events for a specific Lambda invocation, a custom Log Group (eg **/airflow/lambda/airflow-test**) can be created and, inside the Lambda function, log events can be sent to a Log Stream within the custom Log Group. Note that the CloudWatch Log Stream name can be determined by the operator and sent to the Lambda function in the Lambda payload. In this way, the Lambda function can send log events to a Log Stream that Airflow knows. Then the steps of a custom Lambda Operator can be as following.

* Invoking the Lambda function
* Wating for function ended
* Checking the invocation status

![](execute-process.png#center)

## Lambda Operator

Below shows a simplified version of the custom Lambda Operator - the full version can be found [here](https://github.com/jaehyeon-kim/airflow-lambda/blob/master/dags/operators.py). Note that the associating CloudWatch Log Group name is a required argument (*awslogs_group*) while the Log Stream name is determined by a combination of execution date, qualifier and UUID. These are sent to the Lambda function in the payload. Note also that, in `_check_success_invocation()`, whether a function invocation is failed or succeeded is identified by searching *ERROR* within message of log events. I find this gives a more stable outcome than Lambda invocation response.

```python
import re, time, json, math, uuid
from datetime import datetime
from botocore import exceptions
from airflow.exceptions import AirflowException
from airflow.models import BaseOperator
from airflow.utils import apply_defaults
from airflow.contrib.hooks.aws_hook import AwsHook
from airflow.contrib.hooks.aws_logs_hook import AwsLogsHook

class LambdaOperator(BaseOperator):
    @apply_defaults
    def __init__(
        self, function_name, awslogs_group, qualifier="$LATEST", 
        payload={}, aws_conn_id=None, region_name=None, *args, **kwargs
    ):
        super(LambdaOperator, self).__init__(**kwargs)
        self.function_name = function_name
        self.qualifier = qualifier
        self.payload = payload
        # log stream is created and added to payload
        self.awslogs_group = awslogs_group
        self.awslogs_stream = "{0}/[{1}]{2}".format(
            datetime.utcnow().strftime("%Y/%m/%d"),
            self.qualifier,
            re.sub("-", "", str(uuid.uuid4())),
        )
        # lambda client and cloudwatch logs hook
        self.client = AwsHook(aws_conn_id=aws_conn_id).get_client_type("lambda")
        self.awslogs_hook = AwsLogsHook(aws_conn_id=aws_conn_id, region_name=region_name)

    def execute(self, context):        
        # invoke - wait - check
        payload = json.dumps(
            {
                **{"group_name": self.awslogs_group, "stream_name": self.awslogs_stream},
                **self.payload,
            }
        )
        invoke_opts = {
            "FunctionName": self.function_name,
            "Qualifier": self.qualifier,
            "InvocationType": "RequestResponse",
            "Payload": bytes(payload, encoding="utf8"),
        }
        try:
            resp = self.client.invoke(**invoke_opts)
            self.log.info("Lambda function invoked - StatusCode {0}".format(resp["StatusCode"]))
        except exceptions.ClientError as e:
            raise AirflowException(e.response["Error"])

        self._wait_for_function_ended()

        self._check_success_invocation()
        self.log.info("Lambda Function has been successfully invoked")

    def _wait_for_function_ended(self):
        waiter = self.client.get_waiter("function_active")
        waiter.config.max_attempts = math.ceil(
            self._get_function_timeout() / 5
        )  # poll interval - 5 seconds
        waiter.wait(FunctionName=self.function_name, Qualifier=self.qualifier)

    def _check_success_invocation(self):
        self.log.info("Lambda Function logs output")
        has_message, invocation_failed = False, False
        messages, max_trial, current_trial = [], 5, 0
        # sometimes events are not retrieved, run for 5 times if so
        while True:
            current_trial += 1
            for event in self.awslogs_hook.get_log_events(self.awslogs_group, self.awslogs_stream):
                dt = datetime.fromtimestamp(event["timestamp"] / 1000.0)
                self.log.info("[{}] {}".format(dt.isoformat(), event["message"]))
                messages.append(event["message"])
            if len(messages) > 0 or current_trial > max_trial:
                break
            time.sleep(2)
        if len(messages) == 0:
            raise AirflowException("Fails to get log events")
        for m in reversed(messages):
            if re.search("ERROR", m) != None:
                raise AirflowException("Lambda Function invocation is not successful")

    def _get_function_timeout(self):
        resp = self.client.get_function(FunctionName=self.function_name, Qualifier=self.qualifier)
        return resp["Configuration"]["Timeout"]
```

## Lambda Function

Below shows a simplified version of the Lambda function - the full version can be found [here](https://github.com/jaehyeon-kim/airflow-lambda/blob/master/cloudformation/lambda_function.py). **CustomLogManager** includes methods to create CloudWatch Log Stream and to put log events. **LambdaDecorator** manages actions before/after the function invocation as well as when an exception occurs - it's used as a decorator and modified from the [lambda_decorators](https://lambda-decorators.readthedocs.io/en/latest/) package. Before an invocation, it initializes a custom Log Stream. Log events are put to the Log Stream after an invocation or there is an exception. Note that traceback is also sent to the Log Stream when there's an exception. The Lambda function simply exits after a loop or raises an exception at random.

```python
import time, re, random, logging, traceback, boto3
from datetime import datetime
from botocore import exceptions
from io import StringIO
from functools import update_wrapper

# save logs to stream
stream = StringIO()
logger = logging.getLogger()
log_handler = logging.StreamHandler(stream)
formatter = logging.Formatter("%(levelname)-8s %(asctime)-s %(name)-12s %(message)s")
log_handler.setFormatter(formatter)
logger.addHandler(log_handler)
logger.setLevel(logging.INFO)

cwlogs = boto3.client("logs")

class CustomLogManager(object):
    # create log stream and send logs to it
    def __init__(self, event):
        self.group_name = event["group_name"]
        self.stream_name = event["stream_name"]

    def has_log_group(self):
        group_exists = True
        try:
            resp = cwlogs.describe_log_groups(logGroupNamePrefix=self.group_name)
            group_exists = len(resp["logGroups"]) > 0
        except exceptions.ClientError as e:
            logger.error(e.response["Error"]["Code"])
            group_exists = False
        return group_exists

    def create_log_stream(self):
        is_created = True
        try:
            cwlogs.create_log_stream(logGroupName=self.group_name, logStreamName=self.stream_name)
        except exceptions.ClientError as e:
            logger.error(e.response["Error"]["Code"])
            is_created = False
        return is_created

    def delete_log_stream(self):
        is_deleted = True
        try:
            cwlogs.delete_log_stream(logGroupName=self.group_name, logStreamName=self.stream_name)
        except exceptions.ClientError as e:
            # ResourceNotFoundException is ok
            codes = [
                "InvalidParameterException",
                "OperationAbortedException",
                "ServiceUnavailableException",
            ]
            if e.response["Error"]["Code"] in codes:
                logger.error(e.response["Error"]["Code"])
                is_deleted = False
        return is_deleted

    def init_log_stream(self):
        if not all([self.has_log_group(), self.delete_log_stream(), self.create_log_stream()]):
            raise Exception("fails to create log stream")
        logger.info("log stream created")

    def create_log_events(self, stream):
        fmt = "%Y-%m-%d %H:%M:%S,%f"
        log_events = []
        for m in [s for s in stream.getvalue().split("\n") if s]:
            match = re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}", m)
            dt_str = match.group() if match else datetime.utcnow().strftime(fmt)
            log_events.append(
                {"timestamp": int(datetime.strptime(dt_str, fmt).timestamp()) * 1000, "message": m}
            )
        return log_events

    def put_log_events(self, stream):
        try:
            resp = cwlogs.put_log_events(
                logGroupName=self.group_name,
                logStreamName=self.stream_name,
                logEvents=self.create_log_events(stream),
            )
            logger.info(resp)
        except exceptions.ClientError as e:
            logger.error(e)
            raise Exception("fails to put log events")

class LambdaDecorator(object):
    # keep functions to run before, after and on exception
    # modified from lambda_decorators (https://lambda-decorators.readthedocs.io/en/latest/)
    def __init__(self, handler):
        update_wrapper(self, handler)
        self.handler = handler

    def __call__(self, event, context):
        try:
            self.event = event
            self.log_manager = CustomLogManager(event)
            return self.after(self.handler(*self.before(event, context)))
        except Exception as exception:
            return self.on_exception(exception)

    def before(self, event, context):
        # remove existing logs
        stream.seek(0)
        stream.truncate(0)
        # create log stream
        self.log_manager.init_log_stream()
        logger.info("Start Request")
        return event, context

    def after(self, retval):
        logger.info("End Request")
        # send logs to stream
        self.log_manager.put_log_events(stream)
        return retval

    def on_exception(self, exception):
        logger.error(str(exception))
        # log traceback
        logger.error(traceback.format_exc())
        # send logs to stream
        self.log_manager.put_log_events(stream)
        return str(exception)

@LambdaDecorator
def lambda_handler(event, context):
    max_len = event.get("max_len", 6)
    fails_at = random.randint(0, max_len * 2)
    for i in range(max_len):
        if i != fails_at:
            logger.info("current run {0}".format(i))
        else:
            raise Exception("fails at {0}".format(i))
        time.sleep(1)
```

## Run Lambda Task

A simple demo task is created as following. It just runs the Lambda function every 30 seconds.

```python
import airflow
from airflow import DAG
from airflow.utils.dates import days_ago
from datetime import timedelta
from dags.operators import LambdaOperator

function_name = "airflow-test"

demo_dag = DAG(
    dag_id="demo-dag",
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    concurrency=1,
    schedule_interval=timedelta(seconds=30),
)

demo_task = LambdaOperator(
    task_id="demo-task",
    function_name=function_name,
    awslogs_group="/airflow/lambda/{0}".format(function_name),
    payload={"max_len": 6},
    dag=demo_dag,
)
```

The task can be tested by the following docker compose services. Note that the web server and scheduler are split into separate services although it doesn't seem to be recommended for *Local Executor* - I had an issue to launch Airflow when those are combined in ECS.

```yaml
version: "3.7"
services:
  postgres:
    image: postgres:11
    container_name: airflow-postgres
    networks:
      - airflow-net
    ports:
      - 5432:5432
    environment:
      - POSTGRES_USER=airflow
      - POSTGRES_PASSWORD=airflow
      - POSTGRES_DB=airflow
  webserver:
    image: puckel/docker-airflow:1.10.6
    container_name: webserver
    command: webserver
    networks:
      - airflow-net
    user: root # for DockerOperator
    volumes:
      - ${HOME}/.aws:/root/.aws # run as root user
      - ./requirements.txt:/requirements.txt
      - ./dags:/usr/local/airflow/dags
      - ./config/airflow.cfg:/usr/local/airflow/config/airflow.cfg
      - ./entrypoint.sh:/entrypoint.sh # override entrypoint
      - /var/run/docker.sock:/var/run/docker.sock # for DockerOperator
      - ./custom:/usr/local/airflow/custom
    ports:
      - 8080:8080
    environment:
      - AIRFLOW__CORE__EXECUTOR=LocalExecutor
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
      - AIRFLOW__CORE__LOGGING_LEVEL=INFO
      - AIRFLOW__CORE__FERNET_KEY=Gg3ELN1gITETZAbBQpLDBI1y2P0d7gHLe_7FwcDjmKc=
      - AIRFLOW__CORE__REMOTE_LOGGING=True
      - AIRFLOW__CORE__REMOTE_BASE_LOG_FOLDER=s3://airflow-lambda-logs
      - AIRFLOW__CORE__ENCRYPT_S3_LOGS=True
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=airflow
      - POSTGRES_PASSWORD=airflow
      - POSTGRES_DB=airflow
      - AWS_DEFAULT_REGION=ap-southeast-2
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "[ -f /usr/local/airflow/config/airflow-webserver.pid ]"]
      interval: 30s
      timeout: 30s
      retries: 3
  scheduler:
    image: puckel/docker-airflow:1.10.6
    container_name: scheduler
    command: scheduler
    networks:
      - airflow-net
    user: root # for DockerOperator
    volumes:
      - ${HOME}/.aws:/root/.aws # run as root user
      - ./requirements.txt:/requirements.txt
      - ./logs:/usr/local/airflow/logs
      - ./dags:/usr/local/airflow/dags
      - ./config/airflow.cfg:/usr/local/airflow/config/airflow.cfg
      - ./entrypoint.sh:/entrypoint.sh # override entrypoint
      - /var/run/docker.sock:/var/run/docker.sock # for DockerOperator
      - ./custom:/usr/local/airflow/custom
    environment:
      - AIRFLOW__CORE__EXECUTOR=LocalExecutor
      - AIRFLOW__CORE__LOAD_EXAMPLES=False
      - AIRFLOW__CORE__LOGGING_LEVEL=INFO
      - AIRFLOW__CORE__FERNET_KEY=Gg3ELN1gITETZAbBQpLDBI1y2P0d7gHLe_7FwcDjmKc=
      - AIRFLOW__CORE__REMOTE_LOGGING=True
      - AIRFLOW__CORE__REMOTE_BASE_LOG_FOLDER=s3://airflow-lambda-logs
      - AIRFLOW__CORE__ENCRYPT_S3_LOGS=True
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=airflow
      - POSTGRES_PASSWORD=airflow
      - POSTGRES_DB=airflow
      - AWS_DEFAULT_REGION=ap-southeast-2
    restart: always

networks:
  airflow-net:
    name: airflow-network
```

Below shows the demo DAG after running for a while.


![](dags.png#center)

Lambda logs (and traceback) are found for both succeeded and failed tasks.

![](log-success.png#center)


![](log-failure.png#center)
