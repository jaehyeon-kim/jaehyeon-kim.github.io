library(dplyr)
library(rpart)
library(rpart.plot)
library(caret)

## data
require(ISLR)
data(Carseats)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
# structure of predictors
str(subset(Carseats,select=c(-High,-Sales)))
# classification response summary
res.summary = with(Carseats,rbind(table(High),table(High)/length(High)))

# split data
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
trainData = subset(Carseats, select=c(-Sales))[trainIndex,]
testData = subset(Carseats, select=c(-Sales))[-trainIndex,]

# response summary
train.res.summary = with(trainData,rbind(table(High),table(High)/length(High)))
train.res.summary

test.res.summary = with(testData,rbind(table(High),table(High)/length(High)))
test.res.summary

## fit model with equal cost
# set up train control
trControl = trainControl(method="repeatedcv",number=10,repeats=5)

# generate tune grid
cpGrid = function(start,end,len) {
  inc = if(end > start) (end-start)/len else 0
  # update grid
  if(inc > 0) {    
    grid = c(start)
    while(start < end) {
      start = start + inc
      grid = c(grid,start)
    }
  } else {
    message("start > end, default cp value is taken")
    grid = c(0.1)
  }    
  grid
}

grid = expand.grid(cp=cpGrid(0,0.3,20))

# train model with equal cost
set.seed(12357)
mod.eq.cost = train(High ~ .
                    ,data=trainData
                    ,method="rpart"
                    ,tuneGrid=grid
                    ,trControl=trControl)

# select results at best tuned cp
subset(mod.eq.cost$results,subset=cp==mod.eq.cost$bestTune$cp)

# refit the model to the entire training data
cp = mod.eq.cost$bestTune$cp
mod.eq.cost = rpart(High ~ ., data=trainData, control=rpart.control(cp=cp))

# generate confusion matrix on training data
source("mlUtils.R")
fit.eq.cost = predict(mod.eq.cost, type="class")
fit.cm.eq.cost = table(data.frame(actual=trainData$High,response=fit.eq.cost))
fit.cm.eq.cost = getUpdatedCM(fit.cm.eq.cost)
fit.cm.eq.cost

pred.eq.cost = predict(mod.eq.cost, newdata=testData, type="class")
pred.cm.eq.cost = table(data.frame(actual=testData$High,response=pred.eq.cost))
pred.cm.eq.cost = getUpdatedCM(pred.cm.eq.cost)
pred.cm.eq.cost

## fit model with unequal cost
# update prior probabilities
# assuming that incorrectly classifying 'High' has 3 times costly
costs = c(2,1)
train.res.summary
prior.w.weight = c(train.res.summary[2,1] * costs[1]
                   ,train.res.summary[2,2] * costs[2])
priorUp = c(prior.w.weight[1]/sum(prior.w.weight)
            ,prior.w.weight[2]/sum(prior.w.weight))
priorUp

# loss matrix
loss.mat = matrix(c(0,2,1,0),nrow=2,byrow=TRUE)
loss.mat

# refit the model with the updated priors
# fit with updated prior
mod.uq.cost = rpart(High ~ ., data=trainData, parms=list(prior=priorUp), control=rpart.control(cp=cp))
# fit with loss matrix
# mod.uq.cost = rpart(High ~ ., data=trainData, parms=list(loss=loss.mat), control=rpart.control(cp=cp))

# generate confusion matrix on training data
fit.uq.cost = predict(mod.uq.cost, type="class")
fit.cm.uq.cost = table(data.frame(actual=trainData$High,response=fit.uq.cost))
fit.cm.uq.cost = getUpdatedCM(fit.cm.uq.cost)
fit.cm.uq.cost

pred.uq.cost = predict(mod.uq.cost, newdata=testData, type="class")
pred.cm.uq.cost = table(data.frame(actual=testData$High,response=pred.uq.cost))
pred.cm.uq.cost = getUpdatedCM(pred.cm.uq.cost)
pred.cm.uq.cost