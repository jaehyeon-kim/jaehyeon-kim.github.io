library(parallel)
library(doParallel)
library(rpart)
library(randomForest)
library(caret)

# function to set up random seeds
setSeeds <- function(method = "cv", numbers = 1, repeats = 1, tunes = NULL, seed = 1237) {
  #B is the number of resamples and integer vector of M (numbers + tune length if any)
  B <- if (method == "cv") numbers
  else if(method == "repeatedcv") numbers * repeats
  else NULL
  
  if(is.null(length)) {
    seeds <- NULL
  } else {
    set.seed(seed = seed)
    seeds <- vector(mode = "list", length = B)
    seeds <- lapply(seeds, function(x) sample.int(n = 1000000, size = numbers + ifelse(is.null(tunes), 0, tunes)))
    seeds[[length(seeds) + 1]] <- sample.int(n = 1000000, size = 1)
  }
  # return seeds
  seeds
}

# control variables
numbers <- 3
repeats <- 5
cvTunes <- 4 # tune mtry for random forest
rcvTunes <- 12 # tune nearest neighbor for KNN
seed <- 1237

# set up seeds
# cross validation
cvSeeds <- setSeeds(method = "cv", numbers = numbers, tunes = cvTunes, seed = seed)
c('B + 1' = length(cvSeeds), M = length(cvSeeds[[1]]))
cvSeeds[c(1, length(cvSeeds))]

# repeated cross validation
rcvSeeds <- setSeeds(method = "repeatedcv", numbers = numbers, repeats = repeats, tunes = rcvTunes, seed = seed)
c('B + 1' = length(rcvSeeds), M = length(rcvSeeds[[1]]))
rcvSeeds[c(1, length(rcvSeeds))]

# cross validation
cvCtrl <- trainControl(method = "cv", number = numbers, classProbs = TRUE, savePredictions = TRUE, seeds = cvSeeds)

# repeated cross validation
rcvCtrl <- trainControl(method = "repeatedcv", number = numbers, repeats = repeats, classProbs = TRUE, savePredictions = TRUE, seeds = rcvSeeds)

# compare objects
# repeated cross validation
cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
KNN1 <- train(Species ~ ., data = iris, method = "knn", tuneLength = rcvTunes, trControl = rcvCtrl)
stopCluster(cl)

cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
KNN2 <- train(Species ~ ., data = iris, method = "knn", tuneLength = rcvTunes, trControl = rcvCtrl)
stopCluster(cl)

# same outcome, difference only in times element
all.equal(KNN1$results[KNN1$results$k == KNN1$bestTune[[1]],], 
          KNN2$results[KNN2$results$k == KNN2$bestTune[[1]],])
all.equal(KNN1, KNN2)

# cross validation
cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
rf1 <- train(Species ~ ., data = iris, method = "rf", ntree = 100,
             tuneGrid = expand.grid(mtry = seq(1, 2 * as.integer(sqrt(ncol(iris) - 1)), by = 1)),
             importance = TRUE, trControl = cvCtrl)
stopCluster(cl)

cl <- makeCluster(detectCores())
registerDoParallel(cl)
set.seed(1)
rf2 <- train(Species ~ ., data = iris, method = "rf", ntree = 100,
             tuneGrid = expand.grid(mtry = seq(1, 2 * as.integer(sqrt(ncol(iris) - 1)), by = 1)),
             importance = TRUE, trControl = cvCtrl)
stopCluster(cl)

# same outcome, difference only in times element
all.equal(rf1$results[rf1$results$mtry == rf1$bestTune[[1]],], 
          rf2$results[rf2$results$mtry == rf2$bestTune[[1]],])
all.equal(rf1, rf2)