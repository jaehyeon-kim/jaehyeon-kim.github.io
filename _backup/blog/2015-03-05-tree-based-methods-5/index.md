---
layout: post
title: "2015-03-05-Tree-Based-Methods-Part-V-Regression-Evaluation"
description: ""
category: R
tags: [rpart, caret, mlr, dplyr, ggplot2]
---
In the [previous article](http://jaehyeon-kim.github.io/r/2015/03/03/2nd-Trial-of-Turning-Analysis-into-S3-Object/), a class that implements bagging (*rpartDT*) is introduced. Using the class, this article evaluates a single regression tree's performance by comparing to bagged trees' individual oob/test errors, cumulative oob/test errors and variable importance measures.

Before getting started, note that the source of the classes can be found in [this gist](https://gist.github.com/jaehyeon-kim/b89dcbd2fb0b84fd236e) and, together with the relevant packages (see *tags*), it requires a utility function (`bestParam()`) that can be found [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).

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

# split data
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.rg = data.rg[trainIndex,]
testData.rg = data.rg[-trainIndex,]
{% endhighlight %}

Both the single and bagged regression trees are fit. For bagging, 2000 trees are generated.


{% highlight r %}
## run rpartDT
# import constructors
source("src/cart.R")
set.seed(12357)
rg = cartDT(trainData.rg, testData.rg, "Sales ~ .", ntree=2000)
{% endhighlight %}

The summary of the *cp* values of the bagged trees are shown below, followed by the single tree's *cp* value at the least *xerror*.


{% highlight r %}
## cp values
# cart
rg$rpt$cp[1,][[1]]
{% endhighlight %}



{% highlight text %}
## [1] 0.004852267
{% endhighlight %}



{% highlight r %}
# bagging
summary(t(rg$boot.cp)[,2])
{% endhighlight %}



{% highlight text %}
##     Min.  1st Qu.   Median     Mean  3rd Qu.     Max. 
## 0.000000 0.000000 0.000000 0.001430 0.002568 0.018640
{% endhighlight %}

### Individual Error

From the distributions of the oob and test errors, it is found that

- the single tree's test error is not far away from the means of the bagged trees' oob and test errors - it is only 0.92 and 0.65 standard deviation away repectively and
- the distributions are dense in the left hand side where the single tree's test error locates so that it may be considered that the test error is a *likely* value.


{% highlight r %}
## individual errors
# cart test error
crt.err = rg$rpt$test.lst$error$error
crt.err
{% endhighlight %}



{% highlight text %}
## [1] 0.737656
{% endhighlight %}



{% highlight r %}
# bagging error at least xerror - se to see 1-SE rule
ind.oob.err = data.frame(type="oob",error=unlist(rg$ind.oob.lst.err))
ind.tst.err = data.frame(type="test",error=unlist(rg$ind.tst.lst.err))
ind.err = rbind(ind.oob.err,ind.tst.err)
ind.err.summary = as.data.frame(rbind(summary(ind.err$error[ind.err$type=="oob"])
                                      ,summary(ind.err$error[ind.err$type=="test"]))) 
rownames(ind.err.summary) <- c("oob","test")
ind.err.summary
{% endhighlight %}



{% highlight text %}
##           Min. 1st Qu. Median  Mean 3rd Qu.   Max.
## oob  0.0053970  0.9026  1.972 2.247   3.207 10.670
## test 0.0005156  0.5734  1.217 1.442   2.107  6.738
{% endhighlight %}

A graphical illustration of the error distributions and the location of the single tree's test error are shown below.


{% highlight r %}
# plot error distributions
ggplot(ind.err, aes(x=error,fill=type)) + 
  geom_histogram() + geom_vline(xintercept=crt.err, color="blue") + 
  ggtitle("Error distribution") + theme(plot.title=element_text(face="bold"))
{% endhighlight %}

![center](/figs/2015-03-05-Tree-Based-Methods-Part-V-Regression-Evaluation/ind_plot-1.png) 

### Cumulative Error

The plots of cumulative oob and test errors are shown below and both the errors seem to settle around 1000th tree. The oob and test errors at the 1000th tree are 0.018 and 0.512 respectively. Compared to the single tree's test error of 0.738, the bagged trees deliveres imporved results.


{% highlight r %}
bgg.oob.err = data.frame(type="oob"
                         ,ntree=1:length(rg$cum.oob.lst.err)
                         ,error=unlist(rg$cum.oob.lst.err))
bgg.tst.err = data.frame(type="test"
                         ,ntree=1:length(rg$cum.tst.lst.err)
                         ,error=unlist(rg$cum.tst.lst.err))
bgg.err = rbind(bgg.oob.err,bgg.tst.err)
# plot bagging errors
ggplot(data=bgg.err,aes(x=ntree,y=error,colour=type)) + 
  geom_line() + geom_abline(intercept=crt.err,slope=0,color="blue") + 
  ggtitle("Bagging error") + theme(plot.title=element_text(face="bold"))
{% endhighlight %}

![center](/figs/2015-03-05-Tree-Based-Methods-Part-V-Regression-Evaluation/cum_plot-1.png) 

### Variable Importance

While *ShelveLoc* and *Price* are shown to be the two most important variables, both the single and bagged trees show similar variable importance profiles. For evaluating a single tree, this would be a positive result as it could show that the splits of the single tree is reinforced to be valid by the bagged trees. 

For prediction, however, there may be some room for improvement as the bagged trees might be correlated to some extent, especially due to the existence of the two important variables. For example, if earlier splits are determined by these predictors, there are not enough chances for the remaining predictors and it is not easy to identify local systematic patterns.


{% highlight r %}
# cart
cart.varImp = data.frame(method="cart"
                         ,variable=names(rg$rpt$mod$variable.importance)
                         ,value=rg$rpt$mod$variable.importance/sum(rg$rpt$mod$variable.importance)
                         ,row.names=NULL)
# bagging
ntree = 1000
bgg.varImp = data.frame(method="bagging"
                        ,variable=rownames(rg$cum.varImp.lst)
                        ,value=rg$cum.varImp.lst[,ntree])
# plot variable importance measure
rg.varImp = rbind(cart.varImp,bgg.varImp)
rg.varImp$variable = reorder(rg.varImp$variable, 1/rg.varImp$value)
ggplot(data=rg.varImp,aes(x=variable,y=value,fill=method)) + geom_bar(stat="identity")
{% endhighlight %}

![center](/figs/2015-03-05-Tree-Based-Methods-Part-V-Regression-Evaluation/varImp_plot-1.png) 

In this article, a single regression tree is evaluated by bagged trees. Comparing to individual oob/test errors, the single tree's test error seems to be a likely value. Also, while bagged trees improve prediction performance, the single tree may not be a bad choice especially if more focus is on interpretation. Despite the performance improvement of the bagged trees, there seems to be a chance for additional improvement and the right direction of subsequence articles would be looking into it.

