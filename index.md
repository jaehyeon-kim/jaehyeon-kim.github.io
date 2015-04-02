---
layout: page
title: A blog about R, Scala and IDA
---
{% include JB/setup %}

## Background

As a typical graduate of majoring economics and actuarial studies, interactive and imperative programming were usual ways of performing analysis. While I have been developing in-house business applications using C# and Transact-SQL, however, my idea about programming has been changed to a great extent, which is more than appreciating object oriented programming. Now I am interested in implementing analytic tasks as if I were developing an application and I hope a part of it would be actual development.

### R for Intelligent data analysis (IDA)

As the project website describes, [R](http://www.r-project.org/) is a free software environment for statistical computing and graphics. I consider R is quite useful for intelligent data analysis (IDA) where the term here is referred to methods or techniques that include statistical analysis, machine learning, statistical learning, data mining, econometrics, actuarial methods and predictive analytics.

As a tool for IDA, creating a workflow that is performing the same or similar tasks regularly in an automated way would be quite important in a business environment. In academia, reproducible research shares similar ideas but the level of reproducibility introduced in [[Gandrud, 2013](http://www.crcpress.com/product/isbn/9781466572843)] may not suffice as the focus is creating a document in a reproducible way. A **R package**, however, can be an effective tool and it can be considered as a portable class library in C# or Java. Like a class library, it can include a set of necessary tasks (usually using functions) and, being portable, its dependency can be managed suitably. Moreover the benefit of creating a R package would be significant if it has to be deployed in a production server as it’d be a lot easier to convince system admin with the built-in unit tests, object documents and package vignettes. With R Studio and several related packages, it is relatively straightforward to create a package and I'm also interested in developing R packages on top of performing analysis in an interactive/imperative way - an example of steps to create a package can be checked in [this post](http://jaehyeon-kim.github.io/r/2015/03/24/Packaging-Analysis/).

While R attracts more and more so-called data scientists, there are concerns that may prevent it to be used for large scale data analysis. **Lack of multi-threading** and **memory limitation** are two noticeable shortcomings of base R. As R keeps data in memory, its **memory limitation** would be the fundamental obstacle although data may be kept in a backend (eg RDBMS) or more RAM may be bought from a cloud service provider (eg Amazon EC2). On the other hand, multi-threading can be achieved relatively easily provided that data is fit into memory as shown in several posts ([post 1](http://jaehyeon-kim.github.io/r/2015/03/14/Parallel-Processing-on-Single-Machine-Part-I/), [post 2](http://jaehyeon-kim.github.io/r/2015/03/17/Parallel-Processing-on-Single-Machine-Part-II/), [post 3](http://jaehyeon-kim.github.io/r/2015/03/19/Parallel-Processing-on-Single-Machine-Part-III/)). There are some vendors/projects that provide ways to overcome the drawback such as Distributed R, RHadoop, RHipe, H2O and SparkR but none of them seems to be compatible with exisitng R packages and *probably it will not be in the future as existing packages have to be rebuilt*. In this regard it'd be one of the most important challenges that the R community should tackle down in the era of *big data*. At the moment, I'm interested in [Apache Spark](https://spark.apache.org/) and the [SparkR](https://github.com/amplab-extras/SparkR-pkg) package, which provides Spark's RDD API, and planning to develop a package of popular machine learning/data mining algorithms that utilize HDFS via Spark.

### Scala for Intelligent data analysis (IDA)

Although even a beginning developer can be productive using C# with Visual Studio, my impression about the .NET ecosystem is that it requires a level of investment to be more productive or to keep productive. Therefore, if an individual developer is not sure whether the necessary investment can be supported, it may be natural to look for open source tools. While I was searching a programming language for quantitative analysis, I was attracted by the languages in the JVM ecosystem: Java, Scala and Clojure. Among those, I find [Scala](http://scala-ide.org/) is quite interesting and useful.

Scala supports both object oriented and functional programming so that a developer has a potential to benefit from the best of both worlds. As well as algorithms can be built directly in Scala as illustrated in [[Nicolas, 2014](https://www.packtpub.com/big-data-and-business-intelligence/scala-machine-learning)], a number of popular data processing and analysis tools provide Scala APIs - [Spark](https://spark.apache.org/), [H2O](https://github.com/0xdata/h2o/tree/master/h2o-scala) and [Mahout](https://mahout.apache.org/users/sparkbindings/home.html). As mentioned earlier, I'm highly interested in developing a R package of analysis algorithms that integrates Spark and R and, hopefully, the fact that R also supports functional programming would be helpful for the integration project.

While the above potential is of my main interest at the moment, I consider this language can play quite an important role in developing enterprise analysis workflow. For example, [Scalding](https://github.com/twitter/scalding) (with [Sqoop](http://sqoop.apache.org/)) can be used to build data pipelining and/or ETL processes. Moreover analysis can be done using tools that provide Scala APIs mentioned above or even R via PMML. Besides Spark is planned to be supported in V3 of [Cascading](http://www.datanami.com/2014/05/13/cascading-now-supports-tez-spark-storm-next/) - Scalding is ported from this project. Therefore, in the future, it may be possible to intermingle R, Scala, Scaling and Spark and the benefit could be quite significant.

**Last updated on Apr 1, 2015**

---

### Useful Sites


- [R-bloggers](http://www.r-bloggers.com/)