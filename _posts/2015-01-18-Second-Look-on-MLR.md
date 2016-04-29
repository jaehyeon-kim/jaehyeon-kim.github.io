---
layout: post
title: "2015-01-18-Second-Look-on-MLR"
description: ""
category: R
tags: [mlr]
---
In the previous article titled [First Look on MLR](http://jaehyeon-kim.github.io/r/2015/01/17/First-Look-on-MLR/), a quick comparison is made between *stats* and *mlr* packages by fitting logistic regression. However the benefits of using *mlr* (**consistent API** and **extensibility**) cannot be demonstrated well with that kind of simple analysis which has a single learner and no or a simple resampling strategy. 

In this article, the comparison is extended to cover **Resampling** and **Benchmark** so as to illustrate how comprehensive analysis can be implemented - data is '*resampled*' to employ holdout and 10-fold cross validation and the following 4 learners are '*benchmarked*': logistic regression (glm), linear discriminant analysis (lda), quadratic discriminant analysis (qda) and k-nearest neighbors algorithm (knn). Same to the first article, *Chapter 4 Lab* of [ISLR](http://www-bcf.usc.edu/~gareth/ISL/) is reiterated again.

0. Imputation, Processing ...
1. Task
2. Learner
3. Train
4. Predict
5. Performance
6. **Resampling**
7. **Benchmark**

The following packages are used.


{% highlight r %}
library(ISLR) # Smarket data
library(MASS) # lda/qda
library(class) # knn
library(mlr)
{% endhighlight %}

At first, logistic regression (glm), linear discriminant analysis (lda), quadratic discriminant analysis (qda) and k-nearest neighbors algorithm (knn) are fit using individual libraries and their outcomes are consolidated at the end - model name, hyper parameter and mean misclassification error (mmce) are kept. As with the ISLR lab, only *Lag1* and *Lag2* are fit to the response of *Direction* - the structure of data is shown below. For holdout validation, 2005 data is used as the *test* set.


{% highlight r %}
str(Smarket)
{% endhighlight %}



{% highlight text %}
## 'data.frame':	1250 obs. of  9 variables:
##  $ Year     : num  2001 2001 2001 2001 2001 ...
##  $ Lag1     : num  0.381 0.959 1.032 -0.623 0.614 ...
##  $ Lag2     : num  -0.192 0.381 0.959 1.032 -0.623 ...
##  $ Lag3     : num  -2.624 -0.192 0.381 0.959 1.032 ...
##  $ Lag4     : num  -1.055 -2.624 -0.192 0.381 0.959 ...
##  $ Lag5     : num  5.01 -1.055 -2.624 -0.192 0.381 ...
##  $ Volume   : num  1.19 1.3 1.41 1.28 1.21 ...
##  $ Today    : num  0.959 1.032 -0.623 0.614 0.213 ...
##  $ Direction: Factor w/ 2 levels "Down","Up": 2 2 1 2 2 2 1 2 2 2 ...
{% endhighlight %}

## Fitting with individual libraries

### Logistic regression (glm)


{% highlight r %}
## glm
# test on Year == 2005
glm.fit = glm(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), family=binomial, subset=Smarket$Year!=2005)
glm.probs = predict(glm.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)), type="response")
glm.pred = sapply(glm.probs, function(p) { ifelse(p>.5,"Up","Down") })
glm.cm = table(data.frame(response=glm.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
glm.mmce = 1 - sum(diag(glm.cm)) / sum(glm.cm)

# keep output
model = c("glm")
hyper = c(NA)
mmce = c(glm.mmce)
{% endhighlight %}

### Linear discriminant analysis (lda)


{% highlight r %}
## lda
lda.fit = lda(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), subset=Smarket$Year!=2005)
lda.pred = predict(lda.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)))$class
lda.cm = table(data.frame(response=lda.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
lda.mmce = 1 - sum(diag(lda.cm)) / sum(lda.cm)

# keep output
model = c(model,"lda")
hyper = c(hyper, NA)
mmce = c(mmce, lda.mmce)
{% endhighlight %}

### Quadratic discriminant analysis (qda)


{% highlight r %}
## qda
qda.fit = qda(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), subset=Smarket$Year!=2005)
qda.pred = predict(qda.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)))$class
qda.cm = table(data.frame(response=qda.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
qda.mmce = 1 - sum(diag(qda.cm)) / sum(qda.cm)

# keep output
model = c(model,"qda")
hyper = c(hyper, NA)
mmce = c(mmce, qda.mmce)
{% endhighlight %}

### k-nearest neighbors algorithm (knn)


{% highlight r %}
set.seed(12347)
## knn
k = 3 # hyper (or tuning) parameter set to be 3
knn.feat.train = subset(Smarket, Year!=2005, select=c(Lag1,Lag2))
knn.feat.test = subset(Smarket, Year==2005, select=c(Lag1,Lag2))
knn.resp.train = subset(Smarket, Year!=2005, select=c(Direction), drop=TRUE) # should be factors
knn.pred = knn(train=knn.feat.train, test=knn.feat.test, cl=knn.resp.train, k=k)
knn.cm = table(data.frame(response=knn.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
knn.mmce = 1 - sum(diag(knn.cm)) / sum(knn.cm)

# keep output
model = c(model,"knn")
hyper = c(hyper,3)
mmce = c(mmce,knn.mmce)
{% endhighlight %}

The outcomes are kept in **holdout.res**.


{% highlight r %}
## consolidate outputs
holdout.res = data.frame(model=model, hyper=hyper, mmce=mmce)
{% endhighlight %}

## Fitting with MLR

Note that the development version (v2.3) is necessary to fit logistic regression - see the [previous article](http://jaehyeon-kim.github.io/r/2015/01/17/First-Look-on-MLR/) for installation information.

### Task

The task can be set up as following.


{% highlight r %}
task = makeClassifTask(id="Smarket", data=subset(Smarket, select=c(Lag1,Lag2,Direction)), positive="Up", target="Direction")
task
{% endhighlight %}



{% highlight text %}
## Supervised task: Smarket
## Type: classif
## Target: Direction
## Observations: 1250
## Features:
## numerics  factors  ordered 
##        2        0        0 
## Missings: FALSE
## Has weights: FALSE
## Has blocking: FALSE
## Classes: 2
## Down   Up 
##  602  648 
## Positive class: Up
{% endhighlight %}

### Learner

#### Logistic regression (glm)


{% highlight r %}
## glm
glm.lrn = makeLearner("classif.binomial")
glm.lrn
{% endhighlight %}



{% highlight text %}
## Learner classif.binomial from package stats
## Type: classif
## Name: Binomial Regression; Short name: binomial
## Class: classif.binomial
## Properties: twoclass,numerics,factors,prob,weights
## Predict-Type: response
## Hyperparameters:
{% endhighlight %}

#### Linear discriminant analysis (lda)


{% highlight r %}
## lda
lda.lrn = makeLearner("classif.lda")
lda.lrn
{% endhighlight %}



{% highlight text %}
## Learner classif.lda from package MASS
## Type: classif
## Name: Linear Discriminant Analysis; Short name: lda
## Class: classif.lda
## Properties: twoclass,multiclass,numerics,factors,prob
## Predict-Type: response
## Hyperparameters:
{% endhighlight %}

#### Quadratic discriminant analysis (qda)


{% highlight r %}
## qda
qda.lrn = makeLearner("classif.qda")
qda.lrn
{% endhighlight %}



{% highlight text %}
## Learner classif.qda from package MASS
## Type: classif
## Name: Quadratic Discriminant Analysis; Short name: qda
## Class: classif.qda
## Properties: twoclass,multiclass,numerics,factors,prob
## Predict-Type: response
## Hyperparameters:
{% endhighlight %}

#### k-nearest neighbors algorithm (knn)

One hyper- or tuning parameter is set to be 3.


{% highlight r %}
## knn
knn.lrn = makeLearner("classif.knn", par.vals=list(k=3)) # set hyper parameter
knn.lrn
{% endhighlight %}



{% highlight text %}
## Learner classif.knn from package class
## Type: classif
## Name: k-Nearest Neighbor; Short name: knn
## Class: classif.knn
## Properties: twoclass,multiclass,numerics
## Predict-Type: response
## Hyperparameters: k=3
{% endhighlight %}

The three subsequent steps (**Train**, **Predict** and **Performance**) are not directly dealt in this article as the focus is **Resampling** and **Benchmark**. 

### Resampling

**mlr** supports the following resampling strategies and the first and last are chosen.

- **Cross-validation ("CV")**,
- Leave-one-out cross-validation ("LOO""),
- Repeated cross-validation ("RepCV"),
- Out-of-bag bootstrap ("Bootstrap"),
- Subsampling ("Subsample"),
- **Holdout (training/test) ("Holdout")**

There are two ways to set up resampling stragies. The first one is to create [resampling description](http://www.rdocumentation.org/packages/mlr/functions/makeResampleDesc) while the second is to create [resampling instance](http://www.rdocumentation.org/packages/mlr/functions/makeResampleInstance). A resampling instance is created for holdout validation while the more general resampling description is used for 10-fold cross validation - I haven't found a way to set up 2005 records for the test set while a resampling instance can be created by adjusting (row) indices.

#### Resampling instance


{% highlight r %}
# for holdout validation, resampling instance can be specified
start = length(Smarket$Year) - length(Smarket$Direction[Smarket$Year==2005]) + 1
end = length(Smarket$Year)
rin = makeFixedHoldoutInstance(train.inds=1:(start-1), test.inds=start:end, size=end)
rin
{% endhighlight %}



{% highlight text %}
## Resample instance for 1250 cases.
## Resample description: holdout with 0.80 split rate.
## Predict: test
## Stratification: FALSE
{% endhighlight %}

#### Resampling description


{% highlight r %}
# for others, resampling description can be created
rdesc = makeResampleDesc("CV", iters=10)
rdesc
{% endhighlight %}



{% highlight text %}
## Resample description: cross-validation with 10 iterations.
## Predict: test
## Stratification: FALSE
{% endhighlight %}

### Benchmark

For benchmark, lists of tasks, learners, holdout resampling and CV reampling are created.


{% highlight r %}
tasks = list(task)
learners = list(glm.lrn, lda.lrn, qda.lrn, knn.lrn)
holdout.resample = list(rin)
cv.resample = list(rdesc)
{% endhighlight %}

Then benchmark measures (mean misclassification error) are obtained for each learner and resampling strategy.


{% highlight r %}
set.seed(12347)

# holdout
mlr.holdout.res = benchmark(learners=learners, tasks=tasks, resamplings=holdout.resample)

# cv
mlr.cv.res = benchmark(learners=learners, tasks=tasks, resamplings=cv.resample)
{% endhighlight %}

### Outcomes from individual libraries - holdout validation


{% highlight r %}
holdout.res
{% endhighlight %}



{% highlight text %}
##   model hyper      mmce
## 1   glm    NA 0.4404762
## 2   lda    NA 0.4404762
## 3   qda    NA 0.4007937
## 4   knn     3 0.4682540
{% endhighlight %}

### Outcome from mlr - holdout validation


{% highlight r %}
mlr.holdout.res
{% endhighlight %}



{% highlight text %}
##   task.id       learner.id mmce.test.mean
## 1 Smarket classif.binomial      0.4404762
## 2 Smarket      classif.lda      0.4404762
## 3 Smarket      classif.qda      0.4007937
## 4 Smarket      classif.knn      0.4682540
{% endhighlight %}

### Outcome from mlr - cross-validation


{% highlight r %}
mlr.cv.res
{% endhighlight %}



{% highlight text %}
##   task.id       learner.id mmce.test.mean
## 1 Smarket classif.binomial         0.4760
## 2 Smarket      classif.lda         0.4760
## 3 Smarket      classif.qda         0.4888
## 4 Smarket      classif.knn         0.5008
{% endhighlight %}


There is a hyper- or tuning parameter in k-nearest neighbors algorithm and it is set to be 3 without justification. This is limitation of this analysis. As **mlr** supports **nested resampling** so that the parameter(s) can be determined together, this package allows even more extension.
