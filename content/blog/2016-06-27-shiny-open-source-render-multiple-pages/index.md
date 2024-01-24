---
title: Some Thoughts on Shiny Open Source - Render Multiple Pages
date: 2016-06-27
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
  - R
  - Shiny
authors:
  - JaehyeonKim
images: []
cevo: 26
description: In this post, a simple way of internal load balancing is demonstrated by redirecting multiple same applications, depending on the number of processes binded to them
---

R Shiny applications are served as a single page application and it is not built to render multiple pages. There are benefits of rendering multiple pages such as code management and implement authentication. In this page, we discuss how to implement multi-page rendering in a Shiny app.

As indicated above, Shiny is not designed to render multiple pages and, in general, the UI is rendered on the fly as defined in *ui.R* or *app.R*. However this is not the only way as the UI can be rendered as a html output using `htmlOutput()` in *ui.R* and `renderUI()` in *server.R*. In this post, rendering multiple pages will be illustrated using an [**example application**](https://github.com/jaehyeon-kim/shiny-multipage).

## Example application structure

A total of 6 pages exist in the application as shown below.

![](flow.png#center)

At the beginning, the login page is rendered. A user can enter credentials for authentication or move to the register page. User credentials are kept in a SQLite db and the following user information is initialized at each start-up - passwords are encrypted using the [bcrypt package](https://cran.r-project.org/web/packages/bcrypt/index.html).


```r
library(bcrypt)
app_name <- "multipage demo"
added_ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
users <- data.frame(name = c("admin", "john.doe", "jane.doe"),
                    password = unlist(lapply(c("admin", "john.doe", "jane.doe"), hashpw)),
                    app_name = c("all", rep(app_name, 2)),
                    added_ts = rep(added_ts, 3),
                    stringsAsFactors = FALSE)
users
```

```bash
##       name                                                     password
## 1    admin $2a$12$RhUwtbJnr3Uo75npOeE96u1eRGpyQD2tJ38S2lCJ7wtBa.THxMGf2
## 2 john.doe $2a$12$Svzr/4/Ti5u6YVgx04Cy7OXhar71NgjD.gPpoX3hUJ4Pgd.gN1V.u
## 3 jane.doe $2a$12$CGAfSfYWP9eOuZxM1njwtOfGR2MlqDbcCeUE.CkXlZvBGHPlSORDW
##         app_name            added_ts
## 1            all 2016-06-10 17:59:39
## 2 multipage demo 2016-06-10 17:59:39
## 3 multipage demo 2016-06-10 17:59:39
```

Note that the authentication plan of this application is for demonstration only. In practice, for instance, LDAP or Active Directory authentication may be considered if it is possible to contact to a directory server - for Active Directory authentication, the [radhelper package](https://github.com/jaehyeon-kim/radhelper) might be useful.

It is assumed that an application key (*application-key*) should be specified for registration together with user name and password. The register page is shown below.

![](register.png#center)

Once logged on, two extra buttons appear: *Profile* and *App*. The screenshots of before and after login are shown below.

![](login.png#center)

The main purpose of the profile page is to *change* the password.

![](profile.png#center)

The application page keeps the main contents of the application. The default Shiny application is used.

![](app.png#center)

## UI elements

Each UI elements are constructed in a function and it is set to be rendered using `htmlOutput()` in *ui.R*. Actual rendering is made by `renderUI()` in *server.R*. 

Below shows the main login page after removing CSS and Javascript tags.


```r
ui_login <- function(...) {
  args <- list(...)
  fluidRow(
    column(3, offset = 4,
           wellPanel(
             div(id = "login_link",
                 actionButton("login_leave", "Leave", icon = icon("close"), width = "100px")
             ),
             br(),
             br(),
             h4("LOGIN"),
             textInput("login_username", "User name"),
             div(class = "input_msg", textOutput("login_username_msg")),
             passwordInput("login_password", "Password"),
             div(class = "input_msg", textOutput("login_password_msg")),
             actionButton("login_login", "Log in", icon = icon("sign-in"), width = "100px"),
             actionButton("login_register", "Register", icon = icon("user-plus"), width = "100px"),
             br(),
             div(class = "input_fail", textOutput("login_fail")),
             uiOutput("login_more")
           )
    )
  )
}
```

Each UI function has unspecified argument (`...`) so that some values can be passed from *server.R*. For example, the logout and application pages include *message* and *username* from the server.

At the end, UI is set to be rendered as a html output.


```r
ui <- (htmlOutput("page"))
```

## Application logic

A page is rendered using `render_page()` in *server.R*. This function accepts a UI element function in *ui.R* and renders a fluid page with some extra values. I didn't have much luck with Shiny Dashboard that the flud page layout is chosen instead.


```r
render_page <- function(..., f, title = app_name, theme = shinytheme("cerulean")) {
  page <- f(...)
  renderUI({
    fluidPage(page, title = title, theme = theme)
  })
}

server <- function(input, output, session) {
  ...
  
  ## render default login page
  output$page <- render_page(f = ui_login)
  
  ...
}
```

The authentication process shows a tricky part of implementing this setup. Depending on which page is currently rendered, only a part of inputs exist in the current page. In this circumstance, if an input is captured in reactive context such as `observe()` and `reactive()` but it doesn't exist in the current page, an error will be thrown. Therefore whether an input exists or not should be checked as seen in the observer below. On the other hand, `observeEvent()` is free from this error as it works only if the input exists.


```r
  user_info <- reactiveValues(is_logged = is_logged)
  
  # whether an input element exists should be checked
  observe({
    if(!is.null(input$login_login)) {
      username <- input$login_username
      password <- input$login_password
      
      if(username != "") output$login_username_msg <- renderText("")
      if(password != "") output$login_password_msg <- renderText("")
    }
  })
  
  observeEvent(input$login_login, {
    username <- isolate(input$login_username)
    password <- isolate(input$login_password)
    
    if(username == "") output$login_username_msg <- renderText("Please enter user name")
    if(password == "") output$login_password_msg <- renderText("Please enter password")
    
    if(!any(username == "", password == "")) {
      is_valid_credentials <- check_login_credentials(username = username, password = password, app_name = app_name)
      if(is_valid_credentials) {
        user_info$is_logged <- TRUE
        user_info$username <- username
        
        output$login_fail <- renderText("")
        
        log_session(username = username, is_in = 1, app_name = app_name)
      } else {
        output$login_fail <- renderText("Login failed, try again or contact admin")
      }
    }
  })
```

A *try-catch* block can also be useful to prevent this type of error due to a missing element. Below the plot of the application page is handled in `tryCatch` so that the application doesn't stop abruptly with an error although the plot element doesn't exist in the current page.


```r
tryCatch({
  output$distPlot <- renderPlot({
    # generate bins based on input$bins from ui.R
    x    <- faithful[, 2]
    bins <- seq(min(x), max(x), length.out = input$bins + 1)
    
    # draw the histogram with the specified number of bins
    hist(x, breaks = bins, col = 'darkgray', border = 'white')
  })
})
```

I hope this post is useful.

