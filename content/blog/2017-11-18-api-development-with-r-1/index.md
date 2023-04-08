---
title: API Development with R Part I
date: 2017-11-18
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - API development with R
categories:
  - Serverless
tags: 
  - R
  - Rserve
  - rApache
  - Plumber
authors:
  - JaehyeonKim
images: []
---
API is an effective way of distributing analysis outputs to external clients. When it comes to API development with R, however, there are not many choices. Probably development would be made with [plumber](https://github.com/trestletech/plumber), [Rserve](https://www.rforge.net/Rserve/), [rApache](http://rapache.net/) or [OpenCPU](https://www.opencpu.org/) if a client or bridge layer to R is not considered. 

This is 2 part series in relation to _API development with R_. In this post, serving an R function with _plumber_, _Rserve_ and _rApache_ is discussed. _OpenCPU_ is not discussed partly because it could be overkill for API. Also its performance may be similar to _rApache_ with [Prefork Multi-Processing Module](http://httpd.apache.org/docs/2.2/mod/prefork.html) enabled. Then deploying the APIs in a Docker container, making example HTTP requests and their performance will be discussed in [Part II](/2017/11/API-Development-with-R-Part-II).

## Plumber

The _plumber_ package is the easiest way of exposing an R function via API and it is built on top of the [httpuv](https://github.com/rstudio/httpuv) package. 

Here a simple function named _test_ is defined in _plumber-src.R_. `test()` returns a number after waiting the amount of seconds specified by _wait_. Note the details of HTTP methods and resource paths can be specified as the way how a function is documented. By default, the response is converted into a json string and it is set to be [unboxed](https://www.rplumber.io/docs/rendering-and-output.html#boxed-vs-unboxed-json).


```r
#' Test function
#' @serializer unboxedJSON
#' @get /test
#' @post /test
test <- function(n, wait = 0.5, ...) {
    Sys.sleep(wait)
    list(value = n)
}
```

The function can be served as shown below. Port 9000 is set for the _plumber_ API.

```r
library(plumber)
r <- plumb("path-to-plumber-src.R")
r$run(port=9000, host="0.0.0.0")
```

## Rserve

According to its project site, 

> Rserve is a TCP/IP server which allows other programs to use facilities of R from various languages without the need to initialize R or link against R library.

There are a number of [Rserve client libraries](https://www.rforge.net/Rserve/doc.html) and a HTTP API can be developed with one of them. For example, it is possible to set up a client layer to invoke an R function using the [pyRserve](https://pythonhosted.org/pyRserve/) library while a Python web freamwork serves HTTP requests.

Since _Rserve 1.7-0_, however, a client layer is not mandatory because it includes the [built-in R HTTP server](https://www.rforge.net/Rserve/news.html). Using the built-in server has a couple of benefits. First development can be simpler without a client or bridge layer. Also performance of the API can be improved. For example, _pyRserve_ waits for 200ms upon connecting to Rserve and this kind of overhead can be reduced significantly if HTTP requests are handled directly.

The [FastRWeb](https://www.rforge.net/FastRWeb/) package relies on Rserve's built-in HTTP server and basically it serves HTTP requests by sourcing an R script and executing a function named as _run_ - all source scripts must have `run()` as can be checked in the [source](https://github.com/s-u/FastRWeb/blob/master/R/run.R).

I find the _FastRWeb_ package is not convenient for API development for several reasons. First, as mentioned earlier, it sources an R script and executes `run()`. However, after looking into the source code, it doesn't need to be that way. Rather a more flexible way can be executing a function that's already loaded. Secondly _application/json_ is a popular content type but it is not understood by the built-in server. Finally, while it mainly aims to serve R graphics objects and HTML pages, json string can be effective for HTTP responses. In this regards, some modifications are maded as discussed below.

`test()` is the same to the _plumber_ API.

```r
#### HTTP RESOURCES
test <- function(n, wait = 0.5, ...) {
    Sys.sleep(wait)
    list(value = n)
}
```

In order to use the built-in server, a function named _.http.request_ should be found. Here another function named *process_request* is created and it is used instead of `.http.request()` defined in the _FastRWeb_ package. `process_request()` is basically divided into 2 parts: _builing request object_ and _building output object_.

* building request object - the request obeject is built so that the headers are parsed so as to identify the request method. Then the request parameters are parsed according to the request method and content type. 
* building output object - the output object is a list of _payload_, _content-type_, _headers_ and _status-code_. A function can be found by the request URL and it is checked if all function arguments are found in the request parameters. Then _payload_ is obtained by executing the matching function if all arguments are found. Otherwise the _400 (Bad Request) error_ will be returned.

```r
#### PROCESS REQUEST
process_request <- function(url, query, body, headers) {   
    #### building request object
    ## not strictly necessary as in FastRWeb, 
    ## just to make clear of request related variables
    request <- list(uri = url, method = 'POST', 
                        query = query, body = body)
    
    ## parse headers
    request$headers <- parse_headers(headers)
    if ("request-method" %in% names(request$headers)) 
        request$method <- c(request$headers["request-method"])

    ## parse parameters (function arguments)
    ## POST accept only 2 content types
    ## - application/x-www-form-urlencoded by built-in server
    ## - application/json
    ## used below as do.call(function_name, request$pars)
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

    #### building output object
    ## list(payload, content-type, headers, status_code)
    ## https://github.com/s-u/Rserve/blob/master/src/http.c#L358
    payload <- NULL
    content_type <- 'application/json; charset=utf-8'
    headers <- character(0)
    status_code <- 200
    
    ## generate payload (function output)
    ## function name must match to resource path for now
    matched_fun <- gsub('^/', '', request$uri)
    
    ## no resource path means no matching function
    if (matched_fun == '') {
        payload <- list(api_version = '1.0')
        if (grepl('application/json', content_type)) 
            payload <- jsonlite::toJSON(payload, auto_unbox = TRUE)
        return (list(payload, content_type, headers)) # default status 200
    }
    
    ## check if all defined arguments are supplied
    defined_args <- formalArgs(matched_fun)[formalArgs(matched_fun) != '...']
    args_exist <- defined_args %in% names(request$pars)
    if (!all(args_exist)) {
        missing_args <- defined_args[!args_exist]
        payload <- list(message = paste('Missing parameter -', 
                                        paste(missing_args, collapse = ', ')))
        status_code <- 400
    }
    
    if (is.null(payload)) {
        payload <- tryCatch({
            do.call(matched_fun, request$pars)
        }, error = function(err) {
            list(message = 'Internal Server Error')
        })
        
        if ('message' %in% names(payload))
            status_code <- 500
    }

    if (grepl('application/json', content_type)) 
        payload <- jsonlite::toJSON(payload, auto_unbox = TRUE)
    
    return (list(payload, content_type, headers, status_code))
}

# parse headers in process_request()
# https://github.com/s-u/FastRWeb/blob/master/R/run.R#L65
parse_headers <- function(headers) {
    ## process headers to pull out request method (if supplied) and cookies
    if (is.raw(headers)) headers <- rawToChar(headers)
    if (is.character(headers)) {
        ## parse the headers into key/value pairs, collapsing multi-line values
        h.lines <- unlist(strsplit(gsub("[\r\n]+[ \t]+"," ", headers), "[\r\n]+"))
        h.keys <- tolower(gsub(":.*", "", h.lines))
        h.vals <- gsub("^[^:]*:[[:space:]]*", "", h.lines)
        names(h.vals) <- h.keys
        h.vals <- h.vals[grep("^[^:]+:", h.lines)]
        return (h.vals)
    } else {
        return (NULL)
    }
}
```

`process_request()` replaces `.http.request()` in the source script of Rserve - it'll be explained futher in Part II. 


```r
## Rserve requires .http.request function for handling HTTP request
.http.request <- process_request
```

## rApache

> rApache is a project supporting web application development using the R statistical language and environment and the Apache web server.

_rApache_ provides multiple ways to specify an R function that handles incoming HTTP requests - see the [manual](http://rapache.net/manual.html) for details. Among the multiple _RHandlers_, I find using a [Rook](https://github.com/jeffreyhorner/Rook) application can be quite effective.

Here is the test function as a Rook application. As `process_request()`, it parses function arguments according to the request method and content type. Then a value is returned after wating the specified seconds. The response of a Rook application is a list of _status_, _headers_ and _body_.


```r
test <- function(env) {
    req <- Request$new(env)
    res <- Response$new()
    
    request_method <- env[['REQUEST_METHOD']]
    rook_input <- env[['rook.input']]$read()
    content_type <- env[['CONTENT_TYPE']]
    
    req_args <- if (request_method == 'GET') {
        req$GET()
    } else {
        # only accept application/json
        if (!grepl('application/json', content_type, ignore.case = TRUE)) {
            NULL
        } else if (length(rook_input) == 0) {
            NULL
        } else {
            if (is.raw(rook_input))
                rook_input <- rawToChar(rook_input)
            rjson::fromJSON(rook_input)
        }
    }
    
    if (!is.null(req_args)) {
        wait <- if ('wait' %in% names(req_args)) req_args$wait else 1
        n <- if ('n' %in% names(req_args)) req_args$n else 10
        Sys.sleep(wait)
        list(
            status = 200,
            headers = list('Content-Type' = 'application/json'),
            body = rjson::toJSON(list(value=n))
        )
    } else {
        list(
            status = 400,
            headers = list('Content-Type' = 'application/json'),
            body = rjson::toJSON(list(message='No parameters specified'))
        )
    }
}
```

This is all for Part I. In [Part II](/blog/2017-11-19-api-development-with-r-2), it'll be discussed how to deploy the APIs via a Docker container, how to make example requests and their performance. I hope this article is interesting.