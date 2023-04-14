---
layout: post
title: "2015-08-08-Some-Thoughts-on-Python"
description: ""
category: Python
tags: [programming]
---
When I bagan to teach myself C# 3 years ago, I only had some experience in interactive analysis tools such as MATLAB and R - I didn't consider R as a programming language at that time. The general purpose programming language shares some common features (data type, loop, if...) but it is rather different in the way how code is written/organized, which is object oriented. Therefore, while it was not a problem to grap the common features, it took quite some time to understand and keep my code in an object oriented way. 

Python, as another object-oriented programming language, the situation would be similar. The snippets in the following link show an example - ([Link](https://bitbucket.org/snippets/jaehyeon-kim/GApK6)). There 4 classes are defined to connect to the advertiser service of [Sizmek MDX API](http://platform.mediamind.com/Eyeblaster.MediaMind.API.Doc/?v=3). 

Specifically

Auth - class to keep authentication token
Advertiser - class to keep properties and methods to connect to the advertiser service
Soap - class to keep methods that are related to SOAP service
Helper - class to keep utility methods

Then, as seen in *example.py*, advertiser details can be requested by `Advertiser.GetItemRes()`, parsed by `Advertiser.GetItem()` and printed by `Helper.PrintObjects()`. I admit that the code wouldn't be Pythonic as I'm still teaching myself the language but the idea of expressing code in an object oriented way should be valid. In this regard, it would be important to appreciate and adopt this style of coding for successful Python development. (A more extended demo can be found in [my GitHub repo](https://github.com/jaehyeon-kim/sizmek_demo).)

Recently I happened to find a book titled [Introducing Python: Modern Computing in Simple Packages]( http://shop.oreilly.com/product/0636920028659.do). A more generic explanation would be made using it. Its table of contents with some grouping is listed below.

- **Intro**
    + Chapter 1, A Taste of Py
- **Common Features**
    + Chapter 2, Py Ingredients: Numbers, Strings, and Variables
    + Chapter 3, Py Filling: Lists, Tuples, Dictionaries, and Sets
    + Chapter 4, Py Crust: Code Structures
    + Chapter 5, Py Boxes: Modules, Packages, and Programs
- **OOP**
    + Chapter 6, Oh Oh: Objects and Classes
- Application**
    + Chapter 7, Mangle Data Like a Pro
    + Chapter 8, Data Has to Go Somewhere
    + Chapter 9, The Web, Untangled
    + Chapter 10, Systems
    + Chapter 11, Concurrency and Networks
- **A typical development workflow**
    + Chapter 12, Be a Pythonista

Beginning with an introduction in Chapter 1, it covers the common features in Chapter 2 to 5 and OOP is the topic of Chapter 6. Up to this, the fundamentals of Python are covered and the rest can be considered as applications. Specifically text and Unicode data can be handled (Chapter 7), data can be processed to and from external data sources (Chapter 8), web services can be consumed/produced (Chapter 9), system functions (file, directory...) can be accessed/modified (Chapter 10) and performance can be improved (Chapter 11).  Note that, for the application parts, it should be understood what to do well. For example, it is hardly successful to process data to/from a database if one doesn't know how database works.

I find this book is well organized and covers enough topics related to Python itself, its standard/3rd party libraries, and development with it. This book can be used as a comprehensive guide for new or intermediate Python programmers. (Note that the book focuses on Python 3 but the different between Python 2 and 3 would be minimal.)

To summarise, in order for successful Python development, its fundamentals should be understood well (and don't forget it is an object-oriented language) as well as programming targets (or what to program).
