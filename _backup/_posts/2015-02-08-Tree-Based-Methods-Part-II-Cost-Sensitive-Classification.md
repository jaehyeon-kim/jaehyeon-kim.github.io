---
layout: post
title: "2015-02-08-Tree-Based-Methods-Part-II-Cost-Sensitive-Classification"
description: ""
category: R
tags: [dplyr, caret, rpart, rpart.plot]
---
In the previous article ([Tree Based Methods Part I](http://jaehyeon-kim.github.io/r/2015/02/01/Tree-Based-Methods-Part-I/)), a decision tree is created on the *Carseats* data which is in the chapter 8 lab of [ISLR](http://www-bcf.usc.edu/~gareth/ISL/). In that article, potentially asymetric costs due to misclassification are not taken into account. When unbalance between false positive and false negative can have a significant impact, it can be explicitly adjusted either by altering prior (or empirical) probabilities or by adding a loss matrix. 

A comprehensive summary of this topic, as illustrated in [Berk (2008)](http://www.springer.com/mathematics/probability/book/978-0-387-77500-5), is shown below.

      ... when the CART solution is determined solely by the data, the prior distribution is empirically determined, and the costs in the loss matrix of all classification errors are the same. Costs are being assigned even if the data analyst makes no conscious decision about them. Should the balance of false negatives to false positives that results be unsatisfactory, that balance can be changed. Either the costs in the loss matrix can be directly altered, leaving the prior distribution to be empirically determined, or the prior distribution can be altered leaving the default costs untouched. Much of the software currently available makes it easier to change the prior in the binary response case. When there are more than two response categories, it will usually be easier in practice to change the costs in the loss matrix directly.

In this article, cost-sensitive classification is implemented, assuming that misclassifying the *High* class is twice as expensive, both by altering the priors and by adjusting the loss matrix.

The following loss matrix is implemented.

$$
L^*=\begin{bmatrix} 0 & 2 \\ 1 & 0 \end{bmatrix}
$$

The corresponding altered priors can be obtained by

$$
\tilde{\pi}_{i}^* = \frac{\pi_{i}L_{i}^*}{\pi_{i}L_{i}^* + \pi_{j}L_{j}^*}
$$

The bold-cased sections of the [tutorial](http://topepo.github.io/caret/index.html) of the caret package are covered in this article.

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
res.summary = with(Carseats,rbind(table(High),table(High)/length(High)))
res.summary
{% endhighlight %}



{% highlight text %}
##        High     No
## [1,] 164.00 236.00
## [2,]   0.41   0.59
{% endhighlight %}

The train and test data sets are split using `createDataPartition()`.


{% highlight r %}
# split data
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
trainData = subset(Carseats, select=c(-Sales))[trainIndex,]
testData = subset(Carseats, select=c(-Sales))[-trainIndex,]

# response summary
train.res.summary = with(trainData,rbind(table(High),table(High)/length(High)))
test.res.summary = with(testData,rbind(table(High),table(High)/length(High)))
{% endhighlight %}

5 repeats of 10-fold cross validation is set up.


{% highlight r %}
# set up train control
trControl = trainControl(method="repeatedcv",number=10,repeats=5)
{% endhighlight %}

Rather than tuning the complexity parameter (*cp*) using the built-in `tuneLength`, a grid is created. At first, it was intended to use this grid together with altered priors in the `expand.grid()` function of the **caret** package as `rpart()` has an argument named *parms* to enter altered priors (*prior*) or a loss matrix (*loss*) as a list. Later, however, it was found that the function does not accept an argument if it is not set as a tuning parameter. Therefore *cp* is not tuned when each of *parms* values is modified. (Although it is not considered in this article, the **mlr** package seems to support cost sensitive classification by adding a loss matrix as can be checked [here](http://berndbischl.github.io/mlr/tutorial/html/cost_sensitive_classif/index.html))


{% highlight r %}
# generate tune grid
cpGrid = function(start,end,len) {
  inc = if(end > start) (end-start)/len else 0
  # update grid
  if(inc > 0) {    
    grid = c(start)
    while(start < end) {
      start = start + inc
      grid = c(grid,start)
    }
  } else {
    message("start > end, default cp value is taken")
    grid = c(0.1)
  }    
  grid
}

grid = expand.grid(cp=cpGrid(0,0.3,20))
{% endhighlight %}

The default model is fit below.


{% highlight r %}
# train model with equal cost
set.seed(12357)
mod.eq.cost = train(High ~ .
                      ,data=trainData
                      ,method="rpart"
                      ,tuneGrid=grid
                      ,trControl=trControl)

# select results at best tuned cp
subset(mod.eq.cost$results,subset=cp==mod.eq.cost$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##      cp  Accuracy     Kappa AccuracySD   KappaSD
## 2 0.015 0.7303501 0.4383323  0.0836073 0.1743789
{% endhighlight %}

The model is refit with the tuned *cp* value.


{% highlight r %}
# refit the model to the entire training data
cp = mod.eq.cost$bestTune$cp
mod.eq.cost = rpart(High ~ ., data=trainData, control=rpart.control(cp=cp))
{% endhighlight %}

Confusion matrices are obtained from both the training and test data sets. Here the matrices are transposed to the previous article and this is to keep the same structure as used in [Berk (2008)](http://www.springer.com/mathematics/probability/book/978-0-387-77500-5) - the source of `getUpdatedCM()` can be found in this [gist](https://gist.github.com/jaehyeon-kim/23bc73660e0e7b53a36f). 

The **model error** means how successful fitting or prediction is on each class given data and it is shown that the *High* class is more misclassified. The *use error* is to see how useful the model is given fitted or predicted values. It is also found that misclassification of the *High* class becomes worse when the model is applied to the test data.


{% highlight r %}
source("src/mlUtils.R")
fit.eq.cost = predict(mod.eq.cost, type="class")
fit.cm.eq.cost = table(data.frame(actual=trainData$High,response=fit.eq.cost))
fit.cm.eq.cost = getUpdatedCM(cm=fit.cm.eq.cost, type="Fitted")
fit.cm.eq.cost
{% endhighlight %}



{% highlight text %}
##              Fitted: High Fitted: No Model Error
## Actual: High       106.00      26.00        0.20
## Actual: No          24.00     165.00        0.13
## Use Error            0.18       0.14        0.16
{% endhighlight %}



{% highlight r %}
pred.eq.cost = predict(mod.eq.cost, newdata=testData, type="class")
pred.cm.eq.cost = table(data.frame(actual=testData$High,response=pred.eq.cost))
pred.cm.eq.cost = getUpdatedCM(pred.cm.eq.cost)
pred.cm.eq.cost
{% endhighlight %}



{% highlight text %}
##              Pred: High Pred: No Model Error
## Actual: High      21.00     11.0        0.34
## Actual: No         4.00     43.0        0.09
## Use Error          0.16      0.2        0.19
{% endhighlight %}

As mentioned earlier, either althered priors or a loss matrix can be entered into `rpart()`. They are created below.


{% highlight r %}
# update prior probabilities
costs = c(2,1)
train.res.summary
{% endhighlight %}



{% highlight text %}
##            High         No
## [1,] 132.000000 189.000000
## [2,]   0.411215   0.588785
{% endhighlight %}



{% highlight r %}
prior.w.weight = c(train.res.summary[2,1] * costs[1]
                   ,train.res.summary[2,2] * costs[2])
priorUp = c(prior.w.weight[1]/sum(prior.w.weight)
            ,prior.w.weight[2]/sum(prior.w.weight))
priorUp
{% endhighlight %}



{% highlight text %}
##      High        No 
## 0.5827815 0.4172185
{% endhighlight %}


{% highlight r %}
# loss matrix
loss.mat = matrix(c(0,2,1,0),nrow=2,byrow=TRUE)
loss.mat
{% endhighlight %}



{% highlight text %}
##      [,1] [,2]
## [1,]    0    2
## [2,]    1    0
{% endhighlight %}

Both will deliver the same outcome.


{% highlight r %}
# refit the model with the updated priors
# fit with updated prior
mod.uq.cost = rpart(High ~ ., data=trainData, parms=list(prior=priorUp), control=rpart.control(cp=cp))

# fit with loss matrix
# mod.uq.cost = rpart(High ~ ., data=trainData, parms=list(loss=loss.mat), control=rpart.control(cp=cp))
{% endhighlight %}

Confusion matrices are obtained again. It is shown that more values are classified as the *High* class. Note that, although the overall misclassification error is increased, it does not reflect costs. In a situation, the cost adjusted CART may be more beneficial. 


{% highlight r %}
fit.cm.eq.cost
{% endhighlight %}



{% highlight text %}
##              Fitted: High Fitted: No Model Error
## Actual: High       106.00      26.00        0.20
## Actual: No          24.00     165.00        0.13
## Use Error            0.18       0.14        0.16
{% endhighlight %}



{% highlight r %}
fit.uq.cost = predict(mod.uq.cost, type="class")
fit.cm.uq.cost = table(data.frame(actual=trainData$High,response=fit.uq.cost))
fit.cm.uq.cost = getUpdatedCM(fit.cm.uq.cost, type="Fitted")
fit.cm.uq.cost
{% endhighlight %}



{% highlight text %}
##              Fitted: High Fitted: No Model Error
## Actual: High       123.00       9.00        0.07
## Actual: No          44.00     145.00        0.23
## Use Error            0.26       0.06        0.17
{% endhighlight %}


{% highlight r %}
pred.cm.eq.cost
{% endhighlight %}



{% highlight text %}
##              Pred: High Pred: No Model Error
## Actual: High      21.00     11.0        0.34
## Actual: No         4.00     43.0        0.09
## Use Error          0.16      0.2        0.19
{% endhighlight %}



{% highlight r %}
pred.uq.cost = predict(mod.uq.cost, newdata=testData, type="class")
pred.cm.uq.cost = table(data.frame(actual=testData$High,response=pred.uq.cost))
pred.cm.uq.cost = getUpdatedCM(pred.cm.uq.cost)
pred.cm.uq.cost
{% endhighlight %}



{% highlight text %}
##              Pred: High Pred: No Model Error
## Actual: High      26.00     6.00        0.19
## Actual: No        14.00    33.00        0.30
## Use Error          0.35     0.15        0.25
{% endhighlight %}

<script src='http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' type="text/javascript"></script>
