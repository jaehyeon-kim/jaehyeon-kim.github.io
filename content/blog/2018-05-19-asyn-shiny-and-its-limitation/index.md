---
title: Async Shiny and Its Limitation
date: 2018-05-19
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Web Development
tags: 
  - R
  - Shiny
  - JavaScript
authors:
  - JaehyeonKim
images: []
---

A Shiny app is served by one (*single-threaded blocking*) process by [Open Source Shiny Server](https://www.rstudio.com/products/shiny/download-server/). This causes a scalability issue because all requests are handled one by one in a queue. Recently the creator of *Shiny* introduced the [promises](https://rstudio.github.io/promises/) package, which brings *asynchronous programming capabilities to R*. This is a remarkable step forward to web development in R.

In this post, it'll be demonstrated how to implement the async feature of Shiny. Then its limitation will be discussed with an alternative app, which is built by *JavaScript* for the frontend and *RServe* for the backend.

## Async Shiny and Its Limitation
### Brief Intro to Promises
A basic idea of how the *promises* package works is that a (long running) process is passed to a forked process while it immediately returns a *promise* object. Then the result can be obtained once it's finished (or failed) by handlers eg) *onFulfilled* and *onRejected*. The package also provides pipe operators (eg `%...>%`) for ease of use. Typically a *promise* object can be created with the [future](https://cran.r-project.org/web/packages/future/index.html) package. See [this page](https://rstudio.github.io/promises/articles/overview.html) for further details.

### Shiny App
A simple Shiny app is created for demonstration that renders 3 [htmlwidgets](https://www.htmlwidgets.org/): *DT*, *highcharter* and *plotly*. For this, the following *async-compatible* packages are necessary.

* Shiny v1.1+
* DT from _rstudio/DT@async_
* htmlwidgets from _ramnathv/htmlwidgets@async_
* plotly from _jcheng5/plotly@joe/feature/async_
* highcharter - supported by *htmlwidgets*

At startup, it is necessary to allocate the number of workers (forked processes). Note it doesn't necessarily be the same to the number of cores. Rather it may be better to set it higher if the machine has enough resource. This is because, if there are n workers and n+m requests, the m requests tend to be queued.

```r
library(magrittr)
library(DT)
library(highcharter)
library(plotly)

library(shiny)

library(promises)
library(future)
plan(multiprocess, workers = 100)
```

Then a simple *NavBar* page is created as the UI. A widget will be rendered by clicking a button.

```r
tab <- tabPanel(
  title = 'Demo',
  fluidPage(
    fluidRow(
      div(
        style='height: 400px;',
        column(2, actionButton('dt', 'update data table')),
        column(10, dataTableOutput('dt_out'))        
      )
    ),
    fluidRow(
      div(
        style='height: 400px;',
        column(2, actionButton('highchart', 'update highchart')),
        column(10, highchartOutput('highchart_out'))        
      )
    ),
    fluidRow(
      div(
        style='height: 400px;',
        column(2, actionButton('plotly', 'update plotly')),
        column(10, plotlyOutput('plotly_out'))          
      )
       
    )
  )
)

ui <- navbarPage("Async Shiny", tab)
```

A future object is created by `get_iris()`, which returns 10 records randomly from the *iris* data after 2 seconds. `evantReactive()`s generate *htmlwidget* objects and they are passed to the relevant render functions.

```r
server <- function(input, output, session) {
  
  get_iris <- function() {
    future({ Sys.sleep(2); iris[sample(1:nrow(iris), 10),] })
  }
  
  dt_df <- eventReactive(input$dt, {
    get_iris() %...>%
      datatable(options = list(
        pageLength = 5,
        lengthMenu = c(5, 10)
      ))
  })
  
  highchart_df <- eventReactive(input$highchart, {
    get_iris()
  })
  
  plotly_df <- eventReactive(input$plotly, {
    get_iris()
  })
  
  output$dt_out <- renderDataTable(dt_df())
  
  output$highchart_out <- renderHighchart({
    highchart_df() %...>% 
      hchart('scatter', hcaes(x = 'Sepal.Length', y = 'Sepal.Width', group = 'Species')) %...>%
      hc_title(text = 'Iris Scatter')
  })
  
  output$plotly_out <- renderPlotly({
    plotly_df() %...>%
      plot_ly(x = ~Sepal.Length, y = ~Sepal.Width, z = ~Petal.Length, color = ~Species)
  })
}
```

The app code can also be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/more-thoughts-on-shiny).

For deployment, a Docker image is created that includes the *async-compatible* packages, Open Source Shiny Server and RServe. It is available as [rockerextra/shiny-async-dev:3.4](https://hub.docker.com/r/rockerextra/shiny-async-dev/) and its Dockerfile can be found in [this repo](https://github.com/jaehyeon-kim/rocker-extra/blob/3.4/shiny-async-dev/Dockerfile). The app can be deployed with [Docker Compose](https://docs.docker.com/compose/) as can be seen [here](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/blob/master/compose-all/docker-compose.yml).

A screen shot of the Shiny app is seen below. It is possible to check the async feature by opening the app in 2 different browsers and hit buttons multiple times across.

![](shiny.png#center)

### Limitation
You may notice the htmlwidgets are rendered without delay across browsers but it's not the case in the same browser. This is due to the way how [Shiny's flush cycle](https://rstudio.github.io/promises/articles/shiny.html#the-flush-cycle) is implemented. Simply put, a user (or session) is not affected by other users (or sessions) for their async requests. However the async feature of Shiny is of little help for multiple async requests by a single user because all requests are processed one by one as its sync version.

This limitation can have a significant impact on developing a web application. In general, almost all events/actions are handled through the server in a Shiny app. However the async feature of the server is not the full extent that a typical JavaScript app can bring.

## Alternative Implementation
In order to compare the async Shiny app to a typical web app, an app is created with JavaScript for the frontend and RServe for the backend. In the UI, JQuery will be used for AJAX requests by clicking buttons. Then the same htmlwidget elements will be rendered to the app. With this setup, it's possible to make multiple requests concurrently in a session and they are all handled asynchronously by a JavaScript-backed app.

### RServe Backend
So as to render *htmlwidgets* to UI, it is necessary to have a backend API. As discussed in *API Development with R* series ([Part I](/blog/2017-11-18-api-development-with-r-1), [Part II](/blog/2017-11-19-api-development-with-r-2)), RServe can be a performant option for building an API. 

I don't plan to use native JavaScript libraries for creating individual widgets. Rather I'm going to render widgets that are created by R. Therefore it is necessary to understand the structure of a widget. `saveWidget()` of the *htmlwidgets* package helps save a widget into a HTML file and it executes `save_html()` of the *htmltools* package. 

Key parts of a widget is

* head - dependent JavaScript and CSS
* body
  + div - widget container and element
  + script - _application/json_ for widget data
  + script - _application/htmlwidget-sizing_ for widget size

For example,

```html
<!DOCTYPE html>
<html>
  <head>
  <meta charset='utf-8'/>
  <script src="src-to/htmlwidgets.js"></script>
  <script src="src-to/jquery.min.js"></script>
  <script src="src-to/datatables.js"></script>
  ... more DT dependencies
  </head>
  <body>
  <div id="htmlwidget_container">
    <div id="htmlwidget" 
        style="width:960px;height:500px;" 
        class="datatables html-widget">
    </div>
  </div>
  <script type="application/json" 
          data-for="htmlwidget">JSON DATA</script>
  <script type="application/htmlwidget-sizing" 
          data-for="htmlwidget">SIGING INFO</script>
  </body>
</html>
```

`write_widget()` is a slight modification of `saveWidget()` and `save_html()`. Given the following arguments, it returns the necessary widget string (HTML or JSON) and it can be passed to the UI. In this post, _src_ type will be used exclusively.

* w
  + *htmlwidget* object
  + see `widget()` illustrated below
* element_id
  + DOM element id (eg *dt_out*)
* type
  + json - _JSON DATA_ only
  + src - _application/json script_
  + html - body elements
  + all - entire html page

```r
library(htmlwidgets)

write_widget <- function(w, element_id, type = NULL, 
                          cdn = NULL, output_path = NULL) {
  w$elementId <- sprintf('htmlwidget_%s', element_id)
  toHTML <- utils::getFromNamespace(x = 'toHTML', ns = 'htmlwidgets')
  html <- toHTML(w, standalone = TRUE, knitrOptions = list())
  
  type <- match.arg(type, c('src', 'json', 'html', 'all'))
  if (type == 'src') {
    out <- html[[2]]
  } else if (type == 'json') {
    bptn <- paste0('<script type="application/json" data-for="htmlwidget_', 
              element_id, '">')
    eptn <- '</script>'
    out <- sub(eptn, '', sub(bptn, '', html[[2]]))
  } else {
    html_tags <- htmltools::renderTags(html)
    html_tags$html <- sub('htmlwidget_container', 
                  sprintf('htmlwidget_container_%s', element_id) , 
                  html_tags$html)
    if (type == 'html') {
      out <- html_tags$html
    } else { # all
      libdir <- gsub('\\\\', '/', tempdir())
      libdir <- gsub('[[:space:]]|[A-Z]:', '', libdir)
      
      deps <- lapply(html_tags$dependencies, update_dep_path, libdir = libdir)
      deps <- htmltools::renderDependencies(dependencies = deps, 
                                            srcType = c('hred', 'file'))
      deps <- ifelse(!is.null(cdn), gsub(libdir, cdn, deps), deps)
      
      out <- c(
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        "<meta charset='utf-8'/>",
        deps,
        html_tags$head,
        "</head>",
        "<body>",
        html_tags$html,
        "</body>",
        "</html>")
    }
  }
  
  if (!is.null(output_path)) {
    writeLines(out, output_path, useBytes = TRUE)
  } else {
    paste(out, collapse = '')
  }
}

update_dep_path <- function(dep, libdir = 'lib') {
  dir <- dep$src$file
  if (!is.null(dep$package))
    dir <- system.file(dir, package = dep$package)
  
  if (length(libdir) != 1 || libdir %in% c("", "/"))
    stop("libdir must be of length 1 and cannot be '' or '/'")
  
  target <- if (getOption('htmltools.dir.version', TRUE)) {
    paste(dep$name, dep$version, sep = '-')
  } else {
    dep$name
  }
  dep$src$file <- file.path(libdir, target)
  dep
}
```

Essentially the API has 2 endpoints.

* widget
  + returns output from `write_widget()` given element_id and type
* hdata
  + returns iris data as JSON

```r
widget <- function(element_id, type, get_all = FALSE, cdn = 'public', ...) {
  dat <- get_iris(get_all)
  if (grepl('dt', element_id)) {
    w <- dat %>%
      datatable(options = list(
        pageLength = 5,
        lengthMenu = c(5, 10)
      ))
  } else if (grepl('highchart', element_id)) {
    w <- dat %>% 
      hchart('scatter', hcaes(x = 'Sepal.Length', y = 'Sepal.Width', group = 'Species')) %>%
      hc_title(text = 'Iris Scatter')
  } else if (grepl('plotly', element_id)) {
    w <- dat %>%
      plot_ly(x = ~Sepal.Length, y = ~Sepal.Width, z = ~Petal.Length, color = ~Species)
  } else {
    stop('Unexpected element')
  }
  write_widget(w, element_id, type, cdn)
}

hdata <- function() {
  dat <- get_iris(TRUE)
  names(dat) <- sub('\\.', '', names(dat))
  dat %>% toJSON()
    
}

get_iris <- function(get_all = FALSE) {
  Sys.sleep(2)
  if (!get_all) {
    iris[sample(1:nrow(iris), 10),]    
  } else {
    iris
  }
}
```

`process_request()` remains largely the same but needs some modification so that it can be used as a backend of a web app.

* [Cross-Origin Resource Sharing (CORS)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
  + requests from browser will fail without necessary headers and handling *OPTIONS* method
* Response content type
  + depending on _type_, response content type will be either _application/json_ or _text/html_

See *API Development with R* series ([Part I](/blog/2017-11-18-api-development-with-r-1), [Part II](/blog/2017-11-19-api-development-with-r-2)) for further details of `process_request()` and how RServe's built-in HTTP server works.

```r
process_request <- function(url, query, body, headers) {
  #### building request object
  request <- list(uri = url, method = 'POST', query = query, body = body)
  
  ## parse headers
  request$headers <- parse_headers(headers)
  if ("request-method" %in% names(request$headers))
    request$method <- c(request$headers["request-method"])
  
  set_headers <- function(...) {
    paste(list(...), collapse = '\r\n')
  }
  
  h1 <- 'Access-Control-Allow-Headers: Content-Type'
  h2 <- 'Access-Control-Allow-Methods: POST,GET,OPTIONS'
  h3 <- 'Access-Control-Allow-Origin: *'
  
  cors_headers <- set_headers(h1, h2, h3)

  if (request$method == 'OPTIONS') {
    return (list('', 'text/plain', cors_headers))
  }
  
  request$pars <- list()
  if (request$method == 'POST') {
    if (!is.null(body)) {
      if (is.raw(body))
        body <- rawToChar(body)
      if (any(grepl('application/json', request$headers)))
        body <- jsonlite::fromJSON(body)
      request$pars <- as.list(body)
    }
  } else {
    if (!is.null(query)) {
      request$pars <- as.list(query)
    }
  }
  
  if ('type' %in% names(request$pars)) {
    if (request$pars$type == 'json') {
      content_type <- 'application/json; charset=utf-8'
    } else {
      content_type <- 'text/html; charset=utf-8'
    }
  } else {
    content_type <- 'text/plain; charset=utf-8'
  }
  
  message(sprintf('Header:\n%s', cors_headers))
  message(sprintf('Content Type: %s', content_type))
  message('Params:')
  print(do.call(c, request$pars))
  
  #### building output object
  matched_fun <- gsub('^/', '', request$uri)
  
  payload <- tryCatch({
    do.call(matched_fun, request$pars)
  }, error = function(err) {
    'Internal Server Error'
  })
  
  return (list(payload, content_type, cors_headers))
}
``` 

The source can be found in [here](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/tree/master/api) and the API deployment is included in the [docker compose](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/blob/master/compose-all/docker-compose.yml).

### JavaScript Frontend
The app will be kept in [index.html](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/blob/master/javascript/index.html) and will be served by a simple [python web server](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/blob/master/javascript/serve.py). Basically the same Bootstrap page is created.

It is important to keep all the widgets' dependent JavaScript and CSS in _head_. We have 3 htmlwidgets and they are wrapped by the *htmlwidgets* package. Therefore it depends on

* htmlwidgets
* DataTables for DT
* Highcharts for highcharter
* Plotly for plotly
* CrossTalk for DT and plotly
* Bootstrap for layout
* __JQuery__ for all

Note that a htmlwidget package tends to rely on a specific JQuery library. For example, the *DT* package uses 1.12.4 while the *highcharter* uses 1.11.1. Therefore there is a chance to encounter version incompatibility if multiple htmlwidget packages rendered at the same time. The HTML source of Shiny can be helpful because it holds a JQuery lib that can be shared across all widget packages.

```html
<head>
  <meta charset='utf-8'/>
  <!-- necessary to control htmlwidgets -->
  <script src="/public/htmlwidgets/htmlwidgets.js"></script>
  <!-- need a shared JQuery lib -->
  <script src="/public/shared/jquery.min.js"></script>
  <!-- DT -->
  <script src="/public/datatables/datatables.js"></script>
  ... more DT dependencies
  <!-- highchater -->
  <script src="/public/highcharter/lib/proj4js/proj4.js"></script>
  ... more highcharts dependencies
  <script src="/public/highcharter/highchart.js"></script>
  <!-- plotly -->
  <script src="/public/plotly/plotly.js"></script>
  ... more plotly dependencies
  <!-- crosstalk -->
  <script src="/public/crosstalk/js/crosstalk.min.js"></script>
  ... more crosstalk depencencies
  <!-- bootstrap, etc -->
  <script src="/public/shared/bootstrap/js/bootstrap.min.js"></script>
  ... more bootstrap, etc depencencies
</head>
```

The widget containers/elements as well as sizing script are added in *body*. The naming rules for the container and element are

* container - *htmlwidget_container_[element_id]*
* element - *htmlwidget_[element_id]*

In this structure, widgets can be updated if their data (_application/json script_) is added/updated to the page.

```html
<body>
  ... NAV
  <div class="container-fluid">
    ... TAB
    <div class="container-fluid">
      <div class="row">
        <div style="height: 400px;">
          <div class="col-sm-2">
            <button id="dt" type="button" 
                    class="btn btn-default action-button">
              update data table
            </button>
          </div>
          <div class="col-sm-10">
              <div id="htmlwidget_container_dt_out">
                <div id="htmlwidget_dt_out" 
                    style="width:100%;height:100%;" 
                    class="datatables html-widget">
                </div>
              </div>
          </div>
        </div>
      </div>
      ... highcharter wrapper
      ... plotly wrapper
    </div>

  </div>

<script type="application/htmlwidget-sizing" 
        data-for="htmlwidget_dt_out">
  {"browser":{"width":"100%","height":400,"padding":40,"fill":true}}
</script>
... hicharter sizing
... plotly sizing
```

As mentioned earlier, AJAX requests are made by clicking buttons and it's implemented in `req()`. Key steps are

* remove _html-widget-static-bound_ class from a widget
* makes a call with *element_id* and *type=src*
  + note to change _hostname_
* append or replace _application/json script_
  + for plotly, `purge()` chart. Otherwise traces added continuously
* execute `window.HTMLWidgets.staticRender()`

```html
<script type = "text/javascript" language = "javascript">
    function req(elem, tpe) {
     var btn_id = "#" + elem;
     var widget_id = "#htmlwidget_" + elem + "_out";
     var elem_id = elem + "_out";
     var data_for = "htmlwidget_" + elem + "_out";
     var scr_selector = 'script[type="application/json"][data-for="' + 
                          data_for + '"]';      
     $.support.cors = true;
     $(btn_id).prop("disabled", true);
     $(widget_id).removeClass("html-widget-static-bound");
     $.ajax({
       url: "http://[hostname]:8000/widget",
       data: { element_id: elem_id, type: tpe },
       error: function(err) {
         $(btn_id).removeAttr('disabled');
       },
       success: function(data) {
          //console.log(data)
          if($(scr_selector).length == 0) {
            $('body').append(data)
          } else {
            if (elem.includes('plotly')) {
              try {
                //Plotly.deleteTraces(htmlwidget_plotly_out, [0])
                Plotly.purge(data_for);
              }
              catch(err) {
                console.log(err);
              }
            }
            $(scr_selector).replaceWith(data);
          }
          setTimeout(function(){
            window.HTMLWidgets.staticRender();
          }, 500);
          $(btn_id).removeAttr('disabled');
       }
     });      
    }
    
    $(document).ready(function() {
      $("#dt").click(function() {
        req('dt', 'src');
      });
    });
    
    ... button clicks for highcharter and plotly
</script>
```

For comparison, the async Shiny app and the JavaScript frontend/backend are included in the [docker compose](https://github.com/jaehyeon-kim/more-thoughts-on-shiny/blob/master/compose-all/docker-compose.yml). The JavaScript app can be accessed in port 7000. Once started, it's possible to see widgets are rendered without delay when buttons are clicked multiple times.

Compared to the async Shiny app, the JavaScript app is more effective in handling multiple requests. The downside of it is the benefits that Shiny provides are no longer available. Some of them are built-in data binding, event handling and state management. For example, think about what `reactive*()` and `observe*()` do for a Shiny app. Although it is possible to setup those with plain JavaScript or JQuery, life will be a lot easier if an app is built with one of the popular JavaScript frameworks: [Angular](https://angularjs.org/), [React](https://reactjs.org/) and [Vue](https://vuejs.org/). In the next post, it'll be shown how to render htmlwidgets in a Vue application as well as building those with native JavaScript libraries.