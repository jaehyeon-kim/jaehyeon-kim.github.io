---
layout: post
title: "2015-01-14-Quick-Trial-to-Add-Column"
description: ""
category: R
tags: [plyr, dplyr, data.table]
---
This is a quick trial of adding overall and conditional (by user) average columns in a data frame. `base`,`plyr`,`dplyr`,`data.table`,`dplyr + data.table` packages are used. Personally I perfer `dplyr + data.table` - `dplyr` for comperhensive syntax and `data.table` for speed.


{% highlight r %}
## set up variables
size <- 36000
numUsers <- 4900
# roughly each user has 7 sessions
numSessions <- (numUsers / 7) - ((numUsers / 7) %% 1)
 
## create data frame
set.seed(123457)
userIds <- sample.int(numUsers, size=size, replace=TRUE)
ssIds <- sample.int(numSessions, size=size, replace=TRUE)
scores <- sample.int(10, size=size, replace=TRUE) 

preDf <- data.frame(User=userIds, Session=ssIds, Score=scores)
preDf$User <- as.factor(preDf$User) 
{% endhighlight %}

#### Adding overall average

As calculating overall average is not complicated, I don't find a big difference among packages.


{% highlight r %}
# base
system.time(overallDf1 <- transform(preDf, MeanScore=mean(Score, na.rm=TRUE))) 
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.001   0.000   0.002
{% endhighlight %}


{% highlight r %}
# plyr
require(plyr)
system.time(overallDf2 <- mutate(preDf, MeanScore=mean(Score, na.rm=TRUE)))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.002   0.000   0.002
{% endhighlight %}


{% highlight r %}
# dplyr
require(dplyr)
system.time(overallDf3 <- preDf %>% 
                            mutate(MeanScore=mean(Score, na.rm=TRUE)))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.007   0.000   0.007
{% endhighlight %}


{% highlight r %}
# data.table
require(data.table)
preDt <- data.table(preDf)
setkey(preDt, User)
system.time(overallDt <- preDt[,list(User=User
                                     ,Session=Session
                                     ,Score=Score
                                     ,MeanScore=mean(Score, na.rm=T))])
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.007   0.000   0.007
{% endhighlight %}


{% highlight r %}
# dplyr + data.table
system.time(overallDf4 <- preDt %>% 
                            mutate(MeanScore=mean(Score, na.rm=TRUE))) 
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.003   0.000   0.003
{% endhighlight %}

#### Adding average by user

It takes quite long using `plyr` and other packages would be more practial - `base` is not considered even.


{% highlight r %}
# plyr
require(plyr)
system.time(postDf1 <- ddply(preDf
                             ,.(User)
                             ,mutate,MeanScore=mean(Score, na.rm=TRUE))) 
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##  76.488   0.522  76.990
{% endhighlight %}


{% highlight r %}
# dplyr
require(dplyr)
system.time(postDf2 <- preDf %>% 
              group_by(User) %>% 
              mutate(MeanScore=mean(Score, na.rm=TRUE)) %>% 
              arrange(User))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.022   0.006   0.028
{% endhighlight %}


{% highlight r %}
# data.table
require(data.table)
preDt <- data.table(preDf)
setkey(preDt, User)
system.time(postDt <- preDt[,list(Session=Session
                                  ,Score=Score
                                  ,MeanScore=mean(Score, na.rm=T))
                            ,by=User])
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.005   0.004   0.009
{% endhighlight %}


{% highlight r %}
# dplyr + data.table
system.time(postDf3 <- preDt %>% 
              group_by(User) %>% 
              mutate(MeanScore=mean(Score, na.rm=TRUE)) %>% 
              arrange(User))
{% endhighlight %}



{% highlight text %}
##    user  system elapsed 
##   0.008   0.004   0.012
{% endhighlight %}
