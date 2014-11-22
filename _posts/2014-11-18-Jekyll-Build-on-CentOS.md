---
layout: post
title: "2014-11-18-Jekyll-Build-on-CentOS"
description: ""
category: intro
tags: [jekyll, CentOS]
---
{% include JB/setup %}

This blog has been influenced by [Jason Fisher's blog](http://jfisher-usgs.github.io/) and this article illustrates some modification of his [Jekyll Build on Windows](http://jfisher-usgs.github.io/lessons/2012/05/30/jekyll-build-on-windows/) to CentOS.

## GitHub

A [GitHub](https://github.com) repository was created, named _jaehyeon-kim.github.io_ - _jaehyeon-kim_ should be replaced with an individual user name. It is better to have a clean repository even without **README.md** as it is easier to `push` a local repository for the first time.

## Jekyll-Bootstrap

[Jekyll-Bootstrap](https://github.com/plusjade/jekyll-bootstrap/) was cloned into a folder which has the same name to the GitHub repository. Specifically

    $ git clone https://github.com/plusjade/jekyll-bootstrap.git jaehyeon-kim.github.io
    $ cd jaehyeon-kim.github.io
    $ git remote set-url origin git@github.com:jaehyeon-kim/jaehyeon-kim.github.io.git
    $ git push origin master

After a short while, it is possible to access the blog by typing **http://username.github.io**

## Ruby

While a [Ruby](http://www.ruby-lang.org/en/) installer can be downloaded [here](http://rubyinstaller.org/downloads) on Windows, it can be installed through the yum package installer as illustrated in [this site](https://www.digitalocean.com/community/tutorials/how-to-install-ruby-on-rails-on-centos-6). 

However **Ruby 1.8.x** is the default installation on CentOS 6.6 and, in order to install Jekyll, **Ruby 1.9.3 or higher** is necessary. To install a different version of Ruby, see [this site](http://tecadmin.net/install-ruby-1-9-3-or-multiple-ruby-verson-on-centos-6-3-using-rvm/) - **Ruby 1.9.3** as installed for this blog.

After Ruby was installed, the RubyGems, which is a package management framework for Ruby, was installed - see [this site](https://www.digitalocean.com/community/tutorials/how-to-install-ruby-on-rails-on-centos-6) for further details. Finally, using the RubyGems, the Rake, a Ruby build tool, was installed (`gem install rake`).

## Twitter-2.0

Twitter-2.0 theme packaged for Jekyll-Bootstrap was installed for [responsive design](http://twitter.github.com/bootstrap/scaffolding.html#responsive).

    $ rake theme:install git="https://github.com/gdagley/theme-twitter-2.0"

After the install was successful, type **y** and enter to switch to the newly installed theme.

## Pygments

[Pygments](http://pygments.org/) is necessary for code hightlighting and this Python package can be installed via *easy_install*.

**Python 2.6.6** is already installed on CentOS 6.6. To install *easy_install*, the python-setuptools and python-setuptools-devel packages were installed via the yum package installer as illustrated in [this site](http://www.question-defense.com/2009/03/16/install-easy_install-via-yum-on-linux-centos-server).

After installing Pygments, _syntax.css_ was downloaded from [here](http://pygments.org/demo/35195/?style=tango) and all occurrences of *.syntax* were replaced with *.highlight*. Then this css file was saved as */assets/themes/twitter-2.0/css/syntax.css* and the following line was added to the *default.html* file:

    <link href="/assets/themes/twitter-2.0/css/syntax.css" rel="stylesheet" type="text/css">

## Jekyll Server

In order to check articles locally, Jekyll server was installed by the RubyGems, the server doesn't run currently. It is an issue to resolve as of Nov 18, 2014. At the moment, the only way to check articles before pushing the repository is through converting the Rmd files into HTML using _knitr_.

## Configuration

Configuration in *_config.yml* was modified as shown below. Note that [Disqus](http://disqus.com) for comments and [Google](http://www.google.com/analytics/) for web analytics were set up as can be checked in the configuration section.

    title : R, Scala and Machine Learning
    tagline: Blog
    author :
      name : Jaehyeon Kim
      email : dottami@gmail.com
      github : jaehyeon-kim

    # Production URL
    production_url : http://jaehyeon-kim.github.io

    comments :
      provider : disqus
      disqus :
        short_name : short-name-set-up-at-disque

    analytics :
      provider : google
      google :
        tracking_id : 'tracking-id-give-by-google-analytics'
