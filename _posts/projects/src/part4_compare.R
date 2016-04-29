library(reshape2)
library(dplyr)
library(ggplot2)
library(rpart)
library(caret)
library(mlr)

## data
require(ISLR)
data(Carseats)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data = subset(Carseats, select=c(-Sales))

## split data
# caret
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.caret = data[trainIndex,]
testData.caret = data[-trainIndex,]

# mlr
set.seed(1237)
resampleIns = makeResampleInstance(desc=makeResampleDesc(method="Holdout", stratify=TRUE, split=0.8)
                                   ,task=makeClassifTask(data=data,target="High"))
trainData.mlr = data[resampleIns$train.inds[[1]],]
testData.mlr = data[-resampleIns$train.inds[[1]],]

# response summaries
train.res.caret = with(trainData.caret,rbind(table(High),table(High)/length(High)))
train.res.caret
train.res.mlr = with(trainData.mlr,rbind(table(High),table(High)/length(High)))
train.res.mlr

test.res.caret = with(testData.caret,rbind(table(High),table(High)/length(High)))
test.res.caret
test.res.mlr = with(testData.mlr,rbind(table(High),table(High)/length(High)))
test.res.mlr

# data from caret is taken in line with previous articles
trainData = trainData.caret
testData = testData.caret

#### classification with equal cost
source("src/mlUtils.R")
### rpart
## train on training data
set.seed(12357)
mod.rpt.eq = rpart(High ~ ., data=trainData, control=rpart.control(cp=0))
mod.rpt.eq.par = bestParam(mod.rpt.eq$cptable,"CP","xerror","xstd")
mod.rpt.eq.par

# plot xerror vs cp
df = as.data.frame(mod.rpt.eq$cptable)
best = mod.rpt.eq.par
ubound = ifelse(best[2,1]+best[3,1]>max(df$xerror),max(df$xerror),best[2,1]+best[3,1])
lbound = ifelse(best[2,1]-best[3,1]<min(df$xerror),min(df$xerror),best[2,1]-best[3,1])

ggplot(data=df[1:nrow(df),], aes(x=CP,y=xerror)) + 
  geom_line() + geom_point() +   
  geom_abline(intercept=ubound,slope=0, color="purple") + 
  geom_abline(intercept=lbound,slope=0, color="purple") + 
  geom_point(aes(x=best[1,2],y=best[2,2]),color="red",size=3) + 
  geom_point(aes(x=best[1,1],y=best[2,1]),color="blue",size=3)

## performance on train data
mod.rpt.eq.lst.cp = mod.rpt.eq.par[1,1]
mod.rpt.eq.bst.cp = mod.rpt.eq.par[1,2]
# prune
mod.rpt.eq.lst = prune(mod.rpt.eq, cp=mod.rpt.eq.lst.cp)
mod.rpt.eq.bst = prune(mod.rpt.eq, cp=mod.rpt.eq.bst.cp)

# fit to train data
mod.rpt.eq.lst.ftd = predict(mod.rpt.eq.lst, type="class")
mod.rpt.eq.bst.ftd = predict(mod.rpt.eq.bst, type="class")

# confusion matrix
mod.rpt.eq.lst.ftd.cm = table(actual=trainData$High,fitted=mod.rpt.eq.lst.ftd)
mod.rpt.eq.lst.ftd.cm = updateCM(mod.rpt.eq.lst.ftd.cm, type="Fitted")

mod.rpt.eq.bst.ftd.cm = table(actual=trainData$High,fitted=mod.rpt.eq.bst.ftd)
mod.rpt.eq.bst.ftd.cm = updateCM(mod.rpt.eq.bst.ftd.cm, type="Fitted")

# misclassification error
mod.rpt.eq.lst.ftd.mmce = list(pkg="rpart",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.lst.cp,4)
                               ,mmce=mod.rpt.eq.lst.ftd.cm[3,3])
mmce = list(unlist(mod.rpt.eq.lst.ftd.mmce))

mod.rpt.eq.bst.ftd.mmce = list(pkg="rpart",isTest=FALSE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.bst.cp,4)
                               ,mmce=mod.rpt.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.bst.ftd.mmce)

## performance of test data
# fit to test data
mod.rpt.eq.lst.ptd = predict(mod.rpt.eq.lst, newdata=testData, type="class")
mod.rpt.eq.bst.ptd = predict(mod.rpt.eq.bst, newdata=testData, type="class")

# confusion matrix
mod.rpt.eq.lst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.lst.ptd)
mod.rpt.eq.lst.ptd.cm = updateCM(mod.rpt.eq.lst.ptd.cm)

mod.rpt.eq.bst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.bst.ptd)
mod.rpt.eq.bst.ptd.cm = updateCM(mod.rpt.eq.bst.ptd.cm)

# misclassification error
mod.rpt.eq.lst.ptd.mmce = list(pkg="rpart",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.lst.cp,4)
                               ,mmce=mod.rpt.eq.lst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.lst.ptd.mmce)

mod.rpt.eq.bst.ptd.mmce = list(pkg="rpart",isTest=TRUE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.rpt.eq.bst.cp,4)
                               ,mmce=mod.rpt.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.rpt.eq.bst.ptd.mmce)

plyr::ldply(mmce)

### caret
## train on training data
trControl = trainControl(method="repeatedcv", number=10, repeats=5)
set.seed(12357)
mod.crt.eq = caret::train(High ~ .
                          ,data=trainData
                          ,method="rpart"
                          ,tuneLength=20
                          ,trControl=trControl)

# lowest CP
# caret: maximum accuracy, rpart: 1-SE
# according to rpart, caret's best is lowest
df = mod.crt.eq$results
mod.crt.eq.lst.cp = mod.crt.eq$bestTune$cp
mod.crt.eq.lst.acc = subset(df,cp==mod.crt.eq.lst.cp)[[2]]

# best cp by 1-SE rule - values are adjusted from graph 
mod.crt.eq.bst.cp = df[17,1]
mod.crt.eq.bst.acc = df[17,2]

# CP by 1-SE rule
maxAcc = subset(df,Accuracy==max(Accuracy))[[2]]
stdAtMaxAcc = subset(df,subset=Accuracy==max(Accuracy))[[4]]
# max cp within 1 SE
maxCP = subset(df,Accuracy>=maxAcc-stdAtMaxAcc)[nrow(subset(df,Accuracy>=maxAcc-stdAtMaxAcc)),][[1]]
accAtMaxCP = subset(df,cp==maxCP)[[2]]

# plot Accuracy vs cp
ubound = ifelse(maxAcc+stdAtMaxAcc>max(df$Accuracy),max(df$Accuracy),maxAcc+stdAtMaxAcc)
lbound = ifelse(maxAcc-stdAtMaxAcc<min(df$Accuracy),min(df$Accuracy),maxAcc-stdAtMaxAcc)

ggplot(data=df[1:nrow(df),], aes(x=cp,y=Accuracy)) + 
  geom_line() + geom_point() +   
  geom_abline(intercept=ubound,slope=0, color="purple") + 
  geom_abline(intercept=lbound,slope=0, color="purple") + 
  geom_point(aes(x=mod.crt.eq.bst.cp,y=mod.crt.eq.lst.acc),color="red",size=3) + 
  geom_point(aes(x=mod.crt.eq.lst.cp,y=mod.crt.eq.lst.acc),color="blue",size=3)

## performance on train data
# refit from rpart for best cp - cp by 1-SE not fitted by caret
# note no cross-validation necessary - xval=0 (default: xval=10)
set.seed(12357)
mod.crt.eq.bst = rpart(High ~ ., data=trainData, control=rpart.control(xval=0,cp=mod.crt.eq.bst.cp))

# fit to train data - lowest from caret, best (1-SE) from rpart
mod.crt.eq.lst.ftd = predict(mod.crt.eq,newdata=trainData)
mod.crt.eq.bst.ftd = predict(mod.crt.eq.bst, type="class")

# confusion matrix
mod.crt.eq.lst.ftd.cm = table(actual=trainData$High,fitted=mod.crt.eq.lst.ftd)
mod.crt.eq.lst.ftd.cm = updateCM(mod.crt.eq.lst.ftd.cm, type="Fitted")

mod.crt.eq.bst.ftd.cm = table(actual=trainData$High,fitted=mod.crt.eq.bst.ftd)
mod.crt.eq.bst.ftd.cm = updateCM(mod.crt.eq.bst.ftd.cm, type="Fitted")

# misclassification error
mod.crt.eq.lst.ftd.mmce = list(pkg="caret",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.crt.eq.lst.cp,4)
                               ,mmce=mod.crt.eq.lst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.lst.ftd.mmce)

mod.crt.eq.bst.ftd.mmce = list(pkg="caret",isTest=FALSE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.crt.eq.bst.cp,4)
                               ,mmce=mod.crt.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.bst.ftd.mmce)

## performance of test data
# fit to test data - lowest from caret, best (1-SE) from rpart
mod.crt.eq.lst.ptd = predict(mod.crt.eq,newdata=testData)
mod.crt.eq.bst.ptd = predict(mod.crt.eq.bst, newdata=testData)

# confusion matrix
mod.crt.eq.lst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.lst.ptd)
mod.crt.eq.lst.ptd.cm = updateCM(mod.crt.eq.lst.ptd.cm)

mod.crt.eq.bst.ptd.cm = table(actual=testData$High, fitted=mod.rpt.eq.bst.ptd)
mod.crt.eq.bst.ptd.cm = updateCM(mod.crt.eq.bst.ptd.cm)

# misclassification error
mod.crt.eq.lst.ptd.mmce = list(pkg="caret",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(mod.crt.eq.lst.cp,4)
                               ,mmce=mod.crt.eq.lst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.lst.ptd.mmce)

mod.crt.eq.bst.ptd.mmce = list(pkg="caret",isTest=TRUE,isBest=TRUE,isEq=TRUE
                               ,cp=round(mod.crt.eq.bst.cp,4)
                               ,mmce=mod.crt.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.crt.eq.bst.ptd.mmce)

plyr::ldply(mmce)

### mlr
## task and learner
tsk.mlr.eq = makeClassifTask(data=trainData,target="High")
lrn.mlr.eq = makeLearner("classif.rpart",par.vals=list(cp=0))

## tune parameter
cpGrid = function(index) {
  start=0
  end=0.3
  len=20
  inc = (end-start)/len
  grid = c(start)
  while(start < end) {
    start = start + inc
    grid = c(grid,start)
  } 
  grid[index]
}
# create tune control grid
ps.mlr.eq = makeParamSet(
  makeNumericParam("cp",lower=1,upper=20,trafo=cpGrid)
)
ctrl.mlr.eq = makeTuneControlGrid(resolution=c(cp=(20)))

# tune cp
rdesc.mlr.eq = makeResampleDesc("RepCV",reps=5,folds=10,stratify=TRUE)
set.seed(12357)
tune.mlr.eq = tuneParams(learner=lrn.mlr.eq
                         ,task=tsk.mlr.eq
                         ,resampling=rdesc.mlr.eq
                         ,par.set=ps.mlr.eq
                         ,control=ctrl.mlr.eq)

# optimization path
# no standard error like values, only best cp is considered
path.mlr.eq = as.data.frame(tune.mlr.eq$opt.path)
path.mlr.eq = transform(path.mlr.eq,cp=cpGrid(cp))

# obtain fitted and predicted responses
# update cp
lrn.mlr.eq.bst = setHyperPars(lrn.mlr.eq, par.vals=tune.mlr.eq$x)

# train model
trn.mlr.eq.bst = train(lrn.mlr.eq.bst, tsk.mlr.eq)

# fitted responses
mod.mlr.eq.bst.ftd = predict(trn.mlr.eq.bst, tsk.mlr.eq)$data
mod.mlr.eq.bst.ptd = predict(trn.mlr.eq.bst, newdata=testData)$data

# confusion matrix
mod.mlr.eq.bst.ftd.cm = table(actual=mod.mlr.eq.bst.ftd$truth, fitted=mod.mlr.eq.bst.ftd$response)
mod.mlr.eq.bst.ftd.cm = updateCM(mod.mlr.eq.bst.ftd.cm)

mod.mlr.eq.bst.ptd.cm = table(actual=mod.mlr.eq.bst.ptd$truth, fitted=mod.mlr.eq.bst.ptd$response)
mod.mlr.eq.bst.ptd.cm = updateCM(mod.mlr.eq.bst.ptd.cm)

# misclassification error
mod.mlr.eq.bst.ftd.mmce = list(pkg="mlr",isTest=FALSE,isBest=FALSE,isEq=TRUE
                               ,cp=round(tune.mlr.eq$x[[1]],4)
                               ,mmce=mod.mlr.eq.bst.ftd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.mlr.eq.bst.ftd.mmce)

mod.mlr.eq.bst.ptd.mmce = list(pkg="mlr",isTest=TRUE,isBest=FALSE,isEq=TRUE
                               ,cp=round(tune.mlr.eq$x[[1]],4)
                               ,mmce=mod.mlr.eq.bst.ptd.cm[3,3])
mmce[[length(mmce)+1]] = unlist(mod.mlr.eq.bst.ptd.mmce)

plyr::ldply(mmce)

# mmce vs cp
ftd.mmce = c()
ptd.mmce = c()
cps = mod.crt.eq$results[[1]]
for(i in 1:length(cps)) {
  if(i %% 2 == 0) {
    set.seed(12357)
    mod = rpart(High ~ ., data=trainData, control=rpart.control(cp=cps[i]))
    ftd = predict(mod,type="class")
    ptd = predict(mod,newdata=testData,type="class")
    ftd.mmce = c(ftd.mmce,updateCM(table(trainData$High,ftd))[3,3])
    ptd.mmce = c(ptd.mmce,updateCM(table(testData$High,ptd))[3,3])    
  }
}
mmce.crt = data.frame(cp=as.factor(round(cps[seq(2,length(cps),2)],3))
                      ,fitted=ftd.mmce
                      ,predicted=ptd.mmce)
mmce.crt = melt(mmce.crt,id=c("cp"),variable.name="data",value.name="mmce")
ggplot(data=mmce.crt,aes(x=cp,y=mmce,fill=data)) + 
  geom_bar(stat="identity", position=position_dodge())