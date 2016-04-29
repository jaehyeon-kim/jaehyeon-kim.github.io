---
layout: post
title: "2014-11-19-R-Rroject-Setup"
description: ""
category: Intro
tags: [knitr, CentOS]
---
{% include JB/setup %}

The setup of R project is modified from [Jason Fisher's blog](http://jfisher-usgs.github.io/r/2012/07/03/knitr-jekyll/). Instead of moving a markdown (md) and figure folder into the blog repository after they have been created, a R project named **projects** is created in the **_posts** folder so that articles can be created in the same repository. 

Note that the title of a R markdown (Rmd) file is in **_yyyy-mm-dd-article-name.Rmd**. Basically Jekyll parses a markdown (md) file if its title is in **yyyy-mm-dd-article-name.md** in the **_posts** and its subfolders. However it also parses Rmd files as well if they have the same title formats. Therefore, if a Rmd file is created and converted into a md file, there will be two duplicate articles.

In order to produce only a single article, an underscore is added to the beginning of a Rmd file and it is removed when the Rmd file is converted into a md file. Specifically a R script file named **knitSrc.R** is created in the **src** folder in the project root folder. Then a function named **knitPost** is created, which `knit` a Rmd file into a md file in the parent directory ("../") without the underscore in the title.

The **knitPost** function is shown below.


{% highlight r %}
knitPost <- function(title, base.url = "../../") {
  require(knitr)
  opts_knit$set(base.url = base.url)
  # figures saved in subfolders where their titles are the same to articles titles
  fig.path <- paste0(base.url,"figs/", sub(".Rmd$", "", basename(title)), "/")
  opts_chunk$set(fig.path = fig.path)
  opts_chunk$set(fig.cap = "center")
  render_jekyll()
  # md file moved to parent directory without underscore at the beginning
  knit(paste0("_",title,".Rmd"), paste0("../",title,".md"), envir = parent.frame())
}
{% endhighlight %}

**Update on 2014-12-06**: The [original blog](http://jfisher-usgs.github.io/r/2012/07/03/knitr-jekyll/) sets the base URL as the root URL: `base.url = "/"`. This is under the assumption that the **figs** folder locates on the root of the project repository. In order words, if I set the base URL as `base.url = "/"`, it'll indicate **https://github.com/jaehyeon-kim/jaehyeon-kim.github.io/tree/master/** of the [remote repository](https://github.com/jaehyeon-kim/jaehyeon-kim.github.io). However it is not possible to set the base URL as above in my local machine because I don't normally log on with the root account. Therefore an error was caused when I tested embedding charts on [2014-12-06-Testing-Charts](http://jaehyeon-kim.github.io/r/2014/12/06/Testing-Charts/).

In order to tackle down this error, the `knitPost` is modified. Note that

1. `fig.path` is set to be, for example, **./figs/2014-12-06-Testing-Charts/scatter-1.png** and I have to remove the dot at the beginning so that it can correctly indicate the **figs** directory from the root. i.e. **/figs/2014-12-06-Testing-Charts/scatter-1.png**
2. figures should be moved into the folder assumed above. i.e. **figs/2014-12-06-Testing-Charts**


{% highlight r %}
knitPost <- function(title, base.url = "") {
  require(knitr)
  opts_knit$set(base.url = base.url)
  fig.path <- paste0("./figs/", sub(".Rmd$", "", basename(title)), "/")
  opts_chunk$set(fig.path = fig.path)
  opts_chunk$set(fig.cap = "center")
  render_jekyll()
  knit(paste0("_",title,".Rmd"), paste0("../",title,".md"), envir = parent.frame())
  
  # move fig files
  moveFigs(fig.path)
}

moveFigs <- function(fig.path, ...) {
  # set working directory to be the project directory
  setwd("/home/jaehyeon/jaehyeon-kim.github.io/_posts/projects")
  
  if(file.exists(fig.path)) {    
    # create fig folder where a folder of each article will be moved
    if(!file.exists("../../figs")) { dir.create("../../figs")}  
    # create figure folder for an article
    if(!file.exists(paste0("../../",fig.path))) { dir.create(paste0("../../",fig.path)) }
    
    # copy figures
    from <- dir(fig.path, full.name = TRUE)
    to <- paste0("../../",from)
    mapply(file.copy, from=from, to=to) 
    
    # delete folder
    unlink("figs", recursive = TRUE)    
  }
}
{% endhighlight %}

With this function, it is possible to `knit` a Rmd file. For example,

    source("src/knitSrc.R")
    knitPost("2014-11-19-R-Rroject-Setup")

Finally the following CSS code is added to the _/assets/themes/twitter-2.0/css/bootstrap.min.css_ file to center images.

    [alt=center] { display: block; margin: auto; }


Still there is room to improvement and some of it is

1. A table is not shown correctly when it is created by `kable` function.

**Update on 2014-12-06**: The following CSS has been added to _/assets/themes/twitter-2.0/css/style.css_.

    /* table css http://www.textfixer.com/tutorials/css-tables.php */
    table {
      font-family: verdana,arial,sans-serif;
      font-size:11px;
      color:#333333;
      border-width: 1px;
      border-color: #666666;
      border-collapse: collapse;
    }
    table th {
      border-width: 1px;
      padding: 8px;
      border-style: solid;
      border-color: #666666;
      background-color: #dedede;
    }
    table td {
      border-width: 1px;
      padding: 8px;
      border-style: solid;
      border-color: #666666;
      background-color: #ffffff;
    }

2. No article that embeds a figure is tested.

**Update on 2014-12-06**: Now charts can be embeded.
