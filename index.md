---
layout: page
title: A blog about R, Scala and IDA
---
{% include JB/setup %}

## Background

Before I began to work as a developer, the interactive and imperative programming were usual ways of performing quantitative analysis/modelling. While I have been developing in-house business applications using C# and Transact-SQL, my idea about programming has been changed to a great extent. Now I become interested in implementing an analytic task as if I were developing an application and I hope a part of the implementation would be actual development.

### R

As the project website describes, [R](http://www.r-project.org/) is a free software environment for statistical computing and graphics. I consider R is quite useful from gathering data to manipulating it to doing analysis to presenting the result.

There is a concern, however, as R would not be effective if the size of data is large although it could effectively process a lot larger data than I guess at the moment. Another concern is inconsistent APIs even among packages that aim for similar tasks as it has a variety of contributors. Therefore it would be necessary to focus on the packages that provide consistent APIs (eg [Hadley Wickham's packages](https://github.com/hadley)) or that unify existing packages in a comprehensive way (eg [mlr](http://berndbischl.github.io/mlr/tutorial/html/index.html) or [caret](http://topepo.github.io/caret/index.html) ). Finally, as R is not a general purpose language, it would be necessary to use R with another programming language sometimes. For example, it may not be possible or may be so difficult to access a certain type of data using R while it can be accessed easily using another. Or there may be a case where R should be run within another application. In these cases, interoperability with another general programming language can be important. Currently I am interested in the [jvmr](http://cran.r-project.org/web/packages/jvmr/index.html) package.

### Scala

Although even a beginning developer can be productive using C# with Visual Studio, my impression about the .NET ecosystem is that it requires a level of investment to be more productive or to keep productive. Therefore, if an individual developer is not sure if the necessary investment can be supported, it may be natural to look for open source tools. While I was searching a programming language for quantitative analysis, I was attracted by some of the languages in the JVM ecosystem: Java, Scala and Clojure. Among those, I find [Scala](http://scala-ide.org/) is quite interesting and useful.

Scala supports both the object oriented and functional programming so that a developer has a potential to benefit from the best of both worlds. Also some popular tools for data processing and/or analysis provide a Scala API: [Spark](https://spark.apache.org/), [H2O](https://github.com/0xdata/h2o/tree/master/h2o-scala) and [Mahout](https://mahout.apache.org/users/sparkbindings/home.html). Moreover interactive analysis and collaboration can be quite convenient using [Zeppelin](http://zeppelin-project.org/). This open source web-based notebook project currently supports Scala with Spark, Shell and markdown and the maintainer informed to extend its support by adding R and Python in the near future ([LINK](https://groups.google.com/forum/#!topic/zeppelin-developers/NAQNc8pha78) ).

** Update on Jan 18, 2015 **
I consider this language can play quite an important role in developing enterprise data analysis workflow. For example, [Scalding](https://github.com/twitter/scalding) (with [Sqoop](http://sqoop.apache.org/)) can be used to build data pipelining and/or ETL process and analysis can be done using tools that provides APIs such as H2O, Weka, Mahout and R via PMML - even Spark is planned to be supported in V3 of Cascading. Finally, although I haven't searched enough, outcomes can be presented using one of its web frameworks. I look forward to seeing how much I can progress with it...

### C#, F# or .NET in general?

.NET and Visual Studio have been open and they can be fully cross platform in the future ([LINK](http://blogs.msdn.com/b/somasegar/archive/2014/11/12/opening-up-visual-studio-and-net-to-every-developer-any-application-net-server-core-open-source-and-cross-platform-visual-studio-community-2013-and-preview-of-visual-studio-2015-and-net-2015.aspx)). Then my current impression about the .NET ecosystem may be no longer valid and it would be necessary to keep eyes on it.

### Intelligent Data Analysis (IDA)

I am highly interested in intelligent data analysis regardless of what it is called as statistical analysis, machine learning, statistical learning, data mining, econometrics or predictive analytics. While I was taught inferential analysis mostly, I am now more interested in predictive analysis. 

Some of the steps in predictive analysis are relatively new to me (eg resampling) and I am focusing more on them. Also it is quite important to perform analysis in an automated (or reproducible as used in academia) and a scalable way using the tools mentioned above.

I hope the subsequent articles can give me a chance to learn by doing. The source of this blog can be found [here](https://github.com/jaehyeon-kim/jaehyeon-kim.github.io).

Last updated on Jan 18, 2015

---

### Useful Sites

- [R-bloggers](http://www.r-bloggers.com/)