---
layout: post
title: "2014-12-06-Testing-Charts"
description: ""
category: R
tags: [ggplot2, plyr]
---
This is a quick chart test and the examples are from Chapter 2 of [R Graphic Cookbook](http://shop.oreilly.com/product/0636920023135.do).


{% highlight r %}
library(ggplot2)
library(plyr)
{% endhighlight %}

An introduction to building is shown below.


{% highlight r %}
dat <- data.frame(xval=1:4, yval=c(3,5,6,9), group=c("A","B","B","A"))
p <- ggplot(dat, aes(x=xval, y=yval))
p + geom_point()
p + geom_point(aes(color=group)) # colour by group
p + geom_point(colour="blue") # specify colour
p + geom_point() + scale_x_continuous(limit=c(0,8)) # change x range
p + geom_point() + scale_colour_manual(values=c("red","blue"))
{% endhighlight %}

#### Scatter plot


{% highlight r %}
#qplot(wt, mpg, data=mtcars)
ggplot(mtcars, aes(x=wt, y=mpg)) + geom_point()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/scatter-1.png) 

#### Line chart


{% highlight r %}
#qplot(temperature, pressure, data=pressure, geom="line")
ggplot(pressure, aes(x=temperature, y=pressure)) + geom_line()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/line1-1.png) 


{% highlight r %}
#qplot(temperature, pressure, data=pressure, geom=c("line","point"))
ggplot(pressure, aes(x=temperature, y=pressure)) + geom_line() + geom_point()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/line2-1.png) 

#### Bar graph


{% highlight r %}
BOD <- mutate(BOD, Time=as.factor(Time))
names(BOD) <- tolower(names(BOD))

#qplot(time, demand, data=BOD, geom="bar", stat="identity")
ggplot(BOD, aes(x=time, y=demand)) + geom_bar(stat="identity")
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/bar1-1.png) 


{% highlight r %}
#qplot(cyl, data=mtcars) # numeric <- display all values inbetween
#qplot(factor(cyl), data=mtcars) # factor <- display only if count > 0
ggplot(mtcars, aes(x=factor(cyl))) + geom_bar()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/bar2-1.png) 

#### Histogram


{% highlight r %}
#qplot(mpg, data=mtcars, binwidth=4) # default: binwidth = range/30
ggplot(mtcars, aes(x=mpg)) + geom_histogram(binwidth=4)
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/histogram-1.png) 

#### Box plot


{% highlight r %}
tooth <- mutate(ToothGrowth, inter = interaction(supp, dose))
#qplot(supp, len, data=tooth, geom="boxplot")
ggplot(tooth, aes(x=supp, y=len)) + geom_boxplot()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/box1-1.png) 


{% highlight r %}
#qplot(inter, len, data=tooth, geom="boxplot")
ggplot(tooth, aes(x=inter, y=len)) + geom_boxplot()
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/box2-1.png) 

#### Function curve


{% highlight r %}
myFun <- function(var) { 1/(1 + exp(-var + 10)) }
#qplot(c(0, 20), fun=myFun, stat="function", geom="line")
ggplot(data.frame(x=c(0, 20)), aes(x=x)) + stat_function(fun=myFun, geom="line")
{% endhighlight %}

![center](/figs/2014-12-06-Testing-Charts/function-1.png) 
