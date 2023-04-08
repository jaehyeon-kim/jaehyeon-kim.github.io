library(dplyr)
library(ggplot2)
library(grid)
library(gridExtra)
library(rpart)
library(rpart.plot)
library(caret)

## data
require(ISLR)
data(Carseats)
# label order changed (No=1)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("No","High")))
# structure of predictors
str(subset(Carseats,select=c(-High,-Sales)))
# response summaries
res.cl.summary = with(Carseats,rbind(table(High),table(High)/length(High)))
res.cl.summary

res.reg.summary = summary(Carseats$Sales)
res.reg.summary

## split data
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
# classification
trainData.cl = subset(Carseats, select=c(-Sales))[trainIndex,]
testData.cl = subset(Carseats, select=c(-Sales))[-trainIndex,]
# regression
trainData.reg = subset(Carseats, select=c(-High))[trainIndex,]
testData.reg = subset(Carseats, select=c(-High))[-trainIndex,]

# response summary
train.res.cl.summary = with(trainData.cl,rbind(table(High),table(High)/length(High)))
test.res.cl.summary = with(testData.cl,rbind(table(High),table(High)/length(High)))

train.res.reg.summary = summary(trainData.reg$Sales)
test.res.reg.summary = summary(testData.reg$Sales)

## train model
# set up train control
trControl = trainControl(method="repeatedcv",number=10,repeats=5)

# classification
set.seed(12357)
mod.cl = train(High ~ .
               ,data=trainData.cl
               ,method="rpart"
               ,tuneLength=20
               ,trControl=trControl)

# regression - caret
source("src/mlUtils.R")
# caret
set.seed(12357)
mod.reg.caret = train(Sales ~ .
                      ,data=trainData.reg
                      ,method="rpart"
                      ,tuneLength=20
                      ,trControl=trControl)
# R squared meaningless
# Warning message:
#   In nominalTrainWorkflow(x = x, y = y, wts = weights, info = trainInfo,  :
#     There were missing values in resampled performance measures.
# http://stackoverflow.com/questions/26828901/warning-message-missing-values-in-resampled-performance-measures-in-caret-tra
# http://stackoverflow.com/questions/10503784/caret-error-when-using-anything-but-loocv-with-rpart

# regression - rpart
set.seed(12357)
mod.reg.rpart = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=0))
mod.reg.rpart.param = bestParam(mod.reg.rpart$cptable,"CP","xerror","xstd")
mod.reg.rpart.param

mod.reg.caret.param = bestParam(mod.reg.caret$results,"cp","RMSE","RMSESD",isDesc=FALSE)
mod.reg.caret.param

# plot best CP
df = as.data.frame(mod.reg.rpart$cptable)
best = bestParam(mod.reg.rpart$cptable,"CP","xerror","xstd")
ubound = ifelse(best[2,1]+best[3,1]>max(df$xerror),max(df$xerror),best[2,1]+best[3,1])
lbound = ifelse(best[2,1]-best[3,1]<min(df$xerror),min(df$xerror),best[2,1]-best[3,1])

tune.plot = ggplot(data=df[3:nrow(df),], aes(x=CP,y=xerror)) + 
  geom_line() + geom_point() + 
  geom_abline(intercept=ubound,slope=0, color="blue") + 
  geom_abline(intercept=lbound,slope=0, color="blue") + 
  geom_point(aes(x=best[1,2],y=best[2,2]),color="red",size=3)
print(tune.plot)

## show best tuned cp
# classification
subset(mod.cl$results,subset=cp==mod.cl$bestTune$cp)

# regression - caret
subset(mod.reg.caret$results,subset=cp==mod.reg.caret$bestTune$cp)

# regression - rpart
mod.reg.rpart.summary = data.frame(t(mod.reg.rpart.param[,2]))
colnames(mod.reg.rpart.summary) = c("CP","xerror","xstd")
mod.reg.rpart.summary

## refit the model to the entire training data
# classification
cp.cl = mod.cl$bestTune$cp
mod.cl = rpart(High ~ ., data=trainData.cl, control=rpart.control(cp=cp.cl))

# regression - caret
cp.reg.caret = mod.reg.caret$bestTune$cp
mod.reg.caret = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=cp.reg.caret))

# regression - rpart
cp.reg.rpart = mod.reg.rpart.param[1,2]
mod.reg.rpart = rpart(Sales ~ ., data=trainData.reg, control=rpart.control(cp=cp.reg.rpart))

## generate confusion matrix on training data
# fit models
fit.cl = predict(mod.cl, type="class")
fit.reg.caret = predict(mod.reg.caret)
fit.reg.rpart = predict(mod.reg.rpart)

# classification
# percentile that Sales is divided by No and High
eqPercentile = with(trainData.reg,length(Sales[Sales<=8])/length(Sales))
eqPercentile

# classification
fit.cl.cm = table(data.frame(actual=trainData.cl$High,response=fit.cl))
fit.cl.cm = updateCM(fit.cl.cm,type="Fitted")
fit.cl.cm

# regression with equal percentile is not comparable
probs = eqPercentile
fit.reg.caret.cm = regCM(trainData.reg$Sales, fit.reg.caret, probs=probs, type="Fitted")
fit.reg.caret.cm

# regression with selected percentiles
probs = seq(0.2,0.8,0.2)

# regression - caret
# caret produces a better outcome on training data - note lower cp
fit.reg.caret.cm = regCM(trainData.reg$Sales, fit.reg.caret, probs=probs, type="Fitted")
fit.reg.caret.cm

# regression - rpart
fit.reg.rpart.cm = regCM(trainData.reg$Sales, fit.reg.rpart, probs=probs, type="Fitted")
fit.reg.rpart.cm

## generate confusion matrix on test data
# fit models
pred.reg.caret = predict(mod.reg.caret, newdata=testData.reg)
pred.reg.rpart = predict(mod.reg.rpart, newdata=testData.reg)

# regression - caret
pred.reg.caret.cm = regCM(testData.reg$Sales, pred.reg.caret, probs=probs)
pred.reg.caret.cm

# regression - rpart
pred.reg.rpart.cm = regCM(testData.reg$Sales, pred.reg.rpart, probs=probs)
pred.reg.rpart.cm

# model by caret with lower cp produces better outcome
# 1 standard error rule is questionable on this data
pred.reg.caret.rmse = sqrt(sum(testData.reg$Sales-pred.reg.caret)^2/length(testData.reg$Sales))
pred.reg.caret.rmse

pred.reg.rpart.rmse = sqrt(sum(testData.reg$Sales-pred.reg.rpart)^2/length(testData.reg$Sales))
pred.reg.rpart.rmse

## plot actual vs prediced and resid vs fitted
mod.reg.caret.test = rpart(Sales ~ ., data=testData.reg, control=rpart.control(cp=cp.reg.caret))
predDF = data.frame(actual=testData.reg$Sales
                    ,predicted=pred.reg.caret
                    ,resid=resid(mod.reg.caret.test))
# correlation
cor(predDF)

# actual vs predicted
actual.plot = ggplot(predDF, aes(x=predicted,y=actual)) + 
  geom_point(shape=1,position=position_jitter(width=0.1,height=0.1)) + 
  geom_smooth(method=lm,se=FALSE)

# resid vs predicted
resid.plot = ggplot(predDF, aes(x=predicted,y=resid)) + 
  geom_point(shape=1,position=position_jitter(width=0.1,height=0.1)) + 
  geom_smooth(method=lm,se=FALSE)

grid.arrange(actual.plot, resid.plot, ncol = 2)

# plot tree
cols <- ifelse(mod.reg.caret$frame$yval > 8,"green4","darkred") # green if high
prp(mod.reg.caret
    ,main="CART Model Tree"
    #,extra=106           # display prob of survival and percent of obs
    ,nn=TRUE             # display the node numbers
    ,fallen.leaves=TRUE  # put the leaves on the bottom of the page
    ,branch=.5           # change angle of branch lines
    ,faclen=0            # do not abbreviate factor levels
    ,trace=1             # print the automatically calculated cex
    ,shadow.col="gray"   # shadows under the leaves
    ,branch.lty=3        # draw branches using dotted lines
    ,split.cex=1.2       # make the split text larger than the node text
    ,split.prefix="is "  # put "is " before split text
    ,split.suffix="?"    # put "?" after split text
    ,col=cols, border.col=cols   # green if survived
    ,split.box.col="lightgray"   # lightgray split boxes (default is white)
    ,split.border.col="darkgray" # darkgray border on split boxes
    ,split.round=.5)
