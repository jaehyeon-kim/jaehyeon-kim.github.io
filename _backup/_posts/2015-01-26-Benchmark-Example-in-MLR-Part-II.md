---
layout: post
title: "2015-01-26-Benchmark-Example-in-MLR-Part-II"
description: ""
category: R
tags: [mlr, kernlab, caret]
---
In the previous article ([Benchmark Example in MLR Part I](http://jaehyeon-kim.github.io/r/2015/01/24/Benchmark-Example-in-MLR-Part-I/)), SVM and logistic regression are benchmarked on German credit data - this data is from the *credit scoring* example in Chapter 4 of [Applied Predictive Modeling](http://appliedpredictivemodeling.com/). For SVM, the cost parameter (C) is tuned by repeated cross-validation before the test measure is compared to that of logistic regression. 

A potential issue on that approach is *the CV error can be optimistically biased to estimate the expected test error* as discussed in [Varma & Simon (2006)](http://www.ncbi.nlm.nih.gov/pmc/articles/PMC1397873/) and [Tibshirani and Tibshirani (2009)](http://www.stat.cmu.edu/~ryantibs/papers/cvbias.pdf). In this article, the issue is briefly summarized in its nature, remedies and cases where it can be outstanding. Among the two remedies, **nested cross-validation** is performed as (1) **mlr** provides this resampling strategy and (2) this resampling strategy is useful as it can be applied to other topics such as feasure selection.

## Summary of optimistic bias of CV error

**CV error can be optimistically biased to estimate the expected test error ([Tibshirani and Tibshirani (2009)](http://www.stat.cmu.edu/~ryantibs/papers/cvbias.pdf))**

*CV estimate of expected test error or CV error curve*

$$
CV(\theta)=\frac{1}{n}\sum_{k=1}^K\sum_{i\in C_{k}}L\left(y_{i},\hat{f}^{-k}\left(x_i,\theta\right)\right)
$$

*CV error in the kth fold or the error curve computed from the predictions in the kth fold*

$$
e_{k}(\theta)=\frac{1}{n_k}\sum_{i\in C_{k}}L\left(y_{i},\hat{f}^{-k}\left(x_i,\theta\right)\right)
$$

Therefore

- first $$e_{k}(\hat{\theta})\approx CV(\hat{\theta})$$
    - Yes, since both are error curves evaluated at their minima.
- and, for fixed $$\theta$$, $$e_{k}(\hat{\theta})\approx E\Big[ L\left(y,\hat{f}\left(x,\hat{\theta}\right)\right)\Big]$$
    - **Not perfect.** 
    - RHS: $$\left(x,y\right)$$ is stochastically independent of the training data and hence of $$\hat{\theta}$$.
    - LHS: $$\left(x_{i},y_{i}\right)$$ has some dependence on $$\hat{\theta}$$ as $$\hat{\theta}$$ is chosen to minimize the validation error across all folds, including the kth fold.

[Tibshirani and Tibshirani (2009)](http://www.stat.cmu.edu/~ryantibs/papers/cvbias.pdf) show that the bias itself is only an issue when $$p\gg N$$ and its magnitude varies considerably depending on the classifier. Therefore it can be misleading to compare the CV error rates when choosing between models.

In order th tackle down this issue, [Varma & Simon (2006)](http://www.ncbi.nlm.nih.gov/pmc/articles/PMC1397873/) suggest **nested cross-validation** to eliminate the dependence in LHS. However this strategy is computationally intensive and can be impractical. 

[Tibshirani and Tibshirani (2009)](http://www.stat.cmu.edu/~ryantibs/papers/cvbias.pdf) propose a method for the estimation of this bias that uses information from the cross-validation process. Specifically

$$ 
\hat{Bias}=\frac{1}{K}\sum_{k=1}^K[e_{k}(\hat{\theta})-e_{k}(\hat{\theta}_k)]
$$

and if the fold sizes are equal

$$
CV(\hat{\theta})=\frac{1}{K}\sum_{k=1}^Ke_{k}(\hat{\theta})
$$

then

$$
CV(\hat{\theta})+\hat{Bias}=2CV(\hat{\theta})-\frac{1}{K}\sum_{k=1}^Ke_{k}(\hat{\theta}_k)
$$

Let's get started.

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

## Control grid set up for tuning

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

## Resampling

*Repeated cross-validation* is chosen for the outer resampling while *cross-validation* is set up for the inner resampling. The outer resampling is for estimating the test errors of the three learners and the inner resampling is for tuning the hyper parameter for SVM (**lrn.nest**) with the *nested resampling strategy* - the estimated hyper parameter in each fold is expected to be independent from the training data.


{% highlight r %}
### resampling descriptions
rdesc.outer = makeResampleDesc("RepCV", folds=5, reps=5, predict="both")
rdesc.inner = makeResampleDesc("CV", iters=5)
{% endhighlight %}

## Learner

Learners of *support vector machine* with and without nested resampling and *logistic regression* are set up - a wrapped learner is set up to be used with nested resampling. Note that the development version (v2.3) is necessary to fit logistic regression - see [this article](http://jaehyeon-kim.github.io/r/2015/01/17/First-Look-on-MLR/) for installation information.


{% highlight r %}
### learner
lrn.svm = makeLearner("classif.ksvm")
lrn.glm = makeLearner("classif.binomial")

# wrapped learner
lrn.nest = makeTuneWrapper(lrn.svm, rdesc.inner, par.set=ps, control=ctrl, show.info=FALSE)
{% endhighlight %}

## Tuning

The parameter can be tuned using `tuneParams()` as shown below - the hyper parameter (C) of SVM without nested resampling is estimated here.


{% highlight r %}
# tune params
set.seed(123457)
res = tuneParams(lrn.svm, task=task, resampling=rdesc.outer, par.set=ps, control=ctrl, show.info=FALSE)
# optimal parameters - res$x
# measure with optimal parameters - res$y
res
{% endhighlight %}



{% highlight text %}
## Tune result:
## Op. pars: C=4; sigma=0.0125806318763427; kernel=rbfdot
## mmce.test.mean=0.242
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
## 1  0.25 0.0126 rbfdot        0.30000   1  NA          <NA>     3.794
## 2  0.50 0.0126 rbfdot        0.28625   2  NA          <NA>     3.481
## 3  1.00 0.0126 rbfdot        0.25700   3  NA          <NA>     3.488
## 4  2.00 0.0126 rbfdot        0.25025   4  NA          <NA>     3.520
## 5  4.00 0.0126 rbfdot        0.24200   5  NA          <NA>     3.408
## 6  8.00 0.0126 rbfdot        0.25225   6  NA          <NA>     3.567
## 7 16.00 0.0126 rbfdot        0.26225   7  NA          <NA>     4.158
{% endhighlight %}

## Benchmark

Once the hyper- or tuning parameter is determined, the learner can be updated using `setHyperPars()`.


{% highlight r %}
# update svm learner
lrn.svm = setHyperPars(lrn.svm, par.vals=res$x)
{% endhighlight %}

The tuned SVM learner can be bechmarked with the logistic regression learner. It is shown that SVM with nested resampling performs slightly worse than logistic regression.


{% highlight r %}
set.seed(123457)
res.bench = benchmark(learners=list(lrn.nest,lrn.svm,lrn.glm), task=task, resampling=rdesc.outer)
res.bench
{% endhighlight %}



{% highlight text %}
##   task.id         learner.id mmce.test.mean
## 1      gc classif.ksvm.tuned        0.24950
## 2      gc       classif.ksvm        0.24200
## 3      gc   classif.binomial        0.24875
{% endhighlight %}

I consider machine/statistical learning tasks are a combination of art (model/feature selection, feature engineering ...) and science (model/algorithm). While the latter part can be relatively straightforward, the former would require good practice, caution, experience, domain knowledge... (generally things that can easily mislead the researcher/practitioner). In other words, fitting models alone is hardly effective. In this regard, I tried benchmarking with some standard resampling strategies first although I'm yet to be aware of a variety of useful models. As having a whole project in mind when learning a new model would be a lot faster to be practical with it, I'll try to cover as much steps as I can in subsequent posts.

<script src='http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' type="text/javascript"></script>