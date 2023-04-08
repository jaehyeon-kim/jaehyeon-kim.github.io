---
layout: post
title: "2015-11-21-Quick-Test-to-Wrap-Python-in-R"
description: ""
category: R
tags: [programming]
---
As mentioned in an [earlier post](http://jaehyeon-kim.github.io/python/2015/08/08/Some-Thoughts-on-Python-for-R-Users/), things that are not easy in R can be relatively simple in other languages. Another example would be connecting to Amazon Web Services. In relation to s3, although there are a number of existing packages, many of them seem to be deprecated, premature or platform-dependent. (I consider the [cloudyr](https://cloudyr.github.io/) project looks promising though.)

If there isn't a comprehensive *R-way* of doing something yet, it may be necessary to create it from scratch. Actually there are some options to do so by using [AWS Command Line Interface](https://aws.amazon.com/cli/), [AWS REST API](http://docs.aws.amazon.com/AmazonS3/latest/API/APIRest.html) or wrapping functionality of another language.

In this post, a quick summary of the last way using Python is illustrated by introducting the [rs3helper](https://github.com/jaehyeon-kim/rs3helper) package.

The reasons why I've come up with a package are as following.

* Firstly, Python is relatively easy to learn and it has quite a comprehensive interface to Amazon Web Services - [boto](http://boto.cloudhackers.com/en/latest/).
* Secondly, in order to call Python in R, the [rPython](http://rpython.r-forge.r-project.org/) package may be used if it only targets UNIX-like platforms. For cross-platform functionality, however, `system` command has to be executed. 
* Finally, due to the previous reason, it wouldn't be stable to keep the source files locally and it'd be necessary to keep them in a package.

I use Python 2.7 and the boto library can be installed easily using [pip](http://pip.readthedocs.org/en/stable/quickstart/) by executing `pip install boto`.

Using RStudio, it is not that complicated to develop a package. (see [R packages](http://r-pkgs.had.co.nz/) by Hadley Wickham) Even the folder structure and necessary files are generated if the project type is selected as *R Package*. R script files should locate in the **R** folder while Python scripts should be in **inst/python**. 

In the package, the s3-related R functions exists in **R/s3utils.R** while the corresponding python scripts are in **inst/python** - all Python functions are in **inst/python/s3helper.py**. As the Python function outputs should be passed to R, a *response* variable is returned for each function and it is converted into JSON string. The response variable is a Python list, dictionary or list of dictionaries and thus it is parsed as R vector, list or data frame.

An example of the wrapper functions, which looks up a bucket, is shown below.

**Python**: `connect_to_s3()` and `lookup_bucket()` are imported to *inst/python/lookup_bucket.py* from *inst/python/s3helper.py*. The script requires 4 mandatory/optional argumens and prints the response after converting it into JSON string.

{% highlight python %}
## in inst/python/s3helper.py
import boto
from boto.s3.connection import OrdinaryCallingFormat

def connect_to_s3(access_key_id, secret_access_key, region = None):
    try:
        if region is None:
            conn = boto.connect_s3(access_key_id, secret_access_key)
        else:
            conn = boto.s3.connect_to_region(
               region_name = region,
               aws_access_key_id = access_key_id,
               aws_secret_access_key = secret_access_key,
               calling_format = OrdinaryCallingFormat()
               )
    except boto.exception.AWSConnectionError:
        conn = None
    return conn

def lookup_bucket(conn, bucket_name):
    if conn is not None:
        try:
            bucket = conn.lookup(bucket_name)
            if bucket is not None:
                response = {'bucket': bucket_name, 'is_exist': True, 'message': None}
            else:
                response = {'bucket': bucket_name, 'is_exist': False, 'message': None}
        except boto.exception.S3ResponseError as re:
            response = {'bucket': bucket_name, 'is_exist': None, 'message': 'S3ResponseError = {0} {1}'.format(re[0], re[1])}
        except:
            response = {'bucket': bucket_name, 'is_exist': None, 'message': 'Unhandled error occurs'}
    else:
        response = {'bucket': bucket_name, 'is_exist': None, 'message': 'connection is not made'}
    return response
{% endhighlight %}

{% highlight python %}
## in inst/python/lookup_bucket.py
import json
import argparse

from s3helper import connect_to_s3, lookup_bucket

parser = argparse.ArgumentParser(description='lookup a bucket')
parser.add_argument('--access_key_id', required=True, type=str, help='AWS access key id')
parser.add_argument('--secret_access_key', required=True, type=str, help='AWS secret access key')
parser.add_argument('--bucket_name', required=True, type=str, help='S3 bucket name')
parser.add_argument('--region', required=False, type=str, help='Region info')

args = parser.parse_args()

conn = connect_to_s3(args.access_key_id, args.secret_access_key, args.region)
response = lookup_bucket(conn, args.bucket_name)

print(json.dumps(response))
{% endhighlight %}

**R**: `lookup_bucket()` generates the path where *inst/python/lookup_bucket.py* exists and constructs the command to be executed in `system()` - the *intern* argument should be *TRUE* to grap the printed JSON string. Then it parses the returned JSON string into a R object using the **jsoinlite** package.


{% highlight r %}
lookup_bucket <- function(access_key_id, secret_access_key, bucket_name, region = NULL) {
  if(bucket_name == '') stop('bucket_name: expected one argument')

  path <- system.file('python', 'lookup_bucket.py', package = 'rs3helper')
  command <- paste('python', path, '--access_key_id', access_key_id, '--secret_access_key', secret_access_key, '--bucket_name', bucket_name)
  if(!is.null(region)) command <- paste(command, '--region', region)

  response <- system(command, intern = TRUE)
  tryCatch({
    fromJSON(response)
  }, error = function(err) {
    warning('fails to parse JSON response')
    response
  })
}
{% endhighlight %}

A quick example of running this function is shown below.


{% highlight r %}
if (!require("devtools"))
  install.packages("devtools")
devtools::install_github("jaehyeon-kim/rs3helper")

library(rs3helper)
library(jsonlite) # not sure why it is not loaded at the first place

lookup_bucket('access-key-id', 'secret-access-key', 'rs3helper')
{% endhighlight %}



{% highlight text %}
## $is_exist
## [1] TRUE
## 
## $message
## NULL
## 
## $bucket
## [1] "rs3helper"
{% endhighlight %}

