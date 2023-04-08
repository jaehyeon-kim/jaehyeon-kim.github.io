---
layout: post
title: "2015-05-16-R-Tip-a-Day-6-Reading-Unstructured-File"
description: ""
category: R
tags: [programming]
---
In the [previous post](http://jaehyeon-kim.github.io/r/2015/05/09/R-Tip-a-Day-5-Function-Composition/), an introduction to *function composition* is made. As *function* is one of the most important objects in R and functional programming techniques can be beneficial in a way to achieve code reusability and to result in succinct code, it would be important to appreciate their values (and, of course, limitations). 

In this short post, a way to read an unstructured file is illustrated. Although there are many good functions to read files in various formats, there may an occasion that a file fails to be read using one of them. In this case, rather than reformatting it to be fit into one of the existing functions externally, it could be easier to process them internally. This post just shows one of the possible ways with an example which is based on a [StackOverflow question](http://stackoverflow.com/questions/30251576/reading-a-non-standard-csv-file-into-r/30251915).

The question is shown below.


{% highlight r %}
Im trying to read the following csv file into R

http://asic.gov.au/Reports/YTD/2015/RR20150511-001-SSDailyYTD.csv

The code im currently using is:

shorthistory <- read.csv("http://asic.gov.au/Reports/YTD/2015/RR20150511-001-SSDailyYTD.csv",skip=4)

However I keep getting the following error.

1: In readLines(file, skip) : line 1 appears to contain an embedded nul
2: In readLines(file, skip) : line 2 appears to contain an embedded nul
3: In readLines(file, skip) : line 3 appears to contain an embedded nul
4: In readLines(file, skip) : line 4 appears to contain an embedded nul
Which leads me to beleive I am utilizing the function incorrectly as it is failing with every line.

Any help would be very much appreciated!
{% endhighlight %}

As shown below, an Excel pivot table seems to be saved as a csv file so that it has blank (or NULL) values at the top lefthand side. Also, although it is saved as a csv file, its delimiter is *Tab* rather than *comma*. 

![center](/figs/2015-05-16-R-Tip-a-Day-6-Reading-Unstructured-File/csv_sample.png) 

Due to the way how the file is structured, conventional functions such as `read.table()` don't work. Therefore the file is open as *file connection* using `file()` and then read line by line using `readLines()`. Once it is read, some extra processing is performed recursively using `lapply()`.


{% highlight r %}
# open file connection and read lines
path <- "http://asic.gov.au/Reports/YTD/2015/RR20150511-001-SSDailyYTD.csv"
con <- file(path, open = "rt", raw = TRUE)
text <- readLines(con, skipNul = TRUE)
close(con)

# skip first 4 lines
text <- text[5:length(text)]

# recursively split string
text <- do.call(c, lapply(text, strsplit, split = "\t"))

text[[1]][1:6]
{% endhighlight %}



{% highlight text %}
## [1] "1-PAGE LTD ORDINARY" "1PG "                "1330487"            
## [4] "1.72"                "1362948"             "1.76"
{% endhighlight %}

I hope this tip is helpful to handle unstructure files within R.
