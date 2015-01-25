library(kernlab)
library(caret)
library(mlr)

### preprocessing - caret
data(GermanCredit)
GermanCredit <- GermanCredit[, -nearZeroVar(GermanCredit)]
GermanCredit$CheckingAccountStatus.lt.0 <- NULL
GermanCredit$SavingsAccountBonds.lt.100 <- NULL
GermanCredit$EmploymentDuration.lt.1 <- NULL
GermanCredit$EmploymentDuration.Unemployed <- NULL
GermanCredit$Personal.Male.Married.Widowed <- NULL
GermanCredit$Property.Unknown <- NULL
GermanCredit$Housing.ForFree <- NULL

### split data - caret
set.seed(100)
inTrain <- createDataPartition(GermanCredit$Class, p = .8)[[1]]
GermanCreditTrain <- GermanCredit[inTrain, ]
GermanCreditTest  <- GermanCredit[-inTrain, ]

### task
task = makeClassifTask(id="gc", data=GermanCreditTrain, target="Class")
normalizeFeatures(task, method="standardize")

### tune svm
## estimate sigma
set.seed(231)
sigDist = sigest(Class ~ ., data=GermanCreditTrain, frac=1)

trans = function(x) 2^x
ps = makeParamSet(makeNumericParam("C", lower=-2, upper=4, trafo=trans),
                  makeDiscreteParam("sigma", values=c(as.numeric(sigDist[2]))),
                  makeDiscreteParam("kernel", values=c("rbfdot")))
ctrl = makeTuneControlGrid(resolution=c(C=7L))

# check grid
grid <- generateGridDesign(ps, resolution=c(C=7))
# change to transformed values
grid$C = trans(grid$C)
grid$sigma = round(as.numeric(as.character(grid$sigma)),4)
grid

### resampling
rdesc.outer = makeResampleDesc("RepCV", folds=5, reps=5, predict="both")
rdesc.inner = makeResampleDesc("CV", iters=5)

### learner
lrn.svm = makeLearner("classif.ksvm")
lrn.glm = makeLearner("classif.binomial")
# wrapped learner created
lrn.nest = makeTuneWrapper(lrn.svm, rdesc.inner, par.set=ps, control=ctrl, show.info=FALSE)

# tune params
set.seed(123457)
res = tuneParams(lrn.svm, task=task, resampling=rdesc.outer, par.set=ps, control=ctrl, show.info=FALSE)
# optimal parameters - res$x
# measure with optimal parameters - res$y
res

res.opt.grid <- as.data.frame(res$opt.path)
res.opt.grid$C = trans(res.opt.grid$C)
res.opt.grid$sigma = round(as.numeric(as.character(res.opt.grid$sigma)),4)
res.opt.grid

### benchmark
# update svm learner
set.seed(123457)
lrn.svm = setHyperPars(lrn.svm, par.vals=res$x)
res.bench = benchmark(learners=list(lrn.nest,lrn.svm,lrn.glm), task=task, resampling=rdesc.outer)
res.bench