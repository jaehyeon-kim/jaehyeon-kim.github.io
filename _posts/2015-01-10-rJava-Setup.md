---
layout: post
title: "2015-01-10-rJava-Setup"
description: ""
category: Intro
tags: [rJava, RWeka, CentOS]
---
I tried to install **RWeka** but failed as **rJava** couldn't be installed mainly because Java is installed in a non-conventional location. Below is quick summary of installing/loading these packages.

For installation, **JAVA_HOME** should be updated and the following has been done under the _root_ account - it is found [here](http://r.789695.n4.nabble.com/Can-t-get-R-to-recognize-Java-for-rJava-installation-td4553023.html)


{% highlight r %}
[root@localhost /]# su -

[root@localhost /]# export JAVA_HOME=/home/jaehyeon/jdk1.7.0_71
[root@localhost /]# export PATH=$PATH:$JAVA_HOME/bin

[root@localhost /]# export JAVA_HOME=/home/jaehyeon/jdk1.7.0_71/jre
[root@localhost /]# export PATH=$PATH:$JAVA_HOME/bin

[root@localhost /]# R CMD javareconf
{% endhighlight %}

The modified Java paths are shown below.


{% highlight r %}
Java interpreter : /home/jaehyeon/jdk1.7.0_71/jre/bin/java
Java version     : 1.7.0_71
Java home path   : /home/jaehyeon/jdk1.7.0_71/jre
Java compiler    : /home/jaehyeon/jdk1.7.0_71/jre/../bin/javac
Java headers gen.: /home/jaehyeon/jdk1.7.0_71/jre/../bin/javah
Java archive tool: /home/jaehyeon/jdk1.7.0_71/jre/../bin/jar
{% endhighlight %}

However **rJava** couldn't be loaded with the followign error.


{% highlight r %}
> library(rJava)
Error : .onLoad failed in loadNamespace() for 'rJava', details:
  call: dyn.load(file, DLLpath = DLLpath, ...)
  error: unable to load shared object '/home/jaehyeon/R/x86_64-redhat-linux-gnu-library/3.1/rJava/libs/rJava.so':
  libjvm.so: cannot open shared object file: No such file or directory
Error: package or namespace load failed for ‘rJava’
{% endhighlight %}

After some googling, a remedy was found by creating the **java.conf** file - it is found [here](http://stackoverflow.com/questions/13403268/error-while-loading-rjava).


{% highlight r %}
[root@localhost /]# cd /etc/ld.so.conf.d/
[root@localhost ld.so.conf.d]# vi java.conf
{% endhighlight %}

In the Vim editor, the followign two lines are added.


{% highlight r %}
/home/jaehyeon/jdk1.7.0_71/jre/lib/amd64
/home/jaehyeon/jdk1.7.0_71/jre/lib/amd64/server
{% endhighlight %}

Finally the configuration has been executed by following.


{% highlight r %}
[root@localhost ld.so.conf.d]# ldconfig
{% endhighlight %}

After that it was possible to install and load these packages.
