---
title: Self-managed Blog with Hugo and GitHub Pages
date: 2023-04-27
draft: true
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
  - Blog
tags: 
  - Hugo
  - Bootstrap
  - GitHub Pages
authors:
  - JaehyeonKim
images: []
cevo: 26
description: abc
---

I started writing blog posts in 2014. At first, it was based on a simple Jekyll theme that supports posting a [Markdown](https://en.wikipedia.org/wiki/Markdown) file, which is converted by a [RMarkdown](https://github.com/rstudio/rmarkdown) file. Most of my work was in R at that time and the simple theme was good enough to publish posts via [GitHub Pages](https://pages.github.com/). It was around 2018 when I changed my blog with a single page application built by [Vue.js](https://vuejs.org/). It was fun to develop a blog site with the JavaScript framework as I was teaching myself web development seriously while developing an analytics platform for the company I used to work for. Also, I was able to learn the necessary infrastructure in AWS as it was hosted using a group of AWS services - S3, CloudFront, ACM and Route53.

TO BE UPDATED

```
# https://docs.github.com/en/graphql/overview/explorer
query {
  repository(owner: "jaehyeon-kim", name: "jaehyeon-kim.github.io") {
    id # RepositoryID
    name
    discussionCategories(first: 1) {
      nodes {
        id # CategoryID
        name
      }
    }
  }
}


{
  "data": {
    "repository": {
      "id": "MDEwOlJlcG9zaXRvcnkyNjgwMjU0NQ==",
      "name": "jaehyeon-kim.github.io",
      "discussionCategories": {
        "nodes": [
          {
            "id": "DIC_kwDOAZj5cc4CV2fp",
            "name": "General"
          }
        ]
      }
    }
  }
}
```