library(lubridate)
library(data.table)
library(plyr)
library(dplyr)

set.seed(1237) 
trial <- 10000
names <- sample(read.table("http://deron.meranda.us/data/census-derived-all-first.txt")[,1], trial, replace = T)
states <- c("NSW", "VIC", "QLD", "SA", "WA", "ACT", "NT")
territory <- sample(states, trial, replace = T) 
start <- ymd(20140101) + days(sample(1:365, trial, replace = T)) 
inter <- start + months(sample(1:24, trial, replace = T)) 
end <- inter + months(sample(1:24, trial, replace = T))
preDf <- data.frame(name = names, territory = territory, start = start, end = end) 

# create id
uqeName <- data.frame(name = unique(preDf$name), id = 1:length(unique(preDf$name))) 
preDf <- merge(preDf, uqeName, by="name", all.x = TRUE) 
preDf$id <- as.factor(preDf$id)

### add unconditional and conditional mean period
## base
# unconditional
postDf <- transform(preDf, period = as.double(end - start))

agg <- aggregate(postDf[,5:6], by = list(postDf$id), FUN = function(x) if(is.factor(x)) x else mean(x))[, -2]
names(agg) <- c("id", "period")

postDf <- merge(postDf, agg, by = "id", all.x = T)

## plyr
# unconditional
postDf <- plyr::mutate(preDf, period = as.double(end - start))

# conditonal
postDf <- ddply(preDf, .(id), mutate, mean_period = mean(as.double(end - start)))

## dplyr
# unconditional
postDf <- preDf %>% mutate(period = as.double(end - start))

# conditional
postDf <- preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id)

## data.table
# unconditional
preDt <- as.data.table(preDf)
setkey(preDt, id)
postDt <- preDt[, list(name = name, territory = territory,
                       start = start, end = end, id = id,
                       period = as.double(end - start))]

# conditional
postDt <- preDt[,
                list(name = name, territory = territory,
                     start = start, end = end, id = id,
                     mean_period = mean(as.double(end - start))),
                by = id]


## dplyr + data.table
# unconditional
postDt <- preDt %>% mutate(period = as.double(end - start))

# conditional
postDt <- preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id)

head(postDt)

## speed
tim1 <- system.time({
  postDf <- transform(preDf, period = as.double(end - start))
  agg <- aggregate(postDf[,5:6], by = list(postDf$id), FUN = function(x) if(is.factor(x)) x else mean(x))[, -2]
  names(agg) <- c("id", "period")
  postDf <- merge(postDf, agg, by = "id", all.x = T)
})
tim2 <- system.time(ddply(preDf, .(id), mutate, mean_period = mean(as.double(end - start))))
tim3 <- system.time(preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id))
tim4 <- system.time(preDt[,
                          list(name = name, territory = territory,
                               start = start, end = end, id = id,
                               mean_period = mean(as.double(end - start))),
                          by = id])
tim5 <- system.time(preDf %>% group_by(id) %>% mutate(mean_period = mean(as.double(end - start))) %>% arrange(id))

times <- do.call("rbind", list(base = tim1, plyr = tim2, dplyr = tim3, data.table = tim4, both = tim5))
times <- cbind(times, data.frame(package = c("base", "plyr", "dplyr", "data.table", "dplyr+data.table")))
times[, c(1:3,6)]

require(ggplot2)
ggplot(times[-2, ], aes(x = package, y = elapsed, fill = package)) + 
  geom_bar(stat = "identity") + ggtitle("Elapsed time of each package")

# No significant difference if unconditional values
# plyr would be better to be avoided if conditional values
# base can also be used - if other packages are not available
# data.table not easy to add a single column, preserving other columns - dplyr can be used together
# dplyr and data.table (or both) are beneficial for large data with conditional values







