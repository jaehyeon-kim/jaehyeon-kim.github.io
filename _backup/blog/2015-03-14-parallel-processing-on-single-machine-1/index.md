---
layout: post
title: "2015-03-14-Parallel-Processing-on-Single-Machine-Part-I"
description: ""
category: R
tags: [snow, parallel, rlecuyer, MASS, ggplot2, programming]
---
Lack of multi-threading and memory limitation are two outstanding weaknesses of base R. In fact, however, if the size of data is not so large that it can be read in RAM, the former would be relatively easily handled by parallel processing, provided that multiple processors are equipped. This article introduces to a way of implementing parallel processing on a single machine using the **snow** and **parallel** packages - the examples are largely based on [McCallum and Weston (2012)](http://shop.oreilly.com/product/0636920021421.do).

The **snow** and **multicore** are two of the packages for parallel processing and the **parallel** package, which has been included in the base R distribution by CRAN (since R 2.14.0), provides functions of both the packages (and more). Only the functions based on the **snow** package are covered in the article.

The functions are similar to `lapply()` and they just have an additional argument for a cluster object (*cl*). The following 4 functions will be compared.

- `clusterApply(cl, x, fun, ...)`
    + pushes tasks to workers by distributing x elements
- `clusterApplyLB(cl, x, fun, ...)`
    + clusterApply + load balancing (workers pull tasks as needed)
    + efficient if some tasks take longer or some workers are slower
- `parLapply(cl, x, fun, ...)`
    + clusterApply + scheduling tasks by splitting *x* given clusters
    + docall(c, clusterApply(cl, **splitList(x, length(cl))**, lapply, fun, ...))
- `parLapplyLB(cl = NULL, X, fun, ...)`
    + clusterApply + tasks scheduling + load balancing
    + available only in the **parallel** package

Let's get started.

As the packages share the same function names, the following utility function is used to reset environment at the end of examples.


{% highlight r %}
reset = function(package) {
  unloadPkg = function(pkg) { 
    detach(search()[grep(paste0("*",pkg),search())]
           ,unload=TRUE
           ,character.only=TRUE)
  }
  unloadPkg(package) # unload package
  rm(list = ls()[ls()!="knitPost"]) # leave utility function
  rm(list = ls()[ls()!="moveFigs"]) # leave utility function
  par(mfrow=c(1,1),mar=c(5.1, 4.1, 4.1, 2.1)) # reset graphics parameters
}
{% endhighlight %}

## Make and stop a cluster

In order to make a cluster, the socket transport is selected (*type="SOCK"* or *type="PSOCK"*) and the number of workers are set manually using the **snow** package (*spec=4*). In the **parallel** package, it can be detected by `detectCores()`. `stopCluster()` stops a cluster.


{% highlight r %}
## make and stop cluster
require(snow)
spec = 4
cl = makeCluster(spec, type="SOCK")
stopCluster(cl)
reset("snow")

require(parallel)
# number of workers can be detected
# type: "PSOCK" or "FORK", default - "PSOCK"
cl = makeCluster(detectCores())
stopCluster(cl)
reset("parallel")
{% endhighlight %}

## CASE I - load balancing matters

As mentioned earlier, load balancing can be important when some tasks take longer or some workers are slower. In this example, system sleep time is assigned randomly so as to compare how tasks are performed using `snow.time()` in the **snow** package and how long it takes by the functions using `system.time()`.


{% highlight r %}
# snow
require(snow)
set.seed(1237)
sleep = sample(1:10,10)
spec = 4
cl = makeCluster(spec, type="SOCK")
st = snow.time(clusterApply(cl, sleep, Sys.sleep))
stLB = snow.time(clusterApplyLB(cl, sleep, Sys.sleep))
stPL = snow.time(parLapply(cl, sleep, Sys.sleep))
stopCluster(cl)
par(mfrow=c(3,1),mar=rep(2,4))
plot(st, title="clusterApply")
plot(stLB, title="clusterApplyLB")
plot(stPL, title="parLapply")
{% endhighlight %}

![center](/figs/2015-03-14-Parallel-Processing-on-Single-Machine-Part-I/case_I_snow-1.png) 

Both `clusterApplyLB()` and `parLapply()` takes shorter than `clusterApply()`. The efficiency of the former is due to *load balancing (pulling a task when necessary)* while that of the latter is because of a *lower number of I/O operations* thanks to task scheduling, which allows a single I/O operation in a chunk (or split) - its benefit is more outstanding when one or more arguments are sent to workers as shown in the next example. The scheduling can be checked by `clusterSplit()`.


{% highlight r %}
sleep
{% endhighlight %}



{% highlight text %}
##  [1]  4  9  1  8  2 10  5  6  3  7
{% endhighlight %}



{% highlight r %}
clusterSplit(cl, sleep)
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] 4 9 1
## 
## [[2]]
## [1] 8 2
## 
## [[3]]
## [1] 10  5
## 
## [[4]]
## [1] 6 3 7
{% endhighlight %}



{% highlight r %}
# clear env
reset("snow")
{% endhighlight %}

The above functions can also be executed using the **parallel** package and it provides an additional function (`parLapplyLB()`). As `snow.time()` is not available, their system time is compared below.


{% highlight r %}
# parallel
require(parallel)
set.seed(1237)
sleep = sample(1:10,10)
cl = makeCluster(detectCores())
st = system.time(clusterApply(cl, sleep, Sys.sleep))
stLB = system.time(clusterApplyLB(cl, sleep, Sys.sleep))
stPL = system.time(parLapply(cl, sleep, Sys.sleep))
stPLB = system.time(parLapplyLB(cl, sleep, Sys.sleep))
stopCluster(cl)
sysTime = do.call("rbind",list(st,stLB,stPL,stPLB))
sysTime = cbind(sysTime,data.frame(fun=c("clusterApply","clusterApplyLB"
                                         ,"parLapply","parLapplyLB")))
require(ggplot2)
ggplot(data=sysTime, aes(x=fun,y=elapsed,fill=fun)) + 
  geom_bar(stat="identity") + ggtitle("Elapsed time of each function")
{% endhighlight %}

![center](/figs/2015-03-14-Parallel-Processing-on-Single-Machine-Part-I/case_I_par-1.png) 

{% highlight r %}
# clear env
reset("parallel")
{% endhighlight %}

## CASE II - I/O operation matters

In this example, a case where an argument is sent to workers is considered. While the argument is passed to wokers once for each task by `clusterApply()` and `clusterApplyLB()`, it is sent to each chunk once by `parLapply()` and `parLapplyLB()`. Therefore the benefit of the latter group of functions can be outstanding in this example - it can be checked workers are idle inbetween in the first two plots while tasks are performed continuously in the last plot.


{% highlight r %}
# snow
require(snow)
mat = matrix(0, 2000, 2000)
sleep = rep(1,50)
fcn = function(st, arg) Sys.sleep(st)
spec = 4
cl = makeCluster(spec, type="SOCK")
st = snow.time(clusterApply(cl, sleep, fcn, arg=mat))
stLB = snow.time(clusterApplyLB(cl, sleep, fcn, arg=mat))
stPL = snow.time(parLapply(cl, sleep, fcn, arg=mat))
stopCluster(cl)
par(mfrow=c(3,1),mar=rep(2,4))
plot(st, title="clusterApply")
plot(stLB, title="clusterApplyLB")
plot(stPL, title="parLapply")
{% endhighlight %}

![center](/figs/2015-03-14-Parallel-Processing-on-Single-Machine-Part-I/case_II_snow-1.png) 

{% highlight r %}
# clear env
reset("snow")
{% endhighlight %}

Although `clusterApplyLB()` has some improvement over `clusterApply()`, it is `parLapply()` which takes the least amount of time. Actually, for the **snow** package, [McCallum and Weston (2012)](http://shop.oreilly.com/product/0636920021421.do) recommends `parLapply()` and it'd be better to use `parLapplyLB()` if the **parallel** package is used. The elapsed time of each function is shown below - the last two functions' elapsed time is identical as individual tasks are assumed to take exactly the same amount of time.


{% highlight r %}
# parallel
require(parallel)
mat = matrix(0, 2000, 2000)
sleep = rep(1,50)
fcn = function(st, arg) Sys.sleep(st)
cl = makeCluster(detectCores())
st = system.time(clusterApply(cl, sleep, fcn, arg=mat))
stLB = system.time(clusterApplyLB(cl, sleep, fcn, arg=mat))
stPL = system.time(parLapply(cl, sleep, fcn, arg=mat))
stPLB = system.time(parLapplyLB(cl, sleep, fcn, arg=mat))
stopCluster(cl)
sysTime = do.call("rbind",list(st,stLB,stPL,stPLB))
sysTime = cbind(sysTime,data.frame(fun=c("clusterApply","clusterApplyLB"
                                         ,"parLapply","parLapplyLB")))
require(ggplot2)
ggplot(data=sysTime, aes(x=fun,y=elapsed,fill=fun)) + 
  geom_bar(stat="identity") + ggtitle("Elapsed time of each function")
{% endhighlight %}

![center](/figs/2015-03-14-Parallel-Processing-on-Single-Machine-Part-I/case_II_par-1.png) 

{% highlight r %}
# clear env
reset("parallel")
{% endhighlight %}

## Initialization of workers

Sometimes workers have to be initialized (eg loading a library) and two functions can be used: `clusterEvalQ()` and `clusterCall()`. While the former just executes an expression, it is possible to send a variable using the latter. Note that it is recommended to let an expression or a function return *NULL* in order not to receive unnecessary data from workers ([McCallum and Weston (2012)](http://shop.oreilly.com/product/0636920021421.do)). Only an example by the **snow** package is shown below.


{% highlight r %}
# snow and parallel
require(snow)
spec = 4
cl = makeCluster(spec, type="SOCK")
# execute expression
exp = clusterEvalQ(cl, { library(MASS); NULL })
# execute expression + pass variables
worker.init = function(arg) {
  for(a in arg) library(a, character.only=TRUE)
  NULL
}
expCall = clusterCall(cl, worker.init, arg=c("MASS","boot"))
stopCluster(cl)

# clear env
reset("snow")
{% endhighlight %}

## Random number generation

In order to ensure that each worker has different random numbers, independent randome number streams have to be set up. In the **snow** package, either the *L'Ecuyer's random number generator* by the **rlecuyer** package or the *SPRNG generator* by the **rsprng** are used in `clusterSetupRNG()`. Only the former is implemented in the **parallel** package in `clusterSetRNGStream()` and, as it uses its own algorithm, the **rlecuyer** package is not necessary. For reproducibility, a seed can be specified and, for the function in the **snow** package, a vector of six integers is necessary (eg *seed=rep(1237,6)*) while an integer value is required for the function in the **parallel** package (eg *iseed=1237*). Each of the examples are shown below.


{% highlight r %}
# snow
require(snow)
require(rlecuyer)
# Uniform Random Number Generation in SNOW Clusters
# seed is six integer values if RNGStream
spec = 4
cl = makeCluster(spec, type="SOCK")
rndSeed = function(x) {
  clusterSetupRNG(cl, type="RNGstream", seed=rep(1237,6))
  unlist(clusterEvalQ(cl, rnorm(1)))
}
t(sapply(1:2,rndSeed))
{% endhighlight %}



{% highlight text %}
##            [,1]     [,2]      [,3]       [,4]
## [1,] -0.2184466 1.237636 0.2448028 -0.5889211
## [2,] -0.2184466 1.237636 0.2448028 -0.5889211
{% endhighlight %}



{% highlight r %}
stopCluster(cl)

# clear env
reset("snow")

# parallel
require(parallel)
cl = makeCluster(detectCores())
rndSeed = function(x) {
  clusterSetRNGStream(cl, iseed=1237)
  unlist(clusterEvalQ(cl, rnorm(1)))
}
t(sapply(1:2,rndSeed))
{% endhighlight %}



{% highlight text %}
##           [,1]       [,2]      [,3]        [,4]
## [1,] 0.5707716 -0.2752422 0.3562034 -0.08946821
## [2,] 0.5707716 -0.2752422 0.3562034 -0.08946821
{% endhighlight %}



{% highlight r %}
stopCluster(cl)

# clear env
reset("parallel")
{% endhighlight %}

A quick introduction to the **snow** and **parallel** packages is made in this article. Sometimes it may not be easy to create a function that can be sent into clusters or looping may be more natural for computation. In this case, the **foreach** package would be used and an introduction to this package will be made in the next article.
