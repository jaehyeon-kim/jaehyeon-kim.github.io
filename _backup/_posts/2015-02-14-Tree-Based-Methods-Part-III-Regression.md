---
layout: post
title: "2015-02-14-Tree-Based-Methods-Part-III-Regression"
description: ""
category: R
tags: [dplyr, ggplot2, grid, gridExtra, caret, rpart, rpart.plot]
---
While classificaton tasks are implemented in the last two articles ([Link 1](http://jaehyeon-kim.github.io/r/2015/02/01/Tree-Based-Methods-Part-I/) and [Link 2](http://jaehyeon-kim.github.io/r/2015/02/08/Tree-Based-Methods-Part-II-Cost-Sensitive-Classification/)), a regression task is the topic of this article. While the **caret** package selects the tuning parameter (*cp*) that minimizes the error (*RMSE*), the **rpart** packages recommends the *1-SE rule*, which selects the smallest tree within 1 standard error of the minimum cross validation error (*xerror*). The models with 2 complexity parameters that are suggested by the packages are compared.

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
library(knitr)
library(dplyr)
library(ggplot2)
library(grid)
library(gridExtra)
library(rpart)
library(rpart.plot)
library(caret)
{% endhighlight %}

The *Carseats* data from the **ISLR** package is used - a dummy variable (*High*) is created from *Sales* for classification. Note that the order of the labels is changed from the previous articles for comparison with the regression model.


{% highlight r %}
## data
require(ISLR)
data(Carseats)
# label order changed (No=1)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("No","High")))
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
# response summaries
res.cl.summary = with(Carseats,rbind(table(High),table(High)/length(High)))
res.cl.summary
{% endhighlight %}



{% highlight text %}
##          No   High
## [1,] 164.00 236.00
## [2,]   0.41   0.59
{% endhighlight %}



{% highlight r %}
res.reg.summary = summary(Carseats$Sales)
res.reg.summary
{% endhighlight %}



{% highlight text %}
##    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
##   0.000   5.390   7.490   7.496   9.320  16.270
{% endhighlight %}

The data is split as following.


{% highlight r %}
## split data
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
# classification
trainData.cl = subset(Carseats, select=c(-Sales))[trainIndex,]
testData.cl = subset(Carseats, select=c(-Sales))[-trainIndex,]
# regression
trainData.reg = subset(Carseats, select=c(-High))[trainIndex,]
testData.reg = subset(Carseats, select=c(-High))[-trainIndex,]

# response summary
train.res.cl.summary = with(trainData.cl,rbind(table(High),table(High)/length(High)))
test.res.cl.summary = with(testData.cl,rbind(table(High),table(High)/length(High)))

train.res.reg.summary = summary(trainData.reg$Sales)
test.res.reg.summary = summary(testData.reg$Sales)
{% endhighlight %}



{% highlight r %}
## train model
# set up train control
trControl = trainControl(method="repeatedcv",number=10,repeats=5)
{% endhighlight %}

Having 5 times of 10-fold cross-validation set above, both the CART is fit as both classification and regression tasks.


{% highlight r %}
# classification
set.seed(12357)
mod.cl = train(High ~ .
               ,data=trainData.cl
               ,method="rpart"
               ,tuneLength=20
               ,trControl=trControl)
{% endhighlight %}

Note that the package developer informs that, in spite of the warning messages, the function fits the training data without a problem so that the outcome can be relied upon ([Link](http://stackoverflow.com/questions/26828901/warning-message-missing-values-in-resampled-performance-measures-in-caret-tra)). Note that the criterion is selecting the *cp* that has the lowest *RMSE*.


{% highlight r %}
# regression - caret
set.seed(12357)
mod.reg.caret = train(Sales ~ .
                      ,data=trainData.reg
                      ,method="rpart"
                      ,tuneLength=20
                      ,trControl=trControl)
{% endhighlight %}



{% highlight text %}
## Warning in nominalTrainWorkflow(x = x, y = y, wts = weights, info =
## trainInfo, : There were missing values in resampled performance measures.
{% endhighlight %}

For comparison, the data is fit using `rpart()` where the *cp* value is set to 0. This cp value results in an unpruned tree and *cp* can be selected by the *1-SE rule*, which selects the smallest tree within 1 standard error of the minimum cross validation error (*xerror*), which is recommended by the package. Note that a custom function (`bestParam()`) is used to search the best parameter by the *1-SE rule* and the source can be found [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).


{% highlight r %}
# regression - rpart
source("src/mlUtils.R")
set.seed(12357)
mod.reg.rpart = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=0))
mod.reg.rpart.param = bestParam(mod.reg.rpart$cptable,"CP","xerror","xstd")
mod.reg.rpart.param
{% endhighlight %}



{% highlight text %}
##             lowest        best
## param  0.004852267 0.009349806
## error  0.585672544 0.610102155
## errStd 0.041710792 0.041305185
{% endhighlight %}

If it is necessary to apply the *1-SE rule* on the result by the **caret** package, the `bestParam()` can be used by setting *isDesc* to be *FALSE*. The result is shown below as reference.


{% highlight r %}
mod.reg.caret.param = bestParam(mod.reg.caret$results,"cp","RMSE","RMSESD",isDesc=FALSE)
mod.reg.caret.param
{% endhighlight %}



{% highlight text %}
##            lowest       best
## param  0.00828502 0.05661803
## error  2.23430550 2.38751487
## errStd 0.23521777 0.27267509
{% endhighlight %}

A graphical display of the best *cp* is shown below.


{% highlight r %}
# plot best CP
df = as.data.frame(mod.reg.rpart$cptable)
best = bestParam(mod.reg.rpart$cptable,"CP","xerror","xstd")
ubound = ifelse(best[2,1]+best[3,1]>max(df$xerror),max(df$xerror),best[2,1]+best[3,1])
lbound = ifelse(best[2,1]-best[3,1]<min(df$xerror),min(df$xerror),best[2,1]-best[3,1])

ggplot(data=df[3:nrow(df),], aes(x=CP,y=xerror)) + 
  geom_line() + geom_point() + 
  geom_abline(intercept=ubound,slope=0, color="blue") + 
  geom_abline(intercept=lbound,slope=0, color="blue") + 
  geom_point(aes(x=best[1,2],y=best[2,2]),color="red",size=3)
{% endhighlight %}

![center](/figs/2015-02-14-Tree-Based-Methods-Part-III-Regression/show_best-1.png) 

The best *cp* values for each of the models are shown below


{% highlight r %}
## show best tuned cp
# classification
subset(mod.cl$results,subset=cp==mod.cl$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##   cp  Accuracy     Kappa AccuracySD  KappaSD
## 1  0 0.7262793 0.4340102 0.07561158 0.153978
{% endhighlight %}



{% highlight r %}
# regression - caret
subset(mod.reg.caret$results,subset=cp==mod.reg.caret$bestTune$cp)
{% endhighlight %}



{% highlight text %}
##           cp     RMSE  Rsquared    RMSESD RsquaredSD
## 1 0.00828502 2.234305 0.4342292 0.2352178  0.1025357
{% endhighlight %}



{% highlight r %}
# regression - rpart
mod.reg.rpart.summary = data.frame(t(mod.reg.rpart.param[,2]))
colnames(mod.reg.rpart.summary) = c("CP","xerror","xstd")
mod.reg.rpart.summary
{% endhighlight %}



{% highlight text %}
##            CP    xerror       xstd
## 1 0.009349806 0.6101022 0.04130518
{% endhighlight %}

The training data is refit with the best *cp* values.


{% highlight r %}
## refit the model to the entire training data
# classification
cp.cl = mod.cl$bestTune$cp
mod.cl = rpart(High ~ ., data=trainData.cl, control=rpart.control(cp=cp.cl))

# regression - caret
cp.reg.caret = mod.reg.caret$bestTune$cp
mod.reg.caret = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=cp.reg.caret))

# regression - rpart
cp.reg.rpart = mod.reg.rpart.param[1,2]
mod.reg.rpart = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=cp.reg.rpart))
{% endhighlight %}

Initially it was planned to compare the regression model to the classification model. Specifically, as the response is converted as a binary variable and the break is at the value of *8.0*, it is possible to create a regression version of confusion matrix by splitting the data at the equivalent percentile, which is about *0.59* in this data. Then the outcomes can be compared. However it turns out that they cannot be compared directly as the regression outcome is too good as shown below. Note `updateCM()` and `regCM()` are custom functions and their sources can be found [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550).


{% highlight r %}
## generate confusion matrix on training data
# fit models
fit.cl = predict(mod.cl, type="class")
fit.reg.caret = predict(mod.reg.caret)
fit.reg.rpart = predict(mod.reg.rpart)

# classification
# percentile that Sales is divided by No and High
eqPercentile = with(trainData.reg,length(Sales[Sales<=8])/length(Sales))

# classification
fit.cl.cm = table(data.frame(actual=trainData.cl$High,response=fit.cl))
fit.cl.cm = updateCM(fit.cl.cm,type="Fitted")
fit.cl.cm
{% endhighlight %}



{% highlight text %}
##              Fitted: No Fitted: High Model Error
## actual: No       111.00        21.00        0.16
## actual: High      26.00       163.00        0.14
## Use Error          0.19         0.11        0.15
{% endhighlight %}



{% highlight r %}
# regression with equal percentile is not comparable
probs = eqPercentile
fit.reg.caret.cm = regCM(trainData.reg$Sales, fit.reg.caret, probs=probs, type="Fitted")
fit.reg.caret.cm
{% endhighlight %}



{% highlight text %}
##              Fitted: 59%- Fitted: 59%+ Model Error
## actual: 59%-          185         4.00        0.02
## actual: 59%+            0       132.00        0.00
## Use Error               0         0.03        0.01
{% endhighlight %}

As it is not easy to compare the classification and regression models directly, only the 2 regression models are compared from now on. At first, the regression version of confusion matrices are compared by every 20th percentile followed by the residual mean sqaured error (*RMSE*) values.


{% highlight r %}
# regression with selected percentiles
probs = seq(0.2,0.8,0.2)

# regression - caret
# caret produces a better outcome on training data - note lower cp
fit.reg.caret.cm = regCM(trainData.reg$Sales, fit.reg.caret, probs=probs, type="Fitted")
kable(fit.reg.caret.cm)
{% endhighlight %}



|             | Fitted: 20%-| Fitted: 40%-| Fitted: 60%-| Fitted: 80%-| Fitted: 80%+| Model Error|
|:------------|------------:|------------:|------------:|------------:|------------:|-----------:|
|actual: 20%- |        65.00|            0|          0.0|         0.00|            0|        0.00|
|actual: 40%- |         1.00|           49|         14.0|         0.00|            0|        0.23|
|actual: 60%- |         0.00|            0|         56.0|         8.00|            0|        0.12|
|actual: 80%- |         0.00|            0|          0.0|        64.00|            0|        0.00|
|actual: 80%+ |         0.00|            0|          0.0|        16.00|           48|        0.25|
|Use Error    |         0.02|            0|          0.2|         0.27|            0|        0.12|





{% highlight r %}
# regression - rpart
fit.reg.rpart.cm = regCM(trainData.reg$Sales, fit.reg.rpart, probs=probs, type="Fitted")
kable(fit.reg.rpart.cm)
{% endhighlight %}



|             | Fitted: 20%-| Fitted: 40%-| Fitted: 60%-| Fitted: 80%-| Fitted: 80%+| Model Error|
|:------------|------------:|------------:|------------:|------------:|------------:|-----------:|
|actual: 20%- |           59|         6.00|         0.00|         0.00|            0|        0.09|
|actual: 40%- |            0|        50.00|        14.00|         0.00|            0|        0.22|
|actual: 60%- |            0|         0.00|        64.00|         0.00|            0|        0.00|
|actual: 80%- |            0|         0.00|        24.00|        40.00|            0|        0.38|
|actual: 80%+ |            0|         0.00|         0.00|        33.00|           31|        0.52|
|Use Error    |            0|         0.11|         0.37|         0.45|            0|        0.24|





{% highlight r %}
# fitted RMSE
fit.reg.caret.rmse = sqrt(sum(trainData.reg$Sales-fit.reg.caret)^2/length(trainData.reg$Sales))
fit.reg.caret.rmse
{% endhighlight %}



{% highlight text %}
## [1] 2.738924e-15
{% endhighlight %}



{% highlight r %}
fit.reg.rpart.rmse = sqrt(sum(trainData.reg$Sales-fit.reg.rpart)^2/length(trainData.reg$Sales))
fit.reg.rpart.rmse
{% endhighlight %}



{% highlight text %}
## [1] 2.788497e-15
{% endhighlight %}

It turns out that the model by the *caret* package produces a better fit and it can also be checked by *RMSE* values. This is understandable as the model by the *caret* package takes the *cp* that minimizes *RMSE* while the one by the *rpart* package accepts some more error in favor of a smaller tree by the `1-SE rule`. Besides their different resampling strateges can be a source that makes it difficult to compare the outcomes directly. 

As their performance on the test data is more important, they are compared on it.


{% highlight r %}
## generate confusion matrix on test data
# fit models
pred.reg.caret = predict(mod.reg.caret, newdata=testData.reg)
pred.reg.rpart = predict(mod.reg.rpart, newdata=testData.reg)

# regression - caret
pred.reg.caret.cm = regCM(testData.reg$Sales, pred.reg.caret, probs=probs)
kable(pred.reg.caret.cm)
{% endhighlight %}



|             | Pred: 20%-| Pred: 40%-| Pred: 60%-| Pred: 80%-| Pred: 80%+| Model Error|
|:------------|----------:|----------:|----------:|----------:|----------:|-----------:|
|actual: 20%- |         11|       5.00|       0.00|          0|       0.00|        0.31|
|actual: 40%- |          0|      15.00|       1.00|          0|       0.00|        0.06|
|actual: 60%- |          0|       0.00|      15.00|          0|       0.00|        0.00|
|actual: 80%- |          0|       0.00|       0.00|         15|       1.00|        0.06|
|actual: 80%+ |          0|       0.00|       0.00|          0|      16.00|        0.00|
|Use Error    |          0|       0.25|       0.06|          0|       0.06|        0.09|





{% highlight r %}
# regression - rpart
pred.reg.rpart.cm = regCM(testData.reg$Sales, pred.reg.rpart, probs=probs)
kable(pred.reg.rpart.cm)
{% endhighlight %}



|             | Pred: 20%-| Pred: 40%-| Pred: 60%-| Pred: 80%-| Pred: 80%+| Model Error|
|:------------|----------:|----------:|----------:|----------:|----------:|-----------:|
|actual: 20%- |         10|        6.0|        0.0|          0|       0.00|        0.38|
|actual: 40%- |          0|        9.0|        7.0|          0|       0.00|        0.44|
|actual: 60%- |          0|        0.0|       15.0|          0|       0.00|        0.00|
|actual: 80%- |          0|        0.0|        8.0|          6|       2.00|        0.62|
|actual: 80%+ |          0|        0.0|        0.0|          0|      16.00|        0.00|
|Use Error    |          0|        0.4|        0.5|          0|       0.11|        0.29|





{% highlight r %}
pred.reg.caret.rmse = sqrt(sum(testData.reg$Sales-pred.reg.caret)^2/length(testData.reg$Sales))
pred.reg.caret.rmse
{% endhighlight %}



{% highlight text %}
## [1] 1.178285
{% endhighlight %}



{% highlight r %}
pred.reg.rpart.rmse = sqrt(sum(testData.reg$Sales-pred.reg.rpart)^2/length(testData.reg$Sales))
pred.reg.rpart.rmse
{% endhighlight %}



{% highlight text %}
## [1] 1.955439
{% endhighlight %}

Even on the test data, the model by the *caret* package performs well and it seems that the cost of selecting a smaller tree by the *1-SE rule* may be too much on this data set.

Below shows some plots on the model by the *caret* package on the test data.


{% highlight r %}
## plot actual vs prediced and resid vs fitted
mod.reg.caret.test = rpart(Sales ~ ., data=testData.reg, control=rpart.control(cp=cp.reg.caret))
predDF = data.frame(actual=testData.reg$Sales
                    ,predicted=pred.reg.caret
                    ,resid=resid(mod.reg.caret.test))

# actual vs predicted
actual.plot = ggplot(predDF, aes(x=predicted,y=actual)) + 
  geom_point(shape=1,position=position_jitter(width=0.1,height=0.1)) + 
  geom_smooth(method=lm,se=FALSE)

# resid vs predicted
resid.plot = ggplot(predDF, aes(x=predicted,y=resid)) + 
  geom_point(shape=1,position=position_jitter(width=0.1,height=0.1)) + 
  geom_smooth(method=lm,se=FALSE)

grid.arrange(actual.plot, resid.plot, ncol = 2)
{% endhighlight %}

![center](/figs/2015-02-14-Tree-Based-Methods-Part-III-Regression/caret_test-1.png) 

Finally the following shows the CART model tree on the training data.


{% highlight r %}
# plot tree
cols <- ifelse(mod.reg.caret$frame$yval > 8,"green4","darkred") # green if high
prp(mod.reg.caret
    ,main="CART Model Tree"
    #,extra=106           # display prob of survival and percent of obs
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
## cex 0.65   xlim c(0, 1)   ylim c(0, 1)
{% endhighlight %}

![center](/figs/2015-02-14-Tree-Based-Methods-Part-III-Regression/model_tree-1.png) 
