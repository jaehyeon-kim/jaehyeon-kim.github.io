---
layout: post
title: "2014-11-19-R-Rroject-Setup"
description: ""
category: Intro
tags: [R]
---
{% include JB/setup %}

The setup of R project is modified from [Jason Fisher's blog](http://jfisher-usgs.github.io/r/2012/07/03/knitr-jekyll/). Instead of moving a markdown (md) and figure folder into the blog repository after they have been created, a R project named **projects** is created in the **_posts** folder so that articles can be created in the same repository. 

Note that the title of a R markdown (Rmd) file is in **_yyyy-mm-dd-article-name.Rmd**. Basically Jekyll parses a markdown (md) file if its title is in **yyyy-mm-dd-article-name.md** in the **_posts** and its subfolders. However it also parses Rmd files as well if they have the same title formats. Therefore, if a Rmd file is created and converted into a md file, there will be two duplicate articles.

In order to produce only a single article, an underscore is added to the beginning of a Rmd file and it is removed when the Rmd file is converted into a md file. Specifically a R script file named **knitSrc.R** is created in the **src** folder in the project root folder. Then a function named **knitPost** is created, which `knit` a Rmd file into a md file in the parent directory ("../") without the underscore in the title.

The **knitPost** function is shown below.

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

With this function, it is possible to `knit` a Rmd file.

    source("src/knitSrc.R")
    knitPost("2014-11-19-R-Rroject-Setup")

Finally the following CSS code is added to the /assets/themes/twitter-2.0/css/bootstrap.min.css file to center images.

    [alt=center] { display: block; margin: auto; }


Still there is room to improvement and some of it is

1. A table is not shown correctly when it is created by `kable` function.
2. No article that embeds a figure is tested.
