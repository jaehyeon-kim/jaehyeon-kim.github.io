### snow and parallel
unloadPkg = function(pkg) { 
  detach(search()[grep(paste0("*",pkg),search())]
         ,unload=TRUE
         ,character.only=TRUE)
}

## make and stop cluster
require(snow)
spec = 4
cl = makeCluster(spec, type="SOCK")
stopCluster(cl)
unloadPkg("snow")

require(parallel)
# number of workers can be detected
# type: "PSOCK" or "FORK", default - "PSOCK"
cl = makeCluster(detectCores())
stopCluster(cl)
unloadPkg("parallel")

## apply functions
# clusterApply(cl, x, fun, ...)
# - pushes tasks to workers by distributing x elements
# clusterApplyLB(cl, x, fun, ...) <load balancing>
# - workers pull tasks as needed
# - efficient if some tasks take longer or some workers are slower
# parLapply(cl, x, fun, ...)
# - docall(c, clusterApply(cl, splitList(x, length(cl)), lapply, fun, ...))
# - schedule by spliting x according to # of clusters, reduce I/O operation
# parLapplyLB(cl = NULL, X, fun, ...)
# - exists only in parallel, parLapply() with load balancing

## CASE 1 - load balancing matters (different time to execute tasks)
# snow
require(snow)
set.seed(1237)
sleep = sample(1:10,10)
spec = 4
cl = makeCluster(spec, type="SOCK")
st = snow.time(clusterApply(cl, sleep, Sys.sleep))
stLB = snow.time(clusterApplyLB(cl, sleep, Sys.sleep))
stPL = snow.time(parLapply(cl, sleep, Sys.sleep))
stopCluster(cl)
par(mfrow=c(3,1),mar=rep(2,4))
plot(st, title="clusterApply")
plot(stLB, title="clusterApplyLB")
plot(stPL, title="parLapply")
sleep
clusterSplit(cl, sleep)

# clear env
par(mfrow=c(1,1),mar=c(5.1, 4.1, 4.1, 2.1))
unloadPkg("snow")
rm(list = ls()[ls()!="unloadPkg"])

# parallel
require(parallel)
set.seed(1237)
sleep = sample(1:10,10)
cl = makeCluster(detectCores())
st = system.time(clusterApply(cl, sleep, Sys.sleep))
stLB = system.time(clusterApplyLB(cl, sleep, Sys.sleep))
stPL = system.time(parLapply(cl, sleep, Sys.sleep))
stPLB = system.time(parLapplyLB(cl, sleep, Sys.sleep))
stopCluster(cl)
sysTime = do.call("rbind",list(st,stLB,stPL,stPLB))
sysTime = cbind(sysTime,data.frame(fun=c("clusterApply","clusterApplyLB"
                                         ,"parLapply","parLapplyLB")))
require(ggplot2)
ggplot(data=sysTime, aes(x=fun,y=elapsed,fill=fun)) + 
  geom_bar(stat="identity") + ggtitle("Elapsed time of each function")

# clear env
unloadPkg("parallel")
rm(list = ls()[ls()!="unloadPkg"])

## CASE 2 - I/O operations matters (pass additional arguments)
# snow
require(snow)
mat = matrix(0, 2000, 2000)
sleep = rep(1,50)
fcn = function(st, arg) Sys.sleep(st)
spec = 4
cl = makeCluster(spec, type="SOCK")
st = snow.time(clusterApply(cl, sleep, fcn, arg=mat))
stLB = snow.time(clusterApplyLB(cl, sleep, fcn, arg=mat))
stPL = snow.time(parLapply(cl, sleep, fcn, arg=mat))
stopCluster(cl)
par(mfrow=c(3,1),mar=rep(2,4))
plot(st, title="clusterApply")
plot(stLB, title="clusterApplyLB")
plot(stPL, title="parLapply")

# clear env
par(mfrow=c(1,1),mar=c(5.1, 4.1, 4.1, 2.1))
unloadPkg("snow")
rm(list = ls()[ls()!="unloadPkg"])

# parallel
require(parallel)
mat = matrix(0, 2000, 2000)
sleep = rep(1,50)
fcn = function(st, arg) Sys.sleep(st)
cl = makeCluster(detectCores())
st = system.time(clusterApply(cl, sleep, fcn, arg=mat))
stLB = system.time(clusterApplyLB(cl, sleep, fcn, arg=mat))
stPL = system.time(parLapply(cl, sleep, fcn, arg=mat))
stPLB = system.time(parLapplyLB(cl, sleep, fcn, arg=mat))
stopCluster(cl)
sysTime = do.call("rbind",list(st,stLB,stPL,stPLB))
sysTime = cbind(sysTime,data.frame(fun=c("clusterApply","clusterApplyLB"
                                         ,"parLapply","parLapplyLB")))
require(ggplot2)
ggplot(data=sysTime, aes(x=fun,y=elapsed,fill=fun)) + 
  geom_bar(stat="identity") + ggtitle("Elapsed time of each function")

# clear env
unloadPkg("parallel")
rm(list = ls()[ls()!="unloadPkg"])

## initialize workers
# snow and parallel
require(snow)
spec = 4
cl = makeCluster(spec, type="SOCK")
# execute expression
exp = clusterEvalQ(cl, { library(MASS); NULL })
# execute expression + pass variables
worker.init = function(arg) {
  for(a in arg) library(a, character.only=TRUE)
  NULL
}
expCall = clusterCall(cl, worker.init, arg=c("MASS","boot"))
stopCluster(cl)

# clear env
unloadPkg("snow")
rm(list = ls()[ls()!="unloadPkg"])

## random number generation
# snow
require(snow)
require(rlecuyer)
# Uniform Random Number Generation in SNOW Clusters
# seed is six integer values if RNGStream
spec = 4
cl = makeCluster(spec, type="SOCK")
rndSeed = function(x) {
  clusterSetupRNG(cl, type="RNGstream", seed=rep(1237,6))
  unlist(clusterEvalQ(cl, rnorm(1)))
}
t(sapply(1:2,rndSeed))
stopCluster(cl)

# clear env
unloadPkg("snow")
rm(list = ls()[ls()!="unloadPkg"])

# parallel
require(parallel)
cl = makeCluster(detectCores())
rndSeed = function(x) {
  clusterSetRNGStream(cl, iseed=1237)
  unlist(clusterEvalQ(cl, rnorm(1)))
}
t(sapply(1:2,rndSeed))
stopCluster(cl)

# clear env
unloadPkg("parallel")
rm(list = ls()[ls()!="unloadPkg"])