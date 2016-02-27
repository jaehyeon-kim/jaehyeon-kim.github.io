library(ISLR)
library(mlr)
str(Smarket)
cor(subset(Smarket, select=-Direction)) # Direction is a factor

#### logistic regression
### ISLR
## task - no object
## learner - no object
## train
glm.mod = glm(Direction ~ ., data=subset(Smarket, select=c(-Year, -Today)), family=binomial)
summary(glm.mod)
# coef(glm.mod) # also summary(glm.mod)$coef[,4]

## predict
# type = c("link","response","terms"), default - "link"
glm.probs = predict(glm.mod, type="response")
head(glm.probs) # check positive level (1): contrasts(Smarket$Direction)

glm.pred = sapply(glm.probs, function(p) { ifelse(p>.5,"Up","Down") })
head(glm.pred)

## performance
glm.cm = table(data.frame(response=glm.pred, truth=Smarket$Direction))
glm.cm # confusion matrix

# mean misclassificaton error rate 47.84%
glm.mmse = 1 - sum(diag(glm.cm)) / sum(glm.cm)
glm.mmse

### MLR
## task
mlr.glm.task = makeClassifTask(id="Smarket", data=subset(Smarket, select=c(-Year, -Today)), positive="Up", target="Direction")
mlr.glm.task

## learner
mlr.glm.lrn = makeLearner("classif.binomial", predict.type="prob")
mlr.glm.lrn

## train
mlr.glm.mod = train(mlr.glm.lrn, mlr.glm.task)
mlr.glm.mod

## prediction - model + either task or newdata but not both
mlr.glm.pred = predict(object=mlr.glm.mod, task=mlr.glm.task)
mlr.glm.pred

## performance
mlr.glm.cm = table(subset(mlr.glm.pred$data, select=c("response","truth")))
mlr.glm.cm

mlr.glm.mmse = 1 - sum(diag(mlr.glm.cm)) / sum(mlr.glm.cm)
mlr.glm.mmse

# or simply
mlr.glm.mmse = performance(mlr.glm.pred) # default: mean misclassification error (mmse)
mlr.glm.mmse
# see available measures - listMeasures(task.name)

### ISLR
# mmse is too optimistic if tested on training data, need to test on independent data
Smarket.train = subset(Smarket, Year != 2005, select=c(-Year, -Today))
Smarket.test = subset(Smarket, Year == 2005, select=c(-Year, -Today))

## task - no object
## learner - no object
## train
glm.mod.new = glm(Direction ~ ., data=Smarket.train, family=binomial)
glm.mod.new

## predict
glm.probs.new = predict(glm.mod.new, newdata=Smarket.test, type="response")
head(glm.probs.new)

glm.pred.new = sapply(glm.probs.new, function(p) { ifelse(p>.5,"Up","Down") })
head(glm.pred.new)

## performance
glm.cm.new = table(data.frame(response=glm.pred.new, truth=Smarket.test$Direction))
glm.cm.new

glm.mmse.new = 1 - sum(diag(glm.cm.new)) / sum(glm.cm.new)
glm.mmse.new

### MLR
## task
mlr.glm.task.new = makeClassifTask(id="SmarketNew", data=Smarket.train, positive="Up", target="Direction")
mlr.glm.task.new

## learner
mlr.glm.lrn.new = mlr.glm.lrn # learner can be reused

## train
mlr.glm.mod.new = train(mlr.glm.lrn.new, mlr.glm.task.new)
mlr.glm.mod.new

## prediction - model + either task or newdata but not both
mlr.glm.pred.new = predict(object=mlr.glm.mod.new, newdata=Smarket.test)
mlr.glm.pred.new

## performance
mlr.glm.mmse.new = performance(mlr.glm.pred.new)
mlr.glm.mmse.new

# dev install
devtools::install_github("berndbischl/ParamHelpers")
devtools::install_github("berndbischl/BBmisc")
devtools::install_github("berndbischl/parallelMap")
devtools::install_github("berndbischl/mlr")