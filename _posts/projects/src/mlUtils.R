#
# updateCM aims to extend a confusion matrix 
# by adding model errors to the last column and use errors to the last row.
# Both square and non-square matrices are supported
#
# Usage
# set.seed(1)
# actual = ifelse(rnorm(100,0,1)<0,"low","high")
# fitted = ifelse(rnorm(100,1,5)<0,"low","high")
# updateCM(table(actual,fitted))
#
# last modified on Feb 14, 2015
#

updateCM = function(cm, type="Pred") {
  if(class(cm)=="table") {
    if(length(dim(cm)) == 2) {
      if(nrow(cm) > 0) {
        # row wise misclassification
        modelError = function(cm) {
          errors = c()
          # if(square) else(non-square matrix)
          if(nrow(cm)==ncol(cm)) {
            for(i in 1:nrow(cm)) {
              err = (sum(cm[i,]) - sum(cm[i,i])) / sum(cm[i,])
              errors = c(errors,err)
            }
            errors = c(errors,(1-sum(diag(cm))/sum(cm)))             
          } else {
            df = as.data.frame(cm,stringsAsFactors = FALSE)
            colnames(df) = c("row","col","freq")
            for(i in 1:nrow(cm)) {
              freq = tryCatch({
                sum(subset(df,subset=row==rownames(cm)[i] & col==rownames(cm)[i],select=freq))
              },
              error=function(cond) { return(0) }
              )
              err = (sum(cm[i,]) - freq) / sum(cm[i,])
              errors = c(errors,err)
            }            
            freq = tryCatch({
              sum(subset(df,subset=row==col,select=freq))
            },
            error=function(cond) { return(0) }
            )
            errors = c(errors,(1-freq/sum(cm)))            
          } 
          errors
        }    
        # column wise misclassification
        useError = function(cm) {
          errors = c()
          # if(square) else(non-square matrix)
          if(nrow(cm)==ncol(cm)) {
            for(i in 1:ncol(cm)) {
              err = (sum(cm[,i]) - sum(cm[i,i])) / sum(cm[,i])
              errors = c(errors,err)             
            }        
          } else {
            for(i in 1:ncol(cm)) {
              freq = tryCatch({
                sum(subset(df,subset=row==colnames(cm)[i] & col==colnames(cm)[i],select=freq))
              },
              error=function(cond) { return(0) }
              )
              err = (sum(cm[,i]) - freq) / sum(cm[,i])
              errors = c(errors,err)
            }
          }
          errors
        }
        
        # use error added to the last row
        cmUp = rbind(cm,as.table(useError(cm)))
        # model error added to the last column
        cmUp = cbind(cmUp,as.matrix(modelError(cm)))
        rownames(cmUp) = c(paste("actual",rownames(cm),sep=": "),"Use Error")
        colnames(cmUp) = c(paste(type,colnames(cm),sep=": "),"Model Error")  
        round(cmUp,2)        
      } else {
        message("Table has no row")
      }
    }
    else {
      message("Enter a table with 2 variables")
    }
  }
  else {
    message("Enter an object of the 'table' class")
  }
}

#
# regCM() produces a confusion matrix for a continuous response  
# where quantile values of actual data split both actual and fitted response
# Note that it depends on updateCM() and do not include 0 and 1 in probs
#
# Usage
# set.seed(1)
# actual = rnorm(100,0,1)
# fitted = rnorm(100,1,5)
# probs = seq(0.1,0.9,0.1)
# regCM(actual,fitted,probs)
#
# last modified on Feb 14, 2015
#

regCM = function(actual, fitted, probs, type="Pred", ...) {
  if(length(actual[is.na(actual)]) + length(fitted[is.na(fitted)]) > 0) {
    message("Currently NA values are not supported")
  } else {
    probs = sort(round(probs,2))
    conv = function(data,ref,probs) {
      # ref is reference to produce quantile values
      outs = c()
      if(length(probs) == 1) {
        lower = length(data[data<=quantile(ref,probs[1])])
        upper = length(data[data>quantile(ref,probs[1])])
        outs = c(outs,rep(paste0(probs[1]*100,"%-"),lower)
                 ,rep(paste0(probs[1]*100,"%+"),upper))
      } else {
        lower = length(data[data<=quantile(ref,probs[1])])
        outs = c(outs,rep(paste0(probs[1]*100,"%-"),lower))
        for(i in 2:length(probs)) {
          lower = length(data[data<=quantile(ref,probs[i])]) - length(data[data<=quantile(ref,probs[i-1])])
          outs = c(outs,rep(paste0(probs[i]*100,"%-"),lower))
        }
        upper = length(data[data>quantile(ref,probs[length(probs)])])
        outs = c(outs,rep(paste0(probs[length(probs)]*100,"%+"),upper))
      }
      outs
    }
    updateCM(table(conv(actual,actual,probs),conv(fitted,actual,probs)),type)
  }
}

#
# bestParam select best single tunning parameter given measure, error and std of error
# 1 standard error is applied and only 'cptable' of rpart() is tested.
# Note: If caret result, isDesc=FALSE
#
# Usage
# require(ISLR)
# require(rpart)
# set.seed(125)
# mod = rpart(Sales ~ ., data=Carseats, control=rpart.control(cp=0))
# bestParam(mod$cptable,"CP","xerror","xstd")
#
# last modified on Feb 13, 2015
#

bestParam = function(data,param,error,errStd,isDesc=TRUE, ...) {
  # convert name to index
  ind = function(name, df) { match(name, colnames(df)) }
  param = ind(param, data)
  error = ind(error, data)
  errStd = ind(errStd, data)
  # search min error
  from = ifelse(isDesc,1,nrow(data))
  to = ifelse(isDesc,nrow(data),1)
  by = ifelse(isDesc,1,-1)
  pick = c(from,data[from,error],data[from,errStd])
  for(i in seq(from,to,by)) {
    if(data[i,error]<=pick[2]) pick=c(data[i,param],data[i,error],data[i,errStd])
  }
  out = data.frame(lowest=pick,row.names=c("param","error","errStd"))
  # select best param
  best = data[data[,error]<=pick[2]+pick[3],]
  best = if(isDesc) best[1,c(param,error,errStd)] else best[nrow(best),c(param,error,errStd)]
  # correction for caret result
  if(class(best)!="numeric") best = c(t(best))
  out[,2] = data.frame(best=best)
  out
}