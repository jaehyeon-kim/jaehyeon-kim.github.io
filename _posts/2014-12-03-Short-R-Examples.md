---
layout: post
title: "2014-12-03-Short-R-Examples"
description: ""
category: R
tags: [knitr,plyr]
---
As I don't use R at work yet, I haven't got enough chances to learn R by doing. Together with teaching myself machine learning with R, I consider it would be a good idea to collect examples on the web. Recently I have been visiting a Linkedin group called [The R Project for Statistical Computing](http://www.linkedin.com/groups/R-Project-Statistical-Computing-77616?home=&gid=77616&trk=anet_ug_hm) and suggesting scripts on data manipulation or programming topics. Actually I expected some of the topics may also be helpful to learn machine learning/statistics but, possibly due to lack of understaning of the topics in context, I've found only a few - it may be necessary to look for another source. Anyway below is a summary of two examples.

#### Summarise a data frame group by a column

This seems to be a part of an assignment of a Coursera class and the original posting is as following.

- Problem Statement : To find the 'Best' hospital in a particular city under one of the three outcomes(heart attack, heart failure, pneumonia). The data set (dat) contains 54 unique states and a total of 4706 observations with 26 variable columns. Column 11 contains Mortality rate for each hospital(4706) due to heart attack. **Logic is simple as the best hospital would be one with least mortality.** But something is going awry which i'm not able to identify. Please help it out!

As far as I understand, the one who posted this article tried to split the data by state into a list as `x<- split(as.character(dat$Hospital.Name),dat$State)`. Then he was going to combine the list elements after calculating the minimum mortality rate by state.  

Focusing on the logic in bold-cased above, I just created a simple data frame and converted it into another data frame which shows _state_, _name_ and _mininum number_ - an interger vector was assumed rather than mortality rates.

Some notes about the code is

0. It would be good to use a library that provides a comprehensive syntax
    - **plyr** is used
1. **ddply** converts a data frame (**d**dply) into another (d**d**ply)
2. `.data` requires a data frame - dat
3. `.(state)` will group by state when applying a function - eg mininum by state
4. `name = name[num==min(num, na.rm=TRUE)][1]` selects name when `num` is the minimum of num
    - last indexing (`[1]`) is necessary in case there is a tie
    - for example, it'll fail if `num = c(3, 2, 6, 2, 3)` (same number in _state1_)
    - the idea is just selecting the first record when there is a tie


{% highlight r %}
library(knitr)
library(plyr)
{% endhighlight %}


{% highlight r %}
dat <- data.frame(name=c("name1","name2","name3","name4","name5"),
                 num = c(3, 2, 6, 2, 9),
                 state = c("state1","state2","state3","state3","state1"))

# summarise dat by state
sumDat <- ddply(.data=dat, .(state), .drop=FALSE, # missing combination kept
      summarise, name = name[num==min(num, na.rm=TRUE)][1], minNum = min(num, na.rm=TRUE))

# show output
kable(sumDat)
{% endhighlight %}



|state  |name  | minNum|
|:------|:-----|------:|
|state1 |name1 |      3|
|state2 |name2 |      2|
|state3 |name4 |      2|


#### A quick way of simulation

This is a quick way of simulating exponential random variables where the number of variables in each trial is 8 and the rate is fixed to be 1/5. 5000 trials are supposed to be performed and their means and variances are calculated.

The simulation is done using `mapply`, which is a multivariate version of `sapply`. Then `apply` is ued to obtain the sample properties.


{% highlight r %}
# set local variables
n <- 8
times <- 500
rate <- 1/5

set.seed(12347)
# mapply is a multivariate version of sapply
# it allow to apply rexp on a vector rather than a single value
mat <- mapply(rexp, rep(n,times=times), rate=rate)

# apply to get mean and variance
df <- as.data.frame(cbind(apply(mat, 2, mean),apply(mat, 2, var)))
names(df) <- c("mean","var")

# show output
kable(head(df))
{% endhighlight %}



|      mean|       var|
|---------:|---------:|
|  5.755293| 39.998841|
|  7.378336| 64.692667|
| 12.036352| 68.976558|
|  3.454449| 16.025874|
|  5.289533| 11.723384|
|  3.641087|  6.539533|
