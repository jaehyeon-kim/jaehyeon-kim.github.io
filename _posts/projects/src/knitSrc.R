knitPost <- function(title, base.url = "../../") {
  require(knitr)
  opts_knit$set(base.url = base.url)
  fig.path <- paste0(base.url,"figs/", sub(".Rmd$", "", basename(title)), "/")
  opts_chunk$set(fig.path = fig.path)
  opts_chunk$set(fig.cap = "center")
  render_jekyll()
  knit(paste0(title,".Rmd"), paste0("../",title,".md"), envir = parent.frame())
}