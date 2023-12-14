---
title: Parallel Processing on Single Machine - Part II
date: 2015-03-17
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Parallel processing on single machine
categories:
  - R
tags: 
  - R
authors:
  - JaehyeonKim
images: []
description: Part III that demonstrates how to implement parallem processing on single machine in R
---

In the [previous article](/blog/2015-03-14-parallel-processing-on-single-machine-1), parallel processing on a single machine using the **snow** and **parallel** packages are introduced. The four functions are an extension of `lapply()` with an additional argument that specifies a cluster object. In spite of their effectiveness and ease of use, there may be cases where creating a function that can be sent into clusters is not easy or looping may be more natural. In this article, another way of implementing parallel processing on a single machine is introduced using the **foreach** and **doParallel** packages where clusters are created by the **parallel** package. Finally the **iterators** package is briefly covered as it can facilitate writing a loop. The examples here are largely based on the individual packages' vignettes and further details can be found there.

Let's get started.

The following packages are loaded.


```r
library(parallel)
library(iterators)
library(foreach)
library(doParallel)
```

A key difference between the *for* construct in base R and the *foreach* construct in the **foreach** package is as following.

- *for* causes a *side-effect*
    + *side-effect* means state of something is changed. For example, printing a variable, changing the value of a variable and writing data to disk are side-effects.
- *foreach* returns a variable
    + A list is created by default.

An equivalent outcome by the two can be created as following.


```r
x = list()
for(i in 1:3) x[[length(x)+1]] = exp(i) # values of x is changed
x
```



```
## [[1]]
## [1] 2.718282
## 
## [[2]]
## [1] 7.389056
## 
## [[3]]
## [1] 20.08554
```



```r
x = foreach(i=1:3) %do% exp(i)
x
```



```
## [[1]]
## [1] 2.718282
## 
## [[2]]
## [1] 7.389056
## 
## [[3]]
## [1] 20.08554
```

The *foreach* construct has two binary operators for executing a loop: `%do%` and `%dopar%`. The first executes a loop sequentially while the latter does it in parallel. By default, the **doParallel** package uses functionality of the **multicore** package on Unix-like systems and that of the **snow** package on Windows. However the default type value (*PSOCK*) of `makeCluster()` in the **parallel** package is brought from the **snow** package and thus the socket transport by the package will be used in this example regardless of operation systems. The number of cores (or workers in the socket transport) is identified by `detectCores()` and this function is provided by the **parallel** package. Note that, if a cluster object is not setup, the loop will be executed sequentially.


```r
system.time(foreach(i=1:4) %do% Sys.sleep(i))
```



```
##    user  system elapsed 
##   0.010   0.084  10.006
```



```r
cl = makeCluster(detectCores())
registerDoParallel(cl)
system.time(foreach(i=1:4) %dopar% Sys.sleep(i))
```



```
##    user  system elapsed 
##   0.013   0.033   4.056
```



```r
stopCluster(cl)
```

Multiple iterators can be used and (1) more than one expressions can be run in parentheses. (2) If more than one iterators are used, the number of iterations is the minimum length of the iterators. Some examples are shown below.


```r
x = foreach(i=1:3, j=rep(10,3)) %do% (i + j)
x = foreach(i=1:3, j=rep(10,3)) %do% {
  # do something (1)
  i + j
}
x = foreach(i=rep(0,100), j=rep(10,3)) %do% (i + j)
do.call("sum",x) # (2)
```



```
## [1] 30
```

There are some options to control a loop or to change the return data type. Some of them are

- `.combine`: A function can be specified to reduce the outcome variable. `c`, `+ - * / ...`, `rbind/cbind` and `min/max` are some of useful built-in functions. A user-defined function can also be created.
    + `.multicombine` and `.maxcombine` can be set to determine how a function is applied - actually I don't fully understand these options and see the [vignette](https://cran.r-project.org/web/packages/foreach/index.html) for further details.


```r
foreach(i=1:2, .combine="c") %do% exp(i)
```



```
## [1] 2.718282 7.389056
```



```r
foreach(i=1:2, .combine="rbind") %do% exp(i)
```



```
##              [,1]
## result.1 2.718282
## result.2 7.389056
```



```r
foreach(i=1:2, .combine="+") %do% exp(i)
```



```
## [1] 10.10734
```



```r
foreach(i=1:2, .combine="min") %do% exp(i)
```



```
## [1] 2.718282
```



```r
# custom min function
cusMin = function(a, b) if(a < b) a else b
foreach(i=1:2, .combine="cusMin") %do% exp(i)
```



```
## [1] 2.718282
```

- `.inorder`: The order of sequence is reserved if *TRUE* and it is relevant if a loop is executed in parallel. The default value is *TRUE*.

- `.packages`: By specifying one or more pckage names, the package(s) can be loaded in each cluster. This is similar to initialize a worker using `clusterEvalQ()` in the *parallel* package.


```r
# return row dimension of Boston data in each cluster
cl = makeCluster(detectCores())
registerDoParallel(cl)
x = foreach(i=1:detectCores(), .combine="c", .packages="MASS") %dopar% dim(Boston)[1]
stopCluster(cl)
x
```



```
## [1] 506 506 506 506
```

The binary operator of `%:%` can be used for list comprehension (filtering which to loop with `when`) and nested looping.

An example of list comprehension is shown below. It returns a vector of even numbers.


```r
# reutrn a vector of even numbers
foreach(i=1:10, .combine="c") %:% when(i %% 2 == 0) %do% i
```



```
## [1]  2  4  6  8 10
```

Below shows an example of nested looping by *for* and *foreach*. According to the [vignette](https://cran.r-project.org/web/packages/foreach/index.html), it is not necessary to determine which loop (inner or outer) to parallize as `%:%` turns multiple foreach loops into a single stream of tasks that can be parallelized.


```r
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
```



```
##      [,1] [,2] [,3] [,4]
## [1,]   11   12   13   14
## [2,]   21   22   23   24
```



```r
# foreach - sequential
x = foreach(b=1:4, .combine="cbind") %:%
  foreach(a=c(10,20), .combine="c") %do% (a + b)
x
```



```
##      result.1 result.2 result.3 result.4
## [1,]       11       12       13       14
## [2,]       21       22       23       24
```



```r
# foreach - parallel
cl = makeCluster(detectCores())
registerDoParallel(cl)
x = foreach(b=1:4, .combine="cbind") %:% 
  foreach(a=c(10,20), .combine="c") %dopar% (a + b)
stopCluster(cl)
x
```



```
##      result.1 result.2 result.3 result.4
## [1,]       11       12       13       14
## [2,]       21       22       23       24
```

As a loop is constructed by *foreach*, the **iterators** package can be useful as the package allows to create an iterator object from a conventional R objects: vectors, data frames, matrices, lists and even functions. Some examples are shown below.


```r
## create iterator object
# by object
iters = iter(1:10)
c(nextElem(iters),nextElem(iters))
```



```
## [1] 1 2
```



```r
df = data.frame(number=c(1:26), letter=letters)
iters = iter(df, by="row")
nextElem(iters)
```


```
##   number letter
## 1      1      a
```


```r
iters = iter(list(1:2, 3:4))
for(i in 1:iters$length) print(nextElem(iters))
```


```
## [1] 1 2
## [1] 3 4
```


```r
# by function
set.seed(1237)
iters = iter(function() sample(0:9, 4, replace=TRUE))
nextElem(iters)
```


```
## [1] 3 9 0 1
```

The following code generates *Error: StopIteration* error at the end as there is no *nextElem* available.


```r
iters = iter(list(1:2, 3:4))
for(i in 1:(iters$length+1)) print(nextElem(iters))
```

A quick example of using an iterator object with *foreach* is shown below.


```r
set.seed(1237)
mat = matrix(rnorm(100),nrow=1)
iters = iter(mat, by="row")
foreach(a=iters, .combine="c") %do% mean(a)
```


```
## [1] 0.03148661
```

Finally this package provides some wappers around some of built-in functions: `icount()`, `irnorm()`, `irunit()`, `irbinom()`, `irnbinom()` and `irpois()`.

So far two groups of ways are introduced to perform parallel processing on a single machine. The first group uses an extended `lapply()` while the latter is an extension of *for* construct. In the next article, they will be compared with more realistic examples.

