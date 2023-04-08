---
layout: post
title: "2014-12-26-Learning-Scala-Ch2"
description: ""
category: scala
tags: [programming]
---
This post summarises notes and/or exercise solutions of _Chapter 2 Working With Data: Literals, Values, Variables, and Types_ of [Learning Scala](http://chimera.labs.oreilly.com/books/1234000001798/index.html) by  Jason Swartz. More complete solutions can be found [HERE](https://github.com/swartzrock/LearningScalaMaterials). Scala code is originally executed in a Eclipse Scala worksheet.

#### Notes

##### string interpolation and format


{% highlight r %}
val approx = 355/113f
println("Pi, using 355/113, is about " + approx + ".")
println(s"Pi, using 355/113, is about $approx.")

f"I wrote a new $approx%.3s today" // show 3.1
f"I wrote a new $approx%.4f today" // show 3.1416

val item = "apple"
s"How do you like them ${item}s"
{% endhighlight %}

##### regular expressions, see more [here](http://www.javacodegeeks.com/2011/10/scala-tutorial-regular-expressions.html)


{% highlight r %}
"Froggy went a' courting" matches ".* courting" // true
"milk, tea, muck".replaceAll("m[^ ]+k", "coffee") // coffee, tea, coffee
"milk, tea, muck" replaceFirst ("m[^ ]+k", "coffee") // coffee, tea, muck

val input = "Enjoying this apple 3.14159 times today"
val pattern = """.* apple ([\d.]+) times .*""".r
val pattern(amountText) = input
val amount = amountText.toDouble
{% endhighlight %}

##### relation among Scala types


{% highlight r %}
                  Numeric Types
   <-- AnyVal <-- Char
                  Boolean
Any                                          <-- Nothing
                  Collections
   <-- AnyRef <-- Classes         <-- Null
                  String
{% endhighlight %}

- The Unit type is unlike the other core types here (numeric and non-numeric) in that instead of denoting a type of data it denotes the lack of data.
- `&` and `&&`? - `|` (or `||`) don't evaluate the second argument if the first is sufficient
- Scala doesn't support automatic conversions to booleans eg non-null strings is not true, 0 is not false

##### type operations


{% highlight r %}
5.asInstanceOf[Long]
(7.0 / 5).getClass /* double */
"A".hashCode
20.toByte
47.toFloat
(3.0 / 4.0) toString
{% endhighlight %}

##### tuples


{% highlight r %}
val info = (5, "Korben", true)
val red = "red" -> "0xff0000"
val reversed = red._2 -> red._1
{% endhighlight %}

#### Exercises

##### 1. Write a new centigrade-to-fahrenheit conversion (using the formula `(x * 9/5) + 32`), saving each step of the conversion into separate values. What do you expect the type of each value will be?


{% highlight r %}
val celTemp = 22.5
val tempVal1 = celTemp * 9/5
val fahTemp = tempVal1 + 32
{% endhighlight %}

##### 2. Modify the centigrade-to-fahrenheit formula to return an integer instead of a floating-point number.


{% highlight r %}
fahTemp.toInt
{% endhighlight %}

##### 3. Using the input value 2.7255, generate the string **You owe $2.73 dollars**. Is this doable with string interpolation?


{% highlight r %}
val dol = 2.7255
s"You owe $dol dollars."
f"You owe $dol%.2f dollars."
{% endhighlight %}

##### 4. Is there a simpler way to write the following?


{% highlight r %}
val flag = false
val longResult = (flag == false)

val simpleResult = (false == false)
{% endhighlight %}

##### 5. Convert the number 128 to a Char, a String, a Double, and then back to an Int. Do you expect the original amount to be retained? Do you need any special conversion functions for this?


{% highlight r %}
val num = 128
val c = num.toChar
val s = c.toString
val d = s(0).toDouble // note not s.toDouble
val i = d.toInt
{% endhighlight %}

##### 6. Using the input string **Frank,123 Main,925-555-1943,95122** and regular expression matching, retrieve the telephone number. Can you convert each part of the telephone number to its own integer value? How would you store this in a tuple?


{% highlight r %}
val frank = "Frank,123 Main,925-555-1943,95122"
val numPattern = """.*,(\d{3})-(\d{3})-(\d{4}),.*""".r
val numPattern(num1,num2,num3) = frank
{% endhighlight %}
