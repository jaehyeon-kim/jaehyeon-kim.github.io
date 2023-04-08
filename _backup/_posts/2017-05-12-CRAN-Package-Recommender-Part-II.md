---
layout: post
title: "2017-05-12-CRAN-Package-Recommender-Part-II"
description: ""
category: Serverless
tags: [R, Association Rules, Link Analysis, Text Mining]
---
<style>
.center {
  text-align: center;
}
</style>

In the previous post, it was discussed to apply *Hyperlink-Induced Topic Search (HITS)* to association rules mining for creating a CARN package recommender. The link analysis algorithm gives more weights on transactions where strong cross-selling effects exist so that more relevant association rules can be mined for recommendation. Not all packages, however, are likely to be included in those rules and it is necessary to have a way to complement it. [Kaminskas et al. (2015)](https://www.insight-centre.org/content/product-recommendation-small-scale-retailers-0) discusses a recommender system for small retailers. In the paper, a combination of association rules and text-based similarity are utilized, which can be a good fit for the CRAN recommender. Before actual development, relevant data has to be downloaded/processed and it is the topic of this post.

The series plan is listed below.

Development

* [Introduction to HITS and weighted association rules mining](/2017/05/CRAN-Package-Recommender-Part-I)
* [Downloading/Processing relevant data](/2017/05/CRAN-Package-Recommender-Part-II) - this post
* Analysing CRAN package download logs
* Identifying package similarity
* _to be updated_

Deployment

* _to be updated_

Here is the snippet for initialization. *utils.R* can be found [here](https://gist.github.com/jaehyeon-kim/00117dab6338c6f13ffa8040f21ff666).


{% highlight r %}
library(parallel)
library(scales)
library(ggplot2)
library(rvest)

source(file.path(getwd(), 'src', 'utils.R'))
# extra packages loaded in utils.R to facilitate parallel processing
# lubridate, rvest, readr, stringr, data.table, dplyr, arules
{% endhighlight %}

## Preparation

Some functions take quite long and they are executed in parallel. For example, it'll be a lot quicker if files are read in multiple nodes and combined later. A unified function that executes a function in parallel is created and named as `process()`. In the following example, `read_files()` reads/binds multiple files, returning a data frame. This function can be executed in multiple nodes with `process()`. 

An individual function has the common *items* argument that can be files to read/download or package names to scrap. Each function can have a different set of arguments and they are captured in `...` argument. `get_args()` is just for convenience to grap a specific argument in `...`.

`process()` runs an individual function itself if *cores* equals to 1. When *cores* is greather than 1, *items* are split into the number of cores and the function is executed in multiple nodes. Each function may need a specific initialization (eg `library(readr)`) and it is captured in *init_str*. Note that `clusterEvalQ()` accepts an expression, which is not evaluated. An expression is set as a string (*init_str*) and exported in an environment that is created by `set_env()` - see `clusterExport()`. In this way, *init_str*, if exists, can be evaluated in each node. Finally *results* are combined by a function set by *combine*. (See this [post](/2015/03/Parallel-Processing-on-Single-Machine-Part-I.html) to see how `parLapplyLB()` works.)


{% highlight r %}
get_args <- function(args, what, ifnot) {
    if (!is.null(args[[what]])) {
        args[[what]]
    } else {
        ifnot
    }
}

read_files <- function(items, ...) {
    # illustration only
    args <- list(...)
    foo <- get_args(args, 'foo', 'bar') # bar if foo is not found
    
    do.call(rbind, lapply(items, function(itm) {
        read_csv(itm, ...)
    }))
}

process <- function(f, items, cores = detectCores() - 1, init_str = NULL, combine = rbind, ...) {
    stopifnot(cores > 0)
    
    set_env <- function(init_str) {
        e <- new.env()
        e$init_str <- init_str
        e
    }
    
    if (cores == 1) {
        results <- f(items = items, ...)
    } else {
        message('msg: create cluster of ', cores, ' nodes')
        splits <- split(items, 1:cores)
        cl <- makeCluster(cores)
        if (!is.null(init_str)) {
            # export initialization expression as string eg '{ library(readr); NULL }'
            clusterExport(cl, 'init_str', envir = set_env(init_str))
            # initialize nodes by evaluating init string
            init <- clusterEvalQ(cl, eval(parse(text = init_str)))
        }
        results <- parLapplyLB(cl, splits, f, ...)
        stopCluster(cl)
        message('msg: combine results')
        results <- do.call(combine, results)
    }
    results
}

## read files - example
items <- file.path(get_path('raw'), list.files(get_path('raw'))[1:2])
out1 <- process(f = read_files, items = items, cores = 1)
init_str <- '{ library(readr); NULL }'
out2 <- process(f = read_files, items = items, cores = 2, init_str = init_str, combine = rbind)
{% endhighlight %}

## Creating transactions

#### Downloading CRAN log

The log files from 2017-04-01 to 2017-04-30 are downloaded from [this page](http://cran-logs.rstudio.com/). As discussed earlier, they are downloaded in parallel by `download_log()` wrapped in `process()`.


{% highlight r %}
download_log <- function(items, ...) {
    args <- list(...)
    download_folder <- get_args(args, 'download_folder', getwd())
    
    download_log <- function(item, download_folder) {
        base_url <- 'http://cran-logs.rstudio.com'
        year <- lubridate::year(lubridate::ymd(item))
        file_name <- paste0(item, '.csv.gz')
        url <- paste(base_url, year, file_name, sep = '/')
        download.file(url, file.path(download_folder, file_name))
    }
    dir.create(download_folder, showWarnings = FALSE)
    do.call(rbind, lapply(items, function(itm) {
        tryCatch({
            message('msg: start to download data for ', itm)
            download_log(itm, download_folder = download_folder)
            data.frame(date = itm, is_downloaded = TRUE, stringsAsFactors = FALSE)
        }, error = function(e) {
            message('error: fails to download data for ', itm)
            data.frame(date = itm, is_downloaded = FALSE, stringsAsFactors = FALSE)
        })
    }))
}

## download data - example
# url pattern - http://cran-logs.rstudio.com/2017/2017-04-26.csv.gz
items <- seq(as.Date('2017-04-01'), as.Date('2017-04-30'), by = 'day')
ex <- process(f = download_log, items = items, cores = detectCores() - 1, download_folder = get_path('raw'))
{% endhighlight %}

#### Identifying transactions

The log data is anonymized and transactions have to be identified. *date* and *ip_id* are not enough as the following records indicate different *r_version*, *r_arch* and *r_os* with the same *date* and *ip_id*. Also some records have quite small *size* (eg 512) and they'd need to be filtered out.


{% highlight r %}
log <- read_csv(file.path(get_path('raw'), '2017-04-01.csv.gz')) %>% 
    arrange(ip_id, time) %>% as.data.frame() %>% head()
log
{% endhighlight %}



{% highlight text %}
##         date     time   size r_version r_arch         r_os        package
## 1 2017-04-01 19:28:48 653905     3.3.2   i386      mingw32        network
## 2 2017-04-01 19:28:48    523     3.3.2   i386      mingw32        network
## 3 2017-04-01 19:29:00    521     3.3.2 x86_64 darwin13.4.0 statnet.common
## 4 2017-04-01 19:29:01    523     3.3.3 x86_64      mingw32            sna
## 5 2017-04-01 19:29:01  48963     3.3.2 x86_64    linux-gnu statnet.common
## 6 2017-04-01 19:29:01 875721     3.3.2 x86_64    linux-gnu            sna
##   version country ip_id
## 1  1.13.0      US     1
## 2  1.13.0      US     1
## 3   3.3.0      US     1
## 4     2.4      US     1
## 5   3.3.0      US     1
## 6     2.4      US     1
{% endhighlight %}

The data is filtered and grouped by *date*, *ip_id*, *r_version*, *r_arch* and *r_os* followed by adding the number of packages downloded in each group (*count*). Intially 31,777,687 records are found and the number goes down to 22,056,121 after filtering.


{% highlight r %}
#### read log
files <- get_files(path = get_path('raw'), extension = '.csv.gz',
                   min_date = as.Date('2017-04-01'))
items <- file.path(get_path('raw'), files)
init_str <- "{ source(file.path(getwd(), 'src', 'utils.R')); NULL}"
log <- process(f = read_files, items = items, cores = detectCores() - 1,
               init_str = init_str, combine = rbind)

#### filter by size, r_version, r_arch, r_os
log_filtered <- log %>% filter(size > 1024, !is.na(r_version), !is.na(r_arch), !is.na(r_os)) %>%
    select(date, ip_id, r_version, r_arch, r_os, package) %>%
    distinct(date, ip_id, r_version, r_arch, r_os, package) %>%
    group_by(date, ip_id, r_version, r_arch, r_os) %>% mutate(count = n()) %>%
    arrange(date, ip_id, r_version, r_arch, r_os)
{% endhighlight %}

Transactions can be identified from the filtered data as following.


{% highlight r %}
log_trans <- log_filtered %>% group_by(count) %>%
    summarise(num_rec = n()) %>% ungroup() %>%
    mutate(num_trans = num_rec/count, 
           prop_trans = round(num_trans/sum(num_trans)*100, 3)) %>%
    mutate(count = as.factor(count))
{% endhighlight %}

More than 50% of transactions download a single package and up to 1231 packages are found in a transaction. It is unrealistic that a user downloads such a large number of packages and the maximum number of packages is set to be 20.


{% highlight r %}
log_trans <- read_rds(file.path(get_path('data'), 'log_trans_201704.rds'))
log_trans[1:20,]
{% endhighlight %}



{% highlight text %}
## # A tibble: 20 x 4
##     count num_rec num_trans prop_trans
##    <fctr>   <int>     <dbl>      <dbl>
## 1       1 3240984   3240984     51.319
## 2       2 2178820   1089410     17.250
## 3       3 1692183    564061      8.932
## 4       4 1389308    347327      5.500
## 5       5 1174940    234988      3.721
## 6       6  992142    165357      2.618
## 7       7  850143    121449      1.923
## 8       8  742064     92758      1.469
## 9       9  648990     72110      1.142
## 10     10  571810     57181      0.905
## 11     11  503481     45771      0.725
## 12     12  448836     37403      0.592
## 13     13  403065     31005      0.491
## 14     14  358526     25609      0.406
## 15     15  327390     21826      0.346
## 16     16  291856     18241      0.289
## 17     17  270538     15914      0.252
## 18     18  238014     13223      0.209
## 19     19  215555     11345      0.180
## 20     20  198020      9901      0.157
{% endhighlight %}

A total of 6,215,863 transactions are identified and the proportion of transactions by downloaded packages are shown below.


{% highlight r %}
ggplot(log_trans[1:20,], aes(x = count, y = prop_trans)) + 
    geom_bar(stat="identity") + scale_y_continuous(labels = comma) +
    ggtitle('Proportion of Transactions by Downloaded Packages') + 
    theme(plot.title = element_text(hjust = 0.5)) +
    labs(x = 'Number of Downloaded Packages', y = 'Proportion of Transactions')
{% endhighlight %}

{:.center}
![](/figs/CRAN-Package-Recommender/part2_1.png)

#### Constructing transactions

It requires multiple steps to construct a transactions object of the *arules* package from the log data.

* `filter_log()` - Data is filtered and grouped by *date*, *ip_id*, *r_version*, *r_arch* and *r_os* followed by adding *count*. If *max_download* is not *NULL*, data is further filtered by this number.
* `add_group_idx()` - Each group is given a unique id and the id column is added to data.
* `keep_trans_cols()` - Transaction ids are made up of *date* and *(group) id*. Only transaction id, package name and count columns are kept.
* `split_log()` - The previous 3 functions are executed in order and data is split after assigning split group number (*splt*). See below for details.
* `construct_trans()` - A transaction object is made from a matrix (`as(mat, 'transactions')`) and the matrix is created by `dcast()` of the *data.table* package, which returns 0 or 1 elements. Note that the entire log data for even a single day can cause an error in `dcast()` so that it is split by groups (*splt*) and transaction objects are constructed for each group. Transaction objects can efficiently be merged as discussed below.


{% highlight r %}
filter_log <- function(log, max_download = NULL) {
    log <- log %>% filter(size > 1024, !is.na(r_version), !is.na(r_arch), !is.na(r_os)) %>%
        select(date, ip_id, r_version, r_arch, r_os, package) %>%
        distinct(date, ip_id, r_version, r_arch, r_os, package) %>%
        group_by(date, ip_id, r_version, r_arch, r_os) %>% mutate(count = n())
    if (!is.null(max_download)) {
        log %>% filter(count <= max_download)
    } else {
        log
    }
}

add_group_idx <- function(log) {
    group_idx <- log %>% group_indices()
    bind_cols(log, data.frame(id = group_idx)) %>% ungroup()
}

keep_trans_cols <- function(log) {
    bind_rows(log) %>% mutate(trans_id = paste(gsub('-', '', date), id, sep = '_')) %>%
        select(trans_id, package, count)
}

set_split_map <- function() {
    data.frame(count = 1:20, splt = c(1, rep(2, 2), rep(3, 3), rep(4:5, each = 4), rep(6, 6)))
}

split_log <- function(log, max_download, split_map = set_split_map()) {
    log <- log %>% filter_log(max_download = max_download) %>% add_group_idx() %>% keep_trans_cols() %>%
        inner_join(split_map, by = 'count') %>% setDT() %>% setkey(trans_id)
    split(log, by = 'splt')
}

construct_trans <- function(log) {
    log_cast <- log %>% select(trans_id, package) %>% 
        dcast(formula = trans_id ~ package, fun.aggregate = length, value.var = 'package')
    ids <- log_cast$trans_id
    log_cast <- log_cast[, -1] %>% as.matrix()
    rownames(log_cast) <- ids
    as(log_cast, 'transactions')
}
{% endhighlight %}

Transaction objects are saved from individual log data files as shown below. Note that *dcast()* consumes quite a large amount of memory and `process()` is not recommended if the machine doesn't have enough memory.


{% highlight r %}
save_trans <- function(items, ...) {
    args <- list(...)
    max_download <- get_args(args, 'max_download', 20)
    split_map <- get_args(args, 'split_map', set_split_map())
    trans_folder <- get_args(args, 'trans_folder', get_path('trans'))
    
    dir.create(trans_folder, showWarnings = FALSE)
    do.call(rbind, lapply(items, function(itm) {
        gc()
        date <- str_extract(itm, '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        message('msg: current date ', date)
        tryCatch({
            logs <- read_csv(itm) %>% 
                split_log(max_download = max_download, split_map = split_map)
            trans <- lapply(names(logs), function(nm) {
                message('msg: contructing logs of split group ', nm)
                construct_trans(logs[[nm]])
            })
            names(trans) <- names(logs)
            trans_name <- paste0(date, '.rds')
            write_rds(trans, file.path(trans_folder, trans_name), compress = 'gz')
            data.frame(date = date, is_saved = TRUE, stringsAsFactors = FALSE)
        }, error = function(err) {
            warning('err: fails to create transactions')
            data.frame(date = date, is_saved = FALSE, stringsAsFactors = FALSE)
        })
    }))
}

## save transactions - example
files <- get_files(path = get_path('raw'), extension = '.csv.gz', min_date = as.Date('2017-04-01'))
items <- file.path(get_path('raw'), files)
init_str <- "{ source(file.path(getwd(), 'src', 'utils.R')); NULL}"
trans_save <- process(f = save_trans, items = items, cores = 4, init_str = init_str, combine = rbind)
{% endhighlight %}

An example of transaction objects is shown below.


{% highlight r %}
read_rds(file.path(get_path('trans'), '2017-04-01.rds'))
{% endhighlight %}



{% highlight text %}
## $`2`
## transactions in sparse format with
##  32850 transactions (rows) and
##  2494 items (columns)
## 
## $`6`
## transactions in sparse format with
##  1650 transactions (rows) and
##  1741 items (columns)
## 
## $`1`
## transactions in sparse format with
##  65613 transactions (rows) and
##  2769 items (columns)
## 
## $`5`
## transactions in sparse format with
##  2721 transactions (rows) and
##  1606 items (columns)
## 
## $`3`
## transactions in sparse format with
##  14732 transactions (rows) and
##  2258 items (columns)
## 
## $`4`
## transactions in sparse format with
##  6765 transactions (rows) and
##  2095 items (columns)
{% endhighlight %}

#### Merging transactions

The *arules* package has a function to merge transactions (`merge()`). However it doesn't allow to merge transactions that have different number of items. `bind_trans()` is created to overcome this limitation, which accepts multiple transaction objects. First it collects information of transaction objects and all unique items are obtained across those objects. Then, for each of the transaction objects, a sparse matrix is created for the items that don't exist (`get_sm()`) and row binded to the item matrix. Note that the last element is manually set to be *FALSE* where it is set as *TRUE* by default. Finally individual item matrices are column binded, followed by returning a merged transaction object.


{% highlight r %}
get_trans_info <- function(trans) {
    m <- trans@data
    items <- trans@itemInfo %>% unlist() %>% unname()
    itemsets <- trans@itemsetInfo %>% unlist() %>% unname()
    dimnames(m) <- list(items, itemsets)
    list(m = m, items = items, itemsets = itemsets)
}

get_sm <- function(info, items_all) {
    m <- info$m
    items <- info$items
    itemsets <- info$itemsets
    
    sm <- sparseMatrix(
        i = (length(items_all) - length(items)),
        j = ncol(m),
        x = 0,
        dimnames = list(items_all[!items_all %in% items], colnames(m))
    ) %>% as('ngCMatrix')
    sm[nrow(sm), ncol(sm)] <- FALSE
    sm
}

# do.call(bind_trans, list(trans1, trans2, trans3))
bind_trans <- function(...) {
    trans <- list(...)
    infos <- lapply(trans, get_trans_info)
    
    ms <- lapply(infos, function(info) info[['m']])
    items <- lapply(infos, function(info) info[['items']])
    itemsets <- lapply(infos, function(info) info[['itemsets']])
    
    items_all <- sort(unique(unlist(items)))
    sms <- lapply(infos, get_sm, items_all = items_all)
    
    m <- do.call(cBind, lapply(1:length(ms), function(i) {
        mb <- rBind(ms[[i]], sms[[i]])
        mb[sort(rownames(mb)), ]
    }))
    as(m, 'transactions')
}
{% endhighlight %}

An example is shown below. Separate transaction objects are created and merged. The merged object is compared to the original transactions object and they match the same.


{% highlight r %}
txt <- 'A,B,C,D,E\nC,F,G,,\nA,B,,,\nA,,,,\nC,F,G,H,\nA,G,H,,'
df <- read.csv(text = txt, header = FALSE, stringsAsFactors = FALSE) %>%
    mutate(id = row_number()*100)
df_all <- df %>% melt(id = "id") %>% filter(value != '') %>% select(id, value)
df_1 <- df[1:3,] %>% reshape2::melt(id = "id") %>% 
    filter(value != '') %>% select(id, value)
df_2 <- df[4:6,] %>% reshape2::melt(id = "id") %>% 
    filter(value != '') %>% select(id, value)
trans_all <- as(split(df_all[, 'value'], df_all[, 'id']), 'transactions')
trans_1 <- as(split(df_1[, 'value'], df_1[, 'id']), 'transactions')
trans_2 <- as(split(df_2[, 'value'], df_2[, 'id']), 'transactions')
trans_merge <- do.call(bind_trans, list(trans_1, trans_2))

as(trans_all, 'data.frame') %>% 
    inner_join(as(trans_merge, 'data.frame'), by = c('transactionID' = 'itemsetID'))
{% endhighlight %}



{% highlight text %}
##       items.x transactionID     items.y
## 1 {A,B,C,D,E}           100 {A,B,C,D,E}
## 2     {C,F,G}           200     {C,F,G}
## 3       {A,B}           300       {A,B}
## 4         {A}           400         {A}
## 5   {C,F,G,H}           500   {C,F,G,H}
## 6     {A,G,H}           600     {A,G,H}
{% endhighlight %}

The entire transaction objects are merged and verified below. As can be seen, the total number of transactions are the same. Note that more than 50% of transactions have only a single package and those transaction records would need to be removed for association rules mining. On the other hand, the entire transactions records would need to execute *HITS* so that both the objects are necessary for following analysis. (Remind that *authority* will be used for recommendation by keywords.)


{% highlight r %}
files <- get_files(path = get_path('trans'), extension = '.rds')
items <- file.path(get_path('trans'), files)
init_str <- "{ source(file.path(getwd(), 'src', 'utils.R')); NULL}"
trans_all <- process(f = read_trans, items = items, cores = detectCores() - 1,
                     init_str = init_str, combine = bind_trans, excl_group = NULL)
trans_multiple <- process(f = read_trans, items = items, cores = detectCores() - 1,
                          init_str = init_str, combine = bind_trans, excl_group = 1)

trans_size <- data.frame(from_trans_all = nrow(trans_all),
                         from_trans_mult = nrow(trans_multiple))

log_trans %>% filter(as.integer(count) <= 20) %>% 
    summarise(from_log_all = sum(num_trans)) %>% bind_cols(trans_size)
{% endhighlight %}



{% highlight text %}
## # A tibble: 1 x 3
##   from_log_all from_trans_all from_trans_mult
##          <dbl>          <int>           <int>
## 1      6215863        6215863         2974879
{% endhighlight %}

## Collecting Package Information

As indicated earlier, text-based similarity can be used to complement association rules. `get_package_info()` can be used within `process()` to collect relevant information.


{% highlight r %}
## package name
get_pkg_names <- function(base_url = 'https://cran.r-project.org/web/packages/') {
    by_name_url <- paste0(base_url, 'available_packages_by_name.html')
    read_html(by_name_url) %>% html_nodes('td a') %>% html_text()    
}

## package information
get_package_info <- function(items, ...) {
    args <- list(...)
    attribute <- get_args(args, 'attribute', c('version', 'depends', 'imports', 'suggests', 'published'))
    base_url <- get_args(args, 'base_url', 'https://cran.r-project.org/web/packages/')
    
    info <- do.call(rbind, lapply(items, function(itm) {
        message('msg: get information of ', itm)
        htm <- read_html(paste0(base_url, itm))
        title <- tryCatch({
            htm %>% html_nodes('h2') %>% html_text()
        }, error = function(e) {
            NA
        })
        desc <- tryCatch({
            ext <- htm %>% html_nodes('p') %>% html_text()
            if (length(ext) > 1) {
                ext <- ext[1]
            }
        }, error = function(e) {
            NA
        })
        att <- tryCatch({
            htm %>% html_nodes('td') %>% html_text()
        }, error = function(e) {
            NULL
        })
        atts <- if (!is.null(att)) {
            do.call(c, lapply(attribute, function(a) {
                # grep beginning of string
                ind <- grep(paste0('^', a), att, ignore.case = TRUE)
                if (length(ind) > 0) ind <- ind[1]
                att_values <- if (length(ind) > 0 && length(att) > ind) {
                    att[ind + 1]
                } else {
                    NA
                }
            }))
        } else {
            rep(NA, length(attribute))
        }
        data.frame(itm, title, desc, t(atts), stringsAsFactors = FALSE)
    }))
    names(info) <- c('package', 'title', 'desc', attribute)
    rownames(info) <- NULL
    info
}
{% endhighlight %}

An example of collecting package information is shown below.


{% highlight r %}
items <- get_pkg_names()
init_str <- "{ source(file.path(getwd(), 'src', 'utils.R')); NULL}"
ex <- process(f = get_package_info, items = items[1:2], cores = 2, init_str = init_str, combine = rbind)
info <- lapply(1:nrow(ex), function(r) {
    row <- ex[r, -1]
    lst <- lapply(names(row), function(nm) {
        row[[nm]]
    })
    names(lst) <- names(row)
    lst
})
names(info) <- ex[, 1]
info
{% endhighlight %}



{% highlight text %}
## $A3
## $A3$title
## [1] "A3: Accurate, Adaptable, and Accessible Error Metrics for Predictive\nModels"
## 
## $A3$desc
## [1] "Supplies tools for tabulating and analyzing the results of predictive models. The methods employed are applicable to virtually any predictive model and make comparisons between different methodologies straightforward."
## 
## $A3$version
## [1] "1.0.0"
## 
## $A3$depends
## [1] "R (= 2.15.0), xtable, pbapply"
## 
## $A3$imports
## [1] NA
## 
## $A3$suggests
## [1] "randomForest, e1071"
## 
## $A3$published
## [1] "2015-08-16"
## 
## 
## $abbyyR
## $abbyyR$title
## [1] "abbyyR: Access to Abbyy Optical Character Recognition (OCR) API"
## 
## $abbyyR$desc
## [1] "Get text from images of text using Abbyy Cloud Optical Character\n    Recognition (OCR) API. Easily OCR images, barcodes, forms, documents with\n    machine readable zones, e.g. passports. Get the results in a variety of formats\n    including plain text and XML. To learn more about the Abbyy OCR API, see \n    <http://ocrsdk.com/>."
## 
## $abbyyR$version
## [1] "0.5.1"
## 
## $abbyyR$depends
## [1] "R (= 3.2.0)"
## 
## $abbyyR$imports
## [1] "httr, XML, curl, readr, plyr, progress"
## 
## $abbyyR$suggests
## [1] "testthat, rmarkdown, knitr (= 1.11)"
## 
## $abbyyR$published
## [1] "2017-04-12"
{% endhighlight %}

The is all for this post. In the following post, the transaction data will be analysed.

