---
layout: post
title: "2015-12-03-Introduction-to-rs3helper-part-1"
description: ""
category: R
tags: [programming, AWS, S3]
---
### What is rs3helper

[rs3helper](https://github.com/jaehyeon-kim/rs3helper) includes a collection of functions to work on [Amazon Simple Storage Service (Amazon S3)](https://aws.amazon.com/s3/). Each function executes a Python script that performs an action using the [boto S3 library](http://boto.cloudhackers.com/en/latest/ref/s3.html) - [boto](https://github.com/boto/boto) is probably the most popular interface to Amazon Web Services in Python. In this regard, this package can be considered as a R wrapper of Python boto S3 library.

### Why use Python

In relation to s3, although there are a number of existing packages, many of them seem to be deprecated, premature or platform-dependent. If there is not a comprehensive *R-way* of doing something yet, it may be necessary to create it from scratch. I have chosen to use Python as it is easy to learn and it has a comprehensive interface to AWS. For those who are interested in a R-based tool, see the [aws.s3](https://github.com/cloudyr/aws.s3) package of the [cloudyr project](https://github.com/cloudyr).

### Prerequisites

Python and the boto library need to be installed. The Python version that is used for development is 2.7.10. The boto library can be installed using a Python package management system called **pip**. Once it is installed (see [here](http://pip.readthedocs.org/en/stable/installing/)), installing the boto library is as simple as the following.


{% highlight r %}
$ pip install boto
{% endhighlight %}

### Package installation

The package is hosted in GitHub and it is possible to install/load as shown below.


{% highlight r %}
if (!require("devtools"))
  install.packages("devtools")
devtools::install_github("jaehyeon-kim/rs3helper")

library(rs3helper)
{% endhighlight %}

Note, if you see the following error, install the **jsonlite** package again and run the above snippet - this package is used to parse responses of the Python scripts.


{% highlight r %}
Error in (function (dep_name, dep_ver = NA, dep_compare = NA)  : 
  Dependency package jsonlite not available.
Calls: suppressPackageStartupMessages ... <Anonymous> -> load_all -> load_depends 
                                                                      -> mapply -> <Anonymous>
Execution halted

Exited with status 1.
{% endhighlight %}

### Introduction to rs3wrapper

Below is the fomal of *lookup_bucket()* in the package.


{% highlight r %}
lookup_bucket(access_key_id, secret_access_key, bucket_name, 
                      is_ordinary_calling_format = FALSE, region = NULL)
{% endhighlight %}

The first two arguments are for authentication (see [here](http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSGettingStartedGuide/AWSCredentials.html)) while the last two modify connection setting. Specifically, if a bucket name is non-DNS compliant, *is_ordinary_calling_format* should be set to *TRUE* so that connection can be made without an error. For example, if a bucket name begins/ends with a dot(.) or includes both small and capital letters (eg MyAWSBucket), it is not DNS-compliant. For more details, see this [article](http://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html). Also it is possible to specify a specific *region* to connect and the available regions can be checked by executing *lookup_region()*.

Although the last two arguments can be skipped as they have default values, the authentication arguments must be provided each time. Besides there may be occasions when non-default values should be entered for them. Entering these argumens each time can be tedious and thus it will be convenient if they are pre-filled. In this regard, a wrapper function called *rs3wrapper()* is created. As can be seen below, it returns a function that has a function argumnet (*f*) and unspecified argument (*...*). Then it is possible to execute a function where connection related arguments are pre-filled.


{% highlight r %}
rs3wrapper <- function(access_key_id, secret_access_key, 
                       is_ordinary_calling_format = FALSE, region = NULL) {
  function(f, ...) {
    f(access_key_id = access_key_id, secret_access_key = secret_access_key, 
            is_ordinary_calling_format = is_ordinary_calling_format, region = region, ...)
  }
}
{% endhighlight %}

An example of applying *rs3wrapper()* is shown below. At first a function named as *wrapper* is created by filling the connection related arguments. Then *lookup_bucket()* is executed in it by entering the function and other necessary arguments. It returns the same outcome to the original function but now the amount of code can be reduced especially when multiple functions are executed. Further example can be seen in the object document (*?rs3wrapper*).


{% highlight r %}
access_key_id <- Sys.getenv('access_key_id')
secret_access_key <- Sys.getenv('secret_access_key')

wrapper <- rs3wrapper(access_key_id, secret_access_key)
wrapper(lookup_bucket, bucket_name = 'rs3helper') # a bucket called rs3helper exists
{% endhighlight %}



{% highlight text %}
## $message
## NULL
## 
## $bucket_name
## [1] "rs3helper"
## 
## $is_exists
## [1] TRUE
{% endhighlight %}



{% highlight r %}
lookup_bucket(access_key_id, secret_access_key, bucket_name = 'rs3helper')
{% endhighlight %}



{% highlight text %}
## $message
## NULL
## 
## $bucket_name
## [1] "rs3helper"
## 
## $is_exists
## [1] TRUE
{% endhighlight %}

From now on, demonstration will be made using this wrapper function.

### Functions to lookup objects and setting variables

As mentioned earlier, connection can be made to a specific region and it can be checked by executing *lookup_region()*. Also a bucket can be created in a specific location and avaialble locations can be looked up by *lookup_location()*. Both of them return a character vector.


{% highlight r %}
lookup_region()
{% endhighlight %}



{% highlight text %}
##  [1] "us-east-1"      "cn-north-1"     "ap-northeast-1" "eu-west-1"     
##  [5] "ap-southeast-1" "ap-southeast-2" "us-west-2"      "us-gov-west-1" 
##  [9] "us-west-1"      "eu-central-1"   "sa-east-1"
{% endhighlight %}



{% highlight r %}
lookup_location()
{% endhighlight %}



{% highlight text %}
## [1] "APNortheast"  "APSoutheast"  "APSoutheast2" "CNNorth1"    
## [5] "DEFAULT"      "EU"           "SAEast"       "USWest"      
## [9] "USWest2"
{% endhighlight %}

In order to look up specific bucket or key, *lookup_bucket()* and *lookup_key()* can be used. Both of them return a list of lookup information - the *message* element is kept to inform an error or unexpected case.


{% highlight r %}
wrapper(lookup_bucket, bucket_name = 'rs3helper')
{% endhighlight %}



{% highlight text %}
## $message
## NULL
## 
## $bucket_name
## [1] "rs3helper"
## 
## $is_exists
## [1] TRUE
{% endhighlight %}



{% highlight r %}
wrapper(lookup_key, bucket_name = 'rs3helper', key_name = 'iris.csv')
{% endhighlight %}



{% highlight text %}
## $key_name
## [1] "iris.csv"
## 
## $message
## NULL
## 
## $is_exists
## [1] TRUE
{% endhighlight %}

Also more than one objects can be checked by *get_all_buckets()* and *get_keys()*. As the names suggest, the former returns information of all buckets while the latter returns information of keys. *get_keys()* has an extra argument called *prefix* that filters keys. For example, if a bucket has a folder named *json* and only the keys in the folder need to be checked, it is possible to set the argument's value to be *json*. Then only the keys in the folder are looked up - subfolders can also be prefixed (eg folder/subfolder). Both the functions return a data frame of lookup information.

Below shows some examples.


{% highlight r %}
wrapper(get_all_buckets)
{% endhighlight %}



{% highlight text %}
##   message  bucket_name                  created
## 1      NA dev-aws-test 2015-11-06T23:30:20.000Z
## 2      NA    rs3helper 2015-12-02T02:32:00.000Z
## 3      NA  rs3helper_1 2015-12-02T02:50:49.000Z
{% endhighlight %}



{% highlight r %}
wrapper(get_keys, bucket_name = 'rs3helper')
{% endhighlight %}



{% highlight text %}
##              key_name message key_size                 modified
## 1            iris.csv      NA     4177 2015-12-02T02:38:13.000Z
## 2      json/iris.json      NA    14461 2015-12-03T02:41:57.000Z
## 3       test/iris.csv      NA     4177 2015-12-02T02:55:11.000Z
## 4 test/json/iris.json      NA    14461 2015-12-03T02:50:09.000Z
{% endhighlight %}



{% highlight r %}
wrapper(get_keys, bucket_name = 'rs3helper', prefix = 'json')
{% endhighlight %}



{% highlight text %}
##         key_name message key_size                 modified
## 1 json/iris.json      NA    14461 2015-12-03T02:41:57.000Z
{% endhighlight %}

### Functions to get/set access control list

Permission of an S3 object can be checked or set up. In the boto library, the following *'canned'* [access control policy](http://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html) is supported - see [this article](https://boto.readthedocs.org/en/2.6.0/s3_tut.html) for further details.

- private: Owner gets FULL_CONTROL. No one else has any access rights.
- public-read: Owners gets FULL_CONTROL and the anonymous principal is granted READ access.
- public-read-write: Owner gets FULL_CONTROL and the anonymous principal is granted READ and WRITE access.
- authenticated-read: Owner gets FULL_CONTROL and any principal authenticated as a registered Amazon S3 user is granted READ access.

*get_access_control_list()* has 2 extra arguments that are not related to connection: *bucket_name* and *key_name*. If *key_name* is *NULL*, the access control list of the bucket is returned. Otherwise the specific key's access control list is returned.


{% highlight r %}
acl_df <- wrapper(get_access_control_list, bucket_name = 'rs3helper')
acl_df[, !names(acl_df) %in% 'id']
{% endhighlight %}



{% highlight text %}
##   email_address message display_name   permission
## 1            NA      NA      dottami FULL_CONTROL
## 2            NA      NA         <NA>         READ
## 3            NA      NA         <NA>        WRITE
{% endhighlight %}



{% highlight r %}
acl_df <- wrapper(get_access_control_list, bucket_name = 'rs3helper', key_name = 'json/iris.json')
acl_df[, !names(acl_df) %in% 'id']
{% endhighlight %}



{% highlight text %}
##   email_address message display_name   permission
## 1            NA      NA      dottami FULL_CONTROL
{% endhighlight %}

By default, all objects are *private* and an extra level of permission can be set up. For example, the bucket has two extra rows which indicate it has *public-read-write* permission as well.

*set_access_control_list()* can be used to set access control policy. It has one extra argument called *permission* to its '*get*-counterpart' - only *canned* access control policy that is listed above can be added. Below shows some examples.


{% highlight r %}
wrapper(set_access_control_list, bucket_name = 'rs3helper', permission = 'public-read-write')
{% endhighlight %}



{% highlight text %}
## $message
## NULL
## 
## $is_set
## [1] TRUE
## 
## $permission
## [1] "public-read-write"
{% endhighlight %}



{% highlight r %}
wrapper(set_access_control_list, bucket_name = 'rs3helper', key_name = 'json/iris.json', permission = 'private')
{% endhighlight %}



{% highlight text %}
## $message
## NULL
## 
## $is_set
## [1] TRUE
## 
## $permission
## [1] "private"
{% endhighlight %}

In part 1, motivation of the **rs3helper** package is illustrated followed by its installation and basic usage. In the next part, more usage will be demonstrated.
