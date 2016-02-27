## error
# oob error
# test error
## individual error
# non-parametric bootstrap mean approximately equals to non-informative posterior distribution
# CI-like interval may be guessed from the distribution of the errors of individual trees
## cumulative error
# relieving concern of overfitting by averaging or majority voting
# more reliable prediction
## variable importance
# if single tree's variable importance is far different from that of bagged trees
# can check if there are dominant predictors - main benefit of bagging is through reducing variance

## data
require(ISLR)
data(Carseats)
require(dplyr)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data.cl = subset(Carseats, select=c(-Sales))
data.rg = subset(Carseats, select=c(-High))

## import constructors
source("src/cart.R")

# split - cl: classification, rg: regression
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.cl = data.cl[trainIndex,]
testData.cl = data.cl[-trainIndex,]

## instantiate rpartDT
set.seed(12357)
cl = cartDT(trainData.cl, testData.cl, "High ~ .", ntree=10)

# class and names
class(cl)
# rpt - single tree, lst - least xerror, se - 1-SE rule, oob - out-of-bag sample, tst - test data, ind (cum) - individual (cumulative) prediction or error
names(cl)

## cp values
# cart
cl$rpt$cp[1,][[1]]
# bagging
summary(t(cl$boot.cp)[,2])

## fitted values
# individual - each oob sample
cl$ind.oob.lst[3:6,1:8]

# cumulative - majority vote or average
# 1. not used - NA, 2. used once - get name, 3. tie - NA, 4. name at max number of labels
cl$cum.oob.lst[3:6,1:8]

# function to update fitted values - majority vote or average
# response kept in 1st column, should be excluded
retCum = function(fit) {
  if(ncol(fit) < 2) {
    message("no fitted values")
    cum.fit = fit
  } else {
    cum.fit = as.data.frame(apply(fit,2,function(x) { rep(0,times=(nrow(fit))) }))
    cum.fit[,1:2] = fit[,1:2]
    rownames(cum.fit) = rownames(fit)
    for(i in 3:ncol(fit)) {
      if(class(fit[,1])=="factor") {
        retVote = function(x) {
          tbls = apply(x,1,as.data.frame)
          tbls = lapply(tbls,table)
          ret = function(x) {
            if(length(x)==0) NA 
            else if(length(x)==1) names(x) 
            else if(max(x)==min(x)) NA 
            else names(x[x==max(x)])
          }
          maxVal = sapply(tbls,ret)
          maxVal
        }
        cum.fit[,i] = retVote(fit[,2:i]) # retVote already vectorized
      } else {
        cum.fit[,i] = apply(fit[,2:i],1,mean,na.rm=TRUE)
      }
    }  
  }
  cum.fit
}

# function to updated errors - mmce or rmse
# response kept in 1st column, should be excluded
retErr = function(fit) {
  err = data.frame(t(rep(0,times=ncol(fit))))
  colnames(err)=colnames(fit)
  for(i in 2:ncol(fit)) {
    cmpt = complete.cases(fit[,1],fit[,i])
    if(class(fit[,1])=="factor") {
      tbl=table(fit[cmpt,1],fit[cmpt,i])
      err[i] = 1 - sum(diag(tbl))/sum(tbl)
    } else {
      err[i] = sqrt(sum(fit[cmpt,1]-fit[cmpt,i])^2/length(fit[cmpt,1]))
    }    
  }
  err[2:length(err)]
}

cl$ind.oob.lst.err[1:7]
cl$cum.oob.lst.err[1:7]

## variable importance
# cart
data.frame(variable=names(cl$rpt$mod$variable.importance)
           ,value=cl$rpt$mod$variable.importance/sum(cl$rpt$mod$variable.importance)
           ,row.names=NULL)
# bagging - cumulative
ntree = 10
data.frame(variable=rownames(cl$cum.varImp.lst)
           ,value=cl$cum.varImp.lst[,ntree])
