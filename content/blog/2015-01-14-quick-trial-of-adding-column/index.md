---
title: Quick Trial of Adding Column
date: 2015-01-14
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Tree based methods in R
categories:
  - Data Analysis
tags:
  - R
authors:
  - JaehyeonKim
images: []
description: This is a quick trial of adding overall and conditional (by user) average columns in a data frame.
---

This is a quick trial of adding overall and conditional (by user) average columns in a data frame. `base`,`plyr`,`dplyr`,`data.table`,`dplyr + data.table` packages are used. Personally I perfer `dplyr + data.table` - `dplyr` for comperhensive syntax and `data.table` for speed.


```r
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
```

## Adding overall average

As calculating overall average is not complicated, I don't find a big difference among packages.


```r
# base
system.time(overallDf1 <- transform(preDf, MeanScore=mean(Score, na.rm=TRUE))) 
```



```
##    user  system elapsed 
##   0.001   0.000   0.002
```


```r
# plyr
require(plyr)
system.time(overallDf2 <- mutate(preDf, MeanScore=mean(Score, na.rm=TRUE)))
```



```
##    user  system elapsed 
##   0.002   0.000   0.002
```


```r
# dplyr
require(dplyr)
system.time(overallDf3 <- preDf %>% 
                            mutate(MeanScore=mean(Score, na.rm=TRUE)))
```



```
##    user  system elapsed 
##   0.007   0.000   0.007
```


```r
# data.table
require(data.table)
preDt <- data.table(preDf)
setkey(preDt, User)
system.time(overallDt <- preDt[,list(User=User
                                     ,Session=Session
                                     ,Score=Score
                                     ,MeanScore=mean(Score, na.rm=T))])
```



```
##    user  system elapsed 
##   0.007   0.000   0.007
```


```r
# dplyr + data.table
system.time(overallDf4 <- preDt %>% 
                            mutate(MeanScore=mean(Score, na.rm=TRUE))) 
```



```
##    user  system elapsed 
##   0.003   0.000   0.003
```

## Adding average by user

It takes quite long using `plyr` and other packages would be more practial - `base` is not considered even.


```r
# plyr
require(plyr)
system.time(postDf1 <- ddply(preDf
                             ,.(User)
                             ,mutate,MeanScore=mean(Score, na.rm=TRUE))) 
```



```
##    user  system elapsed 
##  76.488   0.522  76.990
```


```r
# dplyr
require(dplyr)
system.time(postDf2 <- preDf %>% 
              group_by(User) %>% 
              mutate(MeanScore=mean(Score, na.rm=TRUE)) %>% 
              arrange(User))
```



```
##    user  system elapsed 
##   0.022   0.006   0.028
```


```r
# data.table
require(data.table)
preDt <- data.table(preDf)
setkey(preDt, User)
system.time(postDt <- preDt[,list(Session=Session
                                  ,Score=Score
                                  ,MeanScore=mean(Score, na.rm=T))
                            ,by=User])
```



```
##    user  system elapsed 
##   0.005   0.004   0.009
```


```r
# dplyr + data.table
system.time(postDf3 <- preDt %>% 
              group_by(User) %>% 
              mutate(MeanScore=mean(Score, na.rm=TRUE)) %>% 
              arrange(User))
```



```
##    user  system elapsed 
##   0.008   0.004   0.012
```
