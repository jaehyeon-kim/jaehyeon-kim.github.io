---
layout: post
title: "2015-05-01-R-Tip-a-Day-3-Comparison-Between-lapply-And-do.call"
description: ""
category: R
tags: [caret, programming]
---
In the [previous post](http://jaehyeon-kim.github.io/r/2015/04/25/R-Tip-a-Day-2-Comparison-Packages-for-Data-Manipulation/), several popular packages for data minipulation are compared. In this post, two useful recursive functions (or functionals), `lapply()` and `do.call()`, are compared. This post is based on a [StackOverflow question](http://stackoverflow.com/questions/29902946/apply-confusionmatrix-to-elements-of-a-split-list-in-r/29904689#29904689).

It is about obtaining some model assessment measures (accuracy, sensitivity and specificity) of each of the 3 groups where confusion matrices are obtained using `confusionMatrix()` in the **caret** package. In each group, there are actual values and three fitted values so that a double loop is necessary to obtain all possible confusion matrices - one by group and the other by each of the fitted values. The answer focuses on how to obtain the confusion matrices effectively.

The data is split as following.


{% highlight r %}
library(caret)
set.seed(10)
dat <- data.frame(Group = c(rep(1, 10), rep(2, 10), rep(3, 10)), Actual = round(runif(30, 0, 1)),
                  Preds1 = round(runif(30, 0, 1)), Preds2 = round(runif(30, 0, 1)), Preds3 = round(runif(30, 0, 1)))
dat[] <- lapply(dat, as.factor)

# split by group
dats <- split(dat[,-1], dat$Group)
dats$`1`
{% endhighlight %}



{% highlight text %}
##    Actual Preds1 Preds2 Preds3
## 1       1      1      0      0
## 2       0      0      0      1
## 3       0      0      0      1
## 4       1      1      0      1
## 5       0      0      1      0
## 6       0      1      1      1
## 7       0      1      1      0
## 8       0      1      0      1
## 9       1      1      0      1
## 10      0      1      0      0
{% endhighlight %}

`lapply()` accepts a list so that confusion matrices can be obtained easily. Below a double loop is implemented, resulting in a nested list - i.e. the list has three elements for each of the groups and each group element has three confusion matrices. There is no problem by itself but code has to be complicated to access those matrices as another double loop is necessary.


{% highlight r %}
lapply(dats, function(x) {
  actual <- x[, 1]
  lapply(x[, 2:4], function(y) {
    confusionMatrix(actual, unlist(y))$table
  })
})[1]
{% endhighlight %}



{% highlight text %}
## $`1`
## $`1`$Preds1
##           Reference
## Prediction 0 1
##          0 3 4
##          1 0 3
## 
## $`1`$Preds2
##           Reference
## Prediction 0 1
##          0 4 3
##          1 3 0
## 
## $`1`$Preds3
##           Reference
## Prediction 0 1
##          0 3 4
##          1 1 2
{% endhighlight %}

The structure of the list can be simplified by `do.call()` with a basic function of `c()` as shown below.


{% highlight r %}
do.call(c, lapply(dats, function(x) {
  actual <- x[, 1]
  lapply(x[, 2:4], function(y) {
    confusionMatrix(actual, unlist(y))$table
  })
}))[1:3]
{% endhighlight %}



{% highlight text %}
## $`1.Preds1`
##           Reference
## Prediction 0 1
##          0 3 4
##          1 0 3
## 
## $`1.Preds2`
##           Reference
## Prediction 0 1
##          0 4 3
##          1 3 0
## 
## $`1.Preds3`
##           Reference
## Prediction 0 1
##          0 3 4
##          1 1 2
{% endhighlight %}

The resulting list is not nested and only a single loop is necessary to have access to all the matrices. There is a popular post about comparing the functions ([link](http://stackoverflow.com/questions/10801750/whats-the-difference-between-lapply-and-do-call-in-r)) and, among the answers, I find Paul Hiemstra's answer is quite straightforward.

+ `lapply()` is similar to map, `do.call()` is not. `lapply()` applies a function to all elements of a list, `do.call()` calls a function where all the function arguments are in a list. So for a **n** element list, `lapply()` has **n** function calls, and `do.call()` has just **one** function call...

As far as I understand, in the above example, the list structure becomes simplified as the matrices are combined as `c(dats$1$Preds1, dats$1$Preds2, dats$1$Preds2 ...)` so that the nested structure is simplified.

As [Hadley Wickham (2014)](https://www.crcpress.com/product/isbn/9781466586963) demonstrates, *for-loops* are better to be avoided, not because it is slower than other recursive functions but because it makes code harder to understand. In this regard, I hope this tip is useful to write more readable code.

