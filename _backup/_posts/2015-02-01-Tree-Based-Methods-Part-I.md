---
layout: post
title: "2015-02-01-Tree-Based-Methods-Part-I"
description: ""
category: R
tags: [dplyr, caret, rpart, rpart.plot]
---
This is the first article about tree based methods using R. *Carseats* data in the chapter 8 lab of [ISLR](http://www-bcf.usc.edu/~gareth/ISL/) is used to perform classification analysis. Unlike the lab example, the **rpart** package is used to fit the CART model on the data and the **caret** package is used for tuning the pruning parameter (`cp`).

The bold-cased sections of the [tutorial](http://topepo.github.io/caret/index.html) are covered in this article.

- Visualizations
- Pre-Processing
- **Data Splitting**
- Miscellaneous Model Functions
- **Model Training and Tuning**
- Using Custom Models
- Variable Importance
- Feature Selection: RFE, Filters, GA, SA
- Other Functions
- Parallel Processing
- Adaptive Resampling

The pruning parameter in the **rpart** package is scaled so that its values are from 0 to 1. Specifically the formula is

$$
R_{cp}\left(T\right)\equiv R\left(T\right) + cp*|T|*R\left(T_{1}\right)
$$

where $$T_{1}$$ is the tree with no splits, $$\mid T\mid$$ is the number of splits for a tree and *R* is the risk.

Due to the inclusion of $$R\left(T_{1}\right)$$, when *cp=1*, the tree will result in no splits while it is not pruned when *cp=0*. On the other hand, in the original setup without the term, the pruning parameter ($$\alpha$$) can range from 0 to infinity.

Let's get started.

The following packages are used.


{% highlight r %}
library(dplyr) # data minipulation
library(rpart) # fit tree
library(rpart.plot) # plot tree
library(caret) # tune model
{% endhighlight %}

*Carseats* data is created as following while the response (*Sales*) is converted into a binary variable.


{% highlight r %}
require(ISLR)
data(Carseats)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
# structure of predictors
str(subset(Carseats,select=c(-High,-Sales)))
{% endhighlight %}



{% highlight text %}
## 'data.frame':	400 obs. of  10 variables:
##  $ CompPrice  : num  138 111 113 117 141 124 115 136 132 132 ...
##  $ Income     : num  73 48 35 100 64 113 105 81 110 113 ...
##  $ Advertising: num  11 16 10 4 3 13 0 15 0 0 ...
##  $ Population : num  276 260 269 466 340 501 45 425 108 131 ...
##  $ Price      : num  120 83 80 97 128 72 108 120 124 124 ...
##  $ ShelveLoc  : Factor w/ 3 levels "Bad","Good","Medium": 1 2 3 3 1 1 3 2 3 3 ...
##  $ Age        : num  42 65 59 55 38 78 71 67 76 76 ...
##  $ Education  : num  17 10 12 14 13 16 15 10 10 17 ...
##  $ Urban      : Factor w/ 2 levels "No","Yes": 2 2 2 2 2 1 2 2 1 1 ...
##  $ US         : Factor w/ 2 levels "No","Yes": 2 2 2 2 1 2 1 2 1 2 ...
{% endhighlight %}



{% highlight r %}
# classification response summary
with(Carseats,table(High))
{% endhighlight %}



{% highlight text %}
## High
## High   No 
##  164  236
{% endhighlight %}



{% highlight r %}
with(Carseats,table(High) / length(High))
{% endhighlight %}



{% highlight text %}
## High
## High   No 
## 0.41 0.59
{% endhighlight %}

The train and test data sets are split using `createDataPartition()`.


{% highlight r %}
## Data Splitting
set.seed(1237)
trainIndex.cl = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
trainData.cl = subset(Carseats, select=c(-Sales))[trainIndex.cl,]
testData.cl = subset(Carseats, select=c(-Sales))[-trainIndex.cl,]
{% endhighlight %}

Stratify sampling is performed by default.


{% highlight r %}
# training response summary
with(trainData.cl,table(High))
{% endhighlight %}



{% highlight text %}
## High
## High   No 
##  132  189
{% endhighlight %}



{% highlight r %}
with(trainData.cl,table(High) / length(High))
{% endhighlight %}



{% highlight text %}
## High
##     High       No 
## 0.411215 0.588785
{% endhighlight %}



{% highlight r %}
# test response summary
with(testData.cl,table(High))
{% endhighlight %}



{% highlight text %}
## High
## High   No 
##   32   47
{% endhighlight %}



{% highlight r %}
with(testData.cl,table(High) / length(High))
{% endhighlight %}



{% highlight text %}
## High
##      High        No 
## 0.4050633 0.5949367
{% endhighlight %}

The following resampling strategies are considered: *cross-validation*, *repeated cross-validation* and *bootstrap*.


{% highlight r %}
## train control
trControl.cv = trainControl(method="cv",number=10)
trControl.recv = trainControl(method="repeatedcv",number=10,repeats=5)
trControl.boot = trainControl(method="boot",number=50)
{% endhighlight %}

There are two methods in the **caret** package: `rpart` and `repart2`. The first method allows the pruning parameter to be tuned. The tune grid is not set up explicitly and it is adjusted by `tuneLength` - equally spaced **cp** values are created from 0 to 0.3 in the package.


{% highlight r %}
set.seed(12357)
fit.cl.cv = train(High ~ .
                  ,data=trainData.cl
                  ,method="rpart"
                  ,tuneLength=20
                  ,trControl=trControl.cv)

fit.cl.recv = train(High ~ .
                    ,data=trainData.cl
                    ,method="rpart"
                    ,tuneLength=20
                    ,trControl=trControl.recv)

fit.cl.boot = train(High ~ .
                    ,data=trainData.cl
                    ,method="rpart"
                    ,tuneLength=20
                    ,trControl=trControl.boot)
{% endhighlight %}

Repeated cross-validation and bootstrap produce the same best tuned **cp** value while cross-validation returns a higher value.


{% highlight r %}
# results at best tuned cp
subset(fit.cl.cv$results,subset=cp==fit.cl.cv$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##           cp  Accuracy     Kappa AccuracySD   KappaSD
## 3 0.03110048 0.7382148 0.4395888 0.06115425 0.1355713
{% endhighlight %}



{% highlight r %}
subset(fit.cl.recv$results,subset=cp==fit.cl.recv$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##           cp  Accuracy    Kappa AccuracySD   KappaSD
## 2 0.01555024 0.7384537 0.456367 0.08602102 0.1821254
{% endhighlight %}



{% highlight r %}
subset(fit.cl.boot$results,subset=cp==fit.cl.boot$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##           cp  Accuracy     Kappa AccuracySD    KappaSD
## 2 0.01555024 0.7178692 0.4163337 0.04207806 0.08445416
{% endhighlight %}

The one from repeated cross-validation is taken to fit to the entire training data.

**Updated on Feb 10, 2015**

- As a value of *cp* is entered in `rpart()`, the function fits the model up to the value and takes the result. Therefore it produces a pruned tree.
- If it is not set or set to be a low value (eg, 0), pruning can be done using the `prune()` function.


{% highlight r %}
## refit the model to the entire training data
cp.cl = fit.cl.recv$bestTune$cp
fit.cl = rpart(High ~ ., data=trainData.cl, control=rpart.control(cp=cp.cl))

# Updated on Feb 10, 2015
# prune if cp not set or too low
# fit.cl = prune(tree=fit.cl, cp=cp.cl)
{% endhighlight %}

The resulting tree is shown as following. The plot shows expected losses and node probabilities in the final nodes. For example, the leftmost node has

- expected loss of 0.13 (= 8/60 (0.13333))
- node probability of 19% (= 60/321)


{% highlight r %}
# plot tree
cols <- ifelse(fit.cl$frame$yval == 1,"green4","darkred") # green if high
prp(fit.cl
    ,main="CART model tree"
    ,extra=106           # display prob of survival and percent of obs
    ,nn=TRUE             # display the node numbers
    ,fallen.leaves=TRUE  # put the leaves on the bottom of the page
    ,branch=.5           # change angle of branch lines
    ,faclen=0            # do not abbreviate factor levels
    ,trace=1             # print the automatically calculated cex
    ,shadow.col="gray"   # shadows under the leaves
    ,branch.lty=3        # draw branches using dotted lines
    ,split.cex=1.2       # make the split text larger than the node text
    ,split.prefix="is "  # put "is " before split text
    ,split.suffix="?"    # put "?" after split text
    ,col=cols, border.col=cols   # green if survived
    ,split.box.col="lightgray"   # lightgray split boxes (default is white)
    ,split.border.col="darkgray" # darkgray border on split boxes
    ,split.round=.5) 
{% endhighlight %}



{% highlight text %}
## cex 0.7   xlim c(0, 1)   ylim c(-0.1, 1.1)
{% endhighlight %}

![center](/figs/2015-02-01-Tree-Based-Methods-Part-I/plot_tree-1.png) 



The fitted model is applied to the test data.


{% highlight r %}
## apply to the test data
pre.cl = predict(fit.cl, newdata=testData.cl, type="class")

# confusion matrix
cMat.cl = table(data.frame(response=pre.cl,truth=testData.cl$High))
cMat.cl
{% endhighlight %}



{% highlight text %}
##         truth
## response High No
##     High   21  4
##     No     11 43
{% endhighlight %}



{% highlight r %}
# mean misclassification error
mmse.cl = 1 - sum(diag(cMat.cl))/sum(cMat.cl)
mmse.cl
{% endhighlight %}



{% highlight text %}
## [1] 0.1898734
{% endhighlight %}

More models are going to be implemented/compared in the subsequent articles.

<script src='http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' type="text/javascript"></script>