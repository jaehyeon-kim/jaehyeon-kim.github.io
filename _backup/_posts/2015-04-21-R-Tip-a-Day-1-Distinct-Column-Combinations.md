---
layout: post
title: "2015-04-21-R-Tip-a-Day-1-Distinct-Column-Combinations"
description: ""
category: R
tags: [programming]
---
This is the first article of this series. One or two tips are going to be included and they are mostly from R-related groups in LinkedIn, StackOverflow, Quora ...

The tip of this post is from the [R Programming](http://www.linkedin.com/grp/home?gid=2229532&sort=RECENT) group of Linkedin and it is included below.

* * *

*Unique Spans in an R data frame?*

Is there a function in R that returns a set of columns that can uniquely identify any set of  rows (not row number) not including any form of measures (so only factors, levels, categories...).

For example:

{% highlight r %}
A B C
1 2 3
2 3 4
3 4 4

A B C
1 1 2
1 2 2
2 1 2
{% endhighlight %}

For First data set, both A and B can uniquely identify any one column. For Second data set, A and B combined can determine anyone row. Another way of explaining it, is there a function that when given a data frame provides the minimum set of factors/levels to describe every instance within that data frame? It could provide multiple spans if more than one exists (so for example 1 it would provide both columns as a solution).

If not, I can produce, but wanted to see if someone has written the code to solve this problem already. Potentially use that library.

* * *

Single columns of the second data frame don't determine rows, but the first and second columns combined. In order to take this kind of cases into account, it is necessary to consider all combinations of columns recursively. This is handled using `Map()` and `do.call()` together. `Map()` is like an extension of `lapply()` where a function is applied to varying number of elements (*1:ncol()*) while `do.call()` reduces a list given a function - `mapply()` can also be used instead of `Map()`. The result that keeps all combinations of column indices in a list by combining these functions are shown below.


{% highlight r %}
df <- data.frame(A = c(1,1,2),
                 B = c(1,2,1),
                 C = c(2,2,2))

comb <- do.call(c, Map(combn, ncol(df), 1:ncol(df), simplify = FALSE))
comb
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] 1
## 
## [[2]]
## [1] 2
## 
## [[3]]
## [1] 3
## 
## [[4]]
## [1] 1 2
## 
## [[5]]
## [1] 1 3
## 
## [[6]]
## [1] 2 3
## 
## [[7]]
## [1] 1 2 3
{% endhighlight %}

Then a UDF (`pste()`) is created by combinding `lapply()` and `do.call()`. The purpose of this function is to select values given a vector of column indices (`lapply()`) and to paste them (`do.call()`). Then this function is applied to all combinations of column indices (*comb*).


{% highlight r %}
pste <- function(arg) {
    do.call(paste, lapply(df[, arg, drop = FALSE], c))
}    
concat <- lapply(comb, pste)
concat
{% endhighlight %}



{% highlight text %}
## [[1]]
## [1] "1" "1" "2"
## 
## [[2]]
## [1] "1" "2" "1"
## 
## [[3]]
## [1] "2" "2" "2"
## 
## [[4]]
## [1] "1 1" "1 2" "2 1"
## 
## [[5]]
## [1] "1 2" "1 2" "2 2"
## 
## [[6]]
## [1] "1 2" "2 2" "1 2"
## 
## [[7]]
## [1] "1 1 2" "1 2 2" "2 1 2"
{% endhighlight %}

As pasted column values uniquely determine rows if they are unique, all non-unique pasted values can be checked if the length of unique pasted values equals to the number of rows. It is checked by another `lapply()` and named as *uqe_col*, which concludes `uniqueCol()`.


{% highlight r %}
uniqueCol <- function(x) {
    out <- list()
    # get combinations of column indices in a list
    comb <- do.call(c, Map(combn, ncol(x), 1:ncol(x), simplify = FALSE))
    out$col <- comb
    # concatenate values column wise
    pste <- function(arg) {
        do.call(paste, lapply(x[, arg, drop = FALSE], c))
    }    
    concat <- lapply(comb, pste)
    # set NA if not unique
    concat_uqe <- lapply(concat, unique)
    uqe_col <- lapply(concat_uqe,
                      function(arg) if(length(arg)==nrow(x)) arg else NA)
    out$uqe <- uqe_col
    out
}

uniqueCol(df)
{% endhighlight %}



{% highlight text %}
## $col
## $col[[1]]
## [1] 1
## 
## $col[[2]]
## [1] 2
## 
## $col[[3]]
## [1] 3
## 
## $col[[4]]
## [1] 1 2
## 
## $col[[5]]
## [1] 1 3
## 
## $col[[6]]
## [1] 2 3
## 
## $col[[7]]
## [1] 1 2 3
## 
## 
## $uqe
## $uqe[[1]]
## [1] NA
## 
## $uqe[[2]]
## [1] NA
## 
## $uqe[[3]]
## [1] NA
## 
## $uqe[[4]]
## [1] "1 1" "1 2" "2 1"
## 
## $uqe[[5]]
## [1] NA
## 
## $uqe[[6]]
## [1] NA
## 
## $uqe[[7]]
## [1] "1 1 2" "1 2 2" "2 1 2"
{% endhighlight %}

As can be seen above, both columns 1 and 2 or all columns uniquely determine rows. I hope this tip is helpful to get familiar with recursive functions.
