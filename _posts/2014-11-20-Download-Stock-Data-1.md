---
layout: post
title: "2014-11-20-Download-Stock-Data-1"
description: ""
category: r
tags: [r, knitr]
---
{% include JB/setup %}

This article illustrates how to download stock price data files from Google, save it into a local drive and merge them into a single data frame. This script is slightly modified from a script which downloads RStudio package download log data. The original source can be found [here](https://github.com/hadley/cran-logs-dplyr/blob/master/1-download.r).  

First of all, the following three packages are used.


{% highlight r %}
library(knitr)
library(lubridate)
library(stringr)
library(plyr)
library(dplyr)
{% endhighlight %}

The script begins with creating a folder to save data files.


{% highlight r %}
# create data folder
dataDir <- paste0("data","_","2014-11-20-Download-Stock-Data-1")
if(file.exists(dataDir)) { 
      unlink(dataDir, recursive = TRUE)
      dir.create(dataDir)
} else {
      dir.create(dataDir)
}
{% endhighlight %}

After creating urls and file paths, files are downloaded using `Map` function - it is a warpper of `mapply`. Note that, in case the function breaks by an error (eg when a file doesn't exist), `download.file` is wrapped by another function that includes an error handler (`tryCatch`). 


{% highlight r %}
# assumes codes are known beforehand
codes <- c("MSFT", "TCHC") # codes <- c("MSFT", "1234") for testing
urls <- paste0("http://www.google.com/finance/historical?q=NASDAQ:",
               codes,"&output=csv")
paths <- paste0(dataDir,"/",codes,".csv") # back slash on windows (\\)
 
# simple error handling in case file doesn't exists
downloadFile <- function(url, path, ...) {
      # remove file if exists already
      if(file.exists(path)) file.remove(path)
      # download file
      tryCatch(            
            download.file(url, path, ...), error = function(c) {
                  # remove file if error
                  if(file.exists(path)) file.remove(path)
                  # create error message
                  c$message <- paste(substr(path, 1, 4),"failed")
                  message(c$message)
            }
      )
}
# wrapper of mapply
Map(downloadFile, urls, paths)
{% endhighlight %}


Finally files are read back using `llply` and they are combined using `rbind_all`. Note that, as the merged data has multiple stocks' records, `Code` column is created.



{% highlight r %}
# read all csv files and merge
files <- dir(dataDir, full.name = TRUE)
dataList <- llply(files, function(file){
      data <- read.csv(file, stringsAsFactors = FALSE)
      # get code from file path
      pattern <- "/[A-Z][A-Z][A-Z][A-Z]"
      code <- substr(str_extract(file, pattern), 2, nchar(str_extract(file, pattern)))
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
}, .progress = "text")
 
data <- rbind_all(dataList)
{% endhighlight %}

Some of the values are shown below.


|Date       |  Open|  High|   Low| Close|   Volume|Code |
|:----------|-----:|-----:|-----:|-----:|--------:|:----|
|2014-11-20 | 48.00| 48.70| 47.87| 48.70| 21510587|MSFT |
|2014-11-19 | 48.66| 48.75| 47.93| 48.22| 26177450|MSFT |
|2014-11-18 | 49.13| 49.32| 48.70| 48.74| 23996457|MSFT |
|2014-11-17 | 49.41| 49.70| 49.14| 49.46| 30318648|MSFT |
|2014-11-14 | 49.74| 50.04| 49.39| 49.58| 29081657|MSFT |
|2014-11-13 | 48.81| 49.64| 48.70| 49.61| 26210433|MSFT |

This way wouldn't be efficient compared to the way where files are read directly without being saved into a local drive. This option may be useful, however, if files are large and the API server breaks connection abrubtly.

I hope this article is useful and I'm going to write an article to show the second way.
