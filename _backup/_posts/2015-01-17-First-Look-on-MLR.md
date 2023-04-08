---
layout: post
title: "2015-01-17-First-Look-on-MLR"
description: ""
category: R
tags: [mlr]
---
R is an open source tool and contribution is made from various fields. In many ways, this can have positive influences but there is a concern that its syntax or API can be quite *non-standardized*. I've looked for a way that various models can be applied consistently for a while and the following two packages are found: [mlr](https://github.com/berndbischl/mlr/) and [caret](https://github.com/topepo/caret).

Among these, I'm more interested in **mlr** as its objects that are related to model building seem to be structured more clearly and strictly, which can be additional benefit while analysis gets complicated.

According to the [tutorial](http://berndbischl.github.io/mlr/tutorial/html/index.html), typical analysis would be performed as following. 

0. Imputation, Processing ...
1. **Task**
2. **Learner**
3. **Train**
4. **Predict**
5. **Performance**
6. Resampling
7. Benchmark

In this article, steps 1 to 5 are briefly introduced by reiterating *Chapter 4 Lab* of [ISLR](http://www-bcf.usc.edu/~gareth/ISL/) - i.e. *logistic regression* is fit on *Smarket* data using *stats* and *mlr* packages.

In order to fit *logistic regression* using *mlr*, the development version (v2.3) has to be installed as `classif.binomial` is yet to be added into the stable version (v2.2) - for further details, see [here](https://github.com/berndbischl/mlr/blob/master/NEWS). Note that [Rtools](http://cran.r-project.org/bin/windows/Rtools/) should be installed to build the packages on Windows.


{% highlight r %}
# dev install
devtools::install_github("berndbischl/ParamHelpers")
devtools::install_github("berndbischl/BBmisc")
devtools::install_github("berndbischl/parallelMap")
devtools::install_github("berndbischl/mlr")
{% endhighlight %}

The following packages are loaded.


{% highlight r %}
library(ISLR)
library(mlr)
{% endhighlight %}

The structure of the data (*Smarket*) is shown below - *Year* and *Today* are going to be excluded.


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

#### Test on training data

##### ISLR

Matching objects for *Task* and *Learner* steps don't exist on *stats* package.

###### 3. Train


{% highlight r %}
glm.mod = glm(Direction ~ ., data=subset(Smarket, select=c(-Year, -Today)), family=binomial)
summary(glm.mod)
{% endhighlight %}



{% highlight text %}
## 
## Call:
## glm(formula = Direction ~ ., family = binomial, data = subset(Smarket, 
##     select = c(-Year, -Today)))
## 
## Deviance Residuals: 
##    Min      1Q  Median      3Q     Max  
## -1.446  -1.203   1.065   1.145   1.326  
## 
## Coefficients:
##              Estimate Std. Error z value Pr(>|z|)
## (Intercept) -0.126000   0.240736  -0.523    0.601
## Lag1        -0.073074   0.050167  -1.457    0.145
## Lag2        -0.042301   0.050086  -0.845    0.398
## Lag3         0.011085   0.049939   0.222    0.824
## Lag4         0.009359   0.049974   0.187    0.851
## Lag5         0.010313   0.049511   0.208    0.835
## Volume       0.135441   0.158360   0.855    0.392
## 
## (Dispersion parameter for binomial family taken to be 1)
## 
##     Null deviance: 1731.2  on 1249  degrees of freedom
## Residual deviance: 1727.6  on 1243  degrees of freedom
## AIC: 1741.6
## 
## Number of Fisher Scoring iterations: 3
{% endhighlight %}



{% highlight r %}
# coef(glm.mod) # also summary(glm.mod)$coef[,4]
{% endhighlight %}

###### 4. Predict


{% highlight r %}
# type = c("link","response","terms"), default - "link"
glm.probs = predict(glm.mod, type="response")
head(glm.probs) # check positive level (1): contrasts(Smarket$Direction)
{% endhighlight %}



{% highlight text %}
##         1         2         3         4         5         6 
## 0.5070841 0.4814679 0.4811388 0.5152224 0.5107812 0.5069565
{% endhighlight %}



{% highlight r %}
glm.pred = sapply(glm.probs, function(p) { ifelse(p>.5,"Up","Down") })
head(glm.pred)
{% endhighlight %}



{% highlight text %}
##      1      2      3      4      5      6 
##   "Up" "Down" "Down"   "Up"   "Up"   "Up"
{% endhighlight %}

###### 5. Performance


{% highlight r %}
glm.cm = table(data.frame(response=glm.pred, truth=Smarket$Direction))
glm.cm # confusion matrix
{% endhighlight %}



{% highlight text %}
##         truth
## response Down  Up
##     Down  145 141
##     Up    457 507
{% endhighlight %}



{% highlight r %}
# mean misclassificaton error rate 47.84%
glm.mmse = 1 - sum(diag(glm.cm)) / sum(glm.cm)
glm.mmse
{% endhighlight %}



{% highlight text %}
## [1] 0.4784
{% endhighlight %}

##### MLR

###### 1. Task


{% highlight r %}
mlr.glm.task = makeClassifTask(id="Smarket", data=subset(Smarket, select=c(-Year, -Today)), positive="Up", target="Direction")
mlr.glm.task
{% endhighlight %}



{% highlight text %}
## Supervised task: Smarket
## Type: classif
## Target: Direction
## Observations: 1250
## Features:
## numerics  factors  ordered 
##        6        0        0 
## Missings: FALSE
## Has weights: FALSE
## Has blocking: FALSE
## Classes: 2
## Down   Up 
##  602  648 
## Positive class: Up
{% endhighlight %}

###### 2. Learner


{% highlight r %}
mlr.glm.lrn = makeLearner("classif.binomial", predict.type="prob")
mlr.glm.lrn
{% endhighlight %}



{% highlight text %}
## Learner classif.binomial from package stats
## Type: classif
## Name: Binomial Regression; Short name: binomial
## Class: classif.binomial
## Properties: twoclass,numerics,factors,prob,weights
## Predict-Type: prob
## Hyperparameters:
{% endhighlight %}

###### 3. Train


{% highlight r %}
mlr.glm.mod = train(mlr.glm.lrn, mlr.glm.task)
mlr.glm.mod
{% endhighlight %}



{% highlight text %}
## Model for id = classif.binomial class = classif.binomial
## Trained on obs: 1250
## Used features: 6
## Hyperparameters:
{% endhighlight %}

###### 4. Predict


{% highlight r %}
## prediction - model + either task or newdata but not both
mlr.glm.pred = predict(object=mlr.glm.mod, task=mlr.glm.task)
mlr.glm.pred
{% endhighlight %}



{% highlight text %}
## Prediction: 1250 observations
## predict.type: prob
## threshold: Down=0.50,Up=0.50
## time: 0.00
##   id truth prob.Down   prob.Up response
## 1  1    Up 0.4929159 0.5070841       Up
## 2  2    Up 0.5185321 0.4814679     Down
## 3  3  Down 0.5188612 0.4811388     Down
## 4  4    Up 0.4847776 0.5152224       Up
## 5  5    Up 0.4892188 0.5107812       Up
## 6  6    Up 0.4930435 0.5069565       Up
{% endhighlight %}

###### 5. Performance


{% highlight r %}
mlr.glm.cm = table(subset(mlr.glm.pred$data, select=c("response","truth")))
mlr.glm.cm
{% endhighlight %}



{% highlight text %}
##         truth
## response Down  Up
##     Down  145 141
##     Up    457 507
{% endhighlight %}



{% highlight r %}
mlr.glm.mmse = 1 - sum(diag(mlr.glm.cm)) / sum(mlr.glm.cm)
mlr.glm.mmse
{% endhighlight %}



{% highlight text %}
## [1] 0.4784
{% endhighlight %}



{% highlight r %}
# or simply
mlr.glm.mmse = performance(mlr.glm.pred) # default: mean misclassification error (mmse)
mlr.glm.mmse
{% endhighlight %}



{% highlight text %}
##   mmce 
## 0.4784
{% endhighlight %}



{% highlight r %}
# see available measures - listMeasures(task.name)
{% endhighlight %}

So far the model is tested on the training data and the resulting test error (mean misclassifcation error) is likely to be overly optimistic. Below the model is tested on an independent data to obtain a more reliable test error rate.

#### Test on independent data


{% highlight r %}
Smarket.train = subset(Smarket, Year != 2005, select=c(-Year, -Today))
Smarket.test = subset(Smarket, Year == 2005, select=c(-Year, -Today))
{% endhighlight %}

##### ISLR

###### 3. Train


{% highlight r %}
glm.mod.new = glm(Direction ~ ., data=Smarket.train, family=binomial)
glm.mod.new
{% endhighlight %}



{% highlight text %}
## 
## Call:  glm(formula = Direction ~ ., family = binomial, data = Smarket.train)
## 
## Coefficients:
## (Intercept)         Lag1         Lag2         Lag3         Lag4  
##    0.191213    -0.054178    -0.045805     0.007200     0.006441  
##        Lag5       Volume  
##   -0.004223    -0.116257  
## 
## Degrees of Freedom: 997 Total (i.e. Null);  991 Residual
## Null Deviance:	    1383 
## Residual Deviance: 1381 	AIC: 1395
{% endhighlight %}

###### 4. Predict


{% highlight r %}
glm.probs.new = predict(glm.mod.new, newdata=Smarket.test, type="response")
head(glm.probs.new)
{% endhighlight %}



{% highlight text %}
##       999      1000      1001      1002      1003      1004 
## 0.5282195 0.5156688 0.5226521 0.5138543 0.4983345 0.5010912
{% endhighlight %}



{% highlight r %}
glm.pred.new = sapply(glm.probs.new, function(p) { ifelse(p>.5,"Up","Down") })
head(glm.pred.new)
{% endhighlight %}



{% highlight text %}
##    999   1000   1001   1002   1003   1004 
##   "Up"   "Up"   "Up"   "Up" "Down"   "Up"
{% endhighlight %}

###### 5. Performance


{% highlight r %}
glm.cm.new = table(data.frame(response=glm.pred.new, truth=Smarket.test$Direction))
glm.cm.new
{% endhighlight %}



{% highlight text %}
##         truth
## response Down Up
##     Down   77 97
##     Up     34 44
{% endhighlight %}



{% highlight r %}
glm.mmse.new = 1 - sum(diag(glm.cm.new)) / sum(glm.cm.new)
glm.mmse.new
{% endhighlight %}



{% highlight text %}
## [1] 0.5198413
{% endhighlight %}

##### MLR

###### 1. Task


{% highlight r %}
mlr.glm.task.new = makeClassifTask(id="SmarketNew", data=Smarket.train, positive="Up", target="Direction")
mlr.glm.task.new
{% endhighlight %}



{% highlight text %}
## Supervised task: SmarketNew
## Type: classif
## Target: Direction
## Observations: 998
## Features:
## numerics  factors  ordered 
##        6        0        0 
## Missings: FALSE
## Has weights: FALSE
## Has blocking: FALSE
## Classes: 2
## Down   Up 
##  491  507 
## Positive class: Up
{% endhighlight %}

###### 2. Learner


{% highlight r %}
mlr.glm.lrn.new = mlr.glm.lrn # learner can be reused
{% endhighlight %}

###### 3. Train


{% highlight r %}
mlr.glm.mod.new = train(mlr.glm.lrn.new, mlr.glm.task.new)
mlr.glm.mod.new
{% endhighlight %}



{% highlight text %}
## Model for id = classif.binomial class = classif.binomial
## Trained on obs: 998
## Used features: 6
## Hyperparameters:
{% endhighlight %}

###### 4. Predict


{% highlight r %}
## prediction - model + either task or newdata but not both
mlr.glm.pred.new = predict(object=mlr.glm.mod.new, newdata=Smarket.test)
mlr.glm.pred.new
{% endhighlight %}



{% highlight text %}
## Prediction: 252 observations
## predict.type: prob
## threshold: Down=0.50,Up=0.50
## time: 0.00
##      truth prob.Down   prob.Up response
## 999   Down 0.4717805 0.5282195       Up
## 1000  Down 0.4843312 0.5156688       Up
## 1001  Down 0.4773479 0.5226521       Up
## 1002    Up 0.4861457 0.5138543       Up
## 1003  Down 0.5016655 0.4983345     Down
## 1004    Up 0.4989088 0.5010912       Up
{% endhighlight %}

###### 5. Performance


{% highlight r %}
mlr.glm.mmse.new = performance(mlr.glm.pred.new)
mlr.glm.mmse.new
{% endhighlight %}



{% highlight text %}
##      mmce 
## 0.5198413
{% endhighlight %}

Above is a quick introcution to *mlr*. I consider the real benefits of using this package would be demonstrated better in *Resampling* and *Benchmark* steps as well as its native support of parallel computing. These will be topics of subsequent articles.
