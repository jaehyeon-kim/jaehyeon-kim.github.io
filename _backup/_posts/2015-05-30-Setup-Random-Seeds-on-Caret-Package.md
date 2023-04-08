---
layout: post
title: "2015-05-30-Setup-Random-Seeds-on-Caret-Package"
description: ""
category: R
tags: [parallel, doParallel, foreach, randomForest, caret]
---
A short while ago I had a chance to perform analysis using the **caret** package. One of the requirements is to run it parallelly and to work in both Windows and Linux. The requirement can be met by using the **parallel** and **doParallel** packages as the **caret** package trains a model using the **foreach** package if clusters are registered by the **doParallel** package - further details about how to implement parallel processing on a single machine can be found in earlier posts ([Link 1](http://jaehyeon-kim.github.io/r/2015/03/14/Parallel-Processing-on-Single-Machine-Part-I/), [Link 2](http://jaehyeon-kim.github.io/r/2015/03/17/Parallel-Processing-on-Single-Machine-Part-II/) and [Link 3](http://jaehyeon-kim.github.io/r/2015/03/19/Parallel-Processing-on-Single-Machine-Part-III/)). While it is relatively straightforward to train a model across multiple clusters using the **caret** package, setting up random seeds may be a bit tricky. As analysis can be more reproducible by random seeds, a way of setting them up is illustrated using a simple function in this post.

The following packages are used.


{% highlight r %}
library(parallel)
library(doParallel)
library(randomForest)
library(caret)
{% endhighlight %}

In the **caret** package, random seeds are set up by adjusting the argument of *seeds* in `trainControl()` and the object document illustrates it as following.

+ **seeds** - an optional set of integers that will be used to set the seed at each resampling iteration. This is useful when the models are run in parallel. A value of **NA** will stop the seed from being set within the worker processes while a value of **NULL** will set the seeds using a random set of integers. Alternatively, **a list can be used**. The list should have *B+1* elements where *B is the number of resamples*. The first B elements of the list should be vectors of integers of length M where *M is the number of models being evaluated*. The last element of the list only needs to be a single integer (for the final model). See the Examples section below and the Details section.

Setting *seeds* to either *NA* or *NULL* wouldn't guarantee a full control of resampling so that a *custom list* would be necessary. Here `setSeeds()` creats the custom list and it handles only (repeated) cross validation and it returns *NA* if a different resampling method is specified - this function is based on the [source code](https://github.com/topepo/caret/blob/master/pkg/caret/R/train.default.R). Specifically *B* is determined by the number of folds (*numbers*) or the number of repeats of it (*numbers x repeats*). Then a list of *B* elements are generated where each element is an integer vector of length *M*. *M* is the sum of the number of folds (*numbers*) and the length of the tune grid (*tunes*). Finally an integer vector of length 1 is added to the list.


{% highlight r %}
# function to set up random seeds
setSeeds <- function(method = "cv", numbers = 1, repeats = 1, tunes = NULL, seed = 1237) {
  #B is the number of resamples and integer vector of M (numbers + tune length if any)
  B <- if (method == "cv") numbers
  else if(method == "repeatedcv") numbers * repeats
  else NULL
  
  if(is.null(length)) {
    seeds <- NULL
  } else {
    set.seed(seed = seed)
    seeds <- vector(mode = "list", length = B)
    seeds <- lapply(seeds, function(x) sample.int(n = 1000000, size = numbers + ifelse(is.null(tunes), 0, tunes)))
    seeds[[length(seeds) + 1]] <- sample.int(n = 1000000, size = 1)
  }
  # return seeds
  seeds
}
{% endhighlight %}

Below shows the control variables of the resampling methods used in this post: k-fold cross validation and repeated k-fold cross validation. Here (5 repeats of) 3-fold cross validation is chosen. Also a grid is set up to tune *mtry* of `randomForest()` (*cvTunes*) and *rcvTunes* is for tuning the number of nearest neighbours of `knn()`.


{% highlight r %}
# control variables
numbers <- 3
repeats <- 5
cvTunes <- 4 # tune mtry for random forest
rcvTunes <- 12 # tune nearest neighbor for KNN
seed <- 1237
{% endhighlight %}

Random seeds for 3-fold cross validation are shown below - *B + 1* and *M* equal to 4 (3 + 1) and 7 (3 + 4) respectively.


{% highlight r %}
# cross validation
cvSeeds <- setSeeds(method = "cv", numbers = numbers, tunes = cvTunes, seed = seed)
c('B + 1' = length(cvSeeds), M = length(cvSeeds[[1]]))
{% endhighlight %}



{% highlight text %}
## B + 1     M 
##     4     7
{% endhighlight %}



{% highlight r %}
cvSeeds[c(1, length(cvSeeds))]
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] 328213 983891  24236 118267 196003 799071 956708
## 
## [[2]]
## [1] 710446
{% endhighlight %}

Random seeds for 5 repeats of 3-fold cross validation are shown below - *B + 1* and *M* equal to 16 (3 x 5 + 1) and 15 (3 + 12) respectively.


{% highlight r %}
# repeated cross validation
rcvSeeds <- setSeeds(method = "repeatedcv", numbers = numbers, repeats = repeats, 
                     tunes = rcvTunes, seed = seed)
c('B + 1' = length(rcvSeeds), M = length(rcvSeeds[[1]]))
{% endhighlight %}



{% highlight text %}
## B + 1     M 
##    16    15
{% endhighlight %}



{% highlight r %}
rcvSeeds[c(1, length(rcvSeeds))]
{% endhighlight %}



{% highlight text %}
## [[1]]
##  [1] 328213 983891  24236 118267 196003 799071 956708 395670 826198 863837
## [11] 119602 864078 177322 382935 513432
## 
## [[2]]
## [1] 751240
{% endhighlight %}

Given the random seeds, train controls are set up as shown below.


{% highlight r %}
# cross validation
cvCtrl <- trainControl(method = "cv", number = numbers, classProbs = TRUE,
                       savePredictions = TRUE, seeds = cvSeeds)
# repeated cross validation
rcvCtrl <- trainControl(method = "repeatedcv", number = numbers, repeats = repeats,
                        classProbs = TRUE, savePredictions = TRUE, seeds = rcvSeeds)
{% endhighlight %}

They are tested by comparing the two learners: *knn* and *randomForest*. Each of the two sets of objects are the same except for *times* elements, which are not related to model reproduciblility.


{% highlight r %}
# repeated cross validation
cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
KNN1 <- train(Species ~ ., data = iris, method = "knn", tuneLength = rcvTunes, trControl = rcvCtrl)
stopCluster(cl)

cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
KNN2 <- train(Species ~ ., data = iris, method = "knn", tuneLength = rcvTunes, trControl = rcvCtrl)
stopCluster(cl)

# same outcome, difference only in times element
all.equal(KNN1$results[KNN1$results$k == KNN1$bestTune[[1]],], 
          KNN2$results[KNN2$results$k == KNN2$bestTune[[1]],])
{% endhighlight %}



{% highlight text %}
## [1] TRUE
{% endhighlight %}



{% highlight r %}
all.equal(KNN1, KNN2)
{% endhighlight %}



{% highlight text %}
## [1] "Component \"times\": Component \"everything\": Mean relative difference: 0.02158273"
{% endhighlight %}



{% highlight r %}
# cross validation
cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
rf1 <- train(Species ~ ., data = iris, method = "rf", ntree = 100,
             tuneGrid = expand.grid(mtry = seq(1, 2 * as.integer(sqrt(ncol(iris) - 1)), by = 1)),
             importance = TRUE, trControl = cvCtrl)
stopCluster(cl)

cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
rf2 <- train(Species ~ ., data = iris, method = "rf", ntree = 100,
             tuneGrid = expand.grid(mtry = seq(1, 2 * as.integer(sqrt(ncol(iris) - 1)), by = 1)),
             importance = TRUE, trControl = cvCtrl)
stopCluster(cl)

# same outcome, difference only in times element
all.equal(rf1$results[rf1$results$mtry == rf1$bestTune[[1]],], 
          rf2$results[rf2$results$mtry == rf2$bestTune[[1]],])
{% endhighlight %}



{% highlight text %}
## [1] TRUE
{% endhighlight %}



{% highlight r %}
all.equal(rf1, rf2)
{% endhighlight %}



{% highlight text %}
## [1] "Component \"times\": Component \"everything\": Mean relative difference: 0.01735016"
## [2] "Component \"times\": Component \"final\": Mean relative difference: 0.6666667"
{% endhighlight %}

I hope this post may be helpful to improve reproducibility of analysis using the **caret** package.
