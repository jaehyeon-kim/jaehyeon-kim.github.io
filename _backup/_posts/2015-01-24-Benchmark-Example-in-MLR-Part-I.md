---
layout: post
title: "2015-01-24-Benchmark-Example-in-MLR-Part-I"
description: ""
category: R
tags: [mlr, kernlab, caret]
---
This is an update of the second article - [Second Look on MLR](http://jaehyeon-kim.github.io/r/2015/01/18/Second-Look-on-MLR/). While a hyper- or turning parameter is either non-existent or given in the previous article, it is estimated here - specifically cost of constraints violation (C) of support vector machine is estimated. 

The *Credit Scoring* example in Chapter 4 of [Applied Predictive Modeling](http://appliedpredictivemodeling.com/) is reimplemented using the **mlr** package. Details of the German Credit Data that is used here can be found [here](http://www.rdocumentation.org/packages/caret/functions/GermanCredit).

The bold-cased topics below are mainly covered.

0. **Imputation, Processing ...**
1. Task
2. Learner
3. Train
4. Predict
5. Performance
6. **Resampling**
7. **Benchmark**

The following packages are used.


{% highlight r %}
library(kernlab)
library(caret)
library(mlr)
{% endhighlight %}

## Preprocessing

**mlr** has different methods of preprocessing and splitting data to **caret**. For comparison that may be necessary in the future, these steps are performed in the same way.


{% highlight r %}
### preprocessing - caret
data(GermanCredit)
GermanCredit <- GermanCredit[, -nearZeroVar(GermanCredit)]
GermanCredit$CheckingAccountStatus.lt.0 <- NULL
GermanCredit$SavingsAccountBonds.lt.100 <- NULL
GermanCredit$EmploymentDuration.lt.1 <- NULL
GermanCredit$EmploymentDuration.Unemployed <- NULL
GermanCredit$Personal.Male.Married.Widowed <- NULL
GermanCredit$Property.Unknown <- NULL
GermanCredit$Housing.ForFree <- NULL
{% endhighlight %}

80% of data is taken as the training set.


{% highlight r %}
### split data - caret
set.seed(100)
inTrain <- createDataPartition(GermanCredit$Class, p = .8)[[1]]
GermanCreditTrain <- GermanCredit[inTrain, ]
GermanCreditTest  <- GermanCredit[-inTrain, ]
{% endhighlight %}

## Task

*Task* is set up using the training data and normalized as the original example.


{% highlight r %}
### task
task = makeClassifTask(id="gc", data=GermanCreditTrain, target="Class")
normalizeFeatures(task, method="standardize")
{% endhighlight %}



{% highlight text %}
## Supervised task: gc
## Type: classif
## Target: Class
## Observations: 800
## Features:
## numerics  factors  ordered 
##       41        0        0 
## Missings: FALSE
## Has weights: FALSE
## Has blocking: FALSE
## Classes: 2
##  Bad Good 
##  240  560 
## Positive class: Bad
{% endhighlight %}

## Learner

The following two learners are set up for benchmark: *Support vector machine* and *logistic regression*. Note that the development version (v2.3) is necessary to fit logistic regression - see [this article](http://jaehyeon-kim.github.io/r/2015/01/17/First-Look-on-MLR/) for installation information.


{% highlight r %}
### learner
lrn.svm = makeLearner("classif.ksvm")
lrn.glm = makeLearner("classif.binomial")
{% endhighlight %}

## Resampling

*Repeated cross-validation* is chosen as the original example.


{% highlight r %}
### resampling
rdesc = makeResampleDesc("RepCV", folds=10, reps=5, predict="both")
{% endhighlight %}

## Tuning

As the original example, *sigma* (inverse kernel width) is estimated first using `sigest()` in the *kernlab* package. Then a control grid is made by varying values of *C* only. 


{% highlight r %}
## estimate sigma
set.seed(231)
sigDist = sigest(Class ~ ., data=GermanCreditTrain, frac=1)

trans = function(x) 2^x
ps = makeParamSet(makeNumericParam("C", lower=-2, upper=4, trafo=trans),
                  makeDiscreteParam("sigma", values=c(as.numeric(sigDist[2]))),
                  makeDiscreteParam("kernel", values=c("rbfdot")))
ctrl = makeTuneControlGrid(resolution=c(C=7L)) # adjust increment
{% endhighlight %}

In `makeParamSet()`, *sigma* and *kernel* are fixed as discrete parameters while *C* is varied from *lower* to *upper* in the scale that is determined by the argument of `trafo`. For numeric and integer parameters, it is possible to adjust increment by *resolution*. Note that the above set up can be relaxed, for example, by varying both *C* and *sigma* and, in this case, it would be more flexible to set *sigma* as a numeric parameter.

The resulting grid can be checked using `generateGridDesign()`


{% highlight r %}
# check grid
grid <- generateGridDesign(ps, resolution=c(C=7))
# change to transformed values
grid$C = trans(grid$C)
grid$sigma = round(as.numeric(as.character(grid$sigma)),4)
grid
{% endhighlight %}



{% highlight text %}
##       C  sigma kernel
## 1  0.25 0.0126 rbfdot
## 2  0.50 0.0126 rbfdot
## 3  1.00 0.0126 rbfdot
## 4  2.00 0.0126 rbfdot
## 5  4.00 0.0126 rbfdot
## 6  8.00 0.0126 rbfdot
## 7 16.00 0.0126 rbfdot
{% endhighlight %}

The parameter can be tuned using `tuneParams()` as shown below.


{% highlight r %}
# tune params
set.seed(123457)
res = tuneParams(lrn.svm, task=task, resampling=rdesc, par.set=ps, control=ctrl, show.info=FALSE)
# optimal parameters - res$x
# measure with optimal parameters - res$y
res
{% endhighlight %}



{% highlight text %}
## Tune result:
## Op. pars: C=4; sigma=0.0125806318763427; kernel=rbfdot
## mmce.test.mean=0.243
{% endhighlight %}

Fitting details can check as following.


{% highlight r %}
res.opt.grid <- as.data.frame(res$opt.path)
res.opt.grid$C = trans(res.opt.grid$C)
res.opt.grid$sigma = round(as.numeric(as.character(res.opt.grid$sigma)),4)
res.opt.grid
{% endhighlight %}



{% highlight text %}
##       C  sigma kernel mmce.test.mean dob eol error.message exec.time
## 1  0.25 0.0126 rbfdot        0.30000   1  NA          <NA>     9.251
## 2  0.50 0.0126 rbfdot        0.28050   2  NA          <NA>     8.822
## 3  1.00 0.0126 rbfdot        0.25100   3  NA          <NA>     8.637
## 4  2.00 0.0126 rbfdot        0.25350   4  NA          <NA>     8.756
## 5  4.00 0.0126 rbfdot        0.24300   5  NA          <NA>     8.746
## 6  8.00 0.0126 rbfdot        0.24525   6  NA          <NA>     9.009
## 7 16.00 0.0126 rbfdot        0.26400   7  NA          <NA>     9.696
{% endhighlight %}

## Benchmark

Once the hyper- or tuning parameter is determined, the learner can be updated using `setHyperPars()`.


{% highlight r %}
# update svm learner
lrn.svm = setHyperPars(lrn.svm, par.vals=res$x)
{% endhighlight %}

The tuned SVM learner can be bechmarked with the logistic regression learner. This shows only a marginal difference.


{% highlight r %}
set.seed(123457)
res.bench = benchmark(learners=list(lrn.svm,lrn.glm), task=task, resampling=rdesc)
res.bench
{% endhighlight %}



{% highlight text %}
##   task.id       learner.id mmce.test.mean
## 1      gc     classif.ksvm          0.243
## 2      gc classif.binomial          0.248
{% endhighlight %}

The *tuning* section of [mlr tutorial](http://berndbischl.github.io/mlr/tutorial/html/tune/index.html) indicates that the above practice in which optimization is undertaken over the same data during tuning the SVM parameter might be optimistically biased to estimate the performance value. In order to handle this issue, **nested resampling** is necessary - a more detailed explanation about nested resampling can be found [here](http://stats.stackexchange.com/questions/65128/nested-cross-validation-for-model-selection). Moreover this resampling strategy can be applied to **feature selection** - see the [benchmark tutorial](http://berndbischl.github.io/mlr/tutorial/html/benchmark_experiments/index.html) and [this article](http://bioconductor.org/packages/release/extra/vignettes/nlcv/inst/doc/nlcv.pdf). In this regards, it would be alright that the topic of the next article is about **nested resampling** for model selection.
