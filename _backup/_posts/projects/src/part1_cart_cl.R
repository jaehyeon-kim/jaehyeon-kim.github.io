library(dplyr)
library(rpart)
library(rpart.plot)
library(caret)

### shared objects
## data
require(ISLR)
data(Carseats)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
# structure of predictors
str(subset(Carseats,select=c(-High,-Sales)))
# classification response summary
with(Carseats,table(High))
with(Carseats,table(High) / length(High))

# regression response summary
summary(Carseats$Sales)

## train control
trControl.cv = trainControl(method="cv",number=10)
trControl.recv = trainControl(method="repeatedcv",number=10,repeats=5)
trControl.boot = trainControl(method="boot",number=50)

### Classification
## Data Splitting
set.seed(1237)
trainIndex.cl = createDataPartition(Carseats$High, p=.8, list=FALSE, times=1)
trainData.cl = subset(Carseats, select=c(-Sales))[trainIndex.cl,]
testData.cl = subset(Carseats, select=c(-Sales))[-trainIndex.cl,]

# training response summary
with(trainData.cl,table(High))
with(trainData.cl,table(High) / length(High))

# test response summary
with(testData.cl,table(High))
with(testData.cl,table(High) / length(High))

## Model Training and Tuning
library(doMC)
registerDoMC(4)

set.seed(12357)
fit.cl.cv = train(High ~ .
                  ,data=trainData.cl
                  ,method="rpart"
                  ,tuneLength=20
                  ,trControl=trControl.cv)

fit.cl.recv = train(High ~ .
                    ,data=trainData.cl
                    ,method="rpart"
                    ,tuneLength=20
                    ,trControl=trControl.recv)

fit.cl.boot = train(High ~ .
                    ,data=trainData.cl
                    ,method="rpart"
                    ,tuneLength=20
                    ,trControl=trControl.boot)

# results at best tuned cp
subset(fit.cl.cv$results,subset=cp==fit.cl.cv$bestTune$cp)
subset(fit.cl.recv$results,subset=cp==fit.cl.recv$bestTune$cp)
subset(fit.cl.boot$results,subset=cp==fit.cl.boot$bestTune$cp)

## refit the model to the entire training data
cp.cl = fit.cl.recv$bestTune$cp
fit.cl = rpart(High ~ ., data=trainData.cl, control=rpart.control(cp=cp.cl))

# plot tree
cols <- ifelse(fit.cl$frame$yval == 1,"green4","darkred") # green if high
prp(fit.cl
    ,main="CART Model Tree"
    ,extra=106           # display prob of survival and percent of obs
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

# expected loss: 0.13 = 8/60 (0.13333)
# prob(node): 19% (60/321)

# another plotting option - don't run
require(partykit)
plot(as.party(fit.cl))

## apply to the test data
pre.cl = predict(fit.cl, newdata=testData.cl, type="class")

# confusion matrix
cMat.cl = table(data.frame(response=pre.cl,truth=testData.cl$High))
cMat.cl

# mean misclassification error
mmse.cl = 1 - sum(diag(cMat.cl))/sum(cMat.cl)
mmse.cl