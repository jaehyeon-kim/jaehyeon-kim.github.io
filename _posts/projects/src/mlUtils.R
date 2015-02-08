#
# getUpdatedCM aims to extend a confusion matrix 
# by adding model errors to the last column and use errors to the last row.
#
# Usage
# getUpdatedCM(cm)
#
# last modified on Feb 8, 2015
#

getUpdatedCM = function(cm, type="Pred") {
  if(class(cm)=="table") {
    if(nrow(cm) > 0 & length(dim(cm)) > 1) {
      # row wise misclassification
      modelError = function(cm) {
        errors = c()
        for(i in 1:nrow(cm)) {
          err = (sum(cm[i,]) - sum(cm[i,i])) / sum(cm[i,])
          errors = c(errors,err)
        }
        errors = c(errors,(1-sum(diag(cm))/sum(cm)))  
        errors
      }    
      # column wise misclassification
      useError = function(cm) {
        errors = c()
        for(i in 1:ncol(cm)) {
          err = (sum(cm[,i]) - sum(cm[i,i])) / sum(cm[,i])
          errors = c(errors,err)
        }
        errors
      }
      
      # use error added to the last row
      cmUp = rbind(cm,as.table(useError(cm)))
      # model error added to the last column
      cmUp = cbind(cmUp,as.matrix(modelError(cm)))
      rownames(cmUp) = c(paste("Actual",rownames(cm),sep=": "),"Use Error")
      colnames(cmUp) = c(paste(type,colnames(cm),sep=": "),"Model Error")  
      round(cmUp,2)
    }
    else {
      message("Enter a square table")
    }
  }
  else {
    message("Enter an object of the 'table' class")
  }
}