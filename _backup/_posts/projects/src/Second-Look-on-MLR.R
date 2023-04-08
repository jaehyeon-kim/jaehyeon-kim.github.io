library(ISLR)
library(MASS) # lda/qda
library(class) # knn
library(mlr)

## use only Lag1 and Lag2 as features / Direction as response
str(Smarket)

#### ISLR
## glm
# test on Year == 2005
glm.fit = glm(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), family=binomial, subset=Smarket$Year!=2005)
glm.probs = predict(glm.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)), type="response")
glm.pred = sapply(glm.probs, function(p) { ifelse(p>.5,"Up","Down") })
glm.cm = table(data.frame(response=glm.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
glm.mmce = 1 - sum(diag(glm.cm)) / sum(glm.cm)

# keep output
model = c("glm")
hyper = c(NA)
mmce = c(glm.mmce)

## lda
lda.fit = lda(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), subset=Smarket$Year!=2005)
lda.pred = predict(lda.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)))$class
lda.cm = table(data.frame(response=lda.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
lda.mmce = 1 - sum(diag(lda.cm)) / sum(lda.cm)

# keep output
model = c(model,"lda")
hyper = c(hyper, NA)
mmce = c(mmce, lda.mmce)

## qda
qda.fit = qda(Direction ~ ., data=subset(Smarket, select=c(Lag1,Lag2,Direction)), subset=Smarket$Year!=2005)
qda.pred = predict(qda.fit, subset(Smarket, Year==2005, select=c(Lag1,Lag2,Direction)))$class
qda.cm = table(data.frame(response=qda.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
qda.mmce = 1 - sum(diag(qda.cm)) / sum(qda.cm)

# keep output
model = c(model,"qda")
hyper = c(hyper, NA)
mmce = c(mmce, qda.mmce)

## knn
k = 3 # hyper (or tuning) parameter set to be 3
knn.feat.train = subset(Smarket, Year!=2005, select=c(Lag1,Lag2))
knn.feat.test = subset(Smarket, Year==2005, select=c(Lag1,Lag2))
knn.resp.train = subset(Smarket, Year!=2005, select=c(Direction), drop=TRUE) # should be factors
knn.pred = knn(train=knn.feat.train, test=knn.feat.test, cl=knn.resp.train, k=k)
knn.cm = table(data.frame(response=knn.pred, truth=subset(Smarket, Year==2005, select=c("Direction"))))
knn.mmce = 1 - sum(diag(knn.cm)) / sum(knn.cm)

# keep output
model = c(model,"knn")
hyper = c(hyper,3)
mmce = c(mmce,knn.mmce)

## consolidate outputs
holdout.res = data.frame(model=model, hyper=hyper, mmce=mmce)

#### MLR
### task
task = makeClassifTask(id="Smarket", data=subset(Smarket, select=c(Lag1,Lag2,Direction)), positive="Up", target="Direction")
task

### learner
## no need to set up learner if kept default setup
## glm
glm.lrn = makeLearner("classif.binomial")
glm.lrn

## lda
lda.lrn = makeLearner("classif.lda")
lda.lrn

## qda
qda.lrn = makeLearner("classif.qda")
qda.lrn

## knn
knn.lrn = makeLearner("classif.knn", par.vals=list(k=3)) # set hyper parameter
knn.lrn

### resampling
# for holdout validation, resampling instance can be specified
start = length(Smarket$Year) - length(Smarket$Direction[Smarket$Year==2005]) + 1
end = length(Smarket$Year)
rin = makeFixedHoldoutInstance(train.inds=1:(start-1), test.inds=start:end, size=end)
rin

# for others, resampling description can be created
rdesc = makeResampleDesc("CV", iters=10)
rdesc

### benchmark
tasks = list(task)
learners = list(glm.lrn, lda.lrn, qda.lrn, knn.lrn)
holdout.resample = list(rin)
cv.resample = list(rdesc)

# default measure for classification - mean misclassification error
# check available measures - listMeasures(task.name)
mlr.holdout.res = benchmark(learners=learners, tasks=tasks, resamplings=holdout.resample)
mlr.cv.res = benchmark(learners=learners, tasks=tasks, resamplings=cv.resample)

### ISLR - holdout validation
holdout.res

### MLR - holdout validation
mlr.holdout.res

### MLR - 10-fold cross validation
mlr.cv.res