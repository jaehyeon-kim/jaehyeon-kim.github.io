---
title: Serverless Data Product POC Backend Part I
date: 2017-04-08
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
  - Amazon API Gateway
  - R
  - Python
authors:
  - JaehyeonKim
images: []
---

Let say you've got a prediction model built in R and you'd like to *productionize* it, for example, by serving it in a web application. One way is exposing the model through an API that returns the predicted result as a web service. However there are many issues. Firstly R is not a language for API development although there may be some ways - eg the [plumber](https://github.com/trestletech/plumber) package. More importantly developing an API is not the end of the story as the API can't be served in a production system if it is not *deployed/managed/upgraded/patched/...* appropriately in a server or if it is not *scalable*, *protected via authentication/authorization* and so on. Therefore it requires quite a vast range of skill sets that cover both development and DevOps (engineering). 

A developer can be relieved from the overwhelming DevOps stuff if his/her model is deployed in a **serverless** environment that is provided by cloud computing companies - Amazon Web Service, Microsoft Azure, Google Cloud Platform and IBM OpenWhisk. They provide *FaaS* ([Function as a Service](https://en.wikipedia.org/wiki/Function_as_a_Service)) and, simply put, it allows to run code on demand without provisioning or managing servers. Furthermore an application can be developed/managed in a more efficient way if the workflow is streamlined by **events**. Let say the model has to be updated periodically. It requires to save new raw data into a place, to export it to a database, to manipulate and save it back to another place for modelling... This kind of workflow can be efficiently managed by events where a function is configured to subscribe a specific event and its code is run accordingly. In this regards, I find there is a huge potential for **serverless** **event-driven** architecture in data product development.

This is the first post of *Serverless Data Product POC* series and I'm planning to introduce a data product in a **serverless** environment. For the backend, a simple logistic regression model is packaged and tested for [AWS Lambda](https://aws.amazon.com/lambda/) - R is not included in [Lambda runtime](http://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html) so that it is packaged and run via the Python [rpy2](https://pypi.python.org/pypi/rpy2) package. Then the model is deployed at [AWS Lambda](https://aws.amazon.com/lambda/) and the Lambda function is exposed via [Amazon API Gateway](https://aws.amazon.com/api-gateway/). For the frontend, a simple single page application is served from [Amazon S3](https://aws.amazon.com/s3/).

* Backend
    * [Packaging R for AWS Lambda - Part I](#) - this post
    * [Deploying at AWS Lambda - Part II](/blog/2017-04-11-serverless-data-product-2)
    * [Exposing via Amazon API Gateway - Part III](/blog/2017-04-13-serverless-data-product-3)
* Frontend
    * [Serving a single page application from Amazon S3 - Part IV](/blog/2017-04-17-serverless-data-product-4)

[**EDIT 2017-04-11**] Deploying at AWS Lambda and exposing via API Gateway are split into 2 posts (Part II and III).

[**EDIT 2017-04-17**] The Lambda function hander (*handler.py*) has been modified to resolve an issue of *Cross-Origin Resource Sharing (CORS)*. See [Part IV](/blog/2017-04-17-serverless-data-product-4) for further details.

## Model

The data is from the [LOGIT REGRESSION - R DATA ANALYSIS EXAMPLES](http://stats.idre.ucla.edu/r/dae/logit-regression/) of UCLA: Statistical Consulting Group. It is hypothetical data about graduate school admission and has 3 featues (_gre_, _gpa_, _rank_) and 1 binary response (_admit_).


```r
data <- read.csv("http://www.ats.ucla.edu/stat/data/binary.csv")
data$rank <- as.factor(data$rank)
summary(data)
```

```bash
##      admit             gre             gpa        rank   
##  Min.   :0.0000   Min.   :220.0   Min.   :2.260   1: 61  
##  1st Qu.:0.0000   1st Qu.:520.0   1st Qu.:3.130   2:151  
##  Median :0.0000   Median :580.0   Median :3.395   3:121  
##  Mean   :0.3175   Mean   :587.7   Mean   :3.390   4: 67  
##  3rd Qu.:1.0000   3rd Qu.:660.0   3rd Qu.:3.670          
##  Max.   :1.0000   Max.   :800.0   Max.   :4.000
```

GLM is fit to the data and the fitted object is saved as _admission.rds_. The choice of logistic regression is because it is included in the *stats* package, which is one of the default packages, and I'd like to have R as small as possible for this POC application. Note that AWS Lambda has limits in deployment package size (50MB compressed) so that it is important to keep a deployment package small - see [AWS Lambda Limits](http://docs.aws.amazon.com/lambda/latest/dg/limits.html) for further details. Then the saved file is uploaded to S3 to a bucket named *serverless-poc-models* - the Lambda function handler will use this object for prediction as described in the next section.

```r
fit <- glm(admit ~ ., data = data, family = "binomial")
saveRDS(fit, "admission.rds")
```

Note that, if data is transformed for better performance, a model object alone may not be sufficient as transformed records are necessary as well. A way to handle this situation is using the [caret package](https://topepo.github.io/caret/index.html). The package has `preProcess()` and associating `predict()` so that a separate object can be created to transform records for prediction - see [this page](https://topepo.github.io/caret/pre-processing.html#the-preprocess-function) for further details.

## Lambda function handler

[Lambda function handler](http://docs.aws.amazon.com/lambda/latest/dg/python-programming-model-handler-types.html) is a function that AWS Lambda can invoke when the service executes the code. In this example, it downloads the model objects from S3, predicts admission status and returns the result - *handler.py* and *test_handler.py* can be found in the [**GitHub repository**](https://github.com/jaehyeon-kim/serverless-poc/tree/master/poc-logit-handler).

This and the next sections are based on the following posts with necessary modifications.

* [Analyzing Genomics Data at Scale using R, AWS Lambda, and Amazon API Gateway](https://aws.amazon.com/blogs/compute/analyzing-genomics-data-at-scale-using-r-aws-lambda-and-amazon-api-gateway/)
* [Run ML predictions with R on AWS Lambda](https://tech.foodora.com/run-machine-learning-predictions-with-r-on-aws-lambda/)

*handler.py* begins with importing packages and setting-up environment variables. The above posts indicate C shared libraries of R must be loaded. When I tested the handler while uncommenting the for-loop of loading those libraries, however, I encountered the following error - `OSError: lib/libRrefblas.so: undefined symbol: xerbla_`. It is only when the for-loop is commented out that the script runs through to the handler. I guess the necessary C shared libraries are loaded via Lambda environment variables although I'm not sure why manual loading creates such an error. According to [Lambda Execution Environment and Available Libraries](http://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html), the following environment variables are available.

* `LAMBDA_TASK_ROOT` - Contains the path to your Lambda function code.
* `LD_LIBRARY_PATH` - Contains `/lib64`, `/usr/lib64`, `LAMBDA_TASK_ROOT`, `LAMBDA_TASK_ROOT/lib`. Used to store helper libraries and function code.

As can be seen in the next section, the shared libraries are saved in `LAMBDA_TASK_ROOT/lib` so that they are loaded appropriately.


```python
import ctypes
import json
import os
import boto3
import logging

# use python logging module to log to CloudWatch
# http://docs.aws.amazon.com/lambda/latest/dg/python-logging.html
logging.getLogger().setLevel(logging.DEBUG)

################### load R
# must load all shared libraries and set the
# R environment variables before you can import rpy2
# load R shared libraries from lib dir

# for file in os.listdir('lib'):
#     if os.path.isfile(os.path.join('lib', file)):
#         ctypes.cdll.LoadLibrary(os.path.join('lib', file))
#  
# # set R environment variables
os.environ["R_HOME"] = os.getcwd()
os.environ["R_LIBS"] = os.path.join(os.getcwd(), 'site-library')

# windows only
# os.environ["R_USER"] = r'C:\Users\jaehyeon'

import rpy2
from rpy2 import robjects
from rpy2.robjects import r
################## end of loading R
```

Then 3 functions are defined as following.

* `get_file_path` - Given a S3 object key, it returns a file name or file path. Note that only `/tmp` has write-access so that a file should be downloaded to this folder
* `download_file` - Given bucket and key names, it downloads the S3 object having the key (eg *admission.rds*). Note that it does nothing if the object file already exists
* `pred_admit` - Given gre, gpa and rank, it returns _True_ or _False_ depending on the predicted probablity


```python
BUCKET = 'serverless-poc-models'
KEY = 'admission.rds'
s3 = boto3.client('s3')

def get_file_path(key, name_only=True):
    file_name = key.split('/')[len(key.split('/'))-1]
    if name_only:
        return file_name
    else:
        return '/tmp/' + file_name

def download_file(bucket, key):
    # caching strategies used to avoid the download of the model file every time from S3
    file_name = get_file_path(key, name_only=True)
    file_path = get_file_path(key, name_only=False)
    if os.path.isfile(file_path):
        logging.debug('{} already downloaded'.format(file_name))
        return
    else:
        logging.debug('attempt to download model object to {}'.format(file_path))
        try:
            s3.download_file(bucket, key, file_path)
        except Exception as e:
            logging.error('error downloading key {} from bucket {}'.format(key, bucket))
            logging.error(e)
            raise e

def pred_admit(gre, gpa, rnk, bucket=BUCKET, key=KEY):
    download_file(bucket, key)
    r.assign('gre', gre)
    r.assign('gpa', gpa)
    r.assign('rank', rnk)
    mod_path = get_file_path(key, name_only=False)
    r('fit <- readRDS("{}")'.format(mod_path))
    r('newdata <- data.frame(gre=as.numeric(gre),gpa=as.numeric(gpa),rank=rank)')
    r('pred <- predict(fit, newdata=newdata, type="response")')    
    return robjects.r('pred')[0] > 0.5
```

This is the Lambda function handler for this POC application. It returns a prediction result if there is no error. 400 HTTP error will be returned if there is an error.


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

Optionally code of the test handler is shown below.


```python
import unittest
import handler

class AdmitHandlerTest(unittest.TestCase):
    def test_admit(self):
        gre = '800'
        gpa = '4'
        ranks = {'1': True, '4': False}
        for rnk in ranks.keys():
            self.assertEqual(handler.pred_admit(gre, gpa, rnk), ranks.get(rnk))

if __name__ == "__main__":
    unittest.main()
```

## Packaging

According to [Lambda Execution Environment and Available Libraries](http://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html), Lambda functions run in *AMI name: amzn-ami-hvm-2016.03.3.x86_64-gp2*. A t2.medium EC2 instance is used from this AMI to create the Lambda deployment package. In order to use R in AWS Lambda, R, some of its C shared libraries, the Lambda function handler (*handler.py*) and the handler's dependent packages should be included in a zip deployment package file. 

### Preparation

In this step, R and necessary libraries are installed followed by cloning the project repository. The package folder is created as `$HOME/$HANDLER` (i.e. `/home/ec2-user/handler`). The subfolder `$HOME/$HANDLER/library` is to copy necessary R default packages separately - remind that I'd like to have R as small as possible.


```bash
sudo yum -y update
sudo yum -y upgrade

# readline for rpy2 and fortran for R
sudo yum install -y python27-devel python27-pip gcc gcc-c++ readline-devel libgfortran.x86_64 R.x86_64

# install Git and clone repository
sudo yum install -y git
git clone https://github.com/jaehyeon-kim/serverless-poc.git

# create folder to R and lambda handler
# note R packages will be copied to $HOME/$HANDLER/library separately
export HANDLER=handler
mkdir -p $HOME/$HANDLER/library
```

### Copy R and shared libraries

Firstly all files and folders in `/usr/lib64/R` except for `library` are copyed to the Lambda package folder. By default 29 packages are installed as can be seen in `/usr/lib64/R/library` but not all them are necessary. Actually only the 7 packages listed below are loaded at startup and 1 package is required additionally by the rpy2 package. Therefore only the 8 default R packages are copyed to `$HOME/$HANDLER/library/`.

* Loaded at startup - stats, graphics, grDevices, utils, datasets, methods, base
* Required by rpy2 - tools

In relation to C shared libraries, the default installation includes 4 libraries as can be checked in `/usr/lib64/R/lib` and 1 library is required additionally by the rpy2 package - this additional library is for regex processing.

* Default C shared libraries - libRblas.so, libRlapack.so, libRrefblas.so, libR.so
* Required by rpy2 - libtre.so.5

Together with the above 5 shared libraries, the following 3 libraries are added: libgomp.so.1, libgfortran.so.3 and libquadmath.so.0. Further investigation is necessary to what extent these are used. Note that the above posts inclue 2 libraries for linear algebra (libblas.so.3 and liblapack.so.3) but they are not added as equivalent libraries seem to exist - I guess they are necessary if R is build from source with the following options: *--with-blas* and *--with-lapack*. A total of 8 C shared libraries are added to the deployment package.


```bash
# copy R except for packages - minimum R packages are copied separately
ls /usr/lib64/R | grep -v library | xargs -I '{}' cp -vr /usr/lib64/R/'{}' $HOME/$HANDLER/

# copy minimal default libraries
# loaded at R startup - stats, graphics, grDevices, utils, datasets, methods and base
# needed for Rpy2 - tools
ls /usr/lib64/R/library | grep 'stats$\|graphics\|grDevices\|utils\|datasets\|methods\|base\|^tools' | \
	xargs -I '{}' cp -vr /usr/lib64/R/library/'{}' $HOME/$HANDLER/library/

# copy shared libraries
ldd /usr/lib64/R/bin/exec/R | grep "=> /" | awk '{print $3}' | \
	grep 'libgomp.so.1\|libgfortran.so.3\|libquadmath.so.0\|libtre.so.5' | \
	xargs -I '{}' cp -v '{}' $HOME/$HANDLER/lib/
```

### Install rpy2 and copy to Lamdba package folder

Python virtualenv is used to install the rpy2 package. The idea is straightforward but actually it was a bit tricky as the rpy2 and its dependent packages can be found in either *site-packages* or *dist-packages* folder even in a single EC2 instance - the [AWS Doc](http://docs.aws.amazon.com/lambda/latest/dg/lambda-python-how-to-create-deployment-package.html) doesn't explain clearly. `pip install rpy2 -t folder-path` was tricky as well because the rpy2 package was not installed sometimes while its dependent packages were installed. One way to check is executing `pip list` in the virtualenv and, if the rpy2 package is not shown, it is in *dist-packages*.


```bash
virtualenv ~/env && source ~/env/bin/activate
pip install rpy2
# either in site-packages or dist-packages
# http://docs.aws.amazon.com/lambda/latest/dg/lambda-python-how-to-create-deployment-package.html
export PY_PACK=dist-packages
cp -vr $VIRTUAL_ENV/lib64/python2.7/$PY_PACK/rpy2* $HOME/$HANDLER
cp -vr $VIRTUAL_ENV/lib/python2.7/$PY_PACK/singledispatch* $HOME/$HANDLER
cp -vr $VIRTUAL_ENV/lib/python2.7/$PY_PACK/six* $HOME/$HANDLER
deactivate
```

### Copy handler.py/test_handler.py, compress and copy to S3 bucket

*handler.py* and *test_handler.py* are copied to the Lambda package folder and all contents in the folder are compressed. Note that *handler.py* should exist in the root of the compressed file so that it is necessary to run *zip* in the deployment package folder. The size of *admission.zip* is about 27MB so that it is good to deploy. Finally the package file is copied to a S3 bucket called *serverless-poc-handlers* - note that the [aws cli should be configured](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) to copy the file to S3.


```bash
cp -v serverless-poc/poc-logit-handler/*.py $HOME/$HANDLER

cd $HOME/$HANDLER
zip -r9 $HOME/admission.zip *
# du -sh ~/admission.zip # check file size
# 27M     /home/ec2-user/admission.zip

# aws s3 mb s3://serverless-poc-handlers # create bucket
aws s3 cp $HOME/admission.zip s3://serverless-poc-handlers
```

## Testing

For testing, an EC2 instance without R is necessary so that testing is made in a separate t2.micro instance from the same AMI. Configure the aws-cli and install the boto3 package - the boto3 package is avaialble in Lambda execution environment so that it doesn't need to be added to the deployment package. *LD_LIBRARY_PATH* is an environment variable that points to the C shared libraries of the Lambda package. After downloading the package and decompressing it, testing can be made by running *test_handler.py*.


```bash
# configure aws-cli if necessary

sudo pip install boto3
export R_HOME=$HOME
export LD_LIBRARY_PATH=$HOME/lib

aws s3 cp s3://serverless-poc-handlers/admission.zip .
unzip admission.zip

python ./test_handler.py
```

This is an example testing output where the model object has been downloaded already.


```bash
[ec2-user@ip-172-31-71-13 ~]$ python ./test_handler.py
DEBUG:root:admission.rds already downloaded
DEBUG:root:admission.rds already downloaded
.
----------------------------------------------------------------------
Ran 1 test in 0.024s

OK
```

This is all that I've prepared for this post and I hope you don't feel bored. The next posts will be much more interesting as this package will be exposed via an API.
