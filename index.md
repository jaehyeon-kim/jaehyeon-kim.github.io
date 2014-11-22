---
layout: page
title: A blog about R, Scala and Machine Learning
---
{% include JB/setup %}

## Background

to complete

### R

to complete

### Scala

to complete

### Machine Learning

to complete

## Posts

Here's the posts list.

<ul class="posts">
  {% for post in site.posts %}
    <li><span>{{ post.date | date_to_string }}</span> &raquo; <a href="{{ BASE_PATH }}{{ post.url }}">{{ post.title }}</a></li>
  {% endfor %}
</ul>