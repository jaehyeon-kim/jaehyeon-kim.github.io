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

## classification
set.seed(12357)
rpt.cl = cartRPART(trainData.cl,testData.cl,formula="High ~ .")
crt.cl = cartCARET(trainData.cl,testData.cl,formula="High ~ .")
mlr.cl = cartMLR(trainData.cl,testData.cl,formula="High ~ .")

# comparison
perf.cl = list(rpt.cl$train.lst$mmce,rpt.cl$train.se$mmce
               ,rpt.cl$test.lst$mmce,rpt.cl$test.se$mmce
               ,crt.cl$train.lst$mmce,crt.cl$test.lst$mmce
               ,mlr.cl$train.lst$mmce,mlr.cl$test.lst$mmce)

mmce = function(mmce.vec) {
  out = list(unlist(mmce.vec[[1]]))
  for(i in 2:length(mmce.vec)) {
    out[[length(out)+1]] = unlist(mmce.vec[[i]])
  }
  t(sapply(out,unlist))
}

mmce(perf.cl)

## regression
set.seed(12357)
rpt.rg = cartRPART(trainData.rg,testData.rg,formula="Sales ~ .")
crt.rg = cartCARET(trainData.rg,testData.rg,formula="Sales ~ .")
mlr.rg = cartMLR(trainData.rg,testData.rg,formula="Sales ~ .")

# comparison
perf.rg = list(rpt.rg$train.lst$mmce,rpt.rg$train.se$mmce
               ,rpt.rg$test.lst$mmce,rpt.rg$test.se$mmce
               ,crt.rg$train.lst$mmce,crt.rg$test.lst$mmce
               ,mlr.rg$train.lst$mmce,mlr.rg$test.lst$mmce)

mmce(perf.rg)

# caret doesn't include 0 in tuneLength
head(crt.rg$mod$result,2)

# rpart plots
plot(rpt.cl)