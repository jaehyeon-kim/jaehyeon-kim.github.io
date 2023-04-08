---
title: Serverless Data Product POC Backend Part IV
date: 2017-04-17
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
  - Serverless Data Product
categories:
  - Serverless
tags: 
  - AWS
  - AWS Lambda
  - Amazon S3
  - Amazon API Gateway
  - R
  - Python
  - CloudFront
  - Route53  
  - React
authors:
  - JaehyeonKim
images: []
---

In the previous posts, it is discussed how to package/deploy a [R](https://www.r-project.org/about.html) model with [AWS Lambda](https://aws.amazon.com/lambda/details/) and to expose the Lambda function via [Amazon API Gateway](https://aws.amazon.com/api-gateway/). Main benefits of **serverless architecture** is cost-effectiveness and being hassle-free from provisioning/managing servers. While the API returns a predicted admission status value given *GRE*, *GPA* and *Rank*, there is an issue if it is served within a web application: *Cross-Origin Resource Sharing (CORS)*. This post discusses how to resolve this issue by updating API configuration and the Lambda function handler  with a simple web application. Also it is illustrated how to host the application in a serverless environment.

* Backend
    * [Packaging R for AWS Lambda - Part I](/blog/2017-04-08-serverless-data-product-1)
    * [Deploying at AWS Lambda - Part II](/blog/2017-04-11-serverless-data-product-2)
    * [Exposing via Amazon API Gateway - Part III](/blog/2017-04-13-serverless-data-product-3)
* Frontend
    * [Serving a single page application from Amazon S3 - Part IV](#) - this post

## Frontend

A simple *single page application* is created using [React](https://facebook.github.io/react/). By clicking the *Check!* button after entering the *GRE*, *GPA* and *Rank* values, information of the expected admimission status pops up in a modal. The status value is `fetch`ed from the API of the POC application that is discussed in [Part III](/blog/2017-04-13-serverless-data-product-3). The code of this application can be found [here](https://github.com/jaehyeon-kim/serverless-poc/tree/master/poc-web).

![](00-app-01.png#center)

## Update Lambda function hander

### CORS

According to [Wikipedia](https://en.wikipedia.org/wiki/Cross-origin_resource_sharing),

> Cross-origin resource sharing (CORS) is a mechanism that allows restricted resources (e.g. fonts) on a web page to be requested from another domain outside the domain from which the first resource was served. A web page may freely embed cross-origin images, stylesheets, scripts, iframes, and videos. Certain "cross-domain" requests, notably Ajax requests, however are forbidden by default by the same-origin security policy.

Here is an example from a [Stack Overflow answer](http://stackoverflow.com/questions/4850702/is-cors-a-secure-way-to-do-cross-domain-ajax-requests) why it can be important to prevent CORS.

* You go to website X and the author of website X has written an evil script which gets sent to your browser.
* That script running on your browser logs onto your bank website and does evil stuff and because it's running as you in your browser it has permission to do so.
* Therefore your bank's website needs some way to tell your browser if scripts on website X should be trusted to access pages at your bank.

The domain name of the API is `api.jaehyeon.me` so that requests fail within the application. An example of the error is shown below.


```bash
Fetch API cannot load ...
No 'Access-Control-Allow-Origin' header is present on the requested resource.
Origin 'http://localhost:9090' is therefore not allowed access. The response had HTTP status code 403.
```

### Cofigure API

API Gateway allows to enable CORS and it can be either on a resource or a method within a resource. The *GET* method is selected and *Enable CORS* is clicked after pulling down *actions*.

![](02-enable-cors-01.png#center)

Simply put, another method of *OPTIONS* is created and the following response headers are added to the *GET* and *OPTIONS* methods.

* Access-Control-Allow-Methods: Added to _OPTIONS_ only
* Access-Control-Allow-Headers: Added to _OPTIONS_ only, __X-API-Key is allowed__
* Access-Control-Allow-Origin: Added to both _GET_ and _OPTIONS_

![](02-enable-cors-02.png#center)

Here is all the steps that enables CORS in API Gateway. Note that the necessary headers are added to *200* response only, not to *400* response so that the above error can't be eliminated for *400* response unless the headers are set separately.

![](02-enable-cors-03.png#center)

After that, the API needs to be deployed again and, as can be seen in the deployment history, the latest deployment is selected as the current stage.

![](02-enable-cors-04.png#center)

### Update handler

Despite enabling CORS, it was not possilbe to resolve the issue. After some search, a way is found in a [Stack Overflow answer](http://stackoverflow.com/questions/35190615/api-gateway-cors-no-access-control-allow-origin-header). It requires to update the Lambda function handler ([handler.py](https://github.com/jaehyeon-kim/serverless-poc/blob/master/poc-logit-handler/handler.py)) that extends the 200 response with *headers* elements - one for *CORS support to work* and the other for *cookies, authorization headers with HTTPS*. The original response is added to the *body* element of the new response. Note it'd be necessary to modify the case of *400* response in order to reduce the risk of encountering the error although it is not covered here.


```python
def lambda_handler(event, context):
    try:
        gre = event["gre"]
        gpa = event["gpa"]
        rnk = event["rank"]        
        can_be_admitted = pred_admit(gre, gpa, rnk)
        res = {
            "httpStatus": 200,
            "headers": {
                # Required for CORS support to work
                "Access-Control-Allow-Origin" : "*",
                # Required for cookies, authorization headers with HTTPS 
                "Access-Control-Allow-Credentials" : True
            },
            "body": {"result": can_be_admitted}
        }
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

The updated handler is packaged again and copied to S3.


```bash
# pull git repo
cd serverless-poc/
git pull origin master

# copy handler.py and create admission.zip
cd ..
export HANDLER=handler

cp -v serverless-poc/poc-logit-handler/*.py $HOME/$HANDLER
cd $HOME/$HANDLER
zip -r9 $HOME/admission.zip *

# copy to S3
aws s3 cp $HOME/admission.zip s3://serverless-poc-handlers
```

The AWS web console doesn't have an option to update a Lambda function where the deployment package is in S3 so that [aws cli](http://docs.aws.amazon.com/cli/latest/reference/lambda/update-function-code.html) is used instead.


```bash
#http://docs.aws.amazon.com/cli/latest/reference/lambda/update-function-code.html
aws lambda update-function-code --function-name ServerlessPOCAdmission \
	--s3-bucket serverless-poc-handlers --s3-key admission.zip
```

The test result shown below indicates the updated handler is executed correctly.

![](01-update-lambda.png#center)

It can also be checked by the API and now the API can be served in a web application.


```r
# updated response
#curl -H 'x-api-key:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
#    'https://api.jaehyeon.me/poc/admit?gre=800&gpa=4&rank=1'
r <- GET("https://api.jaehyeon.me/poc/admit",
         add_headers(`x-api-key` = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'),
         query = list(gre = 800, gpa = 4, rank = 1))
status_code(r)
[1] 200

content(r)
$body
$body$result
[1] TRUE

$headers
$headers$`Access-Control-Allow-Origin`
[1] "*"

$headers$`Access-Control-Allow-Credentials`
[1] TRUE

$httpStatus
[1] 200
```

## Hosting

Amazon S3 is one of the popular ways to store static web contents and it can be used as a way to host a static web site. The React application can be hosted on S3 as the backend logic of calling the API is bundled and accessible. 2 ways are illustrated in this section. The former is via the *Static website hosting* property of [Amazon S3 Buckets](http://docs.aws.amazon.com/AmazonS3/latest/dev/HowDoIWebsiteConfiguration.html) while the latter is through [Amazon CloudFront](https://aws.amazon.com/cloudfront/), which is a content delivery network (CDN) service. Note that only *HTTP* is avaialble if the application is hosted without CloudFront.

Separate S3 buckets are created to store the application as shown below.

* `poc.jaehyeon.me` - For hosting _Static website hosting_ property
* `web.jaehyeon.me` - For hosting through *CloudFront*

In AWS console, two folders are created: *app* and *css*. Then the [application files](https://github.com/jaehyeon-kim/serverless-poc/tree/master/poc-web/dist) are saved to each of the buckets as following.


```bash
app
    bundle.js
css
    bootstrap.css
    style.css
index.html
```

### Static website hosting

First *read-access* is given to all objects in the bucket (*poc.jaehyeon.me*). It is set in *Bucket Policy* of the permissions tab - *Policy* is discussed in [Part II](/blog/2017-04-11-serverless-data-product-2).

![](03-s3-setup-02.png#center)

Then, in the properties tab, *static website hosting* is enabled where *index.html* is set to be rendered for both the default and error document. Now it is possible to have access to the application by the *endpoint*.

![](03-s3-setup-03.png#center)

In order to replace the *endpoint* with a custom domain name, a [Canonical name (CNAME) record](https://en.wikipedia.org/wiki/CNAME_record) is created in [Amazon Route 53](https://aws.amazon.com/route53/). Note that the CNAME record (*poc.jaehyeon.me*) has to be the same to the bucket name. `s3-website-us-east-1.amazonaws.com.` is entered in *Value*, which is used to define the host name as an alias for the Amazon S3 bucket. Note the period at the end is necessary as it signifies the DNS root and, if it is not specified, a DNS resolver could append it's default domain to the domain you provided. (See [Customizing Amazon S3 URLs with CNAMEs](http://docs.aws.amazon.com/AmazonS3/latest/dev/VirtualHosting.html#VirtualHostingCustomURLs) for further details.) Now the application can be accessed using [http://poc.jaehyeon.me](http://poc.jaehyeon.me).

![](04-route53.png#center)

### CloudFront

It is possible to host the application using *Amazon CloudFront* which is a global content delivery network (CDN) service that accelerates delivery of websites, APIs, video content or other web assets. 

*Web* is taken as the delivery method.

![](05-cloudfront-01.png#center)

The S3 bucket (*web.jaehyeon.me*) is selected as the origin domain name. Note, unlike relying on the *static website hosting* property where all objects in the bucket are given *read-access*, in this way, access to the bucket is *restricted* only to CloudFront with a newly created identity. The updated bucket policy is shown below. (See [Using an Origin Access Identity to Restrict Access to Your Amazon S3 Content](http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html) for further details.)


```json
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity xxxxxxxxxxxxxx"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::web.jaehyeon.me/*"
        }
    ]
}
```

![](05-cloudfront-02.png#center)

In default cache behavior settings, *Redirect HTTP to HTTPS* is selected for the viewer protocol policy. All other options are left untouched - they are not shown.

![](05-cloudfront-03.png#center)

In distribution settings, a CNAME record (*web.jaehyeon.me*) is created to be the same to the bucket name. The custom SSL certificate that is obtained from [AWS Certificate Manager](https://aws.amazon.com/certificate-manager/) is chosen rather than the default CloudFront certificate - see [Part III](/blog/2017-04-13-serverless-data-product-3). Finally it is selected to support only clients that support server name indication (SNI). Note all the other options are left untouched - they are not shown.

![](05-cloudfront-04.png#center)

Once the distribution is created, the distribution's CloudFront domain name is created and it is possible to use it to create a custom domain.

![](05-cloudfront-06.png#center)

In Route 53, a new record set is created and `web.jaehyeon.me` is entered in the name field, followed by selecting *A - IPv4 address* as the type. *Alias* is set to be yes and the *distribution domain name* is entered as the alias target.

![](05-cloudfront-07.png#center)

Once it is ready, the application can be accessed using either [http://web.jaehyeon.me](http://web.jaehyeon.me) or [https://web.jaehyeon.me](https://web.jaehyeon.me) where HTTP is redirected to HTTPS.

## Final thoughts

This is the end of the *Serverless Data Product POC* series. I consider a good amount of information is shared in relation to *serverless data product development* and I hope you find the posts useful. For demonstration, I used the AWS web console but it wouldn't be suitable in a production environment as it involves a lot of manual jobs as well as those jobs are not reproducible. There are a number of notable frameworks that help develop applications in serverless environment: [Serverless Framework](https://serverless.com/), [Apex](http://apex.run/), [Chalice](https://github.com/awslabs/chalice) and [Zappa](https://github.com/Miserlou/Zappa). I hope there will be another series that cover one of these frameworks. 


