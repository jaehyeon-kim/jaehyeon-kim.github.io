## data
require(ISLR)
data(Carseats)
require(dplyr)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data.cl = subset(Carseats, select=c(-Sales))
data.rg = subset(Carseats, select=c(-High))

# split data
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.rg = data.rg[trainIndex,]
testData.rg = data.rg[-trainIndex,]

## run rpartDT
# import constructors
source("src/cart.R")
set.seed(12357)
rg = cartDT(trainData.rg, testData.rg, "Sales ~ .", ntree=2000)

## cp values
# cart
rg$rpt$cp[1,][[1]]
# bagging
summary(t(rg$boot.cp)[,2])

## individual errors
# cart test error
crt.err = rg$rpt$test.lst$error$error
crt.err
## single tree's train and test errors are not far away from the corresponding errors of the bagged trees
## oob error 0.9 and test error 0.65 sd
(mean(unlist(rg$ind.oob.lst.err)) - crt.err)/sd(unlist(rg$ind.oob.lst.err))
(mean(unlist(rg$ind.tst.lst.err)) - crt.err)/sd(unlist(rg$ind.tst.lst.err))

# bagging error at least xerror - se to see 1-SE rule
ind.oob.err = data.frame(type="oob",error=unlist(rg$ind.oob.lst.err))
ind.tst.err = data.frame(type="test",error=unlist(rg$ind.tst.lst.err))
ind.err = rbind(ind.oob.err,ind.tst.err)
ind.err.summary = as.data.frame(rbind(summary(ind.err$error[ind.err$type=="oob"])
                                      ,summary(ind.err$error[ind.err$type=="test"]))) 
rownames(ind.err.summary) <- c("oob","test")
ind.err.summary

# plot error distribution
ggplot(ind.err, aes(x=error,fill=type)) + 
  geom_histogram() + geom_vline(xintercept=crt.err, color="blue") + 
  ggtitle("Error distribution") + theme(plot.title=element_text(face="bold"))

## cumulative errors
## single tree's train error is 0 and, around 1000 trees, the oob error stays similar 0.005 at 2000th tree
## roughly the test errors of the bagged tree is around 0.5, which is well lower than the test error of the single tree (0.74)
## bagging doesn't overestimate and provided better prediction
bgg.oob.err = data.frame(type="oob"
                         ,ntree=1:length(rg$cum.oob.lst.err)
                         ,error=unlist(rg$cum.oob.lst.err))
bgg.tst.err = data.frame(type="test"
                         ,ntree=1:length(rg$cum.tst.lst.err)
                         ,error=unlist(rg$cum.tst.lst.err))
bgg.err = rbind(bgg.oob.err,bgg.tst.err)

# plot bagging errors
ggplot(data=bgg.err,aes(x=ntree,y=error,colour=type)) + 
  geom_line() + geom_abline(intercept=crt.err,slope=0,color="blue") + 
  ggtitle("Bagging error") + theme(plot.title=element_text(face="bold"))

## variable importance
## similar variable importance between the bagged and single tree
## ShelveLoc and Price has the two most importance, the bagged trees may be dependent on them than other methods
# cart
cart.varImp = data.frame(method="cart"
                         ,variable=names(rg$rpt$mod$variable.importance)
                         ,value=rg$rpt$mod$variable.importance/sum(rg$rpt$mod$variable.importance)
                         ,row.names=NULL)
# bagging - lst to se to see 1-SE rule
ntree = length(rg$cum.varImp.lst)
bgg.varImp = data.frame(method="bagging"
                        ,variable=rownames(rg$cum.varImp.lst)
                        ,value=rg$cum.varImp.lst[,ntree])
# plot variable importance measure
rg.varImp = rbind(cart.varImp,bgg.varImp)
rg.varImp$variable = reorder(rg.varImp$variable, 1/rg.varImp$value)
ggplot(data=rg.varImp,aes(x=variable,y=value,fill=method)) + geom_bar(stat="identity")