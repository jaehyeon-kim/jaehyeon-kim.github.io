library(rpart)

## data
set.seed(1237)
x <- matrix(runif(500), 100)
y <- runif(100)

data <- as.data.frame(cbind(y, x))
names(data) <- c("y","x1","x2","x3","x4","x5")

## functional
functional <- function(f, ...) {
  f(...)
}

functional(f = lm, formula = y ~ ., data = data)
functional(f = glm, formula = y ~ ., data = data, family = gaussian)
functional(f = rpart, formula = y ~ ., data = data, control = rpart.control(cp = 0))

## closure + functional
ntrial <- 100
bootstrapper <- function(formula, data, ntrial) {
  # check if response is found
  res.name = gsub(" ","",unlist(strsplit(formula,split="~"))[[1]])
  res.ind = match(res.name, colnames(data))
  
  function(f, ...) {
    lapply(1:ntrial, function(i) {
      # do bootstrap
      bag <- sample(nrow(data), size = nrow(data), replace = TRUE)
      model <- f(formula = formula, data = data[bag,], ...)
      fitted <- predict(model)
      actual <- data[bag, res.ind]
      error <- if(class(actual) == "numeric") {
        sqrt(sum((fitted - actual)^2) / length(actual))
      } else {
        1 - diag(table(actual, fitted)) / sum(table(actual, fitted))
      }
      
      list(model = model, error = error)      
    })
  }
}

boot_configure <- bootstrapper(formula = "y ~ .", data = data, ntrial = ntrial)

set.seed(1237)
boot_lm <- boot_configure(lm)
mean(do.call(c, lapply(boot_lm, function(x) x$error)))

set.seed(1237)
boot_cart <- boot_configure(rpart)
mean(do.call(c, lapply(boot_cart, function(x) x$error)))
