---
layout: post
title: "2014-11-20-Download-Stock-Data-2"
description: ""
category: R
tags: [knitr,lubridate,stringr,plyr,dplyr]
---
In an [earlier article](http://jaehyeon-kim.github.io/r/2014/11/20/Download-Stock-Data-1/), a way to download stock price data files from Google, save it into a local drive and merge them into a single data frame. If files are not large, however, it wouldn't be effective and, in this article, files are downloaded and merged internally.

The following packages are used.


{% highlight r %}
library(knitr)
library(lubridate)
library(stringr)
library(plyr)
library(dplyr)
{% endhighlight %}

Taking urls as file locations, files are directly read using `llply` and they are combined using `rbind_all`. As the merged data has multiple stocks' records, `Code` column is created. Note that, when an error occurrs, the function returns a dummy data frame in order not to break the loop - values of the dummy data frame(s) are filtered out at the end.


{% highlight r %}
# assumes codes are known beforehand
codes <- c("MSFT", "TCHC") # codes <- c("MSFT", "1234") for testing
files <- paste0("http://www.google.com/finance/historical?q=NASDAQ:",
                codes,"&output=csv")

dataList <- llply(files, function(file, ...) {
      # get code from file url
      pattern <- "Q:[0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z]"
      code <- substr(str_extract(file, pattern), 3, nchar(str_extract(file, pattern)))
      
      # read data directly from a URL with only simple error handling
      # for further error handling: http://adv-r.had.co.nz/Exceptions-Debugging.html
      tryCatch({
            data <- read.csv(file, stringsAsFactors = FALSE)
            # first column's name is funny
            names(data) <- c("Date","Open","High","Low","Close","Volume")
            data$Date <- dmy(data$Date)
            data$Open <- as.numeric(data$Open)
            data$High <- as.numeric(data$High)
            data$Low <- as.numeric(data$Low)
            data$Close <- as.numeric(data$Close)
            data$Volume <- as.integer(data$Volume)
            data$Code <- code
            data               
      },
      error = function(c) {
            c$message <- paste(code,"failed")
            message(c$message)
            # return a dummy data frame
            data <- data.frame(Date=dmy(format(Sys.Date(),"%d%m%Y")), Open=0, High=0,
                               Low=0, Close=0, Volume=0, Code="NA")
            data
      })
})

# dummy data frame values are filtered out
data <- filter(rbind_all(dataList), Code != "NA")
{% endhighlight %}

Some of the values are shown below.


|Date       |  Open|  High|   Low| Close|   Volume|Code |
|:----------|-----:|-----:|-----:|-----:|--------:|:----|
|2014-11-26 | 47.49| 47.99| 47.28| 47.75| 27164877|MSFT |
|2014-11-25 | 47.66| 47.97| 47.45| 47.47| 28007993|MSFT |
|2014-11-24 | 47.99| 48.00| 47.39| 47.59| 35434245|MSFT |
|2014-11-21 | 49.02| 49.05| 47.57| 47.98| 42884795|MSFT |
|2014-11-20 | 48.00| 48.70| 47.87| 48.70| 21510587|MSFT |
|2014-11-19 | 48.66| 48.75| 47.93| 48.22| 26177450|MSFT |

It took a bit longer to complete the script as I had to teach myself how to handle errors in R. And this is why I started to write articles in this blog.

I hope this article is useful.
