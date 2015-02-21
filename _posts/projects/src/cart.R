#
# 3 constructor functions are included and they create S3 objects of the CART model
# by the rpart, caret and mlr packages - the last two extends the first. They are 
#
# - cartRPART()
# - cartCARET()
# - cartMLR()
#
# Both classification and regression are supported. Together with the relevant packages,
# some utility functions should be sourced and the source can be found in the following link.
# https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550
# 
# Their usage can be found in
# link 1
# link 2
#
# last modified on Feb 21, 2015
#
cartRPART = function(trainData, testData=NULL, formula, ...) {
  if(class(trainData) != "data.frame" & ifelse(is.null(testData),TRUE,class(testData)=="data.frame"))
    stop("data frames should be entered for train and test (if any) data")  
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  if(res.name %in% colnames(trainData) == FALSE)
    stop("response is not found in train data")
  if(class(trainData[,res.ind]) != "factor") {
    if(class(trainData[,res.ind]) != "numeric") {
      stop("response should be either numeric or factor")
    }
  } 
  if("rpart" %in% rownames(installed.packages()) == FALSE)
    stop("rpart package is not installed")
  
  ## import utility functions
  source("src/mlUtils.R")
  
  require(rpart)
  # rpart model - $mod (1)
  mod = rpart(formula=formula, data=trainData, control=rpart.control(cp=0))
  # min/best cp - $cp (2)
  cp = bestParam(mod$cptable,"CP","xerror","xstd")
  # performance
  perf = function(model,data,response,params,isTest=TRUE,isSE=TRUE) {
    param = ifelse(isSE,params[1,2],params[1,1])
    fit = prune(model, cp=param)
    if(class(trainData[,res.ind]) == "factor") {
      ftd = predict(fit, newdata=data, type="class")
      cm = table(actual=data[,res.ind], fitted=ftd)
      cm.up = updateCM(cm,type=ifelse(isTest,"Ptd","Ftd"))
    } else {
      ftd = predict(fit, newdata=data)
      cm.up = regCM(data[,res.ind],ftd,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
    }
    mmce = list(pkg="rpart",isTest=isTest,isSE=isSE
                ,cp=round(param,4),mmce=cm.up[nrow(cm.up),ncol(cm.up)])
    list(ftd=ftd,cm=cm.up,mmce=mmce)
  }
  # $train.lst (3)
  train.perf.lst = perf(mod,trainData,res.name,cp,FALSE,FALSE)
  # $train.se (4)
  train.perf.se = perf(mod,trainData,res.name,cp,FALSE,TRUE)
  if(!is.null(testData)) {
    # $test.lst (5)
    test.perf.lst = perf(mod,testData,res.name,cp,TRUE,FALSE)
    # $test.se (6)
    test.perf.se = perf(mod,testData,res.name,cp,TRUE,TRUE)
  } else {
    test.perf.lst = ls()
    test.perf.se = ls()
  }    
  # update results
  result = list(mod=mod,cp=cp
                ,train.lst=train.perf.lst,train.se=train.perf.se
                ,test.lst=test.perf.lst,test.se=test.perf.se)
  # add class name
  class(result) = "rpartExt"
  return(result)
}

# extend plot method
plot.rpartExt = function(x, ...) {
  require(ggplot2)
  obj = x
  df = as.data.frame(obj$mod$cptable)
  params = obj$cp
  # params should be exported into global environment
  # otherwise geom_point() causes an error without identifying x and y
  .GlobalEnv$params = params
  ubound = ifelse(params[2,1]+params[3,1]>max(df$xerror),max(df$xerror),params[2,1]+params[3,1])
  lbound = ifelse(params[2,1]-params[3,1]<min(df$xerror),min(df$xerror),params[2,1]-params[3,1])
  plot.obj = ggplot(data=df[1:nrow(df),], aes(x=CP,y=xerror)) + 
    scale_x_continuous() + scale_y_continuous() + 
    geom_line() + geom_point() +   
    geom_abline(intercept=ubound,slope=0, color="purple") + 
    geom_abline(intercept=lbound,slope=0, color="purple") + 
    geom_point(aes(x=params[1,2],y=params[2,2]),color="red",size=3) + 
    geom_point(aes(x=params[1,1],y=params[2,1]),color="blue",size=3)
  plot.obj
}

## create modCARET class
cartCARET = function(trainData, testData=NULL, formula
                     ,fitInd=FALSE, tuneLen=20, method="repeatedcv", nDiv=10, nRep=5) {
  if(class(trainData) != "data.frame" & ifelse(is.null(testData),TRUE,class(testData)=="data.frame"))
    stop("data frames should be entered for train and test (if any) data")
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  if(res.name %in% colnames(trainData) == FALSE)
    stop("response is not found in train data")
  if(class(trainData[,res.ind]) != "factor") {
    if(class(trainData[,res.ind]) != "numeric") {
      stop("response should be either numeric or factor")
    }
  } 
  if("rpart" %in% rownames(installed.packages()) == FALSE)
    stop("rpart package is not installed")
  if("caret" %in% rownames(installed.packages()) == FALSE)
    stop("caret package is not installed")  
  
  # fit by rpart package if necessary
  if(fitInd) {
    if(!is.null(ls()[ls()=="cartRPART"])) {
      rpt = cartRPART(trainData,testData,formula="High ~ .")
    } else {
      message("cartRPART is not found")
      message("data is not fit by rpart")
      rpt = ls()
    }
  } else {
    message("data is not fit by rpart")
    rpt = ls()
  }
  
  ## import utility functions
  source("src/mlUtils.R")
  
  # fit by caret package
  require(caret)
  # trControl/train to be updated to accomodate other variables
  trCtrl = trainControl(method=method, number=nDiv, repeats=nRep)
  res.ind = match(res.name, colnames(trainData))
  mod = caret::train(form=as.formula(formula)
                     ,data=trainData
                     ,method="rpart"
                     ,tuneLength=tuneLen
                     ,trControl=trCtrl)
  cp = mod$bestTune$cp
  # performance
  perf = function(model,data,response,param,isTest=TRUE,isSE=TRUE) {
    ftd = predict(model, newdata=data)    
    if(class(data[,res.ind])=="factor") {
      cm = table(actual=data[,res.ind], fitted=ftd)
      cm.up = updateCM(cm,type=ifelse(isTest,"Ptd","Ftd"))      
    } else {
      cm.up = regCM(data[,res.ind],ftd,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
    }
    mmce = list(pkg="caret",isTest=isTest,isSE=isSE
                ,cp=round(param,4),mmce=cm.up[nrow(cm.up),ncol(cm.up)])
    list(ftd=ftd,cm=cm.up,mmce=mmce)
  }
  train.perf.lst = perf(mod,trainData,res.name,cp,FALSE,FALSE)
  if(!is.null(testData)) {
    test.perf.lst = perf(mod,testData,res.name,cp,TRUE,FALSE)
  } else {
    test.perf.lst = ls()
  }    
  # update results
  result = list(rpt=rpt,mod=mod,cp=cp
                ,train.lst=train.perf.lst,test.lst=test.perf.lst)
  # add class name
  class(result) = c("rpartExtCrt","rpartExt")
  return(result)
}

## create modCARET class
cartMLR = function(trainData, testData=NULL, formula
                   ,fitInd=FALSE, tuneLen=20, method="RepCV", nDiv=10, nRep=5) {
  if(class(trainData) != "data.frame" & ifelse(is.null(testData),TRUE,class(testData)=="data.frame"))
    stop("data frames should be entered for train and test (if any) data")
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  if(res.name %in% colnames(trainData) == FALSE)
    stop("response is not found in train data")
  if(class(trainData[,res.ind]) != "factor") {
    if(class(trainData[,res.ind]) != "numeric") {
      stop("response should be either numeric or factor")
    }
  } 
  if("rpart" %in% rownames(installed.packages()) == FALSE)
    stop("rpart package is not installed")
  if("mlr" %in% rownames(installed.packages()) == FALSE)
    stop("mlr package is not installed")  
  
  # fit by rpart package if necessary
  if(fitInd) {
    if(!is.null(ls()[ls()=="cartRPART"])) {
      rpt = cartRPART(trainData,testData,formula="High ~ .")
    } else {
      message("cartRPART is not found")
      message("data is not fit by rpart")
      rpt = ls()
    }
  } else {
    message("data is not fit by rpart")
    rpt = ls()
  }
  
  ## import utility functions
  source("src/mlUtils.R")
  
  # fit by mlr package
  require(mlr)
  if(class(trainData[,res.ind]) == "factor") {
    tsk = makeClassifTask(data=trainData,target=res.name)
    lrn = makeLearner("classif.rpart",par.vals=list(cp=0))
  } else {
    tsk = makeRegrTask(data=trainData,target=res.name)
    lrn = makeLearner("regr.rpart",par.vals=list(cp=0))
  }
  
  # tune parameter
  cpGrid = function(index) {
    start=0
    end=0.3
    len=tuneLen
    inc = (end-start)/len
    grid = c(start)
    while(start < end) {
      start = start + inc
      grid = c(grid,start)
    } 
    grid[index]
  }
  paramSet = makeParamSet(
    makeNumericParam("cp",lower=1,upper=tuneLen,trafo=cpGrid)
  )
  tuneCtrl = makeTuneControlGrid(resolution=c(cp=(tuneLen)))
  # tune cp
  if(class(trainData[,res.ind]) == "factor") {
    resampleDesc = makeResampleDesc(method,reps=nRep,folds=nDiv,stratify=TRUE)
  } else {
    resampleDesc = makeResampleDesc(method,reps=nRep,folds=nDiv)
  }
  tune = tuneParams(learner=lrn, task=tsk, resampling=resampleDesc, par.set=paramSet, control=tuneCtrl)
  # update cp
  lrn = setHyperPars(lrn,par.vals=tune$x)
  # train model
  mod = train(lrn, tsk)  
  cp = tune$x
  # performance
  perf = function(model,data,response,param,isTest=TRUE,isSE=TRUE) {
    ftd = predict(mod, newdata=data)$data
    if(class(data[,res.ind]) == "factor") {
      cm = table(actual=ftd$truth, fitted=ftd$response)
      cm.up = updateCM(cm,type=ifelse(isTest,"Ptd","Ftd"))      
    } else {
      cm.up = regCM(ftd$truth,ftd$response,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
    }
    mmce = list(pkg="mlr",isTest=isTest,isSE=isSE
                ,cp=round(param,4),mmce=cm.up[nrow(cm.up),ncol(cm.up)])
    list(ftd=ftd,cm=cm.up,mmce=mmce)
  }
  train.perf.lst = perf(mod,trainData,res.name,cp[[1]],FALSE,FALSE)
  if(!is.null(testData)) {
    test.perf.lst = perf(mod,testData,res.name,cp[[1]],TRUE,FALSE)
  } else {
    test.perf.lst = ls()
  }    
  # update results
  result = list(rpt=rpt,task=tsk,learner=lrn,mod=mod,cp=cp
                ,train.lst=train.perf.lst,test.lst=test.perf.lst)
  # add class name
  class(result) = c("rpartExtMlr","rpartExt")
  return(result)
}