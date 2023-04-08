---
layout: post
title: "2015-04-25-R-Tip-a-Day-2-Comparison-Packages-for-Data-Manipulation"
description: ""
category: R
tags: [base, plyr, dplyr, data.table, programming]
---
In the [first post](http://jaehyeon-kim.github.io/r/2015/04/21/R-Tip-a-Day-1-Distinct-Column-Combinations/) of this series, a function (`uniqueCol()`) is illustrated. The function returns all combinations of columns that can uniquely identify the records of a data frame and it is created by combining recursive functions. In this post, popular packages or a combination of packages for data manipulation are compared. They are listed below.

- base
- plyr
- dplyr
- data.table
- dplyr + data.table

This post is from a [discussion](https://www.linkedin.com/grp/post/77616-5996370029883510786?trk=groups-post-b-title) in [The R Project for Statistical Computing](https://www.linkedin.com/grp/home?gid=77616&sort=RECENT) of Linkedin.

Let's get started. 

The following packages are used.


{% highlight r %}
library(lubridate)
library(ggplot2)
library(data.table)
library(plyr)
library(dplyr)
{% endhighlight %}

At first, *10000* artificial records of *name*, *territory*, *start date* and *end date* are created. As the first goal is to assign unique ids to individuals, integer ids are mapped to unique names. Then they are merged to the raw data (*preDf*).  


{% highlight r %}
set.seed(1237) 
trial <- 10000
names <- sample(read.table("http://deron.meranda.us/data/census-derived-all-first.txt")[,1], trial, replace = T)
states <- c("NSW", "VIC", "QLD", "SA", "WA", "ACT", "NT")
territory <- sample(states, trial, replace = T) 
start <- ymd(20140101) + days(sample(1:365, trial, replace = T)) 
inter <- start + months(sample(1:24, trial, replace = T)) 
end <- inter + months(sample(1:24, trial, replace = T))
preDf <- data.frame(name = names, territory = territory, start = start, end = end)

# create id
uqeName <- data.frame(name = unique(preDf$name), id = 1:length(unique(preDf$name))) 
preDf <- merge(preDf, uqeName, by="name", all.x = TRUE) 
preDf$id <- as.factor(preDf$id)

head(preDf)
{% endhighlight %}



{% highlight text %}
##    name territory      start        end   id
## 1 AARON       QLD 2014-08-02 2017-06-02 2423
## 2 ABBIE        NT 2014-08-01 2016-08-01 2119
## 3 ABBIE       VIC 2014-04-27 2015-03-27 2119
## 4 ABBIE       NSW 2014-02-13 2017-04-13 2119
## 5  ABBY        WA 2014-05-19 2016-07-19 1038
## 6  ABBY       NSW 2014-12-08 2017-02-08 1038
{% endhighlight %}

A column is added using each of the packages and this new column is the number of days between the start and end dates (*period*). It is either **unconditional**, which is just obtained by individual rows or **conditional**, which is average periods by id.

### base

The unconditional period can be obtained by `transform()` while the conditional values are obtained by `aggregate()` followed by being merged by `merge()`. Compared to other ways, it requires more lines of code if a new column depends on existing columns. However there may be cases where a 3rd party package is not available or have to be avoided. Then this will be quite beneficial.  


{% highlight r %}
## base
# unconditional
postDf <- transform(preDf, period = as.double(end - start))

# conditional
agg <- aggregate(postDf[,5:6], by = list(postDf$id), FUN = function(x) if(is.factor(x)) x else mean(x))[, -2]
names(agg) <- c("id", "period")

postDf <- merge(postDf, agg, by = "id", all.x = T)
{% endhighlight %}

### plyr

This package is the most flexible as it supports not only data frames but also other data types such as lists, arrarys ... However, as shown later, it can be too slow compared to other ways and its use may not be compelling when a new column depend on existing columns and the number of records are large.


{% highlight r %}
## plyr
# unconditional
postDf <- plyr::mutate(preDf, period = as.double(end - start))

# conditonal
postDf <- ddply(preDf, .(id), mutate, mean_period = mean(as.double(end - start)))
{% endhighlight %}

### dplyr

This is a successor of the **plyr** package. Instead of supporting various data types, it only supports data frames (and data tables) to improve speed. It has some SQL-like functions (eg `group_by()`) and thus those who know SQL would find it easier. Interestingly it supports the pipe operator (`%>%`) that chains functions. F# also has a similar operator and people from other programming languages would find it easier than wrapping one or more functions inside a function.


{% highlight r %}
## dplyr
# unconditional
postDf <- preDf %>% mutate(period = as.double(end - start))

# conditional
postDf <- preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id)
{% endhighlight %}

### data.table

This package is also popular and it seems to be the fastest. One or more columns can be indexed to further improve speed using `setkey()`. Its syntax seems to be more similar to the functions in the **base** package compared to the previous two packages. I'm not fully sure but a drawback of this package might be it doesn't seem to provide an easy way that just adds a new column. That is exising column names should be added in a list but, if the number of columns are many, it can be tedious. There may be a way but I haven't found and, in this case, the next way can be used for that.


{% highlight r %}
## data.table
# unconditional
preDt <- as.data.table(preDf)
setkey(preDt, id)
postDt <- preDt[, list(name = name, territory = territory,
                       start = start, end = end, id = id,
                       period = as.double(end - start))]

# conditional
postDt <- preDt[,
                list(name = name, territory = territory,
                     start = start, end = end, id = id,
                     mean_period = mean(as.double(end - start))),
                by = id]
{% endhighlight %}

### dplyr + data.table

The **dplyr** package also supports data tables and there may be cases where using both the packages are necessary - an example case is mentioned above.


{% highlight r %}
## dplyr + data.table
# unconditional
postDt <- preDt %>% mutate(period = as.double(end - start))

# conditional
postDt <- preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id)

head(postDt)
{% endhighlight %}



{% highlight text %}
## Source: local data frame [6 x 6]
## Groups: id
## 
##       name territory      start        end id mean_period
## 1 SHARLENE       ACT 2014-02-14 2016-05-14  1       806.0
## 2 SHARLENE        WA 2014-06-09 2016-08-09  1       806.0
## 3      BEE        NT 2014-05-07 2016-06-07  2       652.4
## 4      BEE        WA 2014-12-10 2015-12-10  2       652.4
## 5      BEE        NT 2014-05-25 2016-02-25  2       652.4
## 6      BEE        NT 2014-07-06 2015-10-06  2       652.4
{% endhighlight %}

### speed

System time to obtain the conditional column is recorded and plotted below - as the **plyr** package takes too long compared to others, it is omitted in the plot. In this example, the **data.table** package takes the least amount of time followed by those that use the **dplyr** package. The functions in the **base** package are slower but not too much and many data manipulation tasks would rely on them. Finally the **plyr** package takes too long but it still has a reason not to be deprecated - flexibility.


{% highlight r %}
## speed
tim1 <- system.time({
  postDf <- transform(preDf, period = as.double(end - start))
  agg <- aggregate(postDf[,5:6], by = list(postDf$id), FUN = function(x) if(is.factor(x)) x else mean(x))[, -2]
  names(agg) <- c("id", "period")
  postDf <- merge(postDf, agg, by = "id", all.x = T)
})
tim2 <- system.time(ddply(preDf, .(id), mutate, mean_period = mean(as.double(end - start))))
tim3 <- system.time(preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id))
tim4 <- system.time(preDt[,
                          list(name = name, territory = territory,
                               start = start, end = end, id = id,
                               mean_period = mean(as.double(end - start))),
                          by = id])
tim5 <- system.time(preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id))

times <- do.call("rbind", list(base = tim1, plyr = tim2, dplyr = tim3, data.table = tim4, both = tim5))
times <- cbind(times, data.frame(package = c("base", "plyr", "dplyr", "data.table", "dplyr+data.table")))
times[, c(1:3,6)]
{% endhighlight %}



{% highlight text %}
##            user.self sys.self elapsed          package
## base           0.578        0   0.578             base
## plyr          63.704        0  63.692             plyr
## dplyr          0.421        0   0.421            dplyr
## data.table     0.370        0   0.369       data.table
## both           0.416        0   0.415 dplyr+data.table
{% endhighlight %}



{% highlight r %}
ggplot(times[-2, ], aes(x = package, y = elapsed, fill = package)) + 
  geom_bar(stat = "identity") + ggtitle("Elapsed time of each package")
{% endhighlight %}

![center](/figs/2015-04-25-R-Tip-a-Day-2-Comparison-Packages-for-Data-Manipulation/speed-1.png) 

### session information


{% highlight r %}
sessionInfo()
{% endhighlight %}



{% highlight text %}
## R version 3.1.1 (2014-07-10)
## Platform: x86_64-redhat-linux-gnu (64-bit)
## 
## locale:
##  [1] LC_CTYPE=en_US.UTF-8       LC_NUMERIC=C              
##  [3] LC_TIME=en_US.UTF-8        LC_COLLATE=en_US.UTF-8    
##  [5] LC_MONETARY=en_US.UTF-8    LC_MESSAGES=en_US.UTF-8   
##  [7] LC_PAPER=en_US.UTF-8       LC_NAME=C                 
##  [9] LC_ADDRESS=C               LC_TELEPHONE=C            
## [11] LC_MEASUREMENT=en_US.UTF-8 LC_IDENTIFICATION=C       
## 
## attached base packages:
## [1] stats     graphics  grDevices utils     datasets  methods   base     
## 
## other attached packages:
## [1] dplyr_0.3.0.2    plyr_1.8.1       data.table_1.9.4 ggplot2_1.0.0   
## [5] lubridate_1.3.3  knitr_1.9.7     
## 
## loaded via a namespace (and not attached):
##  [1] assertthat_0.1    chron_2.3-45      colorspace_1.2-4 
##  [4] DBI_0.3.1         digest_0.6.4      evaluate_0.5.5   
##  [7] formatR_1.0       grid_3.1.1        gtable_0.1.2     
## [10] htmltools_0.2.6   labeling_0.3      lazyeval_0.1.9   
## [13] magrittr_1.0.1    MASS_7.3-33       memoise_0.2.1    
## [16] munsell_0.4.2     parallel_3.1.1    proto_0.3-10     
## [19] Rcpp_0.11.3       reshape2_1.4      rmarkdown_0.5.3.1
## [22] scales_0.2.4      stringr_0.6.2     tools_3.1.1      
## [25] yaml_2.1.13
{% endhighlight %}
