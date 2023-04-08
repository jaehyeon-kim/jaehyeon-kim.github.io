library(parallel)
library(iterators)
library(foreach)
library(doParallel)

## k-means clustering
# parallel
split = detectCores()
eachStart = 25

cl = makeCluster(split)
init = clusterEvalQ(cl, { library(MASS); NULL })
results = parLapplyLB(cl
                      ,rep(eachStart, split)
                      ,function(nstart) kmeans(Boston, 4, nstart=nstart))
withinss = sapply(results, function(result) result$tot.withinss)
result = results[[which.min(withinss)]]
stopCluster(cl)

result$tot.withinss

# foreach
rm(list = ls())
split = detectCores()
eachStart = 25
# set up iterators
iters = iter(rep(eachStart, split))
# set up combine function
comb = function(res1, res2) {
  if(res1$tot.withinss < res2$tot.withinss) res1 else res2
}

cl = makeCluster(split)
registerDoParallel(cl)
result = foreach(nstart=iters, .combine="comb", .packages="MASS") %dopar%
  kmeans(Boston, 4, nstart=nstart)
stopCluster(cl)

result$tot.withinss

## Random forest
library(randomForest)

# parallel
rm(list = ls())
set.seed(1237)
x = matrix(runif(500), 100)
y = gl(2,50)

split = detectCores()
eachTrees = 250
# define function to fit random forest given predictors and response
# data has to be sent to workers using this function
rf = function(ntree, pred, res) {
  randomForest(pred, res, ntree=ntree)
}

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
init = clusterEvalQ(cl, { library(randomForest); NULL })
results = parLapplyLB(cl, rep(eachTrees, split), rf, pred=x, res=y)
result = do.call("combine", results)
stopCluster(cl)

cm = table(data.frame(actual=y, fitted=result$predicted))
cm

# foreach
rm(list = ls())
set.seed(1237)
x = matrix(runif(500), 100)
y = gl(2,50)

split = detectCores()
eachTrees = 250
# set up iterators
iters = iter(rep(eachTrees, split))

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
registerDoParallel(cl)
result = foreach(ntree=iters, .combine="combine", .multicombine=TRUE, .packages="randomForest") %dopar%
  randomForest(x, y, ntree=ntree)
stopCluster(cl)

cm = table(data.frame(actual=y, fitted=result$predicted))
cm

## Bagging
rm(list = ls())
# update variable importance measure of bagged trees
cartBGG = function(formula, trainData, ntree=1, ...) {
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  
  # variable importance - merge by 'var'
  var.imp = data.frame(var=colnames(trainData[,-res.ind]))
  require(rpart)
  for(i in 1:ntree) {
    # create in bag and out of bag sample
    bag = sample(nrow(trainData), size=nrow(trainData), replace=TRUE)
    inbag = trainData[bag,]
    outbag = trainData[-bag,]
    # fit model
    mod = rpart(formula=formula, data=inbag, control=rpart.control(cp=0))
    # set helper variables
    colname = paste("s",i,sep=".")
    pred.type = ifelse(class(trainData[,res.ind])=="factor","class","vector")
    # merge variable importance
    imp = data.frame(names(mod$variable.importance), mod$variable.importance)
    colnames(imp) = c("var", colname)
    var.imp = merge(var.imp, imp, by="var", all=TRUE)
  }
  # adjust outcome
  rownames(var.imp) = var.imp[,1]
  var.imp = var.imp[,2:ncol(var.imp)]
  
  # create outcome as a list
  result=list(var.imp = var.imp)
  class(result) = c("rpartbgg")
  result
}

# combine variable importance of bagged trees
comBGG = function(...) {
  # add rpart objects in a list
  bgglist = list(...)
  # extract variable importance
  var.imp = lapply(bgglist, function(x) x$var.imp)
  # combine and sum by row
  var.imp = do.call("cbind", var.imp)
  var.imp = apply(var.imp, 1, sum, na.rm=TRUE)
  var.imp
}

# data
library(ISLR)
data(Carseats)

# parallel
split = detectCores()
eachTree = 250

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
# rpart is required in cartBGG(), not need to load in each cluster
results = parLapplyLB(cl
                      ,rep(eachTree, split)
                      ,cartBGG, formula="Sales ~ .", trainData=Carseats, ntree=eachTree)
result = do.call("comBGG", results)
stopCluster(cl)

result

# foreach
split = detectCores()
eachTrees = 250
# set up iterators
iters = iter(rep(eachTrees, split))

cl = makeCluster(split)
clusterSetRNGStream(cl, iseed=1237)
registerDoParallel(cl)
# note .multicombine=TRUE as > 2 arguments
# .maxcombine=if (.multicombine) 100 else 2
result = foreach(ntree=iters, .combine="comBGG", .multicombine=TRUE) %dopar%
  cartBGG(formula="Sales ~ .", trainData=Carseats, ntree=ntree)
stopCluster(cl)

result
