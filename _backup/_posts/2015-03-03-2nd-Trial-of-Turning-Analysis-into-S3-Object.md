---
layout: post
title: "2015-03-03-2nd-Trial-of-Turning-Analysis-into-S3-Object"
description: ""
category: R
tags: [rpart, caret, mlr, dplyr, programming]
---
In order to avoid an error that could be caused by conflicting variable names and to keep variables in a more effective way, a trial of turning analysis into a S3 object is made in a ([previous article](http://jaehyeon-kim.github.io/r/2015/02/21/Quick-Trial-of-Turning-Analysis-into-S3-Object/)). The second trial is made recently and a class (*rpartDT*) that extends *rpartExt* is introduced in this article. In line with the first trial, the base class keeps key outcomes of the CART model in a list and the extended class includes outcomes of bagged trees as well as those of the base class. As the main purpose of this class is to evaluate performance of an individual tree, its bagging implementation is a bit different from the conventional one. Specifically, while unpruned trees are fit recursively in the conventional bagging so that bias-variance trade-off could be improved mainly due to lowered variance, it performs with the *cp* values set at the lowest xerror and by the 1-SE rule. Also other control variables are untouched (eg *minbucket* is 20 at default).

The class is constructed so as to produce the following outcomes.

**Error (mean misclassification error or root mean squared error)**

- Error distribution of each bagged tree (individual error)
    + As [Hastie et al.(2008)](http://statweb.stanford.edu/~tibs/ElemStatLearn/) illustrates, non-parametric bootstrap is a computer implementation of non-parametric maximum likelyhood estimation and Bayesian analysis with non-informative prior. Therefore it would be helpful to see the location of a single tree's error in the distribution of individual bagged trees.
- Majority vote or average (cumulative error)
    + By averaging overfit and thus unstable outcomes of a single tree, bagging could provide better results and comparison between them would be necessary.
- Out-of-bag (oob) error
    + With sampling with replacement, the probability that a record is not taken is $$\left(1-\frac{1}{n}\right)$$ and that of n records is $$\left(1-\frac{1}{n}\right)^n = e^{-1}$$ as n goes to infinity (about 36.8% of records are not taken). These records can be used to produce errors if there is no test data available.
- Test error (if exists)
    + It would be even better if a single tree's error is compared to that of independent test data.

**Variable importance**

- This is to see if a single tree's variable importance is far different from that of bagged trees.
- The **rpart** package provides variable importance and it'd be helpful if cumulative variable importance is used for comparison.

Before getting started, note that the source of the classes can be found in [this gist](https://gist.github.com/jaehyeon-kim/b89dcbd2fb0b84fd236e) and, together with the relevant packages (see *tags*), it requires a utility function (`bestParam()`) that can be found [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).

The bootstrap samples are created using the **mlr** package (`makeResampleInstance()`). Note that a sample is discarded if the *cp* values are not obtained - *cnt* is added by 1 only if the sum of *cp* values is not 0 where 0 is assigned as *cp* values when an error is encountered (see the *tryCatch* block).


{% highlight r %}
cnt = 0
while(cnt < ntree) {
  # create resample description and task
  if(class(trainData[,res.ind]) != "factor") {
    boot.desc = makeResampleDesc(method="Bootstrap", stratify=FALSE, iters=1)
    boot.task = makeRegrTask(data=trainData,target=res.name)
  } else {
    # isStratify set to FALSE by default
    boot.desc = makeResampleDesc(method="Bootstrap", stratify=isStratify, iters=1)
    boot.task = makeClassifTask(data=trainData,target=res.name)
  }
  # create bootstrap instance and split data - in-bag and out-of-bag
  boot.ins = makeResampleInstance(desc=boot.desc, task=boot.task) 
  trn.in = trainData[boot.ins$train.inds[[1]],]
  trn.oob = trainData[boot.ins$test.inds[[1]],]
  # fit model on in-bag sample
  mod = rpart(formula=formula, data=trn.in, control=rpart.control(cp=0))
  cp = tryCatch({
    unlist(bestParam(mod$cptable,"CP","xerror","xstd")[1,1:2])
  },
  error=function(cond) { 
    message("cp fails to be generated. The sample is discarded.")
    cp = c(0,0)
  })
  # take sample only if cp values are obtained
  if(sum(cp) != 0) {
    cnt = cnt + 1
  ...
}
{% endhighlight %}

Data is split as usual.


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
{% endhighlight %}

The class is instantiated after importing the constructors.


{% highlight r %}
## run rpartDT
# import constructors
source("src/cart.R")
set.seed(12357)
cl = cartDT(trainData.cl, testData.cl, "High ~ .", ntree=10)
{% endhighlight %}

The naming rule is shown below.

- rpt - single tree
- lst - *cp* at the least *xerror*
- se - *cp* by the *1-SE Rule*
- oob (test) - out-of-bag (test) data
- ind (cum) - individual (cumulative) values


{% highlight r %}
names(cl)
{% endhighlight %}



{% highlight text %}
##  [1] "rpt"             "boot.cp"         "varImp.lst"     
##  [4] "ind.varImp.lst"  "cum.varImp.lst"  "varImp.se"      
##  [7] "ind.varImp.se"   "cum.varImp.se"   "ind.oob.lst"    
## [10] "ind.oob.lst.err" "cum.oob.lst"     "cum.oob.lst.err"
## [13] "ind.oob.se"      "ind.oob.se.err"  "cum.oob.se"     
## [16] "cum.oob.se.err"  "ind.tst.lst"     "ind.tst.lst.err"
## [19] "cum.tst.lst"     "cum.tst.lst.err" "ind.tst.se"     
## [22] "ind.tst.se.err"  "cum.tst.se"      "cum.tst.se.err"
{% endhighlight %}

The summary of the *cp* values of the bagged trees are shown below, followed by the single tree's *cp* value at the least *xerror*.


{% highlight r %}
## cp values
# cart
cl$rpt$cp[1,][[1]]
{% endhighlight %}



{% highlight text %}
## [1] 0.01136364
{% endhighlight %}



{% highlight r %}
# bagging
summary(t(cl$boot.cp)[,2])
{% endhighlight %}



{% highlight text %}
##     Min.  1st Qu.   Median     Mean  3rd Qu.     Max. 
## 0.000000 0.000000 0.003788 0.005303 0.007576 0.022730
{% endhighlight %}

Selective individual and cumulative fitted values are shown below. Don't be confused with the first column as it is the response values of the entire training data - each fitted value column has its own sample number.


{% highlight r %}
## fitted values
# individual - each oob sample
cl$ind.oob.lst[3:6,1:8]
{% endhighlight %}



{% highlight text %}
##    res  s.1  s.2  s.3  s.4  s.5  s.6  s.7
## 3 High <NA> <NA>   No   No   No   No   No
## 4   No <NA> <NA>   No High High <NA> High
## 6 High <NA> High <NA> <NA> High <NA>   No
## 7   No <NA> <NA> <NA> <NA> High   No   No
{% endhighlight %}



{% highlight r %}
# cumulative - majority vote or average
# 1. not used - NA, 2. used once - get name, 3. tie - NA, 4. name at max number of labels
cl$cum.oob.lst[3:6,1:8]
{% endhighlight %}



{% highlight text %}
##    res  s.1  s.2  s.3  s.4  s.5  s.6  s.7
## 3 High <NA> <NA>   No   No   No   No   No
## 4   No <NA> <NA>   No <NA> High High High
## 6 High <NA> High High High High High High
## 7   No <NA> <NA> <NA> <NA> High <NA>   No
{% endhighlight %}

Given a data frame of fitted values of individual trees (*fit*), the fitted values are averaged depending on the class of the respose - majority vote if *factor* or average if *numeric*. For a *numeric* response, `average()` is applied in an expanding way column-wise while a vectorized function (`retVote()`) is created for a *factor* response with the following rules in order.

1. if no fitted value (table length = 0), assign *NA*
2. if a single fitted value (table length = 1), assign *name* of it
3. if there is a tie, assgin *NA*
4. finally take the *name* of the level that occupies most

Note that, as the first column has response values, it is excluded and, although `retCum()` updates values in a way that is vectorized row-wise, it has to be 'for-looped' column-wise. By far this part is the biggest bottleneck and it should be enhanced in the future - the way how *factor* response variables are updated makes it longer to perform classification tasks.


{% highlight r %}
# function to update fitted values - majority vote or average
# response kept in 1st column, should be excluded
retCum = function(fit) {
  if(ncol(fit) < 2) {
    message("no fitted values")
    cum.fit = fit
  } else {
    cum.fit = as.data.frame(apply(fit,2,function(x) { rep(0,times=(nrow(fit))) }))
    cum.fit[,1:2] = fit[,1:2]
    rownames(cum.fit) = rownames(fit)
    for(i in 3:ncol(fit)) {
      if(class(fit[,1])=="factor") {
        retVote = function(x) {
          tbls = apply(x,1,as.data.frame)
          tbls = lapply(tbls,table)
          ret = function(x) {
            if(length(x)==0) NA 
            else if(length(x)==1) names(x) 
            else if(max(x)==min(x)) NA 
            else names(x[x==max(x)])
          }
          maxVal = sapply(tbls,ret)
          maxVal
        }
        cum.fit[,i] = retVote(fit[,2:i]) # retVote already vectorized
      } else {
        cum.fit[,i] = apply(fit[,2:i],1,mean,na.rm=TRUE)
      }
    }  
  }
  cum.fit
}
{% endhighlight %}

Given a data frame of fitted values (*fit*), *mmce* or *rmse* are obtained depending on the class of the response. Note that, as the first column has response values, it is excluded.


{% highlight r %}
# function to updated errors - mmce or rmse
# response kept in 1st column, should be excluded
retErr = function(fit) {
  err = data.frame(t(rep(0,times=ncol(fit))))
  colnames(err)=colnames(fit)
  for(i in 2:ncol(fit)) {
    cmpt = complete.cases(fit[,1],fit[,i])
    if(class(fit[,1])=="factor") {
      tbl=table(fit[cmpt,1],fit[cmpt,i])
      err[i] = 1 - sum(diag(tbl))/sum(tbl)
    } else {
      err[i] = sqrt(sum(fit[cmpt,1]-fit[cmpt,i])^2/length(fit[cmpt,1]))
    }    
  }
  err[2:length(err)]
}
{% endhighlight %}

Selective individual and cumulative errors of bagged trees are shown below.


{% highlight r %}
# individual error
round(cl$ind.oob.lst.err[1:7],4)
{% endhighlight %}



{% highlight text %}
##      s.1   s.2    s.3    s.4    s.5    s.6    s.7
## 1 0.3417 0.248 0.2373 0.3471 0.2437 0.3162 0.3017
{% endhighlight %}



{% highlight r %}
# cumulative error
round(cl$cum.oob.lst.err[1:7],4)
{% endhighlight %}



{% highlight text %}
##      s.1    s.2    s.3    s.4  s.5    s.6    s.7
## 1 0.3417 0.2697 0.2691 0.2445 0.25 0.2564 0.2399
{% endhighlight %}

Importance of each variable of the single and bagged trees is found below.


{% highlight r %}
## variable importance
# cart
data.frame(variable=names(cl$rpt$mod$variable.importance)
           ,value=cl$rpt$mod$variable.importance/sum(cl$rpt$mod$variable.importance)
           ,row.names=NULL)
{% endhighlight %}



{% highlight text %}
##      variable       value
## 1       Price 0.331472010
## 2   ShelveLoc 0.292989310
## 3         Age 0.105875102
## 4 Advertising 0.100231974
## 5   CompPrice 0.085284347
## 6      Income 0.067056406
## 7  Population 0.014197379
## 8   Education 0.002893471
{% endhighlight %}



{% highlight r %}
# bagging - cumulative
ntree = 10
data.frame(variable=rownames(cl$cum.varImp.lst)
           ,value=cl$cum.varImp.lst[,ntree])
{% endhighlight %}



{% highlight text %}
##       variable      value
## 1  Advertising 0.10420483
## 2          Age 0.13376989
## 3    CompPrice 0.14935661
## 4    Education 0.03494124
## 5       Income 0.08071209
## 6   Population 0.06293981
## 7        Price 0.21012575
## 8    ShelveLoc 0.16739729
## 9        Urban 0.01013187
## 10          US 0.04642062
{% endhighlight %}

In the next two articles, the CART analysis will be evaluated using the same data as regression and classification tasks.

<script src='http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' type="text/javascript"></script>