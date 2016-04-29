---
layout: post
title: "2015-05-09-R-Tip-a-Day-5-Function-Composition"
description: ""
category: R
tags: [data.table, programming]
---
In the [previous post](http://jaehyeon-kim.github.io/r/2015/05/04/R-Tip-a-Day-4-Generic-Bootstrapper-Using-Closure-And-Functional/), a generic bootstrapper is created using two higher order functions: **closure** and **functional**. The closure is used to set up bootstrap configuration and it returns an anonymous functional that accepts another function that fits a model - `lm()` and `rpart()` are used as an example. Having a function as an argument enables the bootstrapper to be generic and its main benefit is to achieve **succint code** - in my opinion, there would be many use cases of this kind as R's support to object oriented programming is somewhat limited.

In this post, another way of applying higher order functions is illustrated by **function composition** - this example is from a [StackOverflow question](http://stackoverflow.com/questions/30086163/simplest-way-to-create-wrapper-functions/30086519#30086519). Two functions are under consideration: `prop.table()` and `table()`. While the latter returns a contingency table, the former returns marginal proportions given a value of its margin argument - eg 1 by row and 2 by column. Before moving forward, it'd be necessary to show simple examples of these functions.


{% highlight r %}
## simple examples
set.seed(1237)
val1 <- sample(5, size = 10, replace = TRUE)
val2 <- letters[sample(4, 10, replace = TRUE)]
tbl <- table(val1, val2)
tbl
{% endhighlight %}



{% highlight text %}
##     val2
## val1 a b c d
##    1 1 1 1 0
##    2 1 1 0 0
##    4 1 0 0 0
##    5 1 1 0 2
{% endhighlight %}



{% highlight r %}
# proportion by row
prop.table(tbl, margin = 1)
{% endhighlight %}



{% highlight text %}
##     val2
## val1         a         b         c         d
##    1 0.3333333 0.3333333 0.3333333 0.0000000
##    2 0.5000000 0.5000000 0.0000000 0.0000000
##    4 1.0000000 0.0000000 0.0000000 0.0000000
##    5 0.2500000 0.2500000 0.0000000 0.5000000
{% endhighlight %}

The question is how to wrap `table()` in `prop.table()`. Usually it can be implemented simply by adding `table()` and the additional arguments within `prop.table()` followed by specifying the remaining argument of `prop.table()`. However the requirement is to create a function where the arguments of both the functions are as if those that were of a single function. Both the usual and requested implementations are shown below.


{% highlight r %}
## usual implementation
dt[,prop.table(table(grp, id, useNA="always"), margin=1)]

## requested implementation
dt[,prop.table2(grp, id, useNA="always", margin=1)]
{% endhighlight %}

The following data set is provided in the question.


{% highlight r %}
library(data.table)
set.seed(1237)
dt<-data.table(id=sample(5,size=100,replace=T),
               grp=letters[sample(4,size=100,replace=T)])
{% endhighlight %}

As the name suggests, two functions (`f()` and `g()`) are composed by `compose()`. *margin* is one of the two arguments of `proc.table()` and it is set to be 1. In the body, an anonymous function is set up by wrapping `g()` within `f()`. This function has unspecified arguments (...) and additional arguments of `table()` can be specified with it. The two functions should be specified as `compose()` just returns a function, not data, and it is done using `prop()`. Finally this function is used within a *data.table* object.


{% highlight r %}
# implementation by function composition
compose <- function(f, g, margin = 1) {
  function(...) f(g(...), margin)
}

# specifying functions to be composed of
prop <- compose(prop.table, table)

dt[,prop(grp, id, useNA = "always")]
{% endhighlight %}



{% highlight text %}
##       id
## grp             1          2          3          4          5       <NA>
##   a    0.23529412 0.17647059 0.11764706 0.23529412 0.23529412 0.00000000
##   b    0.11764706 0.29411765 0.05882353 0.17647059 0.35294118 0.00000000
##   c    0.11538462 0.19230769 0.30769231 0.15384615 0.23076923 0.00000000
##   d    0.34782609 0.13043478 0.13043478 0.17391304 0.21739130 0.00000000
##   <NA>
{% endhighlight %}

Below is another implementation and it separates arguments by matching the formal of `prop.table()` (*args*).


{% highlight r %}
# another implementation
prop.table2 <- function(...){
  dots <- list(...)
  passed <- names(dots)
  # filter args based on prop.table's formals
  args <- passed %in% names(formals(prop.table))
  do.call('prop.table', c(list(do.call('table', dots[!args])), dots[args]))
}

dt[, prop.table2(grp, id, useNA="always", margin = 1)]
{% endhighlight %}



{% highlight text %}
##       
##                 1          2          3          4          5       <NA>
##   a    0.23529412 0.17647059 0.11764706 0.23529412 0.23529412 0.00000000
##   b    0.11764706 0.29411765 0.05882353 0.17647059 0.35294118 0.00000000
##   c    0.11538462 0.19230769 0.30769231 0.15384615 0.23076923 0.00000000
##   d    0.34782609 0.13043478 0.13043478 0.17391304 0.21739130 0.00000000
##   <NA>
{% endhighlight %}

A quick comparison between the two would be `prop()` is generic while `prop.table2()` is not. However the latter can be more useful where both the functions have many arguments. For example, the following doesn't work and I haven't found a way to separate ... between the two.


{% highlight r %}
# implementation by function composition
compose <- function(f, g, ...) {
  function(...) f(g(...), margin)
}
{% endhighlight %}
