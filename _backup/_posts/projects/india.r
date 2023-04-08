
# -------------------------------------------------------------------------------------------------------------------------------------
#
# Statistical learning with R 
# A peek into India Literacy
# Designed and developed by Tinniam V Ganesh
# Date 5 Jan 2015
#
# --------------------------------------------------------------------------------------------------------------------------------------

# Set the age vector
#age <- c(2,5,6,7,8,9,10,11,12,13,14,17,22,27,32,37, 62, 70)
age <- c(1,2,3,4.2,5.2,6.2,7.3,8,9,10,11,12,13,14,15,16,17,18)

# Data included for the following states
# 1. Tamil Nadu      2. Uttar Pradhesh   3. Bihar     4. Kerala  5. Andhra Pradhesh
# 6. Arunachal Pradhesh  7. Assam  8. Chattisgarh 9. Gujarat 10.  11. Himachal Pradesh
# 12. Jammu and Kashmir 13. Jharkhand 14. Karnataka 15. Madhya Pradesh 16. Maharashta
# 17. Odisha 18. Punjab  19. Rajashthan 20. Uttarkhand 21. West Bengal
#
## 0.-------------------------------------------------------------------------------------------
#age <- c(1,2,3,4.2,5.2,6.2,7.3,8,9,10,11,12,13,14,15,16,17,18)

# Age set to be centered around the bars in th ebar plot.
age <- c(1, 2, 3, 4.3 ,5.4 ,6.6 ,7.8 ,9.1 , 10.2 ,11.4 ,12.7,
         13.9,15.0,16.2,17.3,18.3,19.3,20.7)
# Read the overal India literacy related data 
india = read.csv("india.csv") 

# Create as a matrix
edumat = as.matrix(india)

indiaTotal = edumat[2:19,7:28]


# Take transpose as this is necessary for plotting bar charts
indiamat = t(indiaTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")



#Create a vector of total Males & Females
totalM = indiamat[3,]
totalF = indiamat[4,]

#Create a vector of males & females attending education institution
eduM = indiamat[6,]
eduF = indiamat[7,]

#Calculate percent of males attending education of total
indiapercentM = round(as.numeric(eduM) *100/as.numeric(totalM),1)

barplot(indiapercentM,names.arg=indiamat[1,],main ="Percentage males attending educational institutions in India ", 
        xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
indiapercentF = round(as.numeric(eduF) *100/as.numeric(totalF),1)

barplot(indiapercentF,names.arg=indiamat[1,],main ="Percentage females attending educational institutions in India ", 
        xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 0a - Education in Rural India

indiaruralmat = edumat[21:38,7:28]

# Take transpose as this is necessary for plotting bar charts
ruralmat = t(indiaruralmat)


#Create a vector of total Males & Females in Rural TN
totalruralM = ruralmat[3,]
totalruralF = ruralmat[4,]

#Create a vector of males & females attending education institution
edururalM = ruralmat[6,]
edururalF = ruralmat[7,]

#Calculate percent of rural males attending education of total
percentruralM = round(as.numeric(edururalM) *100/as.numeric(totalruralM),1)

barplot(percentruralM,names.arg=ruralmat[1,],main ="Percentage males attending educational institutions in rural India ", 
        xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of rural females attending education of total
percentruralF = round(as.numeric(edururalF) *100/as.numeric(totalruralF),1)

barplot(percentruralF,names.arg=ruralmat[1,],main ="Percentage females attending educational institutions in rural India ", 
        xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 0b - -----------------------------------------------------------------------
## 0a - Education in Urban India


indiaurbanmat = edumat[40:57,7:28]
# Take transpose as this is necessary for plotting bar charts
urbanmat = t(indiaurbanmat)


#Create a vector of total Males & Females in Urban India
totalurbanM = urbanmat[3,]
totalurbanF = urbanmat[4,]

#Create a vector of males & females attending education institution
eduurbanM = urbanmat[6,]
eduurbanF = urbanmat[7,]

#Calculate percent of urban males attending education of total
percenturbanM = round(as.numeric(eduurbanM) *100/as.numeric(totalurbanM),1)

barplot(percenturbanM,names.arg=urbanmat[1,],main ="Percentage males attending educational institutions in urban India ", 
        xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
        
#Calculate percent of urban females attending education of total
percenturbanF = round(as.numeric(eduurbanF) *100/as.numeric(totalurbanF),1)
        
barplot(percenturbanF,names.arg=urbanmat[1,],main ="Percentage females attending educational institutions in urban India ", 
                xlab = "Age", ylab= "Percentage", col ="lightblue", legend= c("Females"))
        points(age,indiapercentF,pch=15)
        lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
        legend( x="bottomright", 
                legend=c("National average"),
                col=c("red"), bty="n" , lwd=1, lty=c(2), 
                pch=c(15) )
        
## 1.-------------------------------------------------------------------------------------------

# Read the Tamil nadu literacy related data for Total Tamil Nadu only
tn = read.csv("tamilnadu.csv") 

# Create as a matrix
edumat = as.matrix(tn)

tnTotal = edumat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
tnmat = t(tnTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")



#Create a vector of total Males & Females
totalM = tnmat[3,]
totalF = tnmat[4,]

#Create a vector of males & females attending education institution
eduM = tnmat[6,]
eduF = tnmat[7,]

#Calculate percent of males attending education of total
tnpercentM = round(as.numeric(eduM) *100/as.numeric(totalM),1)

barplot(tnpercentM,names.arg=tnmat[1,],main ="Percentage males attending educational institutions in TN ", 
xlab = "Age", ylab= "Percentage",ylim = c(0,100),  col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
tnpercentF = round(as.numeric(eduF) *100/as.numeric(totalF),1)

barplot(tnpercentF,names.arg=tnmat[1,],main ="Percentage females attending educational institutions in TN ", 
xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
## 2.----------------------------------------------------------------------------------------

# Read the Uttar Pradesh literacy related data 
up = read.csv("uttarpradesh.csv") 

# Create as a matrix
upmat = as.matrix(up)

upTotal = upmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
upmat = t(upTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
upTotalM = upmat[3,]
upTotalF = upmat[4,]

#Create a vector of males & females attending education institution
upM = upmat[6,]
upF = upmat[7,]

#Calculate percent of males attending education of total
uppercentM = round(as.numeric(upM) *100/as.numeric(upTotalM),1)

barplot(uppercentM,names.arg=upmat[1,],main ="Percentage males attending educational institutions in UP ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
uppercentF = round(as.numeric(upF) *100/as.numeric(upTotalF),1)

barplot(uppercentF,names.arg=upmat[1,],main ="Percentage females attending educational institutions in UP ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))

points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 3.-------------------------------------------------------------------------------------------

# Read the Bihar literacy related data 
bihar = read.csv("bihar.csv") 

# Create as a matrix
biharmat = as.matrix(bihar)

biharTotal = biharmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
biharmat = t(biharTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
biharTotalM = biharmat[3,]
biharTotalF = biharmat[4,]

#Create a vector of males & females attending education institution
biharM = biharmat[6,]
biharF = biharmat[7,]

#Calculate percent of males attending education of total
biharpercentM = round(as.numeric(biharM) *100/as.numeric(biharTotalM),1)

barplot(biharpercentM,names.arg=biharmat[1,],main ="Percentage males attending educational institutions in Bihar ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
biharpercentF = round(as.numeric(biharF) *100/as.numeric(biharTotalF),1)

barplot(biharpercentF,names.arg=biharmat[1,],main ="Percentage females attending educational institutions in Bihar ", 
        xlab = "Age", ylab= "Percentage",  ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
## 4.-----------------------------------------------------------------------------------------------

# Read the Kerala literacy related data 
kerala = read.csv("kerala.csv") 

# Create as a matrix
keralamat = as.matrix(kerala)

keralaTotal = keralamat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
keralamat = t(keralaTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
keralaTotalM = keralamat[3,]
keralaTotalF = keralamat[4,]

#Create a vector of males & females attending education institution
keralaM = keralamat[6,]
keralaF = keralamat[7,]

#Calculate percent of males attending education of total
keralapercentM = round(as.numeric(keralaM) *100/as.numeric(keralaTotalM),1)

barplot(keralapercentM,names.arg=keralamat[1,],main ="Percentage males attending educational institutions in Kerala ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
keralapercentF = round(as.numeric(keralaF) *100/as.numeric(keralaTotalF),1)

barplot(keralapercentF,names.arg=keralamat[1,],main ="Percentage females attending educational institutions in Kerala ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )



## 5.---------------------------------------------------------------------------------------------


# Read the Andhra Pradhesh literacy related data 
andhra = read.csv("andhrapradesh.csv") 

# Create as a matrix
andhramat = as.matrix(andhra)

andhraTotal = andhramat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
andhramat = t(andhraTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
andhraTotalM = andhramat[3,]
andhraTotalF = andhramat[4,]

#Create a vector of males & females attending education institution
andhraM = andhramat[6,]
andhraF = andhramat[7,]

#Calculate percent of males attending education of total
andhrapercentM = round(as.numeric(andhraM) *100/as.numeric(andhraTotalM),1)

barplot(andhrapercentM,names.arg=andhramat[1,],main ="Percentage males attending educational institutions in Andhra Pradesh", 
        xlab = "Age", ylab= "Percentage",  ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
andhrapercentF = round(as.numeric(andhraF) *100/as.numeric(andhraTotalF),1)

barplot(andhrapercentF,names.arg=andhramat[1,],main ="Percentage females attending educational institutions in Andhra Pradesh ", 
        xlab = "Age", ylab= "Percentage",  ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
## 6.---------------------------------------------------------------------------------------------
# Read the Arunachal Pradhesh literacy related data 
arunachal = read.csv("arunachal.csv") 

# Create as a matrix
arunachalmat = as.matrix(arunachal)

arunachalTotal = arunachalmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
arunachalmat = t(arunachalTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
arunachalTotalM = arunachalmat[3,]
arunachalTotalF = arunachalmat[4,]

#Create a vector of males & females attending education institution
arunachalM = arunachalmat[6,]
arunachalF = arunachalmat[7,]

#Calculate percent of males attending education of total
arunachalpercentM = round(as.numeric(arunachalM) *100/as.numeric(arunachalTotalM),1)

barplot(arunachalpercentM,names.arg=arunachalmat[1,],main ="Percentage males attending educational institutions in Arunachal Pradesh", 
        xlab = "Age", ylab= "Percentage",ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
arunachalpercentF = round(as.numeric(arunachalF) *100/as.numeric(arunachalTotalF),1)

barplot(arunachalpercentF,names.arg=arunachalmat[1,],main ="Percentage females attending educational institutions in Arunachal Pradesh ", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))

points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 7.---------------------------------------------------------------------------------------------

# Read the Assam  literacy related data 
assam = read.csv("assam.csv") 

# Create as a matrix
assammat = as.matrix(assam)

assamTotal = assammat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
assammat = t(assamTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
assamTotalM = assammat[3,]
assamTotalF = assammat[4,]

#Create a vector of males & females attending education institution
assamM = assammat[6,]
assamF = assammat[7,]

#Calculate percent of males attending education of total
assampercentM = round(as.numeric(assamM) *100/as.numeric(assamTotalM),1)

barplot(assampercentM,names.arg=assammat[1,],main ="Percentage males attending educational institutions in Assam", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
assampercentF = round(as.numeric(assamF) *100/as.numeric(assamTotalF),1)

barplot(assampercentF,names.arg=assammat[1,],main ="Percentage females attending educational institutions in Assam", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 8.-------------------------------------------------------------------------------------------
# Read the Chattisgarh literacy related data 
chattisgarh = read.csv("chattisgarh.csv") 

# Create as a matrix
chattisgarhmat = as.matrix(chattisgarh)

chattisgarhTotal = chattisgarhmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
chattisgarhmat = t(chattisgarhTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
chattisgarhTotalM = chattisgarhmat[3,]
chattisgarhTotalF = chattisgarhmat[4,]

#Create a vector of males & females attending education institution
chattisgarhM = chattisgarhmat[6,]
chattisgarhF = chattisgarhmat[7,]

#Calculate percent of males attending education of total
chattisgarhpercentM = round(as.numeric(chattisgarhM) *100/as.numeric(chattisgarhTotalM),1)

barplot(chattisgarhpercentM,names.arg=chattisgarhmat[1,],main ="Percentage males attending educational institutions in Chattisgarh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )


#Calculate percent of females attending education of total
chattisgarhpercentF = round(as.numeric(chattisgarhF) *100/as.numeric(chattisgarhTotalF),1)

barplot(chattisgarhpercentF,names.arg=chattisgarhmat[1,],main ="Percentage females attending educational institutions in Chattisgarh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 9.---------------------------------------------------------------------------------------------
# Read the Gujarat literacy related data 
gujarat = read.csv("gujarat.csv") 

# Create as a matrix
gujaratmat = as.matrix(gujarat)

gujaratTotal = gujaratmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
gujaratmat = t(gujaratTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
gujaratTotalM = gujaratmat[3,]
gujaratTotalF = gujaratmat[4,]

#Create a vector of males & females attending education institution
gujaratM = gujaratmat[6,]
gujaratF = gujaratmat[7,]

#Calculate percent of males attending education of total
gujaratpercentM = round(as.numeric(gujaratM) *100/as.numeric(gujaratTotalM),1)

barplot(gujaratpercentM,names.arg=gujaratmat[1,],main ="Percentage males attending educational institutions in Gujarat", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
gujaratpercentF = round(as.numeric(gujaratF) *100/as.numeric(gujaratTotalF),1)

barplot(gujaratpercentF,names.arg=gujaratmat[1,],main ="Percentage females attending educational institutions in Gujarat", 
        xlab = "Age", ylab= "Percentage",ylim = c(0,100),  col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
## 10. -----------------------------------------------------------------------------------------
# Read the Haryana literacy related data 
haryana = read.csv("haryana.csv") 

# Create as a matrix
haryanamat = as.matrix(haryana)

haryanaTotal = haryanamat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
haryanamat = t(haryanaTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
haryanaTotalM = haryanamat[3,]
haryanaTotalF = haryanamat[4,]

#Create a vector of males & females attending education institution
haryanaM = haryanamat[6,]
haryanaF = haryanamat[7,]

#Calculate percent of males attending education of total
haryanapercentM = round(as.numeric(haryanaM) *100/as.numeric(haryanaTotalM),1)

barplot(haryanapercentM,names.arg=haryanamat[1,],main ="Percentage males attending educational institutions in Haryana", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
haryanapercentF = round(as.numeric(haryanaF) *100/as.numeric(haryanaTotalF),1)

barplot(haryanapercentF,names.arg=haryanamat[1,],main ="Percentage females attending educational institutions in Haryana", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )
## 11.--------------------------------------------------------------------------------------
# Read the Himachal Pradesh literacy related data 
himachal = read.csv("himachalpradesh.csv") 

# Create as a matrix
himachalmat = as.matrix(himachal)

himachalTotal = himachalmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
himachalmat = t(himachalTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
himachalTotalM = himachalmat[3,]
himachalTotalF = himachalmat[4,]

#Create a vector of males & females attending education institution
himachalM = himachalmat[6,]
himachalF = himachalmat[7,]

#Calculate percent of males attending education of total
himachalpercentM = round(as.numeric(himachalM) *100/as.numeric(himachalTotalM),1)

barplot(himachalpercentM,names.arg=himachalmat[1,],main ="Percentage males attending educational institutions in Himachal Pradesh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
himachalpercentF = round(as.numeric(himachalF) *100/as.numeric(himachalTotalF),1)

barplot(himachalpercentF,names.arg=himachalmat[1,],main ="Percentage females attending educational institutions in Himachal Pradesh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )


## 12.-----------------------------------------------------------------------------------------
# Read the Jammu and Kashmir literacy related data 
jk = read.csv("jammukashmir.csv") 

# Create as a matrix
jkmat = as.matrix(jk)

jkTotal = jkmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
jkmat = t(jkTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
jkTotalM = jkmat[3,]
jkTotalF = jkmat[4,]

#Create a vector of males & females attending education institution
jkM = jkmat[6,]
jkF = jkmat[7,]

#Calculate percent of males attending education of total
jkpercentM = round(as.numeric(jkM) *100/as.numeric(jkTotalM),1)

barplot(jkpercentM,names.arg=jkmat[1,],main ="Percentage males attending educational institutions in Jammu and Kashmir", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
jkpercentF = round(as.numeric(jkF) *100/as.numeric(jkTotalF),1)

barplot(jkpercentF,names.arg=jkmat[1,],main ="Percentage females attending educational institutions in Jammu and Kashmir", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 13. --------------------------------------------------------------------------------------------

# Read the Jharkhand literacy related data 
jharkhand = read.csv("jharkhand.csv") 

# Create as a matrix
jharkhandmat = as.matrix(jharkhand)

jharkhandTotal = jharkhandmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
jharkhandmat = t(jharkhandTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
jharkhandTotalM = jharkhandmat[3,]
jharkhandTotalF = jharkhandmat[4,]

#Create a vector of males & females attending education institution
jharkhandM = jharkhandmat[6,]
jharkhandF = jharkhandmat[7,]

#Calculate percent of males attending education of total
jharkhandpercentM = round(as.numeric(jharkhandM) *100/as.numeric(jharkhandTotalM),1)

barplot(jharkhandpercentM,names.arg=jharkhandmat[1,],main ="Percentage males attending educational institutions in Jharkhand", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
jharkhandpercentF = round(as.numeric(jharkhandF) *100/as.numeric(jharkhandTotalF),1)

barplot(jharkhandpercentF,names.arg=jharkhandmat[1,],main ="Percentage females attending educational institutions in Jharkhand", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 14.---------------------------------------------------------------------------------------

# Read the Karnataka literacy related data 
karnataka = read.csv("karnataka.csv") 

# Create as a matrix
karnatakamat = as.matrix(karnataka)

karnatakaTotal = karnatakamat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
karnatakamat = t(karnatakaTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
karnatakaTotalM = karnatakamat[3,]
karnatakaTotalF = karnatakamat[4,]

#Create a vector of males & females attending education institution
karnatakaM = karnatakamat[6,]
karnatakaF = karnatakamat[7,]

#Calculate percent of males attending education of total
karnatakapercentM = round(as.numeric(karnatakaM) *100/as.numeric(karnatakaTotalM),1)

barplot(karnatakapercentM,names.arg=karnatakamat[1,],main ="Percentage males attending educational institutions in Karnataka", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
karnatakapercentF = round(as.numeric(karnatakaF) *100/as.numeric(karnatakaTotalF),1)

barplot(karnatakapercentF,names.arg=karnatakamat[1,],main ="Percentage females attending educational institutions in Karnataka", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )


## 15.-----------------------------------------------------------------------------
# Read the Madhya Pradesh literacy related data 
mp = read.csv("madhyapradesh.csv") 

# Create as a matrix
mpmat = as.matrix(mp)

mpTotal = mpmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
mpmat = t(mpTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
mpTotalM = mpmat[3,]
mpTotalF = mpmat[4,]

#Create a vector of males & females attending education institution
mpM = mpmat[6,]
mpF = mpmat[7,]

#Calculate percent of males attending education of total
mppercentM = round(as.numeric(mpM) *100/as.numeric(mpTotalM),1)

barplot(mppercentM,names.arg=mpmat[1,],main ="Percentage males attending educational institutions in Madhya Pradesh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
mppercentF = round(as.numeric(mpF) *100/as.numeric(mpTotalF),1)

barplot(mppercentF,names.arg=mpmat[1,],main ="Percentage females attending educational institutions in Madhya Pradesh", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 16.---------------------------------------------------------------------------------------
# Read the Maharashtra literacy related data 
maharashtra = read.csv("maharashtra.csv") 

# Create as a matrix
maharashtramat = as.matrix(maharashtra)

maharashtraTotal = maharashtramat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
maharashtramat = t(maharashtraTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
maharashtraTotalM = maharashtramat[3,]
maharashtraTotalF = maharashtramat[4,]

#Create a vector of males & females attending education institution
maharashtraM = maharashtramat[6,]
maharashtraF = maharashtramat[7,]

#Calculate percent of males attending education of total
maharashtrapercentM = round(as.numeric(maharashtraM) *100/as.numeric(maharashtraTotalM),1)

barplot(maharashtrapercentM,names.arg=maharashtramat[1,],main ="Percentage males attending educational institutions in Maharashtra", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
maharashtrapercentF = round(as.numeric(maharashtraF) *100/as.numeric(maharashtraTotalF),1)

barplot(maharashtrapercentF,names.arg=maharashtramat[1,],main ="Percentage females attending educational institutions in Maharashtra", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 17.-------------------------------------------------------------------------------------------------
# Read the Odisha literacy related data 
odisha = read.csv("odisha.csv") 

# Create as a matrix
odishamat = as.matrix(odisha)

odishaTotal = odishamat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
odishamat = t(odishaTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
odishaTotalM = odishamat[3,]
odishaTotalF = odishamat[4,]

#Create a vector of males & females attending education institution
odishaM = odishamat[6,]
odishaF = odishamat[7,]

#Calculate percent of males attending education of total
odishapercentM = round(as.numeric(odishaM) *100/as.numeric(odishaTotalM),1)

barplot(odishapercentM,names.arg=odishamat[1,],main ="Percentage males attending educational institutions in Odisha", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
odishapercentF = round(as.numeric(odishaF) *100/as.numeric(odishaTotalF),1)

barplot(odishapercentF,names.arg=odishamat[1,],main ="Percentage females attending educational institutions in Odisha", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 18. -----------------------------------------------------------------------------------------------
# Read the Punjab literacy related data 
punjab = read.csv("punjab.csv") 

# Create as a matrix
punjabmat = as.matrix(punjab)

punjabTotal = punjabmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
punjabmat = t(punjabTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
punjabTotalM = punjabmat[3,]
punjabTotalF = punjabmat[4,]

#Create a vector of males & females attending education institution
punjabM = punjabmat[6,]
punjabF = punjabmat[7,]

#Calculate percent of males attending education of total
punjabpercentM = round(as.numeric(punjabM) *100/as.numeric(punjabTotalM),1)

barplot(punjabpercentM,names.arg=punjabmat[1,],main ="Percentage males attending educational institutions in Punjab", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
punjabpercentF = round(as.numeric(punjabF) *100/as.numeric(punjabTotalF),1)

barplot(punjabpercentF,names.arg=punjabmat[1,],main ="Percentage females attending educational institutions in Punjab", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )


## 19. ------------------------------------------------------------------------------------------

# Read the uttarakhand literacy related data 
rajasthan = read.csv("rajasthan.csv") 

# Create as a matrix
rajasthanmat = as.matrix(rajasthan)

rajasthanTotal = rajasthanmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
rajasthanmat = t(rajasthanTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
rajasthanTotalM = rajasthanmat[3,]
rajasthanTotalF = rajasthanmat[4,]

#Create a vector of males & females attending education institution
rajasthanM = rajasthanmat[6,]
rajasthanF = rajasthanmat[7,]

#Calculate percent of males attending education of total
rajasthanpercentM = round(as.numeric(rajasthanM) *100/as.numeric(rajasthanTotalM),1)

barplot(rajasthanpercentM,names.arg=rajasthanmat[1,],main ="Percentage males attending educational institutions in Rajasthan", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
rajasthanpercentF = round(as.numeric(rajasthanF) *100/as.numeric(rajasthanTotalF),1)

barplot(rajasthanpercentF,names.arg=rajasthanmat[1,],main ="Percentage females attending educational institutions in Rajasthan", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

## 20. ----------------------------------------------------------------------------------------
# Read the Uttarakhand literacy related data 
uttarakhand = read.csv("uttarakhand.csv") 

# Create as a matrix
uttarakhandmat = as.matrix(uttarakhand)

uttarakhandTotal = uttarakhandmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
uttarakhandmat = t(uttarakhandTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
uttarakhandTotalM = uttarakhandmat[3,]
uttarakhandTotalF = uttarakhandmat[4,]

#Create a vector of males & females attending education institution
uttarakhandM = uttarakhandmat[6,]
uttarakhandF = uttarakhandmat[7,]

#Calculate percent of males attending education of total
uttarakhandpercentM = round(as.numeric(uttarakhandM) *100/as.numeric(uttarakhandTotalM),1)

barplot(uttarakhandpercentM,names.arg=uttarakhandmat[1,],main ="Percentage males attending educational institutions in Uttarkhand", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
uttarakhandpercentF = round(as.numeric(uttarakhandF) *100/as.numeric(uttarakhandTotalF),1)

barplot(uttarakhandpercentF,names.arg=uttarakhandmat[1,],main ="Percentage females attending educational institutions in Uttarakhand", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )


## 21. --------------------------------------------------------------------------------------------
# Read the West Bengal literacy related data 
westbengal = read.csv("westbengal.csv") 

# Create as a matrix
westbengalmat = as.matrix(westbengal)

westbengalTotal = westbengalmat[2:19,7:28]

# Take transpose as this is necessary for plotting bar charts
westbengalmat = t(westbengalTotal)

# Set the scipen option to format the y axis (otherwise prints as e^05 etc.)
getOption("scipen")
opt <- options("scipen" = 20)
getOption("scipen")

#Create a vector of total Males & Females
westbengalTotalM = westbengalmat[3,]
westbengalTotalF = westbengalmat[4,]

#Create a vector of males & females attending education institution
westbengalM = westbengalmat[6,]
westbengalF = westbengalmat[7,]

#Calculate percent of males attending education of total
westbengalpercentM = round(as.numeric(westbengalM) *100/as.numeric(westbengalTotalM),1)

barplot(westbengalpercentM,names.arg=westbengalmat[1,],main ="Percentage males attending educational institutions in West Bengal", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Males")) 
points(age,indiapercentM,pch=15)
lines(age,indiapercentM,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )

#Calculate percent of females attending education of total
westbengalpercentF = round(as.numeric(westbengalF) *100/as.numeric(westbengalTotalF),1)

barplot(westbengalpercentF,names.arg=westbengalmat[1,],main ="Percentage females attending educational institutions in West Bengal", 
        xlab = "Age", ylab= "Percentage", ylim = c(0,100), col ="lightblue", legend= c("Females"))
points(age,indiapercentF,pch=15)
lines(age,indiapercentF,col="red",pch=20,lty=2,lwd=3)
legend( x="bottomright", 
        legend=c("National average"),
        col=c("red"), bty="n" , lwd=1, lty=c(2), 
        pch=c(15) )





