---
layout: post
title: "2015-02-21-Quick-Trial-of-Turning-Analysis-into-S3-Object"
description: ""
category: R
tags: [ggplot2, rpart, programming]
---
While comparing the three packages (**rpart**, **caret**, **mlr**) in the [previous article](http://jaehyeon-kim.github.io/r/2015/02/15/Tree-Based-Methods-Part-IV-Packages-Comparison/), I was quite concerned that names of new variables are not easy to be kept effectively. First of all, names that are separated by full stop (.) are by no means effective and/or it gets harder to keep a comprehensive naming convention as the number of variables increases. Secondly, although old variables may be replaced, there are cases that some of them should be kept during analysis and/or, at worst, replacement can be unintentional. Also, as R is not type-safe due to its dynamic type system, things can go beyond control easily. In order to keep analysis under control, the S3 object system is looked into and it is found that, at least, key analysis outcomes can be easily encapsulated as members of a list so that it can be easier to perform analysis without making horible names and/or avoidng an error that is caused by confliting names.

This article begins with a simple example that illustrates what seems to be the most relevant for encapculating variables and thus it is not complete - for those who are intested in more details, please see [these slides](http://www.mat.uc.cl/~susana/CE/oopV2.pdf). Then a class that holds CART analysis outcomes is discussed - this class aims to keep the same outcomes by the *rpart* package in the [previous article](http://jaehyeon-kim.github.io/r/2015/02/15/Tree-Based-Methods-Part-IV-Packages-Comparison/)

### Basic example

The basic example creates two classes: *employee* and *manager*. The base class of *employee* has a single property (*name*) and method (`print.employee()`). Note that this method extends the S3 generic function of `print()` so that the full name doesn't need to be entered (ie `print(obj)` is enough). The class of *manager* **is-a** *employee* and thus it can inherit and extend the functionality of the base class. This class has an additional property (*members*) and, as the name suggests, this property aims to keep team members - each member is an instance of the class *employee*.

Although there are a number of ways to create a class, creating one by a function (or constructor) would be good for S3 objects. Below *employee* and *manager* classes are created by `emp()` and `man()` respectively. 


{% highlight r %}
# construct base class - employee
emp = function(name) {
  if(length(name) != 1 && !is.character(name))
    stop("single string value of name necessary")
  # assign name to result
  result = name
  class(result) = "employee"
  return(result)
}

# extend base class - manager
# manager 'is-a' employee
man = function(name, members) {
  # create base class (employee)
  result = emp(name)
  # arguments should be carefully checked
  if(length(sapply(members,class)[sapply(members,class)=="character"]) != length(members))
    stop("a vector of employees necessary")
  # combine name and members as a list
  result = list(name=result,members=members)
  class(result)=c("manager","employee")
  return(result)
}
{% endhighlight %}

Note that

- As *employee* has a single property, a character vector is assigned. If there are multiple properties, a list can be used as the case of *manager*.
- Class names are assigned at the end and, as *manager* extends *employee*, both the classes names are assigned to it.
- A drawback of S3 objects is that their class attribute(s) can be changed without restriction, simply by replacing the exisiting one(s) or by `unclass()`.  Therefore it is important to put pieces to check the arguments of a constructor. `If (condition) stop(message)` can be used for this purpose. For example, `man()` checks whether the class of each element of *members* is *character* and throws an error if not. To illustrate this, a numeric vector of 1 is passed to this function and it causes the following error: *Error in man("John", foo) : a vector of employees necessary*. This can prevent a potentially undesirable result.


{% highlight r %}
tom = emp("Tom")
alice = emp("Alice")
nick = man("Nick",c(tom,alice))

# without print function
tom
{% endhighlight %}



{% highlight text %}
## [1] "Tom"
## attr(,"class")
## [1] "employee"
{% endhighlight %}



{% highlight r %}
nick
{% endhighlight %}



{% highlight text %}
## $name
## [1] "Nick"
## attr(,"class")
## [1] "employee"
## 
## $members
## [1] "Tom"   "Alice"
## 
## attr(,"class")
## [1] "manager"  "employee"
{% endhighlight %}

This throws an error with a message of *Error in man("John", foo) : a vector of employees necessary*.


{% highlight r %}
# incorrectly assigned class should be handled
foo = c(1)
class(foo) = "employee"
class(foo)
man("John",foo)
{% endhighlight %}

Below the S3 generic function of `print()` is extended. Note that it is recommended not to include full stop (.) in a class name. Otherwise R may not be able to identify the correct method to execute.


{% highlight r %}
# S3 base method can be extended
# better not to include full stop(.) in class name
print.employee = function(obj) {
  cat("Employee Name:",obj,"\n")
}

print.manager = function(obj) {
  print.employee(obj$name)
  cat("Members:",obj$members,"\n")
}

# with print function
tom
{% endhighlight %}



{% highlight text %}
## Employee Name: Tom
{% endhighlight %}



{% highlight r %}
nick
{% endhighlight %}



{% highlight text %}
## Employee Name: Nick 
## Members: Tom Alice
{% endhighlight %}

Available methods can be searched by entering a method or class name.


{% highlight r %}
# methods that extends print
head(methods("print"),3)
{% endhighlight %}



{% highlight text %}
## [1] "print.acf"   "print.AES"   "print.anova"
{% endhighlight %}



{% highlight r %}
methods("print")[grep("*employee",methods("print"))]
{% endhighlight %}



{% highlight text %}
## [1] "print.employee"
{% endhighlight %}



{% highlight r %}
# methods that associated with manager class
methods(class="employee")
{% endhighlight %}



{% highlight text %}
## [1] print.employee
{% endhighlight %}

If class attributes are changed, the new print methods no longer work.


{% highlight r %}
# class can be checked/modified
class(tom) = NULL
tom # character vector
{% endhighlight %}



{% highlight text %}
## [1] "Tom"
{% endhighlight %}



{% highlight r %}
# list names and assigned classes can be checked/modified
attributes(nick)
{% endhighlight %}



{% highlight text %}
## $names
## [1] "name"    "members"
## 
## $class
## [1] "manager"  "employee"
{% endhighlight %}



{% highlight r %}
attributes(nick) = NULL
nick
{% endhighlight %}



{% highlight text %}
## [[1]]
## Employee Name: Nick 
## 
## [[2]]
## [1] "Tom"   "Alice"
{% endhighlight %}

### RPART example

This class (*rpartExt*) repeats the previous analysis and produces a list of the following variables

- CART model object by the *rpart* package
- *cp* values at minimum *xerror* and by the *1-SE rule* (it is now abbreviated as *se* rather than *bst*)
- 4 sets of performance results on the train and test data (2 *cp* values on 2 data sets)

In line with the above example, this class plays the same role to *employee* as a base class and the outcomes by the *caret* and *mlr* packages can also be created to extend the base class like *manager*.

As this class encapsulates key outcomes in a list, it is possible to keep variables more effectively. Moreover, as it can handle both classification and regression, it is more easier to update/add new variables as well as the number of variables needed can be quite smaller. The source of this class can be checked on [here](https://gist.github.com/jaehyeon-kim/b89dcbd2fb0b84fd236e). Note that a number of utility functions are necessary and they can be seen on [here](https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550)


{% highlight r %}
## CART example
cartRPART = function(trainData, testData=NULL, formula, ...) {
  if(class(trainData) != "data.frame" & ifelse(is.null(testData),TRUE,class(testData)=="data.frame"))
    stop("data frames should be entered for train and test (if any) data")  
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  if(res.name %in% colnames(trainData) == FALSE)
    stop("response is not found in train data")
  if(class(trainData[,res.ind]) != "factor") {
    if(class(trainData[,res.ind]) != "numeric") {
      stop("response should be either numeric or factor")
    }
  } 
  if("rpart" %in% rownames(installed.packages()) == FALSE)
    stop("rpart package is not installed")
  
  ## import utility functions
  source("src/mlUtils.R")
  
  require(rpart)
  # rpart model - $mod (1)
  mod = rpart(formula=formula, data=trainData, control=rpart.control(cp=0))
  # min/best cp - $cp (2)
  cp = bestParam(mod$cptable,"CP","xerror","xstd")
  # performance
  perf = function(model,data,response,params,isTest=TRUE,isSE=TRUE) {
    param = ifelse(isSE,params[1,2],params[1,1])
    fit = prune(model, cp=param)
    if(class(trainData[,res.ind]) == "factor") {
      ftd = predict(fit, newdata=data, type="class")
      cm = table(actual=data[,res.ind], fitted=ftd)
      cm.up = updateCM(cm,type=ifelse(isTest,"Ptd","Ftd"))
    } else {
      ftd = predict(fit, newdata=data)
      cm.up = regCM(data[,res.ind],ftd,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
    }
    mmce = list(pkg="rpart",isTest=isTest,isSE=isSE
                ,cp=round(param,4),mmce=cm.up[nrow(cm.up),ncol(cm.up)])
    list(ftd=ftd,cm=cm.up,mmce=mmce)
  }
  # $train.lst (3)
  train.perf.lst = perf(mod,trainData,res.name,cp,FALSE,FALSE)
  # $train.se (4)
  train.perf.se = perf(mod,trainData,res.name,cp,FALSE,TRUE)
  if(!is.null(testData)) {
    # $test.lst (5)
    test.perf.lst = perf(mod,testData,res.name,cp,TRUE,FALSE)
    # $test.se (6)
    test.perf.se = perf(mod,testData,res.name,cp,TRUE,TRUE)
  } else {
    test.perf.lst = ls()
    test.perf.se = ls()
  }    
  # update results
  result = list(mod=mod,cp=cp
                ,train.lst=train.perf.lst,train.se=train.perf.se
                ,test.lst=test.perf.lst,test.se=test.perf.se)
  # add class name
  class(result) = "rpartExt"
  return(result)
}
{% endhighlight %}

Finally the S3 default function of `plot()` is extended and the plot function (`plot.rpartExt()`) shows the combination of *xerror* and *cp*. Note that *params* is exported into the global environment (`.GlobalEnv$params = params`). As far as I understand, after the second `geom_abline()`, the ggplot object (*plot.obj*) seems to be registered in the global environment. Therefore the two lines of adding points (`geom_point()`) can't locate *params*, resulting in an error. Therefore the necessary variable is exported so that the plot object can get the values (eg *params[1,2]*) - the function would have to be updated to add lines rather than points in the future.  


{% highlight r %}
# extend plot method
plot.rpartExt = function(x, ...) {
  require(ggplot2)
  obj = x
  df = as.data.frame(obj$mod$cptable)
  params = obj$cp
  # params should be exported into global environment
  # otherwise geom_point() causes an error without identifying x and y
  .GlobalEnv$params = params
  ubound = ifelse(params[2,1]+params[3,1]>max(df$xerror),max(df$xerror),params[2,1]+params[3,1])
  lbound = ifelse(params[2,1]-params[3,1]<min(df$xerror),min(df$xerror),params[2,1]-params[3,1])
  plot.obj = ggplot(data=df[1:nrow(df),], aes(x=CP,y=xerror)) + 
    scale_x_continuous() + scale_y_continuous() + 
    geom_line() + geom_point() +   
    geom_abline(intercept=ubound,slope=0, color="purple") + 
    geom_abline(intercept=lbound,slope=0, color="purple") + 
    geom_point(aes(x=params[1,2],y=params[2,2]),color="red",size=3) + 
    geom_point(aes(x=params[1,1],y=params[2,1]),color="blue",size=3)
  plot.obj
}
{% endhighlight %}

A quick illustration is shown below.


{% highlight r %}
## data
require(ISLR)
data(Carseats)
require(dplyr)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data.cl = subset(Carseats, select=c(-Sales))
data.rg = subset(Carseats, select=c(-High))

# split - cl: classification, rg: regression
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.cl = data.cl[trainIndex,]
testData.cl = data.cl[-trainIndex,]
trainData.rg = data.rg[trainIndex,]
testData.rg = data.rg[-trainIndex,]

## import constructors of S3 objects
source("src/cart.R")
{% endhighlight %}

A classificaton task can be created as following.


{% highlight r %}
set.seed(12357)
rpt.cl = cartRPART(trainData.cl,testData.cl,formula="High ~ .")
{% endhighlight %}

The confusion matrix on the test data is shown below.


{% highlight r %}
rpt.cl$test.lst$cm
{% endhighlight %}



{% highlight text %}
##              Ptd: High Ptd: No Model Error
## actual: High     21.00    11.0        0.34
## actual: No        4.00    43.0        0.09
## Use Error         0.16     0.2        0.19
{% endhighlight %}

The object can be plotted as following.


{% highlight r %}
plot(rpt.cl)
{% endhighlight %}

![center](/figs/2015-02-21-Quick-Trial-of-Turning-Analysis-into-S3-Object/plot-1.png) 

In the next article, further discussion will be made with the other two classes.
