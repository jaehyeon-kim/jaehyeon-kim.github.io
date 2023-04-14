---
title: Boost SparkR with Hive
date: 2016-04-30
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Data Engineering
tags: 
  - Apache Spark
  - Apache Hive
  - R
  - SparkR
authors:
  - JaehyeonKim
images: []
description: One option to boost SparkR's performance as a data processing engine is manipulating data in Hive Context rather than in limited SQL Context. In this post, we discuss how to run SparkR in Hive Context.
---

In the [previous post](/blog/2016-03-02-quick-start-sparkr-in-local-and-cluster-mode), it is demonstrated how to start SparkR in local and cluster mode. While SparkR is in active development, it is yet to fully support Spark's key libraries such as MLlib and Spark Streaming. Even, as a data processing engine, this R API is still limited as it is not possible to manipulate RDDs directly but only via Spark SQL/DataFrame API. As can be checked in the [API doc](http://spark.apache.org/docs/latest/api/R/index.html), SparkR rebuilds many existing R functions to work with Spark DataFrame and notably it borrows some functions from the dplyr package. Also there are some alien functions (eg `from_utc_timestamp()`) and many of them are from [Hive Query Language (HiveQL)](https://cwiki.apache.org/confluence/display/Hive/LanguageManual). In relation to those functions from HiveQL, although some Hive user defined functions (UDFs) are ported, still many useful [UDFs](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF) and [Window functions](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics) don't exist. 

In this circumstances, I consider one option to boost SparkR's performance as a data processing engine is manipulating data in Hive Context rather than in limited SQL Context. There is good and bad news. The good one is existing Hive installation is not necessary to setup Hive Context and the other one is Spark has to be built from source with Hive. In this post, several examples of using Hive UDFs and Window functions are demonstrated, comparing to the dplyr package. Also a summary of Spark build with Hive is discussed.

## SparkR in Hive Context

I tried in local mode on my Windows machine and here is how SparkR context (*sc*) is created - for details, see [this post](/blog/2016-03-02-quick-start-sparkr-in-local-and-cluster-mode). Here the key difference is *spark_home* - this is where my pre-built Spark with Hive locates.


```r
#### set up environment variables
base_path <- getwd()
## SPARK_HOME
#spark_home <- paste0(base_path, '/spark')
spark_home <- paste0(base_path, '/spark-1.6.0-bin-spark-1.6.0-bin-hadoop2.4-hive-yarn')
Sys.setenv(SPARK_HOME = spark_home)
## $SPARK_HOME/bin to PATH
spark_bin <- paste0(spark_home, '/bin')
Sys.setenv(PATH = paste(Sys.getenv(c('PATH')), spark_bin, sep=':')) 
## HADOOP_HOME
hadoop_home <- paste0(spark_home, '/hadoop') # hadoop-common missing on Windows
Sys.setenv(HADOOP_HOME = hadoop_home) # hadoop-common missing on Windows

#### extra driver jar to be passed
postgresql_drv <- paste0(getwd(), '/postgresql-9.3-1103.jdbc3.jar')

#### add SparkR to search path
sparkr_lib <- paste0(spark_home, '/R/lib')
.libPaths(c(.libPaths(), sparkr_lib))

#### specify master host name or localhost
spark_link <- "local[*]"

library(magrittr)
library(dplyr)
library(SparkR)

## include spark-csv package
Sys.setenv('SPARKR_SUBMIT_ARGS'='"--packages" "com.databricks:spark-csv_2.10:1.3.0" "sparkr-shell"')

sc <- sparkR.init(master = spark_link,
                  sparkEnvir = list(spark.driver.extraClassPath = postgresql_drv),
                  sparkJars = postgresql_drv) 
```

```
## Launching java with spark-submit command C:/workspace/sparkr-test/spark-1.6.0-bin-spark-1.6.0-bin-hadoop2.4-hive-yarn/bin/spark-submit.cmd --jars C:\workspace\sparkr-test\postgresql-9.3-1103.jdbc3.jar  --driver-class-path "C:/workspace/sparkr-test/postgresql-9.3-1103.jdbc3.jar" "--packages" "com.databricks:spark-csv_2.10:1.3.0" "sparkr-shell" C:\Users\jaehyeon\AppData\Local\Temp\Rtmp2HKUIN\backend_port295475933bd8
```

I set up both SQL and Hive contexts for comparison.


```r
sqlContext <- sparkRSQL.init(sc)
sqlContext
```

```
## Java ref type org.apache.spark.sql.SQLContext id 1
```

```r
hiveContext <- sparkRHive.init(sc)
hiveContext
```

```
## Java ref type org.apache.spark.sql.hive.HiveContext id 4
```

A synthetic sales data is used in the examples.


```r
sales <- data.frame(dealer = c(rep("xyz", 9), "abc"),
                    make = c("highlander", rep("prius", 3), rep("versa", 3), "s3", "s3", "forrester"),
                    type = c("suv", rep("hatch", 6), "sedan", "sedan", "suv"),
                    day = c(0:3, 1:3, 1:2, 1), stringsAsFactors = FALSE)
sales
```

```
##    dealer       make  type day
## 1     xyz highlander   suv   0
## 2     xyz      prius hatch   1
## 3     xyz      prius hatch   2
## 4     xyz      prius hatch   3
## 5     xyz      versa hatch   1
## 6     xyz      versa hatch   2
## 7     xyz      versa hatch   3
## 8     xyz         s3 sedan   1
## 9     xyz         s3 sedan   2
## 10    abc  forrester   suv   1
```

## Basic data manipulation

The first example is a basic data manipulation, which counts the number of records per *dealer*, *make* and *type*.


```r
sales_s <- createDataFrame(sqlContext, sales)

sales_s %>%
  select(sales_s$dealer, sales_s$make, sales_s$type) %>%
  group_by(sales_s$dealer, sales_s$make, sales_s$type) %>%
  summarize(count = count(sales_s$dealer)) %>%
  arrange(sales_s$dealer, sales_s$make) %>% head()
```

```
##   dealer       make  type count
## 1    abc  forrester   suv     1
## 2    xyz highlander   suv     1
## 3    xyz      prius hatch     3
## 4    xyz         s3 sedan     2
## 5    xyz      versa hatch     3
```

This kind of manipulation also works in Spark SQL after registering the RDD as a temporary table. Here another Spark DataFrame (*sales_h*) is created using Hive Context and the equivalent query is applied - this works in both SQL and Hive context.


```r
sales_h <- createDataFrame(hiveContext, sales)
registerTempTable(sales_h, "sales_h")

qry_h1 <- "SELECT dealer, make, type, count(*) AS count FROM sales_h GROUP BY dealer, type, make ORDER BY dealer, make"
sql(hiveContext, qry_h1) %>% head()
```

```
##   dealer       make  type count
## 1    abc  forrester   suv     1
## 2    xyz highlander   suv     1
## 3    xyz      prius hatch     3
## 4    xyz         s3 sedan     2
## 5    xyz      versa hatch     3
```

### Window function example

Window functions can be useful as data can be summarized by partition but they are not supported in SQL context. Here is an example of adding rank by the number of records per group, followed by dplyr equivalent. Note that some functions in the dplyr package are masked by the SparkR package so that their name space (*dplyr*) is indicated where appropriate.


```r
qry_h2 <- "
SELECT dealer, make, type, rank() OVER (PARTITION BY dealer ORDER BY make, count DESC) AS rank FROM (
  SELECT dealer, make, type, count(*) AS count FROM sales_h GROUP BY dealer, type, make
) t"
sql(hiveContext, qry_h2) %>% head()
```

```
##   dealer       make  type rank
## 1    abc  forrester   suv    1
## 2    xyz highlander   suv    1
## 3    xyz      prius hatch    2
## 4    xyz         s3 sedan    3
## 5    xyz      versa hatch    4
```

```r
sales %>% dplyr::select(dealer, make, type) %>%
  dplyr::group_by(dealer, type, make) %>%
  dplyr::mutate(count = n()) %>%
  dplyr::distinct(dealer, make, type) %>%
  dplyr::arrange(dealer, -count) %>%
  dplyr::ungroup() %>% 
  dplyr::arrange(dealer, make) %>%
  dplyr::group_by(dealer) %>% 
  dplyr::mutate(rank = row_number()) %>%
  dplyr::select(-count)
```

```
## Source: local data frame [5 x 4]
## Groups: dealer [2]
## 
##   dealer       make  type  rank
##    (chr)      (chr) (chr) (int)
## 1    abc  forrester   suv     1
## 2    xyz highlander   suv     1
## 3    xyz      prius hatch     2
## 4    xyz         s3 sedan     3
## 5    xyz      versa hatch     4
```

The next window function example is adding cumulative counts per *dealer* and *make*.


```r
qry_h3 <- "SELECT dealer, make, count, SUM(count) OVER (PARTITION BY dealer ORDER BY dealer, make) as cumsum FROM (
  SELECT dealer, make, count(*) AS count FROM sales_h GROUP BY dealer, make
) t"
sql(hiveContext, qry_h3) %>% head()
```

```
##   dealer       make count cumsum
## 1    abc  forrester     1      1
## 2    xyz highlander     1      1
## 3    xyz      prius     3      4
## 4    xyz         s3     2      6
## 5    xyz      versa     3      9
```

```r
sales %>% dplyr::select(dealer, make) %>%
  dplyr::group_by(dealer, make) %>%
  dplyr::mutate(count = n()) %>%
  dplyr::distinct(dealer, make, count) %>%
  dplyr::arrange(dealer, make) %>%
  dplyr::ungroup() %>%
  dplyr::group_by(dealer) %>%
  dplyr::mutate(cumsum = cumsum(count))
```

```
## Source: local data frame [5 x 4]
## Groups: dealer [2]
## 
##   dealer       make count cumsum
##    (chr)      (chr) (int)  (int)
## 1    abc  forrester     1      1
## 2    xyz highlander     1      1
## 3    xyz      prius     3      4
## 4    xyz         s3     2      6
## 5    xyz      versa     3      9
```

### UDF example

There are lots of useful UDFs in HiveQL and many of them are currently missing in the SparkR package. Here `collect_list()` is used for illustration where sales paths per dealer and type are created - for further details of this and other functions, see this [language manual](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF).


```r
qry_h4 <- "SELECT dealer, type, concat_ws(' > ', collect_list(make)) AS sales_order FROM (
  SELECT dealer, day, type, make FROM sales_h ORDER BY dealer, type, day
) t GROUP BY dealer, type ORDER BY dealer, type
"
sql(hiveContext, qry_h4) %>% head()
```

```
##   dealer  type                                   sales_order
## 1    abc   suv                                     forrester
## 2    xyz hatch prius > versa > prius > versa > prius > versa
## 3    xyz sedan                                       s3 > s3
## 4    xyz   suv                                    highlander
```

```r
sales %>% dplyr::arrange(dealer, type, day) %>%
  dplyr::group_by(dealer, type) %>%
  dplyr::summarise(sales_order = paste(make, collapse = " > ")) %>%
  dplyr::arrange(dealer, type)
```

```
## Source: local data frame [4 x 3]
## Groups: dealer [2]
## 
##   dealer  type                                   sales_order
##    (chr) (chr)                                         (chr)
## 1    abc   suv                                     forrester
## 2    xyz hatch prius > versa > prius > versa > prius > versa
## 3    xyz sedan                                       s3 > s3
## 4    xyz   suv                                    highlander
```

## Spark build with Hive

I built Spark with Hive in the latest LTS Ubuntu - [Ubuntu 16.04 Xenial Xerus](http://releases.ubuntu.com/16.04/). I just used the default JAVA version and Scala 2.10.3. The source is built for Hadoop 2.4 (`-Phadoop-2.4` and `-Dhadoop.version=2.4.0`) with YARN (`-Pyarn`) and Hive (`-Phive` and `-Phive-thriftserver`). I also selected to include SparkR (`-Psparkr`). See the [official documentation](http://spark.apache.org/docs/latest/building-spark.html) for further details.

Here is a summary of steps followed.

* Update packages
    + `sudo apt-get update`
* Install JAVA and set JAVA_HOME
    + `sudo apt-get install default-jdk`
    + `export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"`
* Install Scala 2.10.3
    + `wget http://www.scala-lang.org/files/archive/scala-2.10.3.tgz`
    + `tar xvf scala-2.10.3.tgz`
    + `sudo mv scala-2.10.3 /usr/bin`
    + `sudo ln -s /usr/bin/scala-2.10.3 /usr/bin/scala`
    + `export PATH=$PATH:/usr/bin/scala/bin`
* Download Spark 1.6.0 and run *make-distribution.sh*
    + `wget http://d3kbcqa49mib13.cloudfront.net/spark-1.6.0.tgz`
    + `tar xvf spark-1.6.0.tgz`
    + `cd spark-1.6.0`
    + `export MAVEN_OPTS="-Xmx2g -XX:MaxPermSize=512M -XX:ReservedCodeCacheSize=512m"`
    + `./make-distribution.sh --name spark-1.6.0-bin-hadoop2.4-hive-yarn --tgz -Pyarn -Phadoop-2.4 -Dhadoop.version=2.4.0 -Psparkr -Phive -Phive-thriftserver -DskipTests`

The build was done in a VirtualBox guest where 2 cores and 8 GB of memory were allocated. After about 30 minutes, I was able to see the following output and the pre-built Spark source (*spark-1.6.0-bin-spark-1.6.0-bin-hadoop2.4-hive-yarn.tgz*).

![](reactor_summary.png#center)

I hope this post is useful.










