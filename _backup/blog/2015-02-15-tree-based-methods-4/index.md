---
layout: post
title: "2015-02-15-Tree-Based-Methods-Part-IV-Packages-Comparison"
description: ""
category: R
tags: [reshape2, plyr, dplyr, ggplot2, rpart, caret, mlr]
---
While the last three articles illustrated the CART model for both classification (with equal/unequal costs) and regression tasks, this article is rather technical as it compares three packages: **rpart**, **caret** and **mlr**. For those who are not farmiliar with the last two packages, they are wrappers (or frameworks) that implement a range of models (or algorithms) in a unified way. For example, the CART implementation of the **rpart** package can also be performed in these packages as an integrated learner. As mentioned in an earlier article ([Link](http://jaehyeon-kim.github.io/r/2015/01/17/First-Look-on-MLR/)), inconsistent API could be a drawback of R (like other open source tools) and it would be quite beneficial if there is a way to implement different models in a standardized way. In line with the earlier articles, the *Carseats* data is used for a classification task.

Before getting started, I should admit the names are not defined effectively. I hope the below list may be helpful to follow the script.

- package: **rpt** - rpart, **crt** - caret, **mlr** - mlr
- model fitting: **ftd** - fit on training data, **ptd** - fit on test data
- parameter selection
    - **bst** - best *cp* by *1-SE rule* (recommended by **rpart**)
    - **lst** - best *cp* by highest *accuracy* (**caret**) or lowest *mmce* (**mlr**)
- cost: **eq** - equal cost, **uq** - unequal cost (*uq* case not added in this article)
- etc: **cp** - complexity parameter, **mmce** - mean misclassification error, **acc** - Accuracy (**caret**), **cm** - confusion matrix

Also the data is randomly split into **trainData** and **testData**. In practice, the latter is not observed and it is used here for evaludation.

Let's get started.

The following packages are used.


{% highlight r %}
library(reshape2)
library(plyr)
library(dplyr)
library(ggplot2)
library(rpart)
library(caret)
library(mlr)
{% endhighlight %}

The *Sales* column is converted into a binary variables.


{% highlight r %}
## data
require(ISLR)
data(Carseats)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data = subset(Carseats, select=c(-Sales))
{% endhighlight %}

Balanced splitting of data can be performed in either of the packages as shown below.


{% highlight r %}
## split data
# caret
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.caret = data[trainIndex,]
testData.caret = data[-trainIndex,]

# mlr
set.seed(1237)
split.desc = makeResampleDesc(method="Holdout", stratify=TRUE, split=0.8)
split.task = makeClassifTask(data=data,target="High")
resampleIns = makeResampleInstance(desc=split.desc, task=split.task)
trainData.mlr = data[resampleIns$train.inds[[1]],]
testData.mlr = data[-resampleIns$train.inds[[1]],]

# response summaries
train.res.caret = with(trainData.caret,rbind(table(High),table(High)/length(High)))
train.res.caret
{% endhighlight %}



{% highlight text %}
##            High         No
## [1,] 132.000000 189.000000
## [2,]   0.411215   0.588785
{% endhighlight %}



{% highlight r %}
train.res.mlr = with(trainData.mlr,rbind(table(High),table(High)/length(High)))
train.res.mlr
{% endhighlight %}



{% highlight text %}
##             High          No
## [1,] 131.0000000 188.0000000
## [2,]   0.4106583   0.5893417
{% endhighlight %}



{% highlight r %}
test.res.caret = with(testData.caret,rbind(table(High),table(High)/length(High)))
test.res.caret
{% endhighlight %}



{% highlight text %}
##            High         No
## [1,] 32.0000000 47.0000000
## [2,]  0.4050633  0.5949367
{% endhighlight %}



{% highlight r %}
test.res.mlr = with(testData.mlr,rbind(table(High),table(High)/length(High)))
test.res.mlr
{% endhighlight %}



{% highlight text %}
##            High         No
## [1,] 33.0000000 48.0000000
## [2,]  0.4074074  0.5925926
{% endhighlight %}

Same to the previous articles, the split by the **caret** package is taken.


{% highlight r %}
# data from caret is taken in line with previous articles
trainData = trainData.caret
testData = testData.caret
{% endhighlight %}

Note that two custom functions are used: `bestParam()` and `updateCM()`. The former searches the *cp* values by the *1-SE rule* (**bst**) and at the lowest *xerror* (**lst**) from the cp table of a *rpart* object. The latter produces a confusion matrix with model and use error, added to the last column and row respectively. Their sources can be seen [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).


{% highlight r %}
source("src/mlUtils.R")
{% endhighlight %}

At first, the model is fit using the **rpart** package and **bst** and **lst** *cp* values are obtained.


{% highlight r %}
### rpart
## train on training data
set.seed(12357)
mod.rpt.eq = rpart(High ~ ., data=trainData, control=rpart.control(cp=0))
mod.rpt.eq.par = bestParam(mod.rpt.eq$cptable,"CP","xerror","xstd")
mod.rpt.eq.par
{% endhighlight %}



{% highlight text %}
##            lowest       best
## param  0.01136364 0.10606061
## error  0.65909091 0.70454545
## errStd 0.06033108 0.06157189
{% endhighlight %}

The selected *cp* values can be check graphically below. 


{% highlight r %}
# plot xerror vs cp
df = as.data.frame(mod.rpt.eq$cptable)
best = mod.rpt.eq.par
ubound = ifelse(best[2,1]+best[3,1]>max(df$xerror),max(df$xerror),best[2,1]+best[3,1])
lbound = ifelse(best[2,1]-best[3,1]<min(df$xerror),min(df$xerror),best[2,1]-best[3,1])

ggplot(data=df[1:nrow(df),], aes(x=CP,y=xerror)) + 
  geom_line() + geom_point() +   
  geom_abline(intercept=ubound,slope=0, color="purple") + 
  geom_abline(intercept=lbound,slope=0, color="purple") + 
  geom_point(aes(x=best[1,2],y=best[2,2]),color="red",size=3) + 
  geom_point(aes(x=best[1,1],y=best[2,1]),color="blue",size=3)
{% endhighlight %}

![center](/figs/2015-02-15-Tree-Based-Methods-Part-IV-Packages-Comparison/rpart_cp_graph-1.png) 

The original tree is pruned with the 2 *cp* values, resulting in 2 separate trees, and they are fit on the training data.


{% highlight r %}
## performance on train data
mod.rpt.eq.lst.cp = mod.rpt.eq.par[1,1]
mod.rpt.eq.bst.cp = mod.rpt.eq.par[1,2]
# prune
mod.rpt.eq.lst = prune(mod.rpt.eq, cp=mod.rpt.eq.lst.cp)
mod.rpt.eq.bst = prune(mod.rpt.eq, cp=mod.rpt.eq.bst.cp)

# fit to train data
mod.rpt.eq.lst.ftd = predict(mod.rpt.eq.lst, type="class")
mod.rpt.eq.bst.ftd = predict(mod.rpt.eq.bst, type="class")
{% endhighlight %}

Details of the fitting is kept in a list (*mmce*).

- pkg: package name
- isTest: fit on test data?
- isBest: *cp* by *1-SE* rule?
- isEq: equal cost?
- cp: *cp* value used
- mmce: mean misclassification error


{% highlight r %}
# fit to train data
mod.rpt.eq.lst.ftd = predict(mod.rpt.eq.lst, type="class")
mod.rpt.eq.bst.ftd = predict(mod.rpt.eq.bst, type="class")

# confusion matrix
mod.rpt.eq.lst.ftd.cm = table(actual=trainData$High,fitted=mod.rpt.eq.lst.ftd)
mod.rpt.eq.lst.ftd.cm = updateCM(mod.rpt.eq.lst.ftd.cm, type="Fitted")

mod.rpt.eq.bst.ftd.cm = table(actual=trainData$High,fitted=mod.rpt.eq.bst.ftd)
mod.rpt.eq.bst.ftd.cm = updateCM(mod.rpt.eq.bst.ftd.cm, type="Fitted")

# misclassification error
mod.rpt.eq.lst.ftd.mmce = list(pkg="rpart",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.lst.cp,4)
                               ,mmce=mod.rpt.eq.lst.ftd.cm[3,3])
mmce = list(unlist(mod.rpt.eq.lst.ftd.mmce))

mod.rpt.eq.bst.ftd.mmce = list(pkg="rpart",isTest=FALSE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.bst.cp,4)
                              ,mmce=mod.rpt.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.bst.ftd.mmce)

ldply(mmce)
{% endhighlight %}



{% highlight text %}
##     pkg isTest isBest isEq     cp mmce
## 1 rpart  FALSE  FALSE TRUE 0.0114 0.16
## 2 rpart  FALSE   TRUE TRUE 0.1061 0.29
{% endhighlight %}

The pruned trees are fit into the test data and the same details are added to the list (*mmce*).


{% highlight r %}
## performance of test data
# fit to test data
mod.rpt.eq.lst.ptd = predict(mod.rpt.eq.lst, newdata=testData, type="class")
mod.rpt.eq.bst.ptd = predict(mod.rpt.eq.bst, newdata=testData, type="class")

# confusion matrix
mod.rpt.eq.lst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.lst.ptd)
mod.rpt.eq.lst.ptd.cm = updateCM(mod.rpt.eq.lst.ptd.cm)

mod.rpt.eq.bst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.bst.ptd)
mod.rpt.eq.bst.ptd.cm = updateCM(mod.rpt.eq.bst.ptd.cm)

# misclassification error
mod.rpt.eq.lst.ptd.mmce = list(pkg="rpart",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.lst.cp,4)
                               ,mmce=mod.rpt.eq.lst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.lst.ptd.mmce)

mod.rpt.eq.bst.ptd.mmce = list(pkg="rpart",isTest=TRUE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.bst.cp,4)
                              ,mmce=mod.rpt.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.bst.ptd.mmce)

ldply(mmce)
{% endhighlight %}



{% highlight text %}
##     pkg isTest isBest isEq     cp mmce
## 1 rpart  FALSE  FALSE TRUE 0.0114 0.16
## 2 rpart  FALSE   TRUE TRUE 0.1061 0.29
## 3 rpart   TRUE  FALSE TRUE 0.0114 0.19
## 4 rpart   TRUE   TRUE TRUE 0.1061  0.3
{% endhighlight %}

Secondly the **caret** package is employed to implement the CART model.


{% highlight r %}
### caret
## train on training data
trControl = trainControl(method="repeatedcv", number=10, repeats=5)
set.seed(12357)
mod.crt.eq = caret::train(High ~ .
                          ,data=trainData
                          ,method="rpart"
                          ,tuneLength=20
                          ,trControl=trControl)
{% endhighlight %}

Note that the **caret** package select the best *cp* value that corresponds to the lowest *Accuracy*. Therefore the best *cp* by this package is labeled as **lst** to be consistent with the **rpart** package. And the **bst** *cp* is selected by the *1-SE rule*. Note that, as the standard error of *Accuracy* is relatively wide, an adjustment is maded to select the best *cp* value and it can be checked in the graph below.


{% highlight r %}
# lowest CP
# caret: maximum accuracy, rpart: 1-SE
# according to rpart, caret's best is lowest
df = mod.crt.eq$results
mod.crt.eq.lst.cp = mod.crt.eq$bestTune$cp
mod.crt.eq.lst.acc = subset(df,cp==mod.crt.eq.lst.cp)[[2]]

# best cp by 1-SE rule - values are adjusted from graph 
mod.crt.eq.bst.cp = df[17,1]
mod.crt.eq.bst.acc = df[17,2]
{% endhighlight %}


{% highlight r %}
# CP by 1-SE rule
maxAcc = subset(df,Accuracy==max(Accuracy))[[2]]
stdAtMaxAcc = subset(df,subset=Accuracy==max(Accuracy))[[4]]
# max cp within 1 SE
maxCP = subset(df,Accuracy>=maxAcc-stdAtMaxAcc)[nrow(subset(df,Accuracy>=maxAcc-stdAtMaxAcc)),][[1]]
accAtMaxCP = subset(df,cp==maxCP)[[2]]

# plot Accuracy vs cp
ubound = ifelse(maxAcc+stdAtMaxAcc>max(df$Accuracy),max(df$Accuracy),maxAcc+stdAtMaxAcc)
lbound = ifelse(maxAcc-stdAtMaxAcc<min(df$Accuracy),min(df$Accuracy),maxAcc-stdAtMaxAcc)

ggplot(data=df[1:nrow(df),], aes(x=cp,y=Accuracy)) + 
  geom_line() + geom_point() +   
  geom_abline(intercept=ubound,slope=0, color="purple") + 
  geom_abline(intercept=lbound,slope=0, color="purple") + 
  geom_point(aes(x=mod.crt.eq.bst.cp,y=mod.crt.eq.bst.acc),color="red",size=3) + 
  geom_point(aes(x=mod.crt.eq.lst.cp,y=mod.crt.eq.lst.acc),color="blue",size=3)
{% endhighlight %}

![center](/figs/2015-02-15-Tree-Based-Methods-Part-IV-Packages-Comparison/cp_graph_caret-1.png) 

Similar to above, 2 trees with the respective *cp* values are fit into the train and test data and the details are kept in *mmce*. Below is the update by fitting from the train data.


{% highlight r %}
## performance on train data
# refit from rpart for best cp - cp by 1-SE not fitted by caret
# note no cross-validation necessary - xval=0 (default: xval=10)
set.seed(12357)
mod.crt.eq.bst = rpart(High ~ ., data=trainData, control=rpart.control(xval=0,cp=mod.crt.eq.bst.cp))

# fit to train data - lowest from caret, best (1-SE) from rpart
mod.crt.eq.lst.ftd = predict(mod.crt.eq,newdata=trainData)
mod.crt.eq.bst.ftd = predict(mod.crt.eq.bst, type="class")

# confusion matrix
mod.crt.eq.lst.ftd.cm = table(actual=trainData$High,fitted=mod.crt.eq.lst.ftd)
mod.crt.eq.lst.ftd.cm = updateCM(mod.crt.eq.lst.ftd.cm, type="Fitted")

mod.crt.eq.bst.ftd.cm = table(actual=trainData$High,fitted=mod.crt.eq.bst.ftd)
mod.crt.eq.bst.ftd.cm = updateCM(mod.crt.eq.bst.ftd.cm, type="Fitted")

# misclassification error
mod.crt.eq.lst.ftd.mmce = list(pkg="caret",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.crt.eq.lst.cp,4)
                               ,mmce=mod.crt.eq.lst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.lst.ftd.mmce)

mod.crt.eq.bst.ftd.mmce = list(pkg="caret",isTest=FALSE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.crt.eq.bst.cp,4)
                               ,mmce=mod.crt.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.bst.ftd.mmce)
{% endhighlight %}

Below is the update by fitting from the test data. The updated fitting details can be checked.


{% highlight r %}
## performance of test data
# fit to test data - lowest from caret, best (1-SE) from rpart
mod.crt.eq.lst.ptd = predict(mod.crt.eq,newdata=testData)
mod.crt.eq.bst.ptd = predict(mod.crt.eq.bst, newdata=testData)

# confusion matrix
mod.crt.eq.lst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.lst.ptd)
mod.crt.eq.lst.ptd.cm = updateCM(mod.crt.eq.lst.ptd.cm)

mod.crt.eq.bst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.bst.ptd)
mod.crt.eq.bst.ptd.cm = updateCM(mod.crt.eq.bst.ptd.cm)

# misclassification error
mod.crt.eq.lst.ptd.mmce = list(pkg="caret",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.crt.eq.lst.cp,4)
                               ,mmce=mod.crt.eq.lst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.lst.ptd.mmce)

mod.crt.eq.bst.ptd.mmce = list(pkg="caret",isTest=TRUE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.crt.eq.bst.cp,4)
                               ,mmce=mod.crt.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.bst.ptd.mmce)

ldply(mmce)
{% endhighlight %}



{% highlight text %}
##     pkg isTest isBest isEq     cp mmce
## 1 rpart  FALSE  FALSE TRUE 0.0114 0.16
## 2 rpart  FALSE   TRUE TRUE 0.1061 0.29
## 3 rpart   TRUE  FALSE TRUE 0.0114 0.19
## 4 rpart   TRUE   TRUE TRUE 0.1061  0.3
## 5 caret  FALSE  FALSE TRUE 0.0156 0.16
## 6 caret  FALSE   TRUE TRUE 0.2488 0.29
## 7 caret   TRUE  FALSE TRUE 0.0156 0.19
## 8 caret   TRUE   TRUE TRUE 0.2488  0.3
{% endhighlight %}

Finally the **mlr** package is employed. 

At first, a taks and learner are set up.


{% highlight r %}
### mlr
## task and learner
tsk.mlr.eq = makeClassifTask(data=trainData,target="High")
lrn.mlr.eq = makeLearner("classif.rpart",par.vals=list(cp=0))
{% endhighlight %}

Then a grid of *cp* values is generated followed by tuning the parameter. Note that, as the tuning optimization path does not include a *standard-error-like* variable, only the best *cp* values are taken into consideration.


{% highlight r %}
## tune parameter
cpGrid = function(index) {
  start=0
  end=0.3
  len=20
  inc = (end-start)/len
  grid = c(start)
  while(start < end) {
    start = start + inc
    grid = c(grid,start)
  } 
  grid[index]
}
# create tune control grid
ps.mlr.eq = makeParamSet(
    makeNumericParam("cp",lower=1,upper=20,trafo=cpGrid)
  )
ctrl.mlr.eq = makeTuneControlGrid(resolution=c(cp=(20)))

# tune cp
rdesc.mlr.eq = makeResampleDesc("RepCV",reps=5,folds=10,stratify=TRUE)
set.seed(12357)
tune.mlr.eq = tuneParams(learner=lrn.mlr.eq
                         ,task=tsk.mlr.eq
                         ,resampling=rdesc.mlr.eq
                         ,par.set=ps.mlr.eq
                         ,control=ctrl.mlr.eq)
# tuned cp
tune.mlr.eq$x
{% endhighlight %}



{% highlight text %}
## $cp
## [1] 0.015
{% endhighlight %}



{% highlight r %}
# optimization path
# no standard error like values, only best cp is considered
path.mlr.eq = as.data.frame(tune.mlr.eq$opt.path)
path.mlr.eq = transform(path.mlr.eq,cp=cpGrid(cp))
head(path.mlr.eq,3)
{% endhighlight %}



{% highlight text %}
##      cp mmce.test.mean dob eol error.message exec.time
## 1 0.000      0.2623790   1  NA          <NA>     0.948
## 2 0.015      0.2555407   2  NA          <NA>     0.944
## 3 0.030      0.2629069   3  NA          <NA>     0.945
{% endhighlight %}

Using the best *cp* value, the learner is updated followed by training the model.


{% highlight r %}
# obtain fitted and predicted responses
# update cp
lrn.mlr.eq.bst = setHyperPars(lrn.mlr.eq, par.vals=tune.mlr.eq$x)

# train model
trn.mlr.eq.bst = train(lrn.mlr.eq.bst, tsk.mlr.eq)
{% endhighlight %}

Then the model is fit into the train and test data and the fitting details are updated in *mmce*. The overall fitting results can be checked below.


{% highlight r %}
# fitted responses
mod.mlr.eq.bst.ftd = predict(trn.mlr.eq.bst, tsk.mlr.eq)$data
mod.mlr.eq.bst.ptd = predict(trn.mlr.eq.bst, newdata=testData)$data

# confusion matrix
mod.mlr.eq.bst.ftd.cm = table(actual=mod.mlr.eq.bst.ftd$truth, fitted=mod.mlr.eq.bst.ftd$response)
mod.mlr.eq.bst.ftd.cm = updateCM(mod.mlr.eq.bst.ftd.cm)

mod.mlr.eq.bst.ptd.cm = table(actual=mod.mlr.eq.bst.ptd$truth, fitted=mod.mlr.eq.bst.ptd$response)
mod.mlr.eq.bst.ptd.cm = updateCM(mod.mlr.eq.bst.ptd.cm)

# misclassification error
mod.mlr.eq.bst.ftd.mmce = list(pkg="mlr",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(tune.mlr.eq$x[[1]],4)
                               ,mmce=mod.mlr.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.mlr.eq.bst.ftd.mmce)

mod.mlr.eq.bst.ptd.mmce = list(pkg="mlr",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(tune.mlr.eq$x[[1]],4)
                               ,mmce=mod.mlr.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.mlr.eq.bst.ptd.mmce)

ldply(mmce)
{% endhighlight %}



{% highlight text %}
##      pkg isTest isBest isEq     cp mmce
## 1  rpart  FALSE  FALSE TRUE 0.0114 0.16
## 2  rpart  FALSE   TRUE TRUE 0.1061 0.29
## 3  rpart   TRUE  FALSE TRUE 0.0114 0.19
## 4  rpart   TRUE   TRUE TRUE 0.1061  0.3
## 5  caret  FALSE  FALSE TRUE 0.0156 0.16
## 6  caret  FALSE   TRUE TRUE 0.2488 0.29
## 7  caret   TRUE  FALSE TRUE 0.0156 0.19
## 8  caret   TRUE   TRUE TRUE 0.2488  0.3
## 9    mlr  FALSE  FALSE TRUE  0.015 0.16
## 10   mlr   TRUE  FALSE TRUE  0.015 0.19
{% endhighlight %}

It is shown that the *mmce* values are identical and it seems to be because the model is quite stable with respect to *cp*. It can be checked in the following graph.


{% highlight r %}
# mmce vs cp
ftd.mmce = c()
ptd.mmce = c()
cps = mod.crt.eq$results[[1]]
for(i in 1:length(cps)) {
  if(i %% 2 == 0) {
    set.seed(12357)
    mod = rpart(High ~ ., data=trainData, control=rpart.control(cp=cps[i]))
    ftd = predict(mod,type="class")
    ptd = predict(mod,newdata=testData,type="class")
    ftd.mmce = c(ftd.mmce,updateCM(table(trainData$High,ftd))[3,3])
    ptd.mmce = c(ptd.mmce,updateCM(table(testData$High,ptd))[3,3])    
  }
}
mmce.crt = data.frame(cp=as.factor(round(cps[seq(2,length(cps),2)],3))
                      ,fitted=ftd.mmce
                      ,predicted=ptd.mmce)
mmce.crt = melt(mmce.crt,id=c("cp"),variable.name="data",value.name="mmce")
ggplot(data=mmce.crt,aes(x=cp,y=mmce,fill=data)) + 
  geom_bar(stat="identity", position=position_dodge())
{% endhighlight %}

![center](/figs/2015-02-15-Tree-Based-Methods-Part-IV-Packages-Comparison/mmce_plot-1.png) 

It may not be convicing to use a wrapper by this article about a single model. For example, however, if there are multiple models with a variety of tuning parameters to compare, the benefit of having one can be considerable. In the following articles, a similar approach would be taken, which is comparing individual packages to the wrappers.
