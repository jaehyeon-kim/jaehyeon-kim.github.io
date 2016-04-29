---
layout: post
title: "2014-12-22-Learning-Scala-Ch1"
description: ""
category: scala
tags: [programming]
---
This post summarises notes and/or exercise solutions of _Chapter 1 Getting Started With The Scalable Language_ of [Learning Scala](http://chimera.labs.oreilly.com/books/1234000001798/index.html) by  Jason Swartz. More complete solutions can be found [HERE](https://github.com/swartzrock/LearningScalaMaterials). Scala code is originally executed in a Eclipse Scala worksheet.

#### Exercises

##### 1. Although `println()` is a good way to print a string, can you find a way to print a string without `println`? Also, what kind of numbers, strings and other data does the REPL support?


{% highlight r %}
print("a string")
{% endhighlight %}

##### 2. In the Scala REPL, convert the temperature value of 22.5 Centigrade to Fahrenheit. The conversion formula is _cToF(x) = (x * 9/5) + 32_.


{% highlight r %}
var celTemp = 22.5
var fahTemp = (celTemp * 9/5) + 32
{% endhighlight %}

##### 3. Take the result from exercise 2, half it, and convert it back to Centigrade. You can use the generated constant variable (e.g. **res0**) instead of copying and pasting the value yourself.


{% highlight r %}
celTemp = (fahTemp/2 - 32) * 5/9
celTemp
{% endhighlight %}

##### 4. The REPL can load and interpret Scala code from an external file with the `:load <file>` command. Create a new file named _Hello.scala_ and add a command that will print a greeting, then execute it from the REPL.


{% highlight r %}
// Not working in scala worksheet and tested in REPL
:load Hello.scala

// note: some ways to check current path
new java.io.File(".").getCanonicalPath
new java.io.File(".").getAbsolutePath
{% endhighlight %}

##### 5. Another way to load external Scala code is to paste it into the repl in _raw_ mode, where the code is compiled as if it were actually in a proper source file. To do this, type `:paste -raw`, hit return, and then paste the contents of your source file from exercise 4. After exiting `paste` mode you should see the greeting.


{% highlight r %}
// Not working in scala worksheet and tested in REPL
:paste
// Entering paste mode (ctrl-D to finish)
println("Hello world")

// Exiting paste mode, now interpreting.
Hello world
{% endhighlight %}
