---
layout: post
title: "2016-03-02-Quick-Start-SparkR-in-Local-and-Cluster-Mode"
description: ""
category: Spark
tags: [programming, Spark, SparkR]
---
In the [previous post](http://jaehyeon-kim.github.io/2016/02/Spark-Cluster-Setup-on-VirtualBox), a Spark cluster is set up using 2 VirtualBox Ubuntu guests. while this is a viable option for many, it is not always for others. For those who find setting-up such a cluster is not convenient, there's still another option, which is relying on the local mode of Spark. In this post, a BitBucket repository is introduced, which is a R project that includes *Spark 1.6.0 Pre-built for Hadoop 2.0 and later* and *hadoop-common 2.2.0* - the latter is necessary if it is tested on Windows. Then several initialization steps are discussed such as setting-up environment variables and library path as well as including the [spark-csv package](https://github.com/databricks/spark-csv) and a JDBC driver. Finally it shows some examples of reading JSON and CSV files in the cluster mode.

### [sparkr-test](https://bitbucket.org/jaehyeon/sparkr-test) repo

*Spark 1.6.0 Pre-built for Hadoop 2.0 and later* is downloaded and renamed as *spark* after decompressing. Also, *hadoop-common 2.2.0* is downloaded from this [GitHub repo](https://github.com/srccodes/hadoop-common-2.2.0-bin/archive/master.zip) and saved within the *spark* folder as *hadoop*. The *SparkR* package is in *R/lib* and the *bin* path includes files that execute spark applications interactively and in batch mode. The *conf* folder includes a number of configuration templates. At the moment, only one of the templates is modified - *log4j.properties.template*. This template is renanmed as *log4j.properties* and *log4j.rootCategory* is set to be *WARN* as shown below. Previously it was *INFO* and it may be distracting as a lot of messages are printed with this option.


{% highlight r %}
# Set everything to be logged to the console
log4j.rootCategory=WARN, console
{% endhighlight %}

The spark folder in the repository is shown below.

![center](/figs/2016-03-02-Quick-Start-SparkR-in-Local-and-Cluster-Mode/01_spark_foler.png)

There are 2 data files. *iris.json* is the popular iris data set in JSON format. *iris_up.csv* is the same data set in CSV format with 3 extra columns - 1 integer, 1 date and 1 integer column with NA values - how to read them will be discussed shortly. *postgresql-9.3-1103.jdbc3.jar* is a JDBC driver to connect *PostgreSQL*-like database servers such as PostgreSQL server or Amazon Redshift - you may add another driver for your own DB server.

### Initialization

#### Local mode

It sets two environment variables: **SPARK_HOME** and **HADOOP_HOME**. The latter is mandatory if you're running this example on Windows (possibly in local mode). Otherwise the following error is thrown: `java.lang.NullPointerException`. Note that the Spark pre-built distribution doesn't include *Hadoop-common* and it is downloaded from [this repo](https://github.com/srccodes/hadoop-common-2.2.0-bin/archive/master.zip) and added within the *spark* folder - the foler is named as *hadoop*. If it is running on Linux, this part can be commented out as in the cluster mode example below. 

Also the spark *bin* directory is added to the **PATH** environment variable - this path is where *spark-submit* (Spark batch excutor) and Saprk REPL launchers exist. Then the path of the db driver (*postgresql-9.3-1103.jdbc3.jar*) is specified - see **postgresql_drv**. As can be seen in *sparkR.init()*, the path is added to environment variable on the worker node by adding *sparkEnvir* and the driver is passed to the worker node by setting *sparkJars*.

Finally the search path is updated to add the SparkR package (**sparkr_lib**). For the local mode, the master can be set as _local[*]_ if it is required to use all existing cores or a specific number can be specified - see **spark_link**. The last environment variable (**SPARKR_SUBMIT_ARGS**) is for controlling *spark-submit*. In this setting, the *spark-csv package* is included at launch.

At the end, a spark context (**sc**) and sql context (**sqlContext**) are defined. Note that, in this way, it is possible to run a Spark application interactively as well as in batch mode using Rscript, rather than using *spark-submit*.


{% highlight r %}
#### set up environment variables
base_path <- getwd()
## SPARK_HOME
spark_home <- paste0(base_path, '/spark')
Sys.setenv(SPARK_HOME = spark_home)
## $SPARK_HOME/bin to PATH
spark_bin <- paste0(spark_home, '/bin')
Sys.setenv(PATH = paste(Sys.getenv(c('PATH')), spark_bin, sep=':')) 
## HADOOP_HOME
# hadoop-common missing on Windows and downloaded from 
#   https://github.com/srccodes/hadoop-common-2.2.0-bin/archive/master.zip
# java.lang.NullPointerException if not set
hadoop_home <- paste0(spark_home, '/hadoop') # hadoop-common missing on Windows
Sys.setenv(HADOOP_HOME = hadoop_home) # hadoop-common missing on Windows

#### extra driver jar to be passed
postgresql_drv <- paste0(getwd(), '/postgresql-9.3-1103.jdbc3.jar')

#### add SparkR to search path
sparkr_lib <- paste0(spark_home, '/R/lib')
.libPaths(c(.libPaths(), sparkr_lib))

#### specify master host name or localhost
#spark_link <- system('cat /root/spark-ec2/cluster-url', intern=TRUE)
spark_link <- "local[*]"
#spark_link <- 'spark://192.168.1.10:7077'

library(SparkR)

## include spark-csv package
Sys.setenv('SPARKR_SUBMIT_ARGS'='"--packages" "com.databricks:spark-csv_2.10:1.3.0" "sparkr-shell"')

sc <- sparkR.init(master = spark_link, appName = "SparkR_local",
                  sparkEnvir = list(spark.driver.extraClassPath = postgresql_drv),
                  sparkJars = postgresql_drv) 
sqlContext <- sparkRSQL.init(sc)

## do something

sparkR.stop()
{% endhighlight %}

#### standalone cluster

In order to run the script in the cluster mode, the two data files (*iris.json* and *iris_up.csv*) are copied to `~/data` in both the master and slave machines. (Files should exist in the same location if you're not using HDFS, S3 ...) I simply used WinSCP and you may find [this post](http://jaehyeon-kim.github.io/2015/11/Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server) useful. Also I started a cluster by `~/spark/sbin/start-all.sh` - see [this post](http://jaehyeon-kim.github.io/2016/02/Spark-Cluster-Setup-on-VirtualBox) for further details.

The main difference is the Spark master, which is set to be *spark://192.168.1.10:7077*.


{% highlight r %}
#### set up environment variables
base_path <- '/home/jaehyeon'
## SPARK_HOME
spark_home <- paste0(base_path, '/spark')
Sys.setenv(SPARK_HOME = spark_home)
## $SPARK_HOME/bin to PATH
spark_bin <- paste0(spark_home, '/bin')
Sys.setenv(PATH = paste(Sys.getenv(c('PATH')), spark_bin, sep=':')) 
## HADOOP_HOME
# hadoop-common missing on Windows and downloaded from 
#	https://github.com/srccodes/hadoop-common-2.2.0-bin/archive/master.zip
# java.lang.NullPointerException if not set
#hadoop_home <- paste0(spark_home, '/hadoop') # hadoop-common missing on Windows
#Sys.setenv(HADOOP_HOME = hadoop_home) # hadoop-common missing on Windows

#### extra driver jar to be passed
postgresql_drv <- paste0(getwd(), '/postgresql-9.3-1103.jdbc3.jar')

#### add SparkR to search path
sparkr_lib <- paste0(spark_home, '/R/lib')
.libPaths(c(.libPaths(), sparkr_lib))

#### specify master host name or localhost
#spark_link <- system('cat /root/spark-ec2/cluster-url', intern=TRUE)
#spark_link <- "local[*]"
spark_link <- 'spark://192.168.1.10:7077'

library(SparkR)

## include spark-csv package
Sys.setenv('SPARKR_SUBMIT_ARGS'='"--packages" "com.databricks:spark-csv_2.10:1.3.0" "sparkr-shell"')

sc <- sparkR.init(master = spark_link, appName = "SparkR_cluster",
                  sparkEnvir = list(spark.driver.extraClassPath = postgresql_drv),
                  sparkJars = postgresql_drv) 
{% endhighlight %}



{% highlight text %}
## Launching java with spark-submit command /home/jaehyeon/spark/bin/spark-submit --jars /home/jaehyeon/jaehyeon-kim.github.io/_posts/projects/postgresql-9.3-1103.jdbc3.jar  --driver-class-path "/home/jaehyeon/jaehyeon-kim.github.io/_posts/projects/postgresql-9.3-1103.jdbc3.jar" "--packages" "com.databricks:spark-csv_2.10:1.3.0" "sparkr-shell" /tmp/RtmpuQHgNQ/backend_port1ee16d63ec86
{% endhighlight %}



{% highlight r %}
sqlContext <- sparkRSQL.init(sc)

data_path <- paste0(base_path, '/data')
{% endhighlight %}

The JSON format is built-in so that it suffices to specify the source. By default, `read.df()` infers the schema (or data type) and it is found that all data types are identified correctly except for the last one where it includes some NA values.


{% highlight r %}
iris_js <- read.df(sqlContext, path = paste0(data_path, "/iris.json"), source = "json")
head(iris_js)
{% endhighlight %}



{% highlight text %}
##   Petal_Length Petal_Width Sepal_Length Sepal_Width Species
## 1          1.4         0.2          5.1         3.5  setosa
## 2          1.4         0.2          4.9         3.0  setosa
## 3          1.3         0.2          4.7         3.2  setosa
## 4          1.5         0.2          4.6         3.1  setosa
## 5          1.4         0.2          5.0         3.6  setosa
## 6          1.7         0.4          5.4         3.9  setosa
{% endhighlight %}

The schema inference is worse on CSV as the date field is identified as string.


{% highlight r %}
iris_inf <- read.df(sqlContext, path = paste0(data_path, "/iris_up.csv"),
                    source = "com.databricks.spark.csv", inferSchema = "true", header = "true")
head(iris_inf)
{% endhighlight %}



{% highlight text %}
##   Sepal.Length Sepal.Width Petal.Length Petal.Width Species int       date
## 1          5.1         3.5          1.4         0.2  setosa   1 2016-02-29
## 2          4.9         3.0          1.4         0.2  setosa   2 2016-02-29
## 3          4.7         3.2          1.3         0.2  setosa   3 2016-02-29
## 4          4.6         3.1          1.5         0.2  setosa   4 2016-02-29
## 5          5.0         3.6          1.4         0.2  setosa   5 2016-02-29
## 6          5.4         3.9          1.7         0.4  setosa   6 2016-02-29
##   null
## 1   NA
## 2   NA
## 3   NA
## 4    4
## 5    5
## 6    6
{% endhighlight %}



{% highlight r %}
schema(iris_inf)
{% endhighlight %}



{% highlight text %}
## StructType
## |-name = "Sepal.Length", type = "DoubleType", nullable = TRUE
## |-name = "Sepal.Width", type = "DoubleType", nullable = TRUE
## |-name = "Petal.Length", type = "DoubleType", nullable = TRUE
## |-name = "Petal.Width", type = "DoubleType", nullable = TRUE
## |-name = "Species", type = "StringType", nullable = TRUE
## |-name = "int", type = "IntegerType", nullable = TRUE
## |-name = "date", type = "StringType", nullable = TRUE
## |-name = "null", type = "StringType", nullable = TRUE
{% endhighlight %}

It is possible to specify individual data types by constructing a custom schema (*customSchema*). Note that the last column (*null*) is set as *string* in the custom schema and converted into *integer* using `cast()` after the data is loaded. The reason is *NA* is considered as *string* that the following error will be thrown if it is set as *integer*: `java.lang.NumberFormatException: For input string: "NA"`.


{% highlight r %}
customSchema <- structType(
  structField("Sepal.Length", "double"),
  structField("Sepal.Width", "double"),
  structField("Petal.Length", "double"),
  structField("Petal.Width", "double"),
  structField("Species", "string"),
  structField("integer", "integer"),
  structField("date", "date"),
  structField("null", "string")
)

iris_cus <- read.df(sqlContext, path = paste0(data_path, "/iris_up.csv"),
                    source = "com.databricks.spark.csv", schema = customSchema, header = "true")
cast(iris_cus$null, "integer")
{% endhighlight %}



{% highlight text %}
## Column unresolvedalias(cast(null as int))
{% endhighlight %}



{% highlight r %}
head(iris_cus)
{% endhighlight %}



{% highlight text %}
##   Sepal.Length Sepal.Width Petal.Length Petal.Width Species integer
## 1          5.1         3.5          1.4         0.2  setosa       1
## 2          4.9         3.0          1.4         0.2  setosa       2
## 3          4.7         3.2          1.3         0.2  setosa       3
## 4          4.6         3.1          1.5         0.2  setosa       4
## 5          5.0         3.6          1.4         0.2  setosa       5
## 6          5.4         3.9          1.7         0.4  setosa       6
##         date null
## 1 2016-02-29   NA
## 2 2016-02-29   NA
## 3 2016-02-29   NA
## 4 2016-02-29    4
## 5 2016-02-29    5
## 6 2016-02-29    6
{% endhighlight %}



{% highlight r %}
schema(iris_cus)
{% endhighlight %}



{% highlight text %}
## StructType
## |-name = "Sepal.Length", type = "DoubleType", nullable = TRUE
## |-name = "Sepal.Width", type = "DoubleType", nullable = TRUE
## |-name = "Petal.Length", type = "DoubleType", nullable = TRUE
## |-name = "Petal.Width", type = "DoubleType", nullable = TRUE
## |-name = "Species", type = "StringType", nullable = TRUE
## |-name = "integer", type = "IntegerType", nullable = TRUE
## |-name = "date", type = "DateType", nullable = TRUE
## |-name = "null", type = "StringType", nullable = TRUE
{% endhighlight %}

I hope this post is useful.
