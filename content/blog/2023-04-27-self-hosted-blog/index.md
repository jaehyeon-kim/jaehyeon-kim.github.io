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

I started blogging in 2014. At first, it was based on a simple Jekyll theme that supports posting a [Markdown](https://en.wikipedia.org/wiki/Markdown) file, which is converted from a [RMarkdown](https://github.com/rstudio/rmarkdown) file. Most of my work was in R at that time and the simple theme was good enough, and it was hosted via [GitHub Pages](https://pages.github.com/). It was around 2018 when I changed my blog with a single page application built by [Vue.js](https://vuejs.org/). It was fun to develop a blog site with the JavaScript framework as I was teaching myself web development in order to build an analytics portal for the company I used to work for. Also, I was able to learn the necessary infrastructure in AWS while hosting it using multiple AWS services - S3, CloudFront, ACM and Route53. I stopped writing posts from 2020 to early 2021 when my wife got pregnant and gave birth to my baby. Then I restarted publishing posts to my company's blog page from the middle of 2021. It is good as I can have a post peer-reviewed by colleagues and the company provides an incentive for each post published. However, I find it is not the right place to write small posts as I am recommended to keep in mind e.g. *how an article translates into better customer outcomes* before writing a post. It is a good recommendation, but it requires longer time to write a post while following those recommendations.

## Configuration

To be updated...

### Hugo Bootstrap Theme

To be updated...

## Custom Domain


```yaml
---
Parameters:
  DomainName:
    Description: Fully qualified domain name to secure with an SSL/TLS certificate (eg example.com)
    Type: String
  HostedZoneId:
    Description: Route53 hosted zone id
    Type: String
Resources:
  ACMCertificate:
    Type: AWS::CertificateManager::Certificate
    Properties:
      DomainName: Ref: DomainName
      DomainValidationOptions:
        - DomainName: Ref: DomainName
          HostedZoneId: Ref: HostedZoneId
      SubjectAlternativeNames:
        - !Sub "*.${DomainName}"
      ValidationMethod: DNS
Outputs:
  ACMCertificateArn:
    Value:
      Ref: ACMCertificate
```



## Comment Widget

While it supports multiple [comment widgets](https://hbs.razonyang.com/v1/en/docs/widgets/comments/), I decided to use [Giscus](https://giscus.app/), which is a lightweight comment widget built on GitHub discussions.

I first enabled *Discussions* in the repository *Settings* as shown below.

![](discussion-1.png#center)

After that the *Discussions* tab is showing at the top and there are multiple discussion categories. The widget requires a category for comments, and I am going to use the *General* category.

![](discussion-2.png#center)

Then we need to install the widget as a GitHub app, and it can be installed by visiting its [GitHub App page](https://github.com/apps/giscus).

![](giscus-1.png#center)

![](giscus-2.png#center)

The key configuration values for the widget are the repo name, repo ID and category ID. 

```yaml
# config/_default/params.yaml
...
giscus:
  repo: <repo-owner>/<repository-name>
  repoId: "<repository-id>"
  # category: ""
  categoryId: "<catetory-id>"
  # theme: "dark" # Default to auto.
  # mapping: "title" # Default to pathname.
  inputPosition: "bottom" # Default to top.
  reactions: true # Disable reactions.
  metadata: true # Emit discussion metadata.
  # lang: "en" # Specify language, default to site language.
  # lazyLoading: false # Default to true.
...
```

The repository and category IDs can be queries on the [GitHub GraphQL API Explorer](https://docs.github.com/en/graphql/overview/explorer) as shown below. In the query, it is limited to show only the first one, and you may increase the number if the category you want to use is not queried.

```js
query {
  repository(owner: "<repo-owner>", name: "<repository-name>") {
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
```

```json
{
  "data": {
    "repository": {
      "id": "<repository-id>",
      "name": "<repository-name>",
      "discussionCategories": {
        "nodes": [
          {
            "id": "<catetory-id>",
            "name": "General"
          }
        ]
      }
    }
  }
}
```

![](comment-1.png#center)

![](comment-2.png#center)

![](comment-3.png#center)

![](comment-4.png#center)