---
title: AWS Local Development with LocalStack
date: 2019-07-20
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
  - Engineering
tags: 
  - LocalStack
  - AWS
  - Docker
  - Docker Compose
  - AWS Lambda
  - S3
  - SQS
  - Python
  - Flask
  - Flask-RestPlus
authors:
  - JaehyeonKim
images: []
---

[LocalStack](https://github.com/localstack/localstack) provides an easy-to-use test/mocking framework for developing AWS applications. In this post, a web service will be used for demonstrating how to utilize LocalStack for development.

Specifically a simple web service built with [Flask-RestPlus](https://flask-restplus.readthedocs.io/en/stable/) is used. It supports simple CRUD operations against a database table. It is set that SQS and Lambda are used for creating and updating a record. When a _POST_ or _PUT_ request is made, the service sends a message to a SQS queue and directly returns _204_ reponse. Once a message is received, a Lambda function is invoked and a relevant database operation is performed. 

The source of this post can be found [here](https://github.com/jaehyeon-kim/play-localstack).

## Web Service

As usual, the _GET requests_ returns all records or a single record when an ID is provided as a path parameter. When an ID is not specified, it'll create a new record (_POST_). Otherwise it'll update an existing record (_PUT_). Note that both the _POST_ and _PUT_ method send a message and directly returns _204_ response - the source can be found [here](https://github.com/jaehyeon-kim/play-localstack/blob/master/api/namespace/records.py).

```python
ns = Namespace("records")

@ns.route("/")
class Records(Resource):
    parser = ns.parser()
    parser.add_argument("message", type=str, required=True)

    def get(self):
        """
        Get all records
        """        
        conn = conn_db()
        cur = conn.cursor(real_dict_cursor=True)
        cur.execute(
            """
            SELECT * FROM records ORDER BY created_on DESC
            """)

        records = cur.fetchall()
        return jsonify(records)
    
    @ns.expect(parser)
    def post(self):
        """
        Create a record via queue
        """
        try:
            body = {
                "id": None,
                "message": self.parser.parse_args()["message"]
            }
            send_message(flask.current_app.config["QUEUE_NAME"], json.dumps(body))
            return "", 204
        except Exception as e:
            return "", 500


@ns.route("/<string:id>")
class Record(Resource):
    parser = ns.parser()
    parser.add_argument("message", type=str, required=True)

    def get(self, id):
        """
        Get a record given id
        """        
        record = Record.get_record(id)
        if record is None:
            return {"message": "No record"}, 404
        return jsonify(record)

    @ns.expect(parser)
    def put(self, id):
        """
        Update a record via queue
        """
        record = Record.get_record(id)
        if record is None:
            return {"message": "No record"}, 404        

        try:
            message = {
                "id": record["id"],
                "message": self.parser.parse_args()["message"]
            }
            send_message(flask.current_app.config["QUEUE_NAME"], json.dumps(message))
            return "", 204
        except Exception as e:
            return "", 500

    @staticmethod
    def get_record(id):
        conn = conn_db()
        cur = conn.cursor(real_dict_cursor=True)
        cur.execute(
            """
            SELECT * FROM records WHERE id = %(id)s
            """, {"id": id})

        return cur.fetchone()
```

## Lambda

The SQS queue that messages are sent by the web service is an event source of the following [lambda function](https://github.com/jaehyeon-kim/play-localstack/blob/master/init/lambda_package/lambda_function.py). It polls the queue and processes messages as shown below.

```python
import os
import logging
import json
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

try:
    conn = psycopg2.connect(os.environ["DB_CONNECT"], connect_timeout=5)
except psycopg2.Error as e:
    logger.error(e)
    sys.exit()

logger.info("SUCCESS: Connection to DB")

def lambda_handler(event, context):
    for r in event["Records"]:
        body = json.loads(r["body"])
        logger.info("Body: {0}".format(body))
        with conn.cursor() as cur:
            if body["id"] is None:
                cur.execute(
                    """
                    INSERT INTO records (message) VALUES (%(message)s)
                    """, {k:v for k,v in body.items() if v is not None})
            else:
                cur.execute(
                    """
                    UPDATE records
                       SET message = %(message)s
                     WHERE id = %(id)s
                    """, body)
    conn.commit()

    logger.info("SUCCESS: Processing {0} records".format(len(event["Records"])))
```

## Database

As RDS is not yet supported by LocalStack, a postgres db is created with Docker. The web service will do CRUD operations against the table named as _records_. The [initialization SQL script](https://github.com/jaehyeon-kim/play-localstack/blob/master/init/db/run.sql) is shown below.

```sql
CREATE DATABASE testdb;
\connect testdb;

CREATE SCHEMA testschema;
GRANT ALL ON SCHEMA testschema TO testuser;

-- change search_path on a connection-level
SET search_path TO testschema;

-- change search_path on a database-level
ALTER database "testdb" SET search_path TO testschema;

CREATE TABLE testschema.records (
	id serial NOT NULL,
	message varchar(30) NOT NULL,
	created_on timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT records_pkey PRIMARY KEY (id)
);

INSERT INTO testschema.records (message) 
VALUES ('foo'), ('bar'), ('baz');
```

## Launch Services

Below shows the [docker-compose file](https://github.com/jaehyeon-kim/play-localstack/blob/master/docker-compose.yml) that creates local AWS services and postgres database.

```yaml
version: '3.7'
services:
  localstack:
    image: localstack/localstack
    ports:
      - '4563-4584:4563-4584'
      - '8080:8080'
    privileged: true
    environment:
      - SERVICES=s3,sqs,lambda
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
      - DEFAULT_REGION=ap-southeast-2
      - LAMBDA_EXECUTOR=docker-reuse
      - LAMBDA_REMOTE_DOCKER=false
      - LAMBDA_DOCKER_NETWORK=play-localstack_default
      - AWS_ACCESS_KEY_ID=foobar
      - AWS_SECRET_ACCESS_KEY=foobar
      - AWS_DEFAULT_REGION=ap-southeast-2
      - DB_CONNECT='postgresql://testuser:testpass@postgres:5432/testdb'
      - TEST_QUEUE=test-queue
      - TEST_LAMBDA=test-lambda
    volumes:
      - ./init/create-resources.sh:/docker-entrypoint-initaws.d/create-resources.sh
      - ./init/lambda_package:/tmp/lambda_package   
      # - './.localstack:/tmp/localstack'
      - '/var/run/docker.sock:/var/run/docker.sock'
  postgres:
    image: postgres
    ports:
      - 5432:5432
    volumes:
      - ./init/db:/docker-entrypoint-initdb.d
    depends_on:
      - localstack
    environment:
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD=testpass
```

For LocalStack, it's easier to illustrate by the environment variables.

* SERVICES - _S3, SQS and Lambda_ services are selected
* DEFAULT_REGION - Local AWS resources will be created in _ap-southeast-2_ by default
* LAMBDA_EXECUTOR - By selecting _docker-reuse_, Lambda function will be invoked by another container (based on [lambci/lambda](https://github.com/lambci/lambci) image). Once a container is created, it'll be reused. Note that, in order to invoke a Lambda function in a separate Docker container, it should run in privileged mode (**privileged: true**)
* LAMBDA_REMOTE_DOCKER - It is set to _false_ so that a Lambda function package can be added from a local path instead of a zip file.
* LAMBDA_DOCKER_NETWORK - Although the Lambda function is invoked in a separate container, it should be able to discover the database service (_postgres_). By default, Docker Compose creates a network (`<parent-folder>_default`) and, specifying the network name, the Lambda function can connect to the database with the DNS set by *DB_CONNECT*

Actual AWS resources is created by [*create-resources.sh*](https://github.com/jaehyeon-kim/play-localstack/blob/master/init/create-resources.sh), which will be executed at startup. A SQS queue and Lambda function are created and the queue is mapped to be an event source of the Lambda function.

```bash
#!/bin/bash

echo "Creating $TEST_QUEUE and $TEST_LAMBDA"

aws --endpoint-url=http://localhost:4576 sqs create-queue \
    --queue-name $TEST_QUEUE

aws --endpoint-url=http://localhost:4574 lambda create-function \
    --function-name $TEST_LAMBDA \
    --code S3Bucket="__local__",S3Key="/tmp/lambda_package" \
    --runtime python3.6 \
    --environment Variables="{DB_CONNECT=$DB_CONNECT}" \
    --role arn:aws:lambda:ap-southeast-2:000000000000:function:$TEST_LAMBDA \
    --handler lambda_function.lambda_handler \

aws --endpoint-url=http://localhost:4574 lambda create-event-source-mapping \
    --function-name $TEST_LAMBDA \
    --event-source-arn arn:aws:sqs:elasticmq:000000000000:$TEST_QUEUE
```

The services can be launched as following.

```bash
docker-compose up -d
```

## Test Web Service

Before testing the web service, it can be shown how the SQS and Lambda work by sending a message as following.

```sh
aws --endpoint-url http://localhost:4576 sqs send-message \
    --queue-url http://localhost:4576/queue/test-queue \
    --message-body '{"id": null, "message": "test"}'
```

As shown in the image below, LocalStack invokes the Lambda function in a separate Docker container.

![](send-message.png#center)

The web service can be started as following.

```sh
FLASK_APP=api FLASK_ENV=development flask run
```

Using [HttPie](https://httpie.org/), the record created just before can be checked as following.

```bash
http http://localhost:5000/api/records/4
```

```json
{
    "created_on": "2019-07-20T04:26:33.048841+00:00",
    "id": 4,
    "message": "test"
}
```

For updating it,

```bash
echo '{"message": "test put"}' | \
    http PUT http://localhost:5000/api/records/4

http http://localhost:5000/api/records/4
```

```json
{
    "created_on": "2019-07-20T04:26:33.048841+00:00",
    "id": 4,
    "message": "test put"
}
```