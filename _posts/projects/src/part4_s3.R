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

## import constructors
source("src/cart.R")

## classification
set.seed(12357)
rpt.cl = cartRPART(trainData.cl,testData.cl,formula="High ~ .")
crt.cl = cartCARET(trainData.cl,testData.cl,formula="High ~ .",fitInd=TRUE)
mlr.cl = cartMLR(trainData.cl,testData.cl,formula="High ~ .",fitInd=TRUE)

## classes and attributes
data.frame(rpart=c(class(rpt.cl),""),caret=class(crt.cl),mlr=class(crt.cl))

attributes(rpt.cl)$names
attributes(crt.cl)$names
attributes(mlr.cl)$names
attributes(crt.cl$rpt)$names


# comparison
perf.cl = list(rpt.cl$train.lst$error,rpt.cl$train.se$error
               ,rpt.cl$test.lst$error,rpt.cl$test.se$error
               ,crt.cl$train.lst$error,crt.cl$test.lst$error
               ,mlr.cl$train.lst$error,mlr.cl$test.lst$error)

err = function(perf) {
  out = list(unlist(perf[[1]]))
  for(i in 2:length(perf)) {
    out[[length(out)+1]] = unlist(perf[[i]])
  }
  t(sapply(out,unlist))
}

err(perf.cl)

## regression
set.seed(12357)
rpt.rg = cartRPART(trainData.rg,testData.rg,formula="Sales ~ .")
crt.rg = cartCARET(trainData.rg,testData.rg,formula="Sales ~ .")
mlr.rg = cartMLR(trainData.rg,testData.rg,formula="Sales ~ .")

# comparison
perf.rg = list(rpt.rg$train.lst$error,rpt.rg$train.se$error
               ,rpt.rg$test.lst$error,rpt.rg$test.se$error
               ,crt.rg$train.lst$error,crt.rg$test.lst$error
               ,mlr.rg$train.lst$error,mlr.rg$test.lst$error)

err(perf.rg)