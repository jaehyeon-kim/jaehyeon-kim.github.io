---
title: Serverless Data Product POC Backend Part 3 - Exposing R ML Model via APIG
date: 2017-04-13
draft: false
featured: false
comment: true
toc: true
series:
  - Serverless Data Product
categories:
  - Development
tags: 
  - AWS
  - AWS Lambda
  - Amazon API Gateway
  - Python
  - R
description: Expose an R machine learning model packaged in AWS Lambda through Amazon API Gateway, giving the model a callable HTTP endpoint on AWS.
---

> **Status, September 2026.** The Amazon API Gateway console has been redesigned since these screenshots were taken, so the Actions menu and the method configuration pages below no longer match it. Resources, methods and deployments are now created from buttons on the API pages themselves.

In [Part I](/blog/2017-04-08-serverless-data-product-1) of this series, R and necessary libraries/packages together with a Lambda function handler are packaged and saved to [Amazon S3](https://aws.amazon.com/s3/). Then, in [Part II](/blog/2017-04-11-serverless-data-product-2), the package is deployed at [AWS Lambda](https://aws.amazon.com/lambda/) after creating and assigning a role to the Lambda function. Although the Lambda function can be called via the Invoke API, it'll be much more useful if the function can be called as a web service (or API). In this post, it is discussed how to expose the Lambda function via [Amazon API Gateway](https://aws.amazon.com/api-gateway/). After creating an API by integrating the Lambda function, it is protected with an API key. Finally a custom domain name is used as an alternative URL of the API.

* Backend
    * [Part I - Packaging R ML Model for Lambda](/blog/2017-04-08-serverless-data-product-1)
    * [Part II - Deploying R ML Model via Lambda](/blog/2017-04-11-serverless-data-product-2)
    * [Part III - Exposing R ML Model via APIG](#) - this post
* Frontend
    * [Part IV - Serving R ML Model via S3](/blog/2017-04-17-serverless-data-product-4)

[**EDIT 2017-04-17**] The Lambda function hander (*handler.py*) has been modified to resolve an issue of *Cross-Origin Resource Sharing (CORS)*. See [Part IV](/blog/2017-04-17-serverless-data-product-4) for further details.

## Create API

It can be started by clicking the *Get Started* button if there's no existing API or the *Create API* button if there is an existing one.

![Amazon API Gateway landing page with the Get Started button beside the console list of APIs and the Create API button](A01-create-api-01.png#center "Starting point for creating an API")

Amazon API Gageway provides several options to create an API. *New API* is selected for the API of the POC application and the name of the API (*ServerlessPOC*) and description are entered.

![Create new API form with New API selected, API name ServerlessPOC and the description Serverless POC api](A01-create-api-02.png#center "Naming the new API")

### Create resource and method

According to [Thoughts on RESTful API Design](https://restful-api-design.readthedocs.io/en/latest/index.html), 

> *In any RESTful API, a resource is an* __object__ *with a type, associated data, relationships to other resources, and a set of* __methods__ *that operate on it.*

A resource is represented in the URL and, if the resource is named as *admit*, the resource URL becomes `/admit` (eg `http://example.com/admit`) and a client application can make a request to the URL. 

As can be seen below, the Lambda function hander requires that the event object has 3 elements: *gre*, *gpa* and *rank*.


```python
def lambda_handler(event, context):
    try:
        gre = event["gre"]
        gpa = event["gpa"]
        rnk = event["rank"]        
        can_be_admitted = pred_admit(gre, gpa, rnk)
        res = {"result": can_be_admitted}
        return res
    except Exception as e:
        logging.error('Payload: {0}'.format(event))
        logging.error('Error: {0}'.format(e.message))        
        err = {
            'errorType': type(e).__name__, 
            'httpStatus': 400, 
            'request_id': context.aws_request_id, 
            'message': e.message.replace('\n', ' ')
            }
        raise Exception(json.dumps(err))
```

In Amazon API Gateway, there are two ways to create the resource for the Lambda function of the POC application.

**Query string**

* It is possible to create only a resource and the 3 elements can be added in query string. Then a request with the 3 elements can be made to `/admit?gre=800&gpa=4&rank=1`.


```bash
/
  /admit
```

**Proxy resource**

* Proxy resources can be created by covering path parameters by brackets. Then the equivalent request can be made to `/800/4/1/admit`.


```bash
/
  /{gre}
    /{gpa}
      /{rank}
        /admit
```

For the API of the POC application, the way with query string is used. First it is necessary to create a resource.

![API Gateway Resources view with the Actions menu open and Create Resource underlined in red](A02-create-resource-01.png#center "Creating a resource from the Actions menu")

Then the resource is named as *Admit*.

![New Child Resource form with Resource Name set to Admit and Resource Path set to admit](A02-create-resource-02.png#center "Naming the new resource")

After creating the resource, it is necessary to create one or more [HTTP methods](https://restful-api-design.readthedocs.io/en/latest/methods.html) on it. 

![Actions menu open on the admit resource with Create Method underlined in red](A03-create-method-01.png#center "Adding a method to the admit resource")

Only the *GET* method is created for this API.

![Method picker under the admit resource with GET chosen in the drop-down](A03-create-method-02.png#center "Only the GET method is created")

Now it is time to integrate the method with the Lambda function. *Lambda Function* is selected as the interation type and *ServerlessPOCAdmission* is selected - note that the region where the Lambda function is deployed should be selected first.

![GET setup page with integration type Lambda Function, region us-east-1 and function ServerlessPOCAdmission](A03-create-method-03.png#center "Integrating the GET method with the Lambda function")

### Configure method execution

The lifecycle of a Lambda function is shown below. A Lambda function is called after *Method Request* and *Integration Request*. Also there are two steps until the result is returned back to the client: *Method Response* and *Integration Response*.

![Method execution view, the client calling Method Request then Integration Request into the Lambda function, and returning through Integration Response and Method Response](A04-00-method-execution.png#center "Lifecycle of a request through the method")

#### Method request

As discussed earlier, only a single resource is created so that a request is made with query string. Therefore the 3 event elements (*gre*, *gpa* and *rank*) should be created in *URL Query String Parameters*. Note that *API Key Required* is set to be *false* and it is necessary to change it to be *true* if the API needs to be protected with an API key - it'll be discussed further below. The other sections (*HTTP Request Header*, *Request Body*, ...) are not touched for this API.

![Method Request page with authorization NONE, API Key Required false, and gpa, gre and rank listed as URL query string parameters](A04-01-method-request.png#center "Method request with the three query string parameters")

#### Integration request

It is possible to update the target backend or to modify data from the incoming request. It is not necessary to change the target backend as it is already set appropriately.

![Integration Request page with integration type Lambda Function, region us-east-1 and the target function already set](A04-02-integration-request-01.png#center "Integration request pointing at the Lambda function")

Among the 3 event elements (*gre*, *gpa* and *rank*), *rank* is a factor or, at least, it should be a string while the others can be either numbers or *numeric* strings. Therefore the Lambda function will complain if a numeric *rank* value is included in a query string (eg `rank=1`). Although it is possible to modify the Lambda function handler, an easier way is to modify data from the incoming request. 

In *Body Mapping Templates*, the recommended option of *When there are no templates defined (recommended)* is selected in request body passthrough and *application/json* is added to *Content-Type*. Data from incoming request can be updated in the template that is shown by clicking the added content type (*application/json*). As shown below, *rank* is changed into a string before the Lambda function is called. Note [Velocity Template Engine](https://velocity.apache.org/) is used in Amazon API Gateway.


```js
{
    "gre": $input.params('gre'),
    "gpa": $input.params('gpa'),
    "rank": "$input.params('rank')"
}
```

![Body mapping template for application/json, mapping gre and gpa as numbers and rank in quotes as a string, underlined in red](A04-02-integration-request-02.png#center "Mapping template that turns rank into a string")

#### Method response

If a request is successful, the HTTP status code of 200 is returned. As can be seen in the code of the Lambda function handler above, the status code of 400 is planned to be returned if there is an error. Therefore it is necessary to add 400 response so that it is mapped in *Integration Response*.

![Method Response page listing HTTP status 200 and the newly added 400](A04-04-method-response.png#center "Method response with a 400 status added")

#### Integration response

The output of a response can be mapped in *Body Mapping Templates*. The body of the default 200 response doesn't need modification as the Lambda function already returns a JSON string -  `{"result": true}` or `{"result": false}`. If the function returns only *True* or *False*, however, the response can be modified as shown below. (Note that this is only for illustration and nothing is added to the content type.)


```js
{
    "result": $input.path('$')
}
```

![Integration Response for status 200 with no Lambda error regex and a body template returning result as the Lambda output](A04-03-integration-response-01.png#center "Integration response for a successful call")

For 400 response, the HTTP status is identified by `.*"httpStatus":400.*` and the body is mapped as following.


```js
#set ($errorMessageObj = $util.parseJson($input.path('$.errorMessage')))
{
  "code" : $errorMessageObj.httpStatus,
  "message" : "$errorMessageObj.message",
  "request-id" : "$errorMessageObj.request_id"
}
```

![Integration Response for status 400, matched by a Lambda error regex on httpStatus 400, with a template returning code, message and request-id](A04-03-integration-response-02.png#center "Integration response that maps the error into JSON")

## Test API

The API can be tested by adding the 3 elements in query string. As expected, the response returns `{"result": true}` with the HTTP status code of 200.

![Method test with gre 800, gpa 4 and rank 1, returning status 200, latency 330 ms and a response body of result true](A05-test-01.png#center "Successful test call through the console")

In order to test 400 response, the value of *gre* is set to be a string (gre). The status code of 400 is returned as expected but it fails to parse the message of the error into JSON. It is necessary to modify the message, referring to [Error Handling Patterns in Amazon API Gateway and AWS Lambda](https://aws.amazon.com/blogs/compute/error-handling-patterns-in-amazon-api-gateway-and-aws-lambda/).


```python
        ...
        
        err = {
            'errorType': type(e).__name__, 
            'httpStatus': 400, 
            'request_id': context.aws_request_id, 
            'message': e.message.replace('\n', ' ')
            }
        ...
```

![Method test with gre set to the string gre, returning status 400 and a message saying the request body could not be parsed into JSON](A05-test-02.png#center "Failing test call before the error message is tidied")

## Deploy API

Once testing is done, it is ready to deploy the API.

![Actions menu open on the GET method with Deploy API underlined in red](A06-deploy-01.png#center "Deploying the API from the Actions menu")

It is possible to create a new stage by selecting *[New Stage]* or to update an existing one by selecting its name in deployment stage. Although it is recommended to create at least 2 stages (eg development and production stage), only a singe production stage is created for the POC application.

![Deploy API dialog with New Stage selected, stage name prod and a deployment description naming the Lambda function](A06-deploy-02.png#center "Creating the production stage")

Once created, the invoke URL can be found when the relevant method (*GET*) is clicked. The default root URL is of the following format.


```bash
https://api-id.execute-api.region.amazonaws.com/stage
```

![Stage view for prod GET admit, showing the invoke URL with the API id blacked out and settings inherited from the stage](A06-deploy-03.png#center "Invoke URL of the deployed method")

The API has been deployed successfully and it is possible to make a request using *curl* and R's *httr* package as following - note the API ID is hidden.


```r
## no API Key
#curl 'https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/admit?gre=800&gpa=4&rank=1'
r <- GET("https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/admit",
         query = list(gre = 800, gpa = 4, rank = 1))

status_code(r)
[1] 200

content(r)
$result
[1] TRUE
```


## Protecting by API key

### Enable API key

It is on individual methods whether to enable an API key or not. In order to enable an API key, select the GET method in the resources section and change *API Key Required* to true in *Method Request*. Note that *the API has to be deployed again in order to have the change in effect*.

![Method Request settings with API Key Required changed to true and underlined in red](K01-make-key-required.png#center "Requiring an API key on the GET method")

### Create usage plan

A usage plan enforces *Throttling (Rate and Burst)* and *Quota* of an API and it associates API stages and keys. Since its launch on August 11, 2016, it is enabled in a region where API Gateway is used for the first time. The meaning of the throttling and quota values are as following. 

* __Rate__ is the rate at which tokens are added to the Token Bucket and this value indicates the average number of requests per second over an extended period of time.
* __Burst__ is the capacity of the Token Bucket.
* __Quota__ is the total number of requests in a given time period.

For further details, see [Manage API Request Throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html) and [Token Bucket vs Leaky Bucket](https://www.youtube.com/watch?v=ac23ul88jLU).

A usage plan named *ServerlessPOC* is created where the rate, burst and quote are 10 requests per second, 20 requests and 500 requests per day respectively. 

![Create Usage Plan form named ServerlessPOC, with throttling at 10 requests per second, a burst of 20 and a quota of 500 requests per day](K02-usage-plan-01.png#center "Usage plan with throttling and quota limits")

Then the production stage (*prod*) of *ServerlessPOC* API is added to the plan.

![Usage plan details listing rate 10 per second, burst 20, quota 500 per day, and the ServerlessPOC prod stage in associated API stages](K02-usage-plan-02.png#center "The prod stage added to the usage plan")

### Create API key

An API key can be created in *API Keys* section of the Console. The key is named as *ServerlessPOC* and it is set to be auto-generated.

![Create API Key form named ServerlessPOC with Auto Generate selected, and Create API key underlined in the Actions menu](K03-api-key-01.png#center "Creating an auto-generated API key")

The usage plan created earlier is added to the API key.

![API key details with the id blacked out, status Enabled, and the ServerlessPOC usage plan on the prod stage listed below](K03-api-key-02.png#center "The usage plan added to the API key")

Now the API has been protected with an API key and it is possible to make a request using *curl* and R's *httr* package as following. Note that the API key should be added with the key named *x-api-key*. Without the API key in the header, the request returns *403 Forbidden* error. (Note also tick marks rather than single quotations in `GET()`)


```r
## API Key
# 403 Forbidden without api key
#curl -H 'x-api-key:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
#    'https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/admit?gre=800&gpa=4&rank=1'
r <- GET("https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/admit",
         add_headers(`x-api-key` = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
         query = list(gre = 800, gpa = 4, rank = 1))

status_code(r)
[1] 200

content(r)
$result
[1] TRUE
```

## Using custom domain name

The invoke URL generated by API Gateway can be difficult to recall and not user-friendly. In order to have a more inituitive URL for the API, it is possible to set up a custom domain name as the API's host name and choose a base path to present an alternative URL of the API. For example, instead of using `xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`, it is possible to use `api.jaehyeon.me`.

The prerequisites for using a custom dome name for an API are

* Domain name
* ACM Certificate (us-east-1 only)

I registered a domain name (`jaehyeon.me`) in [Amazon Route 53](https://aws.amazon.com/route53/) and requested ACM Certificate through [AWS Certificate Manager](https://aws.amazon.com/certificate-manager/). It was quite quick to me and it took less than 1 day. See the following articles for how-to.

  * [Registering Domain Names Using Amazon Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/registrar.html)
  * [Requesting and Managing ACM Certificates](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm.html)

The domain name of the API is set to be `api.jaehyeon.me` and the approved ACM Certificate is selected. In *Base Path Mappings*, *poc* is added to the path and the production stage of the ServerlessPOC API is selected as the destination. In this way, it is possible to change the resource URL as following.


```bash
# default resource URL
https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/admit

# custom resource URL
https://api.jaehyeon.me/poc/admit
```

![Custom domain name api.jaehyeon.me with an ACM certificate selected, and a base path mapping from poc to the ServerlessPOC prod stage](D01-create-01.png#center "Custom domain name and base path mapping")

When clicking the *save* button above, a *distribution domain name* is assigned by [Amazon CloudFront](https://aws.amazon.com/cloudfront/). This step takes up to 40 minutes to complete and, in the meantime, A-record alias for the API domain name is set up so that it can be mapped to the associated *distribution domain name*.

![Custom domain name page after saving, showing an assigned cloudfront.net distribution domain name and the ACM certificate still initialising](D01-create-02.png#center "CloudFront distribution domain name assigned to the custom domain")

In Route 53, a new record set is created and `api.jaehyeon.me` is entered in the name field, followed by selecting *A - IPv4 address* as the type. *Alias* is set to be yes and the *distribution domain name* is entered as the alias target.

![Route 53 Create Record Set panel with name api, type A IPv4 address, alias set to yes and the cloudfront.net distribution as the alias target](D02-map.png#center "Route 53 alias record pointing at the distribution")

Once it is ready, the custom domain name can be used as an alternative domain name of the API and it is possible to make a request using *curl* and R's *httr* package as following.


```r
## custom domain name
#curl -H 'x-api-key:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
#    'https://api.jaehyeon.me/poc/admit?gre=800&gpa=4&rank=1'
r <- GET("https://api.jaehyeon.me/poc/admit",
         add_headers(`x-api-key` = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
         query = list(gre = 800, gpa = 4, rank = 1))

status_code(r)
[1] 200

content(r)
$result
[1] TRUE
```

That's it! This is all that I was planning to discuss with regard to exposing a Lambda function backed by a prediction model in R via an API. I hope this series of posts are useful to *productionize* your analysis.
