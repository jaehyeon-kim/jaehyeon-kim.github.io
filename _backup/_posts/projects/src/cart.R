#
# 4 constructor functions are included and they create S3 objects of the CART model
# by the rpart, caret and mlr packages - the last two extends the first. They are 
#
# - cartRPART()
# - cartCARET()
# - cartMLR()
# - cartDT()
#
# Both classification and regression are supported. Together with the relevant packages,
# some utility functions should be sourced and the source can be found in the following link.
# https://gist.github.com/jaehyeon-kim/5622ae9fa982e0b46550
# 
# Their usage can be found in
# cartRPART()
# - http://jaehyeon-kim.github.io/r/2015/02/21/Quick-Trial-of-Turning-Analysis-into-S3-Object/
# cartCARET() and cartMLR()
# - http://jaehyeon-kim.github.io/r/2015/02/23/Tree-Based-Methods-Part-IV-Packages-Comparison-in-S3/
# cartDT()
# - http://jaehyeon-kim.github.io/r/2015/03/03/2nd-Trial-of-Turning-Analysis-into-S3-Object/
#
# last modified on Mar 3, 2015
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
      err = cm.up[nrow(cm.up),ncol(cm.up)]
    } else {
      ftd = predict(fit, newdata=data)
      cm.up = regCM(data[,res.ind],ftd,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
      err = round(sqrt(sum(data[,res.ind]-ftd)^2/length(data[,res.ind])),6)
    }
    error = list(pkg="rpart",isTest=isTest,isSE=isSE,cp=round(param,4),error=err)
    list(ftd=ftd,cm=cm.up,error=error)
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
                     ,fitInd=FALSE, tuneLen=30, method="repeatedcv", nDiv=10, nRep=5) {
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
      rpt = cartRPART(trainData,testData,formula=formula)
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
      err = cm.up[nrow(cm.up),ncol(cm.up)]
    } else {
      cm.up = regCM(data[,res.ind],ftd,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
      err = round(sqrt(sum(data[,res.ind]-ftd)^2/length(data[,res.ind])),6)
    }
    error = list(pkg="caret",isTest=isTest,isSE=isSE,cp=round(param,4),error=err)
    list(ftd=ftd,cm=cm.up,error=error)
  }
  train.perf.lst = perf(mod,trainData,res.name,cp,FALSE,FALSE)
  if(!is.null(testData)) {
    test.perf.lst = perf(mod,testData,res.name,cp,TRUE,FALSE)
  } else {
    test.perf.lst = ls()
  }    
  # update results
  result = list(rpt=rpt,mod=mod,cp=cp,train.lst=train.perf.lst,test.lst=test.perf.lst)
  # add class name
  class(result) = c("rpartExtCrt","rpartExt")
  return(result)
}

## create modCARET class
cartMLR = function(trainData, testData=NULL, formula
                   ,fitInd=FALSE, tuneLen=30, method="RepCV", nDiv=10, nRep=5) {
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
      rpt = cartRPART(trainData,testData,formula=formula)
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
      err = cm.up[nrow(cm.up),ncol(cm.up)]
    } else {
      cm.up = regCM(data[,res.ind],ftd$response,probs=c(0.25,0.5,0.75),ifelse(isTest,"Ptd","Ftd"))
      err = round(sqrt(sum(data[,res.ind]-ftd$response)^2/length(data[,res.ind])),6)
    }
    error = list(pkg="mlr",isTest=isTest,isSE=isSE,cp=round(param,4),error=err)
    list(ftd=ftd,cm=cm.up,error=error)
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

cartDT = function(trainData, testData=NULL, formula, ntree = 2, isStratify = FALSE, ...) {
  if(class(trainData) != "data.frame" & ifelse(is.null(testData),TRUE,class(testData)=="data.frame"))
    stop("data frames should be entered for train and test (if any) data")  
  # extract response name and index
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(trainData))
  if(res.name %in% colnames(trainData) == FALSE)
    stop("response is not found in train data")
  if(!class(trainData[,res.ind]) %in% c("factor","numeric"))
    stop("response should be either factor or numeric")
  if(!("rpart" %in% rownames(installed.packages()) & "mlr" %in% rownames(installed.packages())))
    stop("rpart or mlr package is not installed")  
  # source classes and utilities
  source("src/cart.R")
  source("src/mlUtils.R")
  # create base class
  rpt = tryCatch({
    cartRPART(trainData,testData,formula=formula)
  },
  error=function(cond) {
    message("cartRPART is not sourced")
    list()
  })
  
  require(rpart)
  require(mlr)
  ## set up variables
  # cp values to keet at each sample at lowest xerror and by 1-SE rule
  mge.boot.cp = data.frame(measure=c("lowest","best"))
  # variable importance at each sample
  # standardized individual and cummulative variable importance will also be calculated below
  mge.varImp.lst = data.frame(var=colnames(trainData[,-res.ind]))
  mge.varImp.se = mge.varImp.lst
  # oob response and fitted values at each sample
  mge.oob.lst = data.frame(ind=as.numeric(rownames(trainData)),res=trainData[,res.ind])
  mge.oob.se = mge.oob.lst
  # test response and fitted values at each sample
  if(!is.null(testData)) {
    mge.tst.lst = data.frame(ind=as.numeric(rownames(testData)),res=testData[,res.ind])
    mge.tst.se = mge.tst.lst
  }
  ## split data and fit model on in-bag sample
  # some samples that cause an error to obtain cp values will be discarded - create sample recursively
  cnt = 0
  while(cnt < ntree) {
    # create resample description and task
    if(class(trainData[,res.ind]) != "factor") {
      boot.desc = makeResampleDesc(method="Bootstrap", stratify=FALSE, iters=1)
      boot.task = makeRegrTask(data=trainData,target=res.name)
    } else {
      boot.desc = makeResampleDesc(method="Bootstrap", stratify=isStratify, iters=1)
      boot.task = makeClassifTask(data=trainData,target=res.name)
    }
    # create bootstrap instance and split data - in-bag and out-of-bag
    boot.ins = makeResampleInstance(desc=boot.desc, task=boot.task) 
    trn.in = trainData[boot.ins$train.inds[[1]],]
    trn.oob = trainData[boot.ins$test.inds[[1]],]
    # fit model on in-bag sample
    mod = rpart(formula=formula, data=trn.in, control=rpart.control(cp=0))
    cp = tryCatch({
      unlist(bestParam(mod$cptable,"CP","xerror","xstd")[1,1:2])
    },
    error=function(cond) { 
      message("cp fails to be generated. The sample is discarded.")
      cp = c(0,0)
    })
    # take sample only if cp values are obtained
    if(sum(cp) != 0) {
      cnt = cnt + 1
      message(paste("Current sample:",cnt))
      colName = paste("s",cnt,sep=".")
      ## update cp
      boot.cp = data.frame(names(cp),cp)
      colnames(boot.cp) = c("measure",colName)
      mge.boot.cp = merge(mge.boot.cp,boot.cp,by="measure",all=TRUE)
      ## update variable importance with cps at least xerror and 1-SE rule
      # lst
      prune.lst = prune(mod, cp=cp[1])
      varImp.lst = data.frame(names(prune.lst$variable.importance),prune.lst$variable.importance)
      colnames(varImp.lst) = c("var",colName)
      mge.varImp.lst = merge(mge.varImp.lst,varImp.lst,by="var",all=TRUE)
      # se
      prune.se = prune(mod, cp=cp[2])
      varImp.se = data.frame(names(prune.se$variable.importance),prune.se$variable.importance)
      colnames(varImp.se) = c("var",colName)
      mge.varImp.se = merge(mge.varImp.se, varImp.se, by="var",all=TRUE)
      ## function to generate fitted values df
      fitData = function(model, data, response, count, col.name) {
        ind = match(response, colnames(data))
        type = ifelse(class(data[,ind])=="factor","class","vector")
        fit = predict(model, newdata=data, type=type)
        fitDF = data.frame(as.numeric(names(fit)),fit,row.names=NULL)
        colnames(fitDF) = c("ind",col.name)
        fitDF
      }
      ## update oob fitted and response values    
      # lst
      fit.oob.lst = fitData(prune.lst, trn.oob, res.name, cnt, colName)
      mge.oob.lst = merge(mge.oob.lst,fit.oob.lst,by="ind",all=TRUE)
      # se
      fit.oob.se = fitData(prune.se, trn.oob, res.name, cnt, colName)
      mge.oob.se = merge(mge.oob.se,fit.oob.se,by="ind",all=TRUE)
      ## update test fitted and response values
      if(!is.null(testData)) {
        # lst
        fit.tst.lst = fitData(prune.lst, testData, res.name, cnt, colName)
        mge.tst.lst = merge(mge.tst.lst, fit.tst.lst, by="ind", all=TRUE)
        # se
        fit.tst.se = fitData(prune.se, testData, res.name, cnt, colName)
        mge.tst.se = merge(mge.tst.se, fit.tst.se, by="ind", all=TRUE)
      }
    }
  } # end of while
  ## update cp values data frame
  message("Update cp values")
  rownames(mge.boot.cp) = mge.boot.cp[,1]
  mge.boot.cp = mge.boot.cp[,2:ncol(mge.boot.cp)]
  ## update individual and cumulative variable importance
  message("Update variable importance")
  # lst
  if(ncol(mge.varImp.lst) > 0) {
    # remove variable colume at col 1
    rownames(mge.varImp.lst) = mge.varImp.lst[,1]
    mge.varImp.lst = mge.varImp.lst[,2:ncol(mge.varImp.lst)]
    # create ind and cum varImp data frames
    ind.varImp.lst = as.data.frame(apply(mge.varImp.lst,2,function(x) {rep(0,times=nrow(mge.varImp.lst))}))
    rownames(ind.varImp.lst) = rownames(mge.varImp.lst)
    cum.varImp.lst = ind.varImp.lst
    for(i in 1:ncol(mge.varImp.lst)) {
      ind.varImp.lst[,i] = mge.varImp.lst[,i]/sum(mge.varImp.lst[,i],na.rm=TRUE)
      if(i==1) cum.varImp.lst[,i] = ind.varImp.lst[,i]
      else cum.varImp.lst[,i] = rowSums(mge.varImp.lst[,1:i],na.rm=TRUE)/sum(mge.varImp.lst[,1:i],na.rm=TRUE)
    }
  }
  # se
  if(ncol(mge.varImp.se) > 0) {
    # remove variable colume at col 1
    rownames(mge.varImp.se) = mge.varImp.se[,1]
    mge.varImp.se = mge.varImp.se[,2:ncol(mge.varImp.se)]
    # create ind and cum varImp data frames
    ind.varImp.se = as.data.frame(apply(mge.varImp.se,2,function(x) {rep(0,times=nrow(mge.varImp.se))}))
    rownames(ind.varImp.se) = rownames(mge.varImp.se)
    cum.varImp.se = ind.varImp.se
    for(i in 1:ncol(mge.varImp.se)) {
      ind.varImp.se[,i] = mge.varImp.se[,i]/sum(mge.varImp.se[,i],na.rm=TRUE)
      if(i==1) cum.varImp.se[,i] = ind.varImp.se[,i]
      else cum.varImp.se[,i] = rowSums(mge.varImp.se[,1:i],na.rm=TRUE)/sum(mge.varImp.se[,1:i],na.rm=TRUE)
    }
  }
  ## update fitted values (individual, cumulative) and errors (mmce, rmse)
  # function to update fitted values - majority vote or average
  retCum = function(fit) {
    if(ncol(fit) < 2) {
      message("no fitted values")
      cum.fit = fit
    } else {
      cum.fit = as.data.frame(apply(fit,2,function(x) { rep(0,times=(nrow(fit))) }))
      cum.fit[,1:2] = fit[,1:2]
      rownames(cum.fit) = rownames(fit)
      for(i in 3:ncol(fit)) {
        if(class(fit[,1])=="factor") {
          retVote = function(x) {
            tbls = apply(x,1,as.data.frame)
            tbls = lapply(tbls,table)
            ret = function(x) {
              if(length(x)==0) NA 
              else if(length(x)==1) names(x) 
              else if(max(x)==min(x)) NA 
              else names(x[x==max(x)])
            }
            maxVal = sapply(tbls,ret)
            maxVal
          }
          cum.fit[,i] = retVote(fit[,2:i]) # retVote already vectorized
        } else {
          cum.fit[,i] = apply(fit[,2:i],1,mean,na.rm=TRUE)
        }
      }  
    }
    cum.fit
  }  
  # function to updated errors - mmce or rmse
  retErr = function(fit) {
    err = data.frame(t(rep(0,times=ncol(fit))))
    colnames(err)=colnames(fit)
    for(i in 2:ncol(fit)) {
      cmpt = complete.cases(fit[,1],fit[,i])
      if(class(fit[,1])=="factor") {
        tbl=table(fit[cmpt,1],fit[cmpt,i])
        err[i] = 1 - sum(diag(tbl))/sum(tbl)
      } else {
        err[i] = sqrt(sum(fit[cmpt,1]-fit[cmpt,i])^2/length(fit[cmpt,1]))
      }    
    }
    err[2:length(err)]
  }
  # function to combine jobs
  combine = function(ind.fit) {
    if(ncol(ind.fit) > 0) {
      # set row names from values of index column and remove the index column 
      rownames(ind.fit) = ind.fit[,1]
      ind.fit = ind.fit[,-1]
      # update fitted values - majority vote or average
      cum.fit = retCum(ind.fit)
      # update error - mmce or rmse
      ind.fit.err = retErr(ind.fit)
      cum.fit.err = retErr(cum.fit)
    } else {
      cum.fit = NA
      ind.fit.err = NA
      cum.fit.err = NA
    }
    list(ind.fit,cum.fit,ind.fit.err,cum.fit.err)
  }
  ## update individual elements
  message("Update oob lst")
  # oob lst
  com.oob.lst = combine(mge.oob.lst)
  mge.oob.lst = com.oob.lst[[1]]
  cum.oob.lst = com.oob.lst[[2]]
  mge.oob.lst.err = com.oob.lst[[3]]
  cum.oob.lst.err = com.oob.lst[[4]]  
  # oob se
  message("Update oob se")
  com.oob.se = combine(mge.oob.se)
  mge.oob.se = com.oob.se[[1]]
  cum.oob.se = com.oob.se[[2]]
  mge.oob.se.err = com.oob.se[[3]]
  cum.oob.se.err = com.oob.se[[4]]
  
  if(!is.null(testData)) {
    # test lst
    message("Update test lst")
    com.tst.lst = combine(mge.tst.lst)
    mge.tst.lst = com.tst.lst[[1]]
    cum.tst.lst = com.tst.lst[[2]]
    mge.tst.lst.err = com.tst.lst[[3]]
    cum.tst.lst.err = com.tst.lst[[4]]
    # test se
    message("Update test se")
    com.tst.se = combine(mge.tst.se)
    mge.tst.se = com.tst.se[[1]]
    cum.tst.se = com.tst.se[[2]]
    mge.tst.se.err = com.tst.se[[3]]
    cum.tst.se.err = com.tst.se[[4]]
  }
  
  ## create result
  if(!is.null(testData)) {
    result = list(rpt=rpt, boot.cp=mge.boot.cp
                  ,varImp.lst=mge.varImp.lst, ind.varImp.lst=ind.varImp.lst, cum.varImp.lst=cum.varImp.lst
                  ,varImp.se=mge.varImp.se, ind.varImp.se=ind.varImp.se, cum.varImp.se=cum.varImp.se
                  ,ind.oob.lst=mge.oob.lst, ind.oob.lst.err=mge.oob.lst.err
                  ,cum.oob.lst=cum.oob.lst, cum.oob.lst.err=cum.oob.lst.err
                  ,ind.oob.se=mge.oob.se, ind.oob.se.err=mge.oob.se.err
                  ,cum.oob.se=cum.oob.se, cum.oob.se.err=cum.oob.se.err
                  ,ind.tst.lst=mge.tst.lst, ind.tst.lst.err=mge.tst.lst.err
                  ,cum.tst.lst=cum.tst.lst, cum.tst.lst.err=cum.tst.lst.err
                  ,ind.tst.se=mge.tst.se, ind.tst.se.err=mge.tst.se.err
                  ,cum.tst.se=cum.tst.se, cum.tst.se.err=cum.tst.se.err)
  } else {
    result = list(rpt=rpt, boot.cp=mge.boot.cp
                  ,varImp.lst=mge.varImp.lst, ind.varImp.lst=ind.varImp.lst, cum.varImp.lst=cum.varImp.lst
                  ,varImp.se=mge.varImp.se, ind.varImp.se=ind.varImp.se, cum.varImp.se=cum.varImp.se
                  ,ind.oob.lst=mge.oob.lst, ind.oob.lst.err=mge.oob.lst.err
                  ,cum.oob.lst=cum.oob.lst, cum.oob.lst.err=cum.oob.lst.err
                  ,ind.oob.se=mge.oob.se, ind.oob.se.err=mge.oob.se.err
                  ,cum.oob.se=cum.oob.se, cum.oob.se.err=cum.oob.se.err)
  }
  class(result) = c("rpartDT","rpartExt")
  return(result)
}