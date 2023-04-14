---
title: Asynchronous Processing Using Job Queue
date: 2016-05-12
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Web Development
tags: 
  - R
authors:
  - JaehyeonKim
images: []
description: In this post, a way to overcome one of R's limitations of lack of multi-threading is discussed by job queuing using the jobqueue package
---

In this post, a way to overcome one of R's limitations (**lack of multi-threading**) is discussed by job queuing using the [jobqueue package](http://jobqueue.r-forge.r-project.org/) - a generic asynchronous job queue implementation for R. See the package description below.

> The jobqueue package is meant to provide an easy-to-use interface that allows to queue computations for background evaluation while the calling R session remains responsive. It is based on a *1-node socket cluster from the parallel package*. The package provides a way to do basic threading in R. The main focus of the package is on an intuitive and easy-to-use interface for the job queue programming construct. ... Typical applications include: **background computation of lengthy tasks (such as data sourcing, model fitting, bootstrapping), simple/interactive parallelization (if you have 5 different jobs, move them to up to 5 different job queues), and concurrent task scheduling in more complicated R programs.** ...

Added to the typical applications indicated above, this package can be quite beneficial with a Shiny application especially when long-running process has to be served.

The package is not on CRAN and it can be installed as following.


```r
# http://r-forge.r-project.org/R/?group_id=2066
if(!require(jobqueue)) {
  pkg_src <- if(grepl("win", Sys.info()["sysname"], ignore.case = TRUE)) {
    "http://download.r-forge.r-project.org/bin/windows/contrib/3.2/jobqueue_1.0-4.zip"
  } else {
    "http://download.r-forge.r-project.org/src/contrib/jobqueue_1.0-4.tar.gz"
  }
  
  install.packages(pkg_src, repos = NULL)
}

library(jobqueue)
```

As can be seen in the description, it is highly related to the **parallel** package and thus it wouldn't be hard to understand how it works if you know how to do parallel processing using that package - if not, have a look at [this post](http://jaehyeon-kim.github.io/2015/03/Parallel-Processing-on-Single-Machine-Part-I.html). 

Here is a quick example of job queue. In the following function, execution is suspended for 1 second at each iteration and the processed is blocking until it is executed in base R.


```r
fun <- function(max_val) {
  unlist(lapply(1:max_val, function(x) {
    Sys.sleep(1)
    x
  }))
}
```

Using the package, however, the function can be executed asynchronously as shown below.


```r
# create queue
# similar to makeCluster()
queue <- Q.make()
# send local R object
# similar to clusterEvalQ() or clusterCall()
Q.sync(queue, fun)
# execute function
# similar to clusterApply() or parLapply()
Q.push(queue, fun(10))
### another job can be done while it is being executed
# get result - NULL is not complete
Q.pop(queue)
```


```
## NULL
```


```r
while (TRUE) {
  out <- Q.pop(queue)
  message(paste("INFO execution not completed?", is.null(out)))
  if(!is.null(out)) {
    break
  }
}
```



```
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
## INFO execution not completed? TRUE
```



```
## INFO execution not completed? FALSE
```



```r
# close queue
# similar to stopCluster()
Q.close(queue)
out
```



```
##  [1]  1  2  3  4  5  6  7  8  9 10
```

Another example of applying *job queue* is fitting a bootstrap-based algorithm. In this example, each of 500 trees are grown and they are combined at the end - note that, in practice, it'd be better to save outputs and combine them later.


```r
q1 <- Q.make()
q2 <- Q.make()
# load library
Q.push(q1, library(randomForest), mute = TRUE)
Q.push(q2, library(randomForest), mute = TRUE)
Q.push(q1, rf <- randomForest(Species ~ ., data=iris, importance=TRUE, proximity=TRUE))
Q.push(q2, rf <- randomForest(Species ~ ., data=iris, importance=TRUE, proximity=TRUE))
# should be waited until completion in practice
r1 <- Q.pop(q1)
r2 <- Q.pop(q2)
Q.close(q1)
Q.close(q2)

library(randomForest)
do.call("combine", list(r1, r2))
```

```
## 
## Call:
##  randomForest(formula = Species ~ ., data = iris, importance = TRUE,      proximity = TRUE) 
##                Type of random forest: classification
##                      Number of trees: 1000
## No. of variables tried at each split: 2
```

I hope this article is useful.
