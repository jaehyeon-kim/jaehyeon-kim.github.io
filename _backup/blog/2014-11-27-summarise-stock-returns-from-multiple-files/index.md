---
layout: post
title: "2014-11-27-Summarise-Stock-Returns-from-Multiple-Files"
description: ""
category: R
tags: [knitr,lubridate,stringr,reshape2,plyr,dplyr]
---
This is a slight extension of the previous two articles ( [2014-11-20-Download-Stock-Data-1](http://jaehyeon-kim.github.io/r/2014/11/20/Download-Stock-Data-1/), [2014-11-20-Download-Stock-Data-2](http://jaehyeon-kim.github.io/r/2014/11/20/Download-Stock-Data-2/) ) and it aims to produce gross returns, standard deviation and correlation of multiple shares.

The following packages are used.


{% highlight r %}
library(knitr)
library(lubridate)
library(stringr)
library(reshape2)
library(plyr)
library(dplyr)
{% endhighlight %}

The script begins with creating a data folder in the format of *data_YYYY-MM-DD*.


{% highlight r %}
# create data folder
dataDir <- paste0("data","_",format(Sys.Date(),"%Y-%m-%d"))
if(file.exists(dataDir)) {
  unlink(dataDir, recursive = TRUE)
  dir.create(dataDir)
} else {
  dir.create(dataDir)
}
{% endhighlight %}

Given company codes, URLs and file paths are created. Then data files are downloaded by `Map`, which is a wrapper of `mapply`. Note that R's `download.file` function is wrapped by `downloadFile` so that the function does not break when an error occurs.


{% highlight r %}
# assumes codes are known beforehand
codes <- c("MSFT", "TCHC")
urls <- paste0("http://www.google.com/finance/historical?q=NASDAQ:",
               codes,"&output=csv")
paths <- paste0(dataDir,"/",codes,".csv") # backward slash on windows (\)

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

Once the files are downloaded, they are read back to combine using `rbind_all`. Some more details about this step is listed below.

* only Date, Close and Code columns are taken
* codes are extracted from file paths by matching a regular expression
* data is arranged by date as the raw files are sorted in a descending order
* error is handled by returning a dummy data frame where its code value is NA.
* individual data files are merged in a long format
    * 'NA' is filtered out


{% highlight r %}
# read all csv files and merge
files <- dir(dataDir, full.name = TRUE)
dataList <- llply(files, function(file){
  # get code from file path
  pattern <- "/[A-Z][A-Z][A-Z][A-Z]"
  code <- substr(str_extract(file, pattern), 2, nchar(str_extract(file, pattern)))
  tryCatch({
    data <- read.csv(file, stringsAsFactors = FALSE)
    # first column's name is funny
    names(data) <- c("Date","Open","High","Low","Close","Volume")
    data$Date <- dmy(data$Date)
    data$Close <- as.numeric(data$Close)
    data$Code <- code
    # optional
    data$Open <- as.numeric(data$Open)
    data$High <- as.numeric(data$High)
    data$Low <- as.numeric(data$Low)
    data$Volume <- as.integer(data$Volume)
    # select only 'Date', 'Close' and 'Code'
    # raw data should be arranged in an ascending order
    arrange(subset(data, select = c(Date, Close, Code)), Date)
  },
  error = function(c){
    c$message <- paste(code,"failed")
    message(c$message)
    # return a dummy data frame not to break function
    data <- data.frame(Date=dmy(format(Sys.Date(),"%d%m%Y")), Close=0, Code="NA")
    data
  })
}, .progress = "text")

# data is combined to create a long format
# dummy data frame values are filtered out
data <- filter(rbind_all(dataList), Code != "NA")
{% endhighlight %}

Some values of this long format data is shown below.


|Date       | Close|Code |
|:----------|-----:|:----|
|2013-11-29 | 38.13|MSFT |
|2013-12-02 | 38.45|MSFT |
|2013-12-03 | 38.31|MSFT |
|2013-12-04 | 38.94|MSFT |
|2013-12-05 | 38.00|MSFT |
|2013-12-06 | 38.36|MSFT |

The data is converted into a wide format data where the x and y variables are Date and Code respectively (`Date ~ Code`) while the value variable is Close (`value.var="Close"`). Some values of the wide format data is shown below.


{% highlight r %}
# data is converted into a wide format
data <- dcast(data, Date ~ Code, value.var="Close")
kable(head(data))
{% endhighlight %}



|Date       |  MSFT|  TCHC|
|:----------|-----:|-----:|
|2013-11-29 | 38.13| 13.52|
|2013-12-02 | 38.45| 13.81|
|2013-12-03 | 38.31| 13.48|
|2013-12-04 | 38.94| 13.71|
|2013-12-05 | 38.00| 13.55|
|2013-12-06 | 38.36| 13.95|

The remaining steps are just differencing close price values after taking log and applying `sum`, `sd`, and `cor`.


{% highlight r %}
# select except for Date column
data <- select(data, -Date)

# apply log difference column wise
dailyRet <- apply(log(data), 2, diff, lag=1)

# obtain daily return, variance and correlation
returns <- apply(dailyRet, 2, sum, na.rm = TRUE)
std <- apply(dailyRet, 2, sd, na.rm = TRUE)
correlation <- cor(dailyRet)

returns
{% endhighlight %}



{% highlight text %}
##      MSFT      TCHC 
## 0.2249777 0.6293973
{% endhighlight %}



{% highlight r %}
std
{% endhighlight %}



{% highlight text %}
##       MSFT       TCHC 
## 0.01167381 0.03203031
{% endhighlight %}



{% highlight r %}
correlation
{% endhighlight %}



{% highlight text %}
##           MSFT      TCHC
## MSFT 1.0000000 0.1481043
## TCHC 0.1481043 1.0000000
{% endhighlight %}

Finally the data folder is deleted.


{% highlight r %}
# delete data folder
if(file.exists(dataDir)) { unlink(dataDir, recursive = TRUE) }
{% endhighlight %}
