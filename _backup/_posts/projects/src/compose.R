library(data.table)
set.seed(1237)
dt<-data.table(id=sample(5,size=100,replace=T),
               grp=letters[sample(4,size=100,replace=T)])

# original requirement
dt[,prop.table(table(grp,id,useNA="always"),margin=1)]

# implementation by function composition
compose <- function(f, g, margin = 1) {
  function(...) f(g(...), margin)
}

prop <- compose(prop.table, table)
dt[,prop(grp, id, useNA = "always")]

# another solution
prop2 <- function(...){
  dots <- list(...)
  passed <- names(dots)
  # filter args based on prop.table's formals
  args <- passed %in% names(formals(prop.table))
  do.call('prop.table', c(list(do.call('table', dots[!args])), dots[args]))
}

dt[,prop2(grp,id,useNA="always",margin=1)]

m <- matrix(1:4, 2)
m
prop.table(m, 1)