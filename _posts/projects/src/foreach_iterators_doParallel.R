### foreach
## load libraries
library(parallel)
library(iterators)
library(foreach)
library(doParallel)

## basic examples
x = foreach(a=1:3) %do% sqrt(a)
x

x = foreach(a=1:3, b=rep(10,3)) %do% (a + b)
x = foreach(a=1:3, b=rep(10,3)) %do% {
  a + b
}
# iteration to min(length(a), length(b), ...)
x = foreach(a=1:100, b=rep(10,3)) %do% (a + b)

## options
# .combine
x = foreach(a=1:3, .combine="c") %do% exp(a)
x = foreach(a=1:3, .combine="rbind") %do% exp(a)
x = foreach(a=1:3, .combine="+") %do% exp(a)
x = foreach(a=1:3, .combine="min") %do% exp(a)

cfun = function(a, b) NULL
x = foreach(a=1:4, .combine="cfun") %do% rnorm(4)
comMin = function(a, b) if(a < b) a else b
x = foreach(a=1:3, .combine="comMin") %do% exp(a)

cfun = function(...) NULL
x = foreach(a=1:4, .combine="cfun", .multicombine=TRUE) %do% rnorm(4)
x = foreach(a=1:4, .combine="cfun", .multicombine=TRUE, .maxcombine=10) %do% rnorm(4)

# .inorder
cl = makeCluster(detectCores())
registerDoParallel(cl)
foreach(a=4:1, .combine="c") %dopar% {
  Sys.sleep(a)
  a
}
foreach(a=4:1, .combine="c", .inorder=FALSE) %dopar% {
  Sys.sleep(a)
  a
}
stopCluster(cl)

# .packages
cl = makeCluster(detectCores())
registerDoParallel(cl)
foreach(a=1:4, .combine="c", .packages="MASS") %dopar% dim(Boston)[1]
stopCluster(cl)

## list comprehension
foreach(a=1:10, .combine="c") %:% when(a %% 2 == 0) %do% a

## nested loop
avec = c(10,20)
bvec = 1:4
mat = matrix(0, nrow=length(avec), ncol=length(bvec))
for(b in bvec) {
  for(a in 1:length(avec)) {
    mat[a,b] = avec[a] + bvec[b]
  }
}
mat

foreach(b=1:4, .combine="cbind") %:%
  foreach(a=c(10,20), .combine="c") %do% (a + b)

# no need to consider which loop to parallize
# - %:% turns multiple foreach loops into a single stream of tasks that can be parallelized
# - chunking that's backed only by doNWS not considered (parLapply?)
cl = makeCluster(detectCores())
registerDoParallel(cl)
foreach(b=1:4, .combine="cbind") %:%
  foreach(a=c(10,20), .combine="c") %dopar% (a + b)
stopCluster(cl)

## iterators
# by object
iters = iter(1:10)
c(nextElem(iters),nextElem(iters))

df = data.frame(number=c(1:26), letter=letters)
iters = iter(df, by="row")
nextElem(iters)

iters = iter(list(1:2, 3:4))
for(i in 1:(iters$length+1)) print(nextElem(iters))

# by function
set.seed(1237)
iters = iter(function() sample(0:9, 4, replace=TRUE))
nextElem(iters)

# example
set.seed(1237)
mat = matrix(rnorm(100),nrow=1)
iters = iter(mat, by="row")
foreach(a=iters, .combine="c") %do% mean(a)

# special iterators
# icount, irnorm, irunit, irbinom, irnbinom, irpois














data = data.frame(a=c(1,1,2,2), b=c(1:4))
set.seed(125)
bag = sample(nrow(data), size=nrow(data), replace=TRUE)
train = data[bag,]
rownames(train) = bag
test = data[-bag,]









