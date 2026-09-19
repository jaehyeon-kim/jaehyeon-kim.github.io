---
title: Download Stock Data - Part I
date: 2014-11-20
draft: false
featured: false
comment: true
toc: true
series:
  - Download Stock Data
categories:
  - Data Analysis
tags:
  - R
description: This article illustrates how to download stock price data files from Google, save it into a local drive and merge them into a single data frame.
---

> **Status, September 2026.** Google retired the `finance/historical` CSV endpoint that this script downloads from, so the download step no longer returns data. The folder creation, error handling and merge patterns still hold if you point them at a price source that is still published.

Stock price data files are downloaded from Google, saved into a local drive and merged into a single data frame. This script is slightly modified from a script which downloads RStudio package download log data. The original source can be found [here](https://github.com/hadley/cran-logs-dplyr/blob/master/1-download.r).  

## R Packages Used

First of all, the following three packages are used.


```r
library(knitr)
library(lubridate)
library(stringr)
library(plyr)
library(dplyr)
```

## Create a Data Folder

The script begins with creating a folder to save data files.


```r
# create data folder
dataDir <- paste0("data","_","2014-11-20-Download-Stock-Data-1")
if(file.exists(dataDir)) { 
      unlink(dataDir, recursive = TRUE)
      dir.create(dataDir)
} else {
      dir.create(dataDir)
}
```

## Download Files with Error Handling

After creating urls and file paths, files are downloaded using `Map` function - it is a warpper of `mapply`. Note that, in case the function breaks by an error (eg when a file doesn't exist), `download.file` is wrapped by another function that includes an error handler (`tryCatch`). 


```r
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
```


## Read Files Back and Merge

Finally files are read back using `llply` and they are combined using `rbind_all`. Note that, as the merged data has multiple stocks' records, `Code` column is created.



```r
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
```

Some of the values are shown below.


|Date       |  Open|  High|   Low| Close|   Volume|Code |
|:----------|-----:|-----:|-----:|-----:|--------:|:----|
|2014-11-26 | 47.49| 47.99| 47.28| 47.75| 27164877|MSFT |
|2014-11-25 | 47.66| 47.97| 47.45| 47.47| 28007993|MSFT |
|2014-11-24 | 47.99| 48.00| 47.39| 47.59| 35434245|MSFT |
|2014-11-21 | 49.02| 49.05| 47.57| 47.98| 42884795|MSFT |
|2014-11-20 | 48.00| 48.70| 47.87| 48.70| 21510587|MSFT |
|2014-11-19 | 48.66| 48.75| 47.93| 48.22| 26177450|MSFT |

This way wouldn't be efficient compared to the way where files are read directly without being saved into a local drive. This option may be useful, however, if files are large and the API server breaks connection abrubtly.

I hope this article is useful and I'm going to write an article to show the second way.

## Related posts

* [Download Stock Data - Part II](/blog/2014-11-21-download-stock-data-2) - the same download done in memory, without saving each file to a local drive
* [Summarise Stock Returns from Multiple Files](/blog/2014-11-27-summarise-stock-returns-from-multiple-files) - turns merged price files into gross returns, standard deviation and correlation
* [Short R Examples](/blog/2014-12-03-short-r-examples) - short examples of summarising a data frame by group and running a quick simulation
* [Looping without for](/blog/2014-12-17-looping-without-for) - replaces for-loops with the apply family and plyr, the style the download script here uses
* [Quick Trial of Adding Column](/blog/2015-01-14-quick-trial-of-adding-column) - adds average columns with base R, plyr, dplyr and data.table, and times each one
* [Packaging Analysis](/blog/2015-03-24-packaging-analysis) - turns an analysis into an R package with roxygen2 documents, testthat tests and vignettes
* [Setup Random Seeds on Caret Package](/blog/2015-05-30-setup-random-seeds-on-caret-package) - sets random seeds with caret so an analysis can be reproduced
