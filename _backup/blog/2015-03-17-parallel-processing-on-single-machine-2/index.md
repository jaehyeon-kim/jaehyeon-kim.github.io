---
layout: post
title: "2015-03-17-Parallel-Processing-on-Single-Machine-Part-II"
description: ""
category: R
tags: [foreach, doParallel, parallel, iterators, programming]
---
In the [previous article](http://jaehyeon-kim.github.io/r/2015/03/14/Parallel-Processing-on-Single-Machine-Part-I/), parallel processing on a single machine using the **snow** and **parallel** packages are introduced. The four functions are an extension of `lapply()` with an additional argument that specifies a cluster object. In spite of their effectiveness and ease of use, there may be cases where creating a function that can be sent into clusters is not easy or looping may be more natural. In this article, another way of implementing parallel processing on a single machine is introduced using the **foreach** and **doParallel** packages where clusters are created by the **parallel** package. Finally the **iterators** package is briefly covered as it can facilitate writing a loop. The examples here are largely based on the individual packages' vignettes and further details can be found there.

Let's get started.

The following packages are loaded.


{% highlight r %}
library(parallel)
library(iterators)
library(foreach)
library(doParallel)
{% endhighlight %}

A key difference between the *for* construct in base R and the *foreach* construct in the **foreach** package is as following.

- *for* causes a *side-effect*
    + *side-effect* means state of something is changed. For example, printing a variable, changing the value of a variable and writing data to disk are side-effects.
- *foreach* returns a variable
    + A list is created by default.

An equivalent outcome by the two can be created as following.


{% highlight r %}
x = list()
for(i in 1:3) x[[length(x)+1]] = exp(i) # values of x is changed
x
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] 2.718282
## 
## [[2]]
## [1] 7.389056
## 
## [[3]]
## [1] 20.08554
{% endhighlight %}



{% highlight r %}
x = foreach(i=1:3) %do% exp(i)
x
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] 2.718282
## 
## [[2]]
## [1] 7.389056
## 
## [[3]]
## [1] 20.08554
{% endhighlight %}

The *foreach* construct has two binary operators for executing a loop: `%do%` and `%dopar%`. The first executes a loop sequentially while the latter does it in parallel. By default, the **doParallel** package uses functionality of the **multicore** package on Unix-like systems and that of the **snow** package on Windows. However the default type value (*PSOCK*) of `makeCluster()` in the **parallel** package is brought from the **snow** package and thus the socket transport by the package will be used in this example regardless of operation systems. The number of cores (or workers in the socket transport) is identified by `detectCores()` and this function is provided by the **parallel** package. Note that, if a cluster object is not setup, the loop will be executed sequentially.


{% highlight r %}
system.time(foreach(i=1:4) %do% Sys.sleep(i))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.010   0.084  10.006
{% endhighlight %}



{% highlight r %}
cl = makeCluster(detectCores())
registerDoParallel(cl)
system.time(foreach(i=1:4) %dopar% Sys.sleep(i))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.013   0.033   4.056
{% endhighlight %}



{% highlight r %}
stopCluster(cl)
{% endhighlight %}

Multiple iterators can be used and (1) more than one expressions can be run in parentheses. (2) If more than one iterators are used, the number of iterations is the minimum length of the iterators. Some examples are shown below.


{% highlight r %}
x = foreach(i=1:3, j=rep(10,3)) %do% (i + j)
x = foreach(i=1:3, j=rep(10,3)) %do% {
  # do something (1)
  i + j
}
x = foreach(i=rep(0,100), j=rep(10,3)) %do% (i + j)
do.call("sum",x) # (2)
{% endhighlight %}



{% highlight text %}
## [1] 30
{% endhighlight %}

There are some options to control a loop or to change the return data type. Some of them are

- `.combine`: A function can be specified to reduce the outcome variable. `c`, `+ - * / ...`, `rbind/cbind` and `min/max` are some of useful built-in functions. A user-defined function can also be created.
    + `.multicombine` and `.maxcombine` can be set to determine how a function is applied - actually I don't fully understand these options and see the [vignette](http://cran.r-project.org/web/packages/foreach/vignettes/foreach.pdf) for further details.


{% highlight r %}
foreach(i=1:2, .combine="c") %do% exp(i)
{% endhighlight %}



{% highlight text %}
## [1] 2.718282 7.389056
{% endhighlight %}



{% highlight r %}
foreach(i=1:2, .combine="rbind") %do% exp(i)
{% endhighlight %}



{% highlight text %}
##              [,1]
## result.1 2.718282
## result.2 7.389056
{% endhighlight %}



{% highlight r %}
foreach(i=1:2, .combine="+") %do% exp(i)
{% endhighlight %}



{% highlight text %}
## [1] 10.10734
{% endhighlight %}



{% highlight r %}
foreach(i=1:2, .combine="min") %do% exp(i)
{% endhighlight %}



{% highlight text %}
## [1] 2.718282
{% endhighlight %}



{% highlight r %}
# custom min function
cusMin = function(a, b) if(a < b) a else b
foreach(i=1:2, .combine="cusMin") %do% exp(i)
{% endhighlight %}



{% highlight text %}
## [1] 2.718282
{% endhighlight %}

- `.inorder`: The order of sequence is reserved if *TRUE* and it is relevant if a loop is executed in parallel. The default value is *TRUE*.

- `.packages`: By specifying one or more pckage names, the package(s) can be loaded in each cluster. This is similar to initialize a worker using `clusterEvalQ()` in the *parallel* package.


{% highlight r %}
# return row dimension of Boston data in each cluster
cl = makeCluster(detectCores())
registerDoParallel(cl)
x = foreach(i=1:detectCores(), .combine="c", .packages="MASS") %dopar% dim(Boston)[1]
stopCluster(cl)
x
{% endhighlight %}



{% highlight text %}
## [1] 506 506 506 506
{% endhighlight %}

The binary operator of `%:%` can be used for list comprehension (filtering which to loop with `when`) and nested looping.

An example of list comprehension is shown below. It returns a vector of even numbers.


{% highlight r %}
# reutrn a vector of even numbers
foreach(i=1:10, .combine="c") %:% when(i %% 2 == 0) %do% i
{% endhighlight %}



{% highlight text %}
## [1]  2  4  6  8 10
{% endhighlight %}

Below shows an example of nested looping by *for* and *foreach*. According to the [vignette](http://cran.r-project.org/web/packages/foreach/vignettes/foreach.pdf), it is not necessary to determine which loop (inner or outer) to parallize as `%:%` turns multiple foreach loops into a single stream of tasks that can be parallelized.


{% highlight r %}
# for
avec = c(10,20)
bvec = 1:4
mat = matrix(0, nrow=length(avec), ncol=length(bvec))
for(b in bvec) {
  for(a in 1:length(avec)) {
    mat[a,b] = avec[a] + bvec[b]
  }
}
mat
{% endhighlight %}



{% highlight text %}
##      [,1] [,2] [,3] [,4]
## [1,]   11   12   13   14
## [2,]   21   22   23   24
{% endhighlight %}



{% highlight r %}
# foreach - sequential
x = foreach(b=1:4, .combine="cbind") %:%
  foreach(a=c(10,20), .combine="c") %do% (a + b)
x
{% endhighlight %}



{% highlight text %}
##      result.1 result.2 result.3 result.4
## [1,]       11       12       13       14
## [2,]       21       22       23       24
{% endhighlight %}



{% highlight r %}
# foreach - parallel
cl = makeCluster(detectCores())
registerDoParallel(cl)
x = foreach(b=1:4, .combine="cbind") %:% 
  foreach(a=c(10,20), .combine="c") %dopar% (a + b)
stopCluster(cl)
x
{% endhighlight %}



{% highlight text %}
##      result.1 result.2 result.3 result.4
## [1,]       11       12       13       14
## [2,]       21       22       23       24
{% endhighlight %}

As a loop is constructed by *foreach*, the **iterators** package can be useful as the package allows to create an iterator object from a conventional R objects: vectors, data frames, matrices, lists and even functions. Some examples are shown below.


{% highlight r %}
## create iterator object
# by object
iters = iter(1:10)
c(nextElem(iters),nextElem(iters))
{% endhighlight %}



{% highlight text %}
## [1] 1 2
{% endhighlight %}



{% highlight r %}
df = data.frame(number=c(1:26), letter=letters)
iters = iter(df, by="row")
nextElem(iters)
{% endhighlight %}



{% highlight text %}
##   number letter
## 1      1      a
{% endhighlight %}



{% highlight r %}
iters = iter(list(1:2, 3:4))
for(i in 1:iters$length) print(nextElem(iters))
{% endhighlight %}



{% highlight text %}
## [1] 1 2
## [1] 3 4
{% endhighlight %}



{% highlight r %}
# by function
set.seed(1237)
iters = iter(function() sample(0:9, 4, replace=TRUE))
nextElem(iters)
{% endhighlight %}



{% highlight text %}
## [1] 3 9 0 1
{% endhighlight %}

The following code generates *Error: StopIteration* error at the end as there is no *nextElem* available.


{% highlight r %}
iters = iter(list(1:2, 3:4))
for(i in 1:(iters$length+1)) print(nextElem(iters))
{% endhighlight %}

A quick example of using an iterator object with *foreach* is shown below.


{% highlight r %}
set.seed(1237)
mat = matrix(rnorm(100),nrow=1)
iters = iter(mat, by="row")
foreach(a=iters, .combine="c") %do% mean(a)
{% endhighlight %}



{% highlight text %}
## [1] 0.03148661
{% endhighlight %}

Finally this package provides some wappers around some of built-in functions: `icount()`, `irnorm()`, `irunit()`, `irbinom()`, `irnbinom()` and `irpois()`.

So far two groups of ways are introduced to perform parallel processing on a single machine. The first group uses an extended `lapply()` while the latter is an extension of *for* construct. In the next article, they will be compared with more realistic examples.

