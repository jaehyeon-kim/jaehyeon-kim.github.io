---
layout: post
title: "2014-12-17-Looping-without-for"
description: ""
category: R
tags: [plyr, knitr]
---
Purely programming point of view, I consider **for-loops** would be better to be avoided in R as 

* the script can be more readable 
* it is easier to handle errors 

Some articles on the web indicate that looping functions (or apply family of functions) don't guarantee faster execution and sometimes even slower. Although, assuming that the experiments are correct, in my opinion, code readability itself is beneficial enough to avoid for-loops. Even worse, R's dynamic typing system coupled with poor readability can result in a frustrating consequence as the code grows. 

Also one of the R's best IDE (RStudio) doesn't seem to provide an incremental debugging - it may be wrong as I'm new to it. Therefore it is not easy to debug pieces in a for-loop. In this regard, it would be a good idea to refactor for-loops into pieces. 

If one has decided to avoid for-loops, the way how to code would need to be changed. With for-loops, the focus is 'how to get the job done'. One the other hand, if it is replaced with looping functions, the focus should be 'what does the outcome look like'. In other words, the way of thinking should be declarative, rather than imperative.

Below shows two examples from [The R Project for Statistical Computing](http://www.linkedin.com/groups/R-Project-Statistical-Computing-77616?home=&gid=77616&trk=anet_ug_hm) in LinkedIn. Instead of using for-loop, _apply_ family of functions or _plyr_ package are used for recursive computation.

The following packages are used.


{% highlight r %}
library(knitr)
library(plyr)
{% endhighlight %}

#### [How can I set up for function for the following codes?](http://www.linkedin.com/groups/How-can-I-set-up-77616.S.5944557854001238016?trk=groups_search_item_list-0-b-ttl&goback=%2Egna_77616)

In this post, the goal is to create a function that creates a simulated vector with the following code.


{% highlight r %}
n=100
m=1000
mu=c()
sigma2=c()
for(i in 1:m){
  x = rnorm(n)
  s=sum((x-mean(x))^2)
  v=sum(x[1:n-1]^2)
  sigma2[i]=s/v
  mu[i]=mean(x)+x[n]*sqrt(sigma2[i]/n) 
}
{% endhighlight %}

The above for-loop can be replaced easily with `apply` and `mapply` as following.


{% highlight r %}
sim <- function(n, m) {
  # create internal functions
  sigmaSquared <- function(x) {
    sum((x-mean(x))^2) / sum(x[1:length(x)-1]^2)
  }
  mu <- function(x) {
    mean(x) + x[length(x)] + sqrt(sigmaSquared(x) / length(x))
  }
  
  # create random numbers
  set.seed(123457)
  mat <- mapply(rnorm, rep(n, m))
  
  apply(mat, 2, mu)
}
{% endhighlight %}

The function named `sim` is evaluated below.


{% highlight r %}
n <- 100
m <- 1000
simVec <- sim(n, m)

head(simVec)
{% endhighlight %}



{% highlight text %}
## [1]  0.90176825 -0.55948429  0.23258654  0.08713173  0.49159634  0.71904362
{% endhighlight %}

#### [Automatically selecting groups of numeric values in a data frame](http://www.linkedin.com/groups/Automatically-selecting-groups-numeric-values-77616.S.5950288359975899139?trk=groups_followed_item_list-0-b-ttl)

* I'm trying to extract subsets of values from my dataset which are grouped by a value (which could be any number). This column is set by another piece of software and so the code needs to be flexible enough to identify groups of identical numbers without the number being specified. I.e. if value in row10 = row11 then group. For that I have used:


{% highlight r %}
for (n in 1:length(data$BPM)){
  for(i in 1:length(data$Date)){
    bird<-subset(data, Date == Date[i] & BPM == BPM[n], select = c(Date:Power))
    head(bird)
  }
}
{% endhighlight %}

* This seems to work. I then need to identify all of the groups which have >4 rows and separate those from each other.

Here the goal is to select records that have preset _Date_ and _BPM_ pairs. Also it is necessary that the numbers of each group are greater than 4.

Initial selection conditions are shown below. Note that, for simplicity, the groups will be selected only if the numbers are greater than or equal to 2.


{% highlight r %}
# create initial conditions
numRec <- 2 # assumed to be 2 for simplicity
dateFilter <- c(as.Date("2014/12/1"), as.Date("2014/12/3"))
numFilter <- c(1)
{% endhighlight %}

Then a data frame is created.


{% highlight r %}
# create a data frame
set.seed(123457) 
days <- seq(as.Date("2014/12/1"), as.Date("2014/12/3"), "day") 
randDays <- sample(days, size=10, replace=TRUE) 
randBpm <- sample(1:3, size=10, replace=TRUE) 
df <- data.frame(Date=randDays, BPM = randBpm) 
{% endhighlight %}

At first, the data frame is converted into a list by _Date_ and _BPM_ using `ldply`.


{% highlight r %}
# data frame to list by Date and BPM
lst <- dlply(df, .(Date, BPM))
{% endhighlight %}

Then dimensions of each list elements are checked using `sapply`. Then a Boolean vector is created so that the value will be **TRUE** only if the row dimension is greater than 2.


{% highlight r %}
# find which list elements >= numRec
dimDf <- sapply(lst, dim)
isGreater <- dimDf[1,] >= numRec
{% endhighlight %}

Finally the list is converted into a data frame using `ldply` by subsetting the Boolean vector.


{% highlight r %}
# convert into data frame only if # elements >= numRec
exDf <- ldply(lst[isGreater])
kable(subset(exDf, subset = Date %in% dateFilter & BPM %in% numFilter, select = c(-.id)))
{% endhighlight %}



|   |Date       | BPM|
|:--|:----------|---:|
|3  |2014-12-03 |   1|
|4  |2014-12-03 |   1|
|5  |2014-12-03 |   1|
