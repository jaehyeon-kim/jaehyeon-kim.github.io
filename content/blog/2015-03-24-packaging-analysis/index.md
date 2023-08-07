---
title: Packaging Analysis
date: 2015-03-24
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
  - R
tags: 
  - R
authors:
  - JaehyeonKim
images: []
description: We discuss how to turn analysis into an R package.
---

When I imagine a workflow, it is performing the same or similar tasks regularly (daily or weekly) in an automated way. Although those tasks can be executed in a script or a *source()*d script, it may not be easy to maintain separate scripts while the size of tasks gets bigger or if they have to be executed in different machines. In academia, reproducible research shares similar ideas but the level of reproducibility introduced in [Gandrud, 2013](http://www.crcpress.com/product/isbn/9781466572843) may not suffice in a business environment as the focus is documenting in a reproducible way. A R package, however, can be an effective tool and it can be considered like a portable class library in C# or Java. Like a class library, it can include a set of necessary tasks (usually using functions) and, being portable, its dependency can be managed well - for example, it is possible to set so that dependent packages can also be installed if some of them are not installed already. Moreover the benefit of creating a R package would be significant if it has to be deployed in a production server as it'd be a lot easier to convince system admin with the built-in unit tests, object documents and package vignettes. In this article an example of creating a R package is illustrated.

## Introduction to the [treebgg](https://github.com/jaehyeon-kim/treebgg) package

This package extends the CART model by the rpart package (`cartmore()`) and implements bagging both sequentially (`cartbgg()`) and in parallel (`cartbggs()`). For sequantial bagging implementation, it returns the number of trees, variable importance, out-of-bag/test response and out-of-bag/test prediction of each tree in a list. The outputs of the sequential implementation are *combined* and it is performed so as to obtain variable importance measures and errors of bagged trees.

## Steps to create the treebgg package

The **treebgg** package is created, following [Wickham, 2015](http://r-pkgs.had.co.nz/) - an overview of package development can also be checked in the [Jeff Leek's repo](https://github.com/jtleek/rpackages). With RStudio and several packages in Step 1, it is quite straightforward as long as something to be included is clear. Specific steps are listed below.

1. Install necessary packages in [Getting Started](http://r-pkgs.had.co.nz/intro.html) section of [Wickham, 2015](http://r-pkgs.had.co.nz/).
    - `install.packages(c("devtools", "roxygen2", "testthat", "knitr"))`
2. Create a R package in a new folder via R Studio ([link](http://r-pkgs.had.co.nz/package.html)).
    - create *README.md* - just a new text file where the file extension is *md*.
3. Create a GitHub repo with the same name (*treebgg*)
    - *empty repo without initialization with README.md*
4. Push into the remote GitHub repository
    - **HTTPS**
        + `cd treebgg`
        + `git status`
        + `git add *`
        + `git commit -a -m "initial commit"`
        + `git remote add origin https://github.com/jaehyeon-kim/treebgg.git`
        + `git push -u origin master`
    - **SSH**
        + `git remote add origin git@github.com:jaehyeon-kim/treebgg.git`
        + *Otherwise the following error occurs*
        + *error: The requested URL returned error: 403 Forbidden while accessing https://github.com/jaehyeon-kim/treebgg.git/info/refs*
    - Or **Modify directly**
        + Open *.git/confit* and update url
        + **HTTP**: url=https://github.com/jaehyeon-kim/treebgg.git
        + **SSH**: url=git@github.com:jaehyeon-kim/treebgg.git
5. Update R code, package meta data and object documents.
    - [R code](http://r-pkgs.had.co.nz/r.html) - */R*
    - [Package meta data](http://r-pkgs.had.co.nz/description.html) - *DESCRIPTION*
        + mostly auto-generated by **roxygen2**
    - [Object documents](http://r-pkgs.had.co.nz/man.html) - */man*
        + [if necessary] Build and reload package: Build --> Build and Reload (*Ctrl + Shift + B*) or Clean and Rebuild
        + Create documents: `devtools::document()`
6. Complete unit tests using the **testthat** package.
    - [Testing](http://r-pkgs.had.co.nz/tests.html)
        + `devtools::use_testthat()`
        + */tests* is created and testing files of 5 constructors/functions are created in */tests/testthat*
        + Build --> Test Package or *Ctrl + Shift + T*
7. Create a vignette document using the **knitr** package.
    - [Vignettes](http://r-pkgs.had.co.nz/vignettes.html)
        + `devtools::use_vignette("intro_treebgg")`
        + */vignettes* created with a RMD file named above and *DESCRIPTION* updated to suggest the **knitr** package, *VignetteBuilder* set to **knitr**

## Installation

The **devtools** package should be installed as the package exists in a GitHub repository only. For Windows users, [Rtools](http://cran.r-project.org/bin/windows/Rtools/) has to be installed to build from source.

The package can be installed and loaded as following. Note that the following packages will be installed if they are not installed already: **rpart**, **foreach**, **doParallel**, **iterators**.


```r
library(devtools)
install_github("jaehyeon-kim/treebgg")
{% endhighlight %}


{% highlight r %}
library(treebgg)
```

## CART extension

To extend the CART model, a S3 object is instantiated (*cartmore*) by `cartmore()`, which fits the model at the least *xerror* or by the *1-SE* rule - both classification and regression trees can be extended. The signature of this constructor is show below. 

- `cartmore(formula, trainData, testData = NULL)`


```r
data(car90, package="rpart")
# data for regression tree
cars <- car90[, -match(c("Rim", "Tires", "Model2"), names(car90))]
cars$Price <- cars$Price/1000
# data for classification tree
div = quantile(cars$Price, 0.5, na.rm = TRUE)
cars.cl <- transform(cars, Price = as.factor(ifelse(Price > div, "High","No")))
# regression (rg) and classification (cl) tree
fit.rg <- cartmore("Price ~ .", cars, cars) # cars in testData is for illustration only
fit.cl <- cartmore("Price ~ .", cars.cl)
```

The object has 4 groups of elements. *train/test* means train/test data sets while *lst/se* means the cp values at the least *xerror* and by the *1-SE* rule. The train elements keeps the model (*rpart* object), complexity-related values (*cp*, *xerror* and *xstd*), fitted values (*fitted*), variable importance measure (*var.imp*) and error (mean misclassification error or root mean squared error) (*error*). The test elements only hold the fitted values and error if a data set is specified and *NULL* if not.


```r
class(fit.rg)
```



```
## [1] "cartmore"
```



```r
names(fit.rg)
```



```
## [1] "train.lst" "test.lst"  "train.se"  "test.se"
```


```r
names(fit.rg$train.lst)
```



```
## [1] "mod"     "cp"      "xerror"  "xstd"    "fitted"  "var.imp" "error"
```



```r
names(fit.rg$test.lst)
```



```
## [1] "fitted" "error"
```



```r
names(fit.cl$test.lst)
```



```
## NULL
```



```r
c(fit.cl$train.lst$error, fit.cl$train.se$error)
```



```
## [1] 0.1047619 0.1714286
```

## Sequential bagging implementation

For sequantial bagging implementation, `cartbgg()` instantiates the *cartbgg* object and it returns a list of the number of trees (*ntree*), variable importance (*var.imp*), out-of-bag/test response (*oob.res* and *test.res*) and out-of-bag/test prediction of each tree (*oob.pred* and *test.pred*). The signature of `cartbgg()` is shown below. 

- `cartbgg(formula, trainData, testData = NULL, ntree = 1L)`

As can be seen in the signature, it has one extra argument that specifies the number of trees to generate - note that the type is restricted to be *integer* so that *L* should be followed by a numeric value.


```r
data(car90, package="rpart")
# data for regression tree
cars <- car90[, -match(c("Rim", "Tires", "Model2"), names(car90))]
cars$Price <- cars$Price/1000
# data for classification tree
div = quantile(cars$Price, 0.5, na.rm = TRUE)
cars.cl <- transform(cars, Price = as.factor(ifelse(Price > div, "High","No")))
# regression (rg) and classification (cl) bagged trees
bgg.rg <- cartbgg("Price ~ .", cars, cars, ntree = 10L) # note integer, not numeric
bgg.cl <- cartbgg("Price ~ .", cars.cl, ntree = 10L) # note integer, not numeric
```

The class and elements can be checked by `class()` and `names()`. This object keeps the variable importance, response and prediction values in a data frame for ease of merging. In fact, values from each tree are `merge()`d. If *testData* is not specified, *NULL* is returned.


```r
class(bgg.rg)
```



```
## [1] "cartbgg"
```



```r
names(bgg.rg)
```



```
## [1] "ntree"     "var.imp"   "oob.res"   "oob.pred"  "test.res"  "test.pred"
```



```r
lst <- list(bgg.rg$var.imp, bgg.rg$oob.res, bgg.rg$oob.pred)
sapply(lst, class)
```



```
## [1] "data.frame" "data.frame" "data.frame"
```



```r
sapply(list(bgg.cl$test.res, bgg.cl$test.pred), c)
```



```
## [[1]]
## NULL
## 
## [[2]]
## NULL
```

## Parallel bagging implementation

Basically `cartbggs()` combines the *cartbgg* objects in parallel, instantiating the *cartbggs* object. The parallel processing is performed by utilizing the following packages: **parallel**, **foreach**, **doParallel** and **iterators**. The signature of `cartbggs()` is shown below.

- `cartbggs(formula, trainData, testData = NULL, eachTree = 1L, ncl = NULL, seed = NULL)`

It has three extra arguments - *eachTree*, *ncl* and *seed*. Rather than specifying the total number of trees to generate (*ntree*) in `cartbgg()`, it requires the number of trees to generate in each cluster (*eachTree*). The number of clusters (*ncl*) can be either specified or left out - if the number is left out, it is detected. The last arguments is for specifying a random seed. Note that the type of these argumens is restricted to be *integer* so that *L* should be followed by a numeric value.


```r
data(car90, package="rpart")
# data for regression tree
cars <- car90[, -match(c("Rim", "Tires", "Model2"), names(car90))]
cars$Price <- cars$Price/1000
# data for classification tree
div = quantile(cars$Price, 0.5, na.rm = TRUE)
cars.cl <- transform(cars, Price = as.factor(ifelse(Price > div, "High","No")))
# regression (rg) and classification (cl) bagged trees in parallel
bggs.rg <- cartbggs("Price ~ .", cars, cars, eachTree = 10L, seed = 1237L) # note integer, not numeric
bggs.cl <- cartbggs("Price ~ .", cars.cl, eachTree = 10L, seed = 1237L) # note integer, not numeric
```

The *ntree* value is the total number of trees and it is *eachTree* multiplied by *ncl*. The bagged trees' variable importance measure is converted as percentage so that its sum is 100. Only the out-of-bag/test errors of bagged trees are returned and the test error is *NULL* if a data set is not entered in *testData*.


```r
class(bggs.rg)
```



```
## [1] "cartbggs"
```



```r
names(bggs.rg)
```



```
## [1] "ntree"    "var.imp"  "oob.err"  "test.err"
```



```r
bggs.rg
```



```
## $ntree
## [1] 60
## 
## $var.imp
##      Country         Disp        Disp2      Eng.Rev     Front.Hd 
##  3.550772559 12.950732392 11.824200206  0.079064381  1.567940833 
## Frt.Leg.Room     Frt.Shld   Gear.Ratio        Gear2       Height 
##  2.064551549  1.321197687  0.070177629  1.894963262  1.118311638 
##           HP      HP.revs       Length      Luggage      Mileage 
## 16.135667088  1.633101113  6.023700543  1.148433807  0.004728218 
##      Rear.Hd Rear.Seating     RearShld  Reliability     Sratio.m 
##  0.726666309  1.599366429  1.745734662  0.047711318  0.001935001 
##     Sratio.p     Steering         Tank       Trans1       Trans2 
##  0.279495784  0.919217450 11.254315624  0.442100562  0.133071794 
##      Turning         Type       Weight   Wheel.base        Width 
##  1.387680928  3.965640488  9.667418558  4.661085995  1.781016195 
## 
## $oob.err
## [1] 1.112348
## 
## $test.err
## [1] 0.1138147
## 
## attr(,"class")
## [1] "cartbggs"
```

Roughly there would be two ways of performing a task. One is easy to start but hard to maintain and the other is hard to start but easy to maintain. Developing a R package should require more time to start but its benefit will be ongoing with little or no maintenance. Depending on complexity of a task, it'd be considerable to turning analysis into a package.