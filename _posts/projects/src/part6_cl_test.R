## data
require(ISLR)
data(Carseats)
require(dplyr)
Carseats = Carseats %>% 
  mutate(High=factor(ifelse(Sales<=8,"No","High"),labels=c("High","No")))
data.cl = subset(Carseats, select=c(-Sales))
data.rg = subset(Carseats, select=c(-High))

## import constructors
source("src/cart.R")

# split data
require(caret)
set.seed(1237)
trainIndex = createDataPartition(Carseats$High, p=0.8, list=FALSE, times=1)
trainData.cl = data.cl[trainIndex,]
testData.cl = data.cl[-trainIndex,]

## run rpartDT
set.seed(12357)
cl = cartDT(trainData.cl, testData.cl, "High ~ .", ntree=500)

## cp values
# cart
cl$rpt$cp[1,][[1]]
# bagging
summary(t(cl$boot.cp)[,2])

## individual errors
# cart test error
crt.err = cl$rpt$test.lst$error$error
crt.err

## single tree's train and test errors are quite lower
## for oob error, 2.3 sd away / for test error, 1.4 sd away
## if the mean of oob errors approximately equals to poterior means, the train error rate of the single tree may be unreasonable
(mean(unlist(cl$ind.oob.lst.err)) - crt.err)/sd(unlist(cl$ind.oob.lst.err))
(mean(unlist(cl$ind.tst.lst.err)) - crt.err)/sd(unlist(cl$ind.tst.lst.err))

# bagging error at least xerror - se to see 1-SE rule
ind.oob.err = data.frame(type="oob",error=unlist(cl$ind.oob.lst.err))
ind.tst.err = data.frame(type="test",error=unlist(cl$ind.tst.lst.err))
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
## for oob error, the bagging error stays around 0.225, which is well over the training error of 0.16
## for test error, the bagging error converges to around 0.164, which is lower than 0.19
## bagging doesn't overestimate and provided better prediction
bgg.oob.err = data.frame(type="oob"
                         ,ntree=1:length(cl$cum.oob.lst.err)
                         ,error=unlist(cl$cum.oob.lst.err))
bgg.tst.err = data.frame(type="test"
                         ,ntree=1:length(cl$cum.tst.lst.err)
                         ,error=unlist(cl$cum.tst.lst.err))
bgg.err = rbind(bgg.oob.err,bgg.tst.err)

# plot bagging errors
ggplot(data=bgg.err,aes(x=ntree,y=error,colour=type)) + 
  geom_line() + geom_abline(intercept=crt.err,slope=0,color="blue") + 
  ggtitle("Bagging error") + theme(plot.title=element_text(face="bold"))

## variable importance
## variable importance is somewhat different - US, Urban and Education are rarely considered in the single tree
# cart
cart.varImp = data.frame(method="cart"
                         ,variable=names(cl$rpt$mod$variable.importance)
                         ,value=cl$rpt$mod$variable.importance/sum(cl$rpt$mod$variable.importance)
                         ,row.names=NULL)
# bagging
ntree = length(cl$cum.varImp.lst)
bgg.varImp = data.frame(method="bagging"
                        ,variable=rownames(cl$cum.varImp.lst)
                        ,value=cl$cum.varImp.lst[,ntree])
# plot variable importance measure
cl.varImp = rbind(cart.varImp,bgg.varImp)
cl.varImp$variable = reorder(cl.varImp$variable, 1/cl.varImp$value)
ggplot(data=cl.varImp,aes(x=variable,y=value,fill=method)) + geom_bar(stat="identity") + 
  ggtitle("Variable importance") + theme(plot.title=element_text(face="bold"))

