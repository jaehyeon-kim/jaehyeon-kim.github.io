---
title: Some Thoughts on Shiny Open Source - Internal Load Balancing
date: 2016-05-23
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Development
tags: 
  - R Shiny
  - R
authors:
  - JaehyeonKim
images: []
description: In this post, a simple way of internal load balancing is demonstrated by redirecting multiple same applications, depending on the number of processes binded to them
---

Shiny is an interesting web framework that helps create a web application quickly. If it targets a large number of users, however, there are several limitations and it is so true when the open source version of Shiny is in use. It would be possible to tackle down some of the limitations with the enterprise version but it is not easy to see enough examples of Shiny applications in production environment. While whether Shiny can be used in production environment is a controversial issue, this series of posts illustrate some ways to use **open source Shiny** a bit more wisely. Specifically the following topics are going to be covered.

+ Load balancing (and auto scaling)
    - Each application (or folder in `/srv/shiny-server`) is binded by a single process so that multiple users or sessions are served by the same process. Let say multiple cores exist in the server machine. Then this can be one of the main causes of performance bottleneck as only a single process is reserved for an application.
+ Rendering multiple pages, including authentication
    - An application is served as a single-page web application and thus it is not built to render multiple pages. Application code could be easier to manage if code is split by different pages. Moreover it is highly desirable to implement authentication.
+ Running with a Proxy and SSL configuration for HTTPS
    - By default, an application is served by HTTP with port 3838. A useful use case to serve a Shiny application via HTTPS is it can be integrated with a Tableau dashboard.

In this post, a simple way of **internal load balancing** is demonstrated by *redirecting multiple same applications, depending on the number of processes binded to them* - this is originally from [Huidong Tian's blog](http://withr.me/a-shiny-app-serves-as-shiny-server-load-balancer/).

## Folder structure

As an illustration, 5 applications are added to `/srv/shiny-server/redirect` as shown below. The folders named **1 to 4** are the same application in different folders and the application that redirects a user (or session) to the individual applications is placed in **app** folder. How many sessions are binded by each application is monitored by **monitor.R** and the output is recorded in **monitor.log**.

![](folder_structure.png#center)

## Process monitoring

The following script saves records of the number of sessions (*users*) that belong to each application (*app*) at the end of each iteration. It begins with filtering processes that is been initiated by *shiny* user using the `top` command. Then, for each **PID**, it extracts a condition if TCP socket is established using the `netstat` command as well as the corresponding application (folder) using the `lsof` command.


```r
lapply(1:60, function(x) {
  tops <- system("top -n 1 -b -u shiny", intern = TRUE)
  if(length(tops) > 0) {
    ids <- grep("R *$", tops)
    header <- grep("%CPU", tops)
    names <- strsplit(gsub("^ +|%|\\+", "", tops[header]), " +")[[1]]
    
    if(length(ids) > 0) {
      dat <- as.data.frame(do.call(rbind, strsplit(gsub("^ *", "", tops[ids]), " +")))
      names(dat) <- names
      info <- as.data.frame(do.call(rbind, lapply(dat$PID, function(pid) {
        netstat <- system(paste("sudo netstat -p | grep", pid), intern = TRUE)
        lsof <- system(paste("sudo lsof -p", pid, "| grep /srv"), intern = TRUE)
        users <- length(grep("ESTABLISHED", netstat) & grep("tcp", netstat))
        app <- regmatches(lsof, regexec("srv/(.*)", lsof))[[1]][2]
        c(app = app, users = users)
      })))
    } else {
      info <- data.frame(app = "app", users = 0)
    }
    write.table(info, file = "/srv/shiny-server/redirect/monitor.log")
  }  
})
```

The script should be run as *root* so that all processes are seen. Below shows an example output when two applications are open in a browser.


```bash
                      app users
1 shiny-server/redirect/1     1
2 shiny-server/redirect/2     1
```

Due to process visibility, the above script cannot be run in a Shiny application and a cron job is created in root (`sudo crontab -e`). It is executed every minute but a single run of the script completes quite quickly. Therefore it is wrapped in `lapply()` so that records are saved multiple times until the next run.


```bash
* * * * * Rscript /srv/shiny-server/redirect/monitor.R
```

## Application code

The redirect application and associating javascript code are shown below. The application that has the least number of users is selected in the server function (`app$app[which.min(app$users)]`) and the link to that application is constructed. Then it is added to the input text input and a java script function named `setInterval()` in **redirect.js** is triggered.


```r
library(shiny)
library(magrittr)
library(dplyr)

ui <- fluidPage(
  fluidRow(
    #uncomment in practice
    #tags$style("#link {visibility: hidden;}"),
    tags$script(type="text/javascript", src = "redirect.js"),
    column(3, offset = 4,
           wellPanel(
             h3("app info"),
             tableOutput("app_info")
             )
           )
  ),
  fluidRow(
    column(3, offset = 4,
           wellPanel(
             h3("Redirecting ..."),
             textInput(inputId = "link", label = "", value = "")
             )
           )
  )
)

server <- function(input, output, session) {
  users <- read.table("/srv/shiny-server/redirect/monitor.log", header = TRUE, stringsAsFactors = FALSE)
  app <- data.frame(app = paste0("shiny-server/redirect/", 1:4), stringsAsFactors = FALSE)
  app <- app %>% left_join(users, by = "app") %>% mutate(app = sub("shiny-server/", "", app),
                                                         users = ifelse(is.na(users), "0", as.character(users)))
  link <- paste0("hostname-or-ip-address[:port]/", app$app[which.min(app$users)])
  
  # info tables
  output$app_info <- renderTable(app)
  
  updateTextInput(session, inputId = "link", value = link)
}

shinyApp(ui = ui, server = server)
```



```r
# put redirect.js in www folder
setInterval(function() {
  var link = document.getElementById('link').value;
  if (link.length > 1) {
    window.open(link, "_top")
  }
}, 1000)
```

An example of the application is shown below.

![](redirect.png#center)

Here is the code for the *redirected* application.


```r
library(shiny)

ui <- fluidPage(
  fluidRow(
    column(3, offset = 4,
           wellPanel(
             h3("URL components"),
             verbatimTextOutput("urlText")
             )
           )
  )
)

server <- function(input, output, session) {
  output$urlText <- renderText({
    paste(sep = "",
          "protocol: ", session$clientData$url_protocol, "\n",
          "hostname: ", session$clientData$url_hostname, "\n",
          "pathname: ", session$clientData$url_pathname, "\n",
          "port: ",     session$clientData$url_port,     "\n",
          "search: ",   session$clientData$url_search,   "\n"
    )
  })
}

shinyApp(ui = ui, server = server)
```

![](app.png#center)


