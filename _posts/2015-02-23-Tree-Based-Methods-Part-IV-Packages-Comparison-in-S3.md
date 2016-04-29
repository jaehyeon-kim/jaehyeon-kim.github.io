---
layout: post
title: "2015-02-23-Tree-Based-Methods-Part-IV-Packages-Comparison-in-S3"
description: ""
category: R
tags: [ggplot2, rpart, caret, mlr, programming]
---
In the [previous article](http://jaehyeon-kim.github.io/r/2015/02/21/Quick-Trial-of-Turning-Analysis-into-S3-Object/), a brief introduction to the S3 object is made as well as a class that encapsulates the CART analysis by the **rpart** package is illustrated. Extending an [earlier article](http://jaehyeon-kim.github.io/r/2015/02/15/Tree-Based-Methods-Part-IV-Packages-Comparison/) of comparing the three packages (**rpart**, **caret** and **mlr**), this article compares them using the following 3 S3 objects: *rpartExt*, *rpartExtCrt* and *rpartExtMlr*. Like *manager* **is-a** *employee* so that it can extends the base class in the previous article, it is roughly conceptualized that the last two classes extend the first. On this setting, performance of both classification and regression tasks are compared in this article.

Before getting started, note that the source of these classes can be found in [this gist](https://gist.github.com/jaehyeon-kim/b89dcbd2fb0b84fd236e) and, together with the relevant packages, it requires 3 utility functions that can be found [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).

Let's get started.

The data is split for both classification and regression.


{% highlight r %}
## data
require(ISLR)
data(Carseats)
require(dplyr)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data.cl = subset(Carseats, select=c(-Sales))
data.rg = subset(Carseats, select=c(-High))

# split - cl: classification, rg: regression
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.cl = data.cl[trainIndex,]
testData.cl = data.cl[-trainIndex,]
trainData.rg = data.rg[trainIndex,]
testData.rg = data.rg[-trainIndex,]
{% endhighlight %}

The constructors are sourced.


{% highlight r %}
## import constructors
source("src/cart.R")
{% endhighlight %}

The classification task is fit by each of the packages. Note that the constructors of the subclasses (*rpartExtCrt* and *rpartExtMlr*) have an option to fit data using the base class (*rpartExt*) and it is determined by the argument of *fitInd*. Once it is set *TRUE*, the constructor of the base class is executed (or the base class is instantiated), resulting that its outcome (named *rpt*) is kept as a member of the outcome list. Otherwise a null list is added as a placeholder.


{% highlight r %}
## classification
set.seed(12357)
rpt.cl = cartRPART(trainData.cl,testData.cl,formula="High ~ .")
crt.cl = cartCARET(trainData.cl,testData.cl,formula="High ~ .",fitInd=TRUE)
mlr.cl = cartMLR(trainData.cl,testData.cl,formula="High ~ .",fitInd=TRUE)
{% endhighlight %}

Class and names attributes of each object can be seen below. As the latter two are assumed to extend the first, their class attributes include the class name of the first. Also, as *fitInd* is set *TRUE*, the base class is instantiated, which can be checked that the names attributes of *rpt.cl* and *crt.cl$rpt* are the same.


{% highlight r %}
## classes and attributes
data.frame(rpart=c(class(rpt.cl),""),caret=class(crt.cl),mlr=class(mlr.cl))
{% endhighlight %}



{% highlight text %}
##      rpart       caret         mlr
## 1 rpartExt rpartExtCrt rpartExtMlr
## 2             rpartExt    rpartExt
{% endhighlight %}



{% highlight r %}
attributes(rpt.cl)$names
{% endhighlight %}



{% highlight text %}
## [1] "mod"       "cp"        "train.lst" "train.se"  "test.lst"  "test.se"
{% endhighlight %}



{% highlight r %}
attributes(crt.cl)$names
{% endhighlight %}



{% highlight text %}
## [1] "rpt"       "mod"       "cp"        "train.lst" "test.lst"
{% endhighlight %}



{% highlight r %}
attributes(mlr.cl)$names
{% endhighlight %}



{% highlight text %}
## [1] "rpt"       "task"      "learner"   "mod"       "cp"        "train.lst"
## [7] "test.lst"
{% endhighlight %}



{% highlight r %}
attributes(crt.cl$rpt)$names
{% endhighlight %}



{% highlight text %}
## [1] "mod"       "cp"        "train.lst" "train.se"  "test.lst"  "test.se"
{% endhighlight %}

The performance of the classfication task is compared and, as seen earlier, the classification tree is not sensitive to *cp* values.


{% highlight r %}
# comparison
perf.cl = list(rpt.cl$train.lst$error,rpt.cl$train.se$error
               ,rpt.cl$test.lst$error,rpt.cl$test.se$error
               ,crt.cl$train.lst$error,crt.cl$test.lst$error
               ,mlr.cl$train.lst$error,mlr.cl$test.lst$error)

err = function(perf) {
  out = list(unlist(perf[[1]]))
  for(i in 2:length(perf)) {
    out[[length(out)+1]] = unlist(perf[[i]])
  }
  t(sapply(out,unlist))
}

err(perf.cl)
{% endhighlight %}



{% highlight text %}
##      pkg     isTest  isSE    cp       error 
## [1,] "rpart" "FALSE" "FALSE" "0.0114" "0.16"
## [2,] "rpart" "FALSE" "TRUE"  "0.1061" "0.29"
## [3,] "rpart" "TRUE"  "FALSE" "0.0114" "0.19"
## [4,] "rpart" "TRUE"  "TRUE"  "0.1061" "0.3" 
## [5,] "caret" "FALSE" "FALSE" "0.0204" "0.16"
## [6,] "caret" "TRUE"  "FALSE" "0.0204" "0.19"
## [7,] "mlr"   "FALSE" "FALSE" "0.02"   "0.16"
## [8,] "mlr"   "TRUE"  "FALSE" "0.02"   "0.19"
{% endhighlight %}

Then the data is fit as regression. Note that the default *fitInd* value is *FALSE* and the base class is not instantiated.


{% highlight r %}
## regression
set.seed(12357)
rpt.rg = cartRPART(trainData.rg,testData.rg,formula="Sales ~ .")
crt.rg = cartCARET(trainData.rg,testData.rg,formula="Sales ~ .")
mlr.rg = cartMLR(trainData.rg,testData.rg,formula="Sales ~ .")
{% endhighlight %}

The performance of the regression task is compared below. It is found that, unlike the classification task, the *cp* plays a more role. 

Specifically 

- the value (*0.0049*) at the minimum *xerror* by the **rpart** package records the least *RMSE* (*0,74*)
- the *1-SE rule* is also questionable by delivering the highest *RMSE* (*1.96*)
- the best *cp* value by the **caret** and **mlr** packages is *0* and the resulting *RMSE* (*0.95*) is higher


{% highlight r %}
# comparison
perf.rg = list(rpt.rg$train.lst$error,rpt.rg$train.se$error
               ,rpt.rg$test.lst$error,rpt.rg$test.se$error
               ,crt.rg$train.lst$error,crt.rg$test.lst$error
               ,mlr.rg$train.lst$error,mlr.rg$test.lst$error)

err(perf.rg)
{% endhighlight %}



{% highlight text %}
##      pkg     isTest  isSE    cp       error     
## [1,] "rpart" "FALSE" "FALSE" "0.0049" "0"       
## [2,] "rpart" "FALSE" "TRUE"  "0.0093" "0"       
## [3,] "rpart" "TRUE"  "FALSE" "0.0049" "0.737656"
## [4,] "rpart" "TRUE"  "TRUE"  "0.0093" "1.955439"
## [5,] "caret" "FALSE" "FALSE" "0"      "0"       
## [6,] "caret" "TRUE"  "FALSE" "0"      "0.952237"
## [7,] "mlr"   "FALSE" "FALSE" "0"      "0"       
## [8,] "mlr"   "TRUE"  "FALSE" "0"      "0.952237"
{% endhighlight %}

The last is due to the way how the grids are set up in these packages. The *tuneLength* of the **caret** package is set to *30* so that the *cp* increments roughly by *0.01* and the increment is set to be exact in the **mlr** package. Therefore the grids cannot check the impact of *cp* values in the third or higher decimal points - if the increment were set to be *0.005* (*tuneLength=60*), their performance would be similar. However (1) it cannot be anticipated how precisely a grid should be constructed and (2) it can cost too much if the size of a grid is quite high. Therefore another strategy of construcing a grid would be necessary. A quick idea is a sequential fit, which fits with a default grid (eg *tuneLenght=20*) at first so as to select sub-ranges of *cp* values and then fits with finer grids in those sub-ranges. It would also be necessary to look into the source of the **rpart** package to see if it is possible to replicate its method.


{% highlight r %}
head(crt.rg$mod$result,3)
{% endhighlight %}



{% highlight text %}
##            cp     RMSE  Rsquared    RMSESD RsquaredSD
## 1 0.000000000 2.188466 0.4553325 0.2935515  0.1307225
## 2 0.008840786 2.263287 0.4187306 0.2943552  0.1320449
## 3 0.017681573 2.359903 0.3664765 0.2680164  0.1200120
{% endhighlight %}
