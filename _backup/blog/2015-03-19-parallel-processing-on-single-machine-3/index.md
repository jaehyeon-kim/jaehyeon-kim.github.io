---
layout: post
title: "2015-03-19-Parallel-Processing-on-Single-Machine-Part-III"
description: ""
category: R
tags: [parallel, foreach, doParallel, iterators, rpart, randomForest, ISLR, programming]
---
In the previous posts, two groups of ways to implement parallel processing on a single machine are introduced. The first group is provided by the **snow** or **parallel** package and the functions are an extension of `lapply()` ([link](http://jaehyeon-kim.github.io/r/2015/03/14/Parallel-Processing-on-Single-Machine-Part-I/)). The second group is based on an extension of the *for* construct (*foreach*, *%dopar%* and *%:%*). The *foreach* construct is provided by the *foreach* package while clusters are made and registered by the **parallel** and **doParallel** packages respectively ([link](http://jaehyeon-kim.github.io/r/2015/03/17/Parallel-Processing-on-Single-Machine-Part-II/)). To conclude this series, three practical examples are discussed for comparison in this article.

Let's get started.

The following packages are loaded at first. Note that the **randomForest**, **rpart** and **ISLR** packages are necessary for the second and third examples and they are loaded later.


{% highlight r %}
library(parallel)
library(iterators)
library(foreach)
library(doParallel)
{% endhighlight %}

## k-means clustering

This example is from [McCallum and Weston (2012)](http://shop.oreilly.com/product/0636920021421.do). It is originally created using `clusterApply()` in the **snow** package. Firstly a slight modification is made to be used with `parLapplyLB()` in the **parallel** package. Also a *foreach* construct is created for comparison.

According to the document, 

- *the data given by x are clustered by the k-means method, which aims to partition the points into k groups such that the sum of squares from points to the assigned cluster centres is minimized*

At the minimum, all data points are nearest to the cluster centres. The number of centers are specified by *centers* (4 in this example). The distance value is kept in *tot.withinss*. As initial clusters are randomly assigned at the beginning, fitting is performed multiple times and it is determined by *nstart*.

### parallel package

The clusters are initialized by `clusterEvalQ()` as *Boston* data is available in the **MASS** package. A list of outputs are returned by **parLapplyLB()** and *tot.withinss* is extract by `sapply()`. The final outcome is what gives the minimum *tot.withinss*.


{% highlight r %}
# parallel
split = detectCores()
eachStart = 25

cl = makeCluster(split)
init = clusterEvalQ(cl, { library(MASS); NULL })
results = parLapplyLB(cl
                      ,rep(eachStart, split)
                      ,function(nstart) kmeans(Boston, 4, nstart=nstart))
withinss = sapply(results, function(result) result$tot.withinss)
result = results[[which.min(withinss)]]
stopCluster(cl)

result$tot.withinss
{% endhighlight %}



{% highlight text %}
## [1] 1814438
{% endhighlight %}

### foreach package

The corresponding implementation using the **foreach** package is shown below. An iterator object is created to repeat the individual *nstart* value for the number of clusters (*iters*). A funtion to combine the outcome is created (`comb()`), which just keeps the outcome that gives the minimum *tot.withinss* - as *.combine* doesn't seem to allow an argument, this kind of modification would be necessary.


{% highlight r %}
# foreach
split = detectCores()
eachStart = 25
# set up iterators
iters = iter(rep(eachStart, split))
# set up combine function
comb = function(res1, res2) {
  if(res1$tot.withinss < res2$tot.withinss) res1 else res2
}

cl = makeCluster(split)
registerDoParallel(cl)
result = foreach(nstart=iters, .combine="comb", .packages="MASS") %dopar%
  kmeans(Boston, 4, nstart=nstart)
stopCluster(cl)

result$tot.withinss
{% endhighlight %}



{% highlight text %}
## [1] 1814438
{% endhighlight %}

## random forest

This example is from **foreach** packages's [vignette](http://cran.r-project.org/web/packages/foreach/vignettes/foreach.pdf).

According to the package document,

- *randomForest implements Breiman's random forest algorithm (based on Breiman and Cutler's original Fortran code) for classification and regression*.

### parallel package

*x* and *y* keep the predictors and response. A function (`rf()`) is created to implement the algorithm. If data has to be sent to each worker, it can be sent either by `clusterCall()` or by a function. If `clusterApply()` or `clusterApplyLB()` are used, the former should be used to reduce I/O operations time and it'd be alright to send by a function if `parLapply()` or `parLapplyLB()` are used - single I/O for each task split. (for details, see the [first article](http://jaehyeon-kim.github.io/r/2015/03/14/Parallel-Processing-on-Single-Machine-Part-I/)) As the **randomForest** package provides a function to combine the objects (`combine()`), it is used in `do.call()`. Finally a confusion table is created.


{% highlight r %}
## Random forest
library(randomForest)

# parallel
rm(list = ls())
set.seed(1237)
x = matrix(runif(500), 100)
y = gl(2,50)

split = detectCores()
eachTrees = 250
# define function to fit random forest given predictors and response
# data has to be sent to workers using this function
rf = function(ntree, pred, res) {
  randomForest(pred, res, ntree=ntree)
}

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
init = clusterEvalQ(cl, { library(randomForest); NULL })
results = parLapplyLB(cl, rep(eachTrees, split), rf, pred=x, res=y)
result = do.call("combine", results)
stopCluster(cl)

cm = table(data.frame(actual=y, fitted=result$predicted))
cm
{% endhighlight %}



{% highlight text %}
##       fitted
## actual  1  2
##      1 23 27
##      2 28 22
{% endhighlight %}

### foreach package

`randomForest()` is directly used in the *foreach* construct and the returned outcomes are combined by `combine()` (*.combine="combine"*). The fitting function has to be available in each worker and it is set by *.packages="randomForest"*. As there are multiple argument in the combine function, it is necessary to set the multi-combine option to be *TRUE* (*.multicombine=TRUE*) - this option will be discussed further in the next example. As the above example, a confusion matrix is created at the end - both the results should be the same as the same streams of random numbers are set to be generated by `clusterSetRNGStream()`.


{% highlight r %}
# foreach
rm(list = ls())
set.seed(1237)
x = matrix(runif(500), 100)
y = gl(2,50)

split = detectCores()
eachTrees = 250
# set up iterators
iters = iter(rep(eachTrees, split))

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
registerDoParallel(cl)
result = foreach(ntree=iters, .combine="combine", .multicombine=TRUE, .packages="randomForest") %dopar%
  randomForest(x, y, ntree=ntree)
stopCluster(cl)

cm = table(data.frame(actual=y, fitted=result$predicted))
cm
{% endhighlight %}



{% highlight text %}
##       fitted
## actual  1  2
##      1 23 27
##      2 28 22
{% endhighlight %}

## bagging

Although bagging can be implemented using the **randomForest** package, another quick implementation is tried using the **rpart** package for illustration (`cartBGG()`). Specifically bootstrap samples can be created for the number of trees specified by *ntree*. To simplify discussion, only the variable importance values are kept - an *rpart* object keeps this details in *variable.importance*. Therefore `cartBGG()` returns a list where its only element is a data frame where the number of rows is the same to the number of predictors and the number of columns is the same to the number of trees. In fact, `cartBGG()` is a constructor that generates a S3 object (*rpartbgg*).


{% highlight r %}
## Bagging
rm(list = ls())
# update variable importance measure of bagged trees
cartBGG = function(formula, trainData, ntree=1, ...) {
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  
  # variable importance - merge by 'var'
  var.imp = data.frame(var=colnames(trainData[,-res.ind]))
  require(rpart)
  for(i in 1:ntree) {
    # create in bag and out of bag sample
    bag = sample(nrow(trainData), size=nrow(trainData), replace=TRUE)
    inbag = trainData[bag,]
    outbag = trainData[-bag,]
    # fit model
    mod = rpart(formula=formula, data=inbag, control=rpart.control(cp=0))
    # set helper variables
    colname = paste("s",i,sep=".")
    pred.type = ifelse(class(trainData[,res.ind])=="factor","class","vector")
    # merge variable importance
    imp = data.frame(names(mod$variable.importance), mod$variable.importance)
    colnames(imp) = c("var", colname)
    var.imp = merge(var.imp, imp, by="var", all=TRUE)
  }
  # adjust outcome
  rownames(var.imp) = var.imp[,1]
  var.imp = var.imp[,2:ncol(var.imp)]
  
  # create outcome as a list
  result=list(var.imp = var.imp)
  class(result) = c("rpartbgg")
  result
}
{% endhighlight %}

If the total number of trees are split into clusters (eg into 4 clusters), there will be 4 lists and it is possible to *combine* them. Below is an example of such a function (`comBGG()`) - it just sums individual variable importance values. 

Specifically 

1. arguments shouldn't be dertermined (*...*) as the number of clusters can vary (an thus the number of lists) 
2. a list is created that binds the variable number of arguments (`list(...)`)
3. only the elements that keeps variable importance are extracted into another list by `lapply()` 
4. the new list of variable importance values can be restructured using `do.call()` and `cbind()`
5. finally each row values are added by `apply()`


{% highlight r %}
# combine variable importance of bagged trees
comBGG = function(...) {
  # add rpart objects in a list
  bgglist = list(...)
  # extract variable importance
  var.imp = lapply(bgglist, function(x) x$var.imp)
  # combine and sum by row
  var.imp = do.call("cbind", var.imp)
  var.imp = apply(var.imp, 1, sum, na.rm=TRUE)
  var.imp
}
{% endhighlight %}

### parallel package

Similar to the above example, bagged trees are generated across clusters using `cartBGG()`. Then the result is combined by `comBGG()`.


{% highlight r %}
# data
library(ISLR)
data(Carseats)

# parallel
split = detectCores()
eachTree = 250

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
# rpart is required in cartBGG(), not need to load in each cluster
results = parLapplyLB(cl
                      ,rep(eachTree, split)
                      ,cartBGG, formula="Sales ~ .", trainData=Carseats, ntree=eachTree)
result = do.call("comBGG", results)
stopCluster(cl)

result
{% endhighlight %}



{% highlight text %}
## Advertising         Age   CompPrice   Education      Income  Population 
##   295646.22   366140.36   514889.28   144642.19   271524.31   232959.06 
##       Price   ShelveLoc       Urban          US 
##   964252.07   978758.83    24794.35    80023.66
{% endhighlight %}

### foreach package

This example is simplar to the random forest example. Note that *.multicombine* determines how many arguments are combined. For performance, the maximum number is 100 if the value is *TRUE* and 2 if *FALSE* by default (*.maxcombine=if (.multicombine) 100 else 2*). As there are more than 2 lists in this example, it should be set *TRUE* so that all lists generated by the clusters can be combined.


{% highlight r %}
# foreach
split = detectCores()
eachTrees = 250
# set up iterators
iters = iter(rep(eachTrees, split))

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
registerDoParallel(cl)
# note .multicombine=TRUE as > 2 arguments
# .maxcombine=if (.multicombine) 100 else 2
result = foreach(ntree=iters, .combine="comBGG", .multicombine=TRUE) %dopar%
  cartBGG(formula="Sales ~ .", trainData=Carseats, ntree=ntree)
stopCluster(cl)

result
{% endhighlight %}



{% highlight text %}
## Advertising         Age   CompPrice   Education      Income  Population 
##   295646.22   366140.36   514889.28   144642.19   271524.31   232959.06 
##       Price   ShelveLoc       Urban          US 
##   964252.07   978758.83    24794.35    80023.66
{% endhighlight %}

Three practical examples of implementing parallel processing in a single machine are discussed in this post. They are relatively easy to implement and all existing packages can be used directly. I hope this series of posts are useful.
