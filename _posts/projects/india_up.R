folder <- "data_2015-01-08-India-Education"
data <- read.csv(paste(folder,"india.csv",sep="/"))
data <- data[,c(2,c(5:13))]
names(data) <- c("code","state","area","age","totalPop","malePop","femalePop","totalEdu","maleEdu","femaleEdu")
data$code <- as.factor(data$code)

head(data)

# grouping ages

# 