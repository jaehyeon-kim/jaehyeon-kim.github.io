---
layout: post
title: "2015-01-03-Learning-Scala-Ch4"
description: ""
category: scala
tags: [programming]
---
{% include JB/setup %}

This post summarises notes and/or exercise solutions of _Chapter 4 Functions_ of [Learning Scala](http://chimera.labs.oreilly.com/books/1234000001798/index.html) by  Jason Swartz. More complete solutions can be found [HERE](https://github.com/swartzrock/LearningScalaMaterials). Scala code is originally executed in a Eclipse Scala worksheet.

#### Notes

##### function is a named, reusable expression


{% highlight r %}
def safeTrim(s: String): String = {
	if (s == null) return null // early termination
	s.trim()
}
def safeTrim1(s: String) = if (s == null) null else s.trim()
{% endhighlight %}

##### procedure is a function that doesn’t have a return value


{% highlight r %}
def log(d: Double) = println(f"Got value $d.2f")
{% endhighlight %}

##### functions with side effects should use parentheses


{% highlight r %}
def hi = "Hi"
def hi1() = println("Hi")
{% endhighlight %}
##### invoking a function using a single parameter with expression blocks


{% highlight r %}
def formatDollar(amt: Double) = "$" + f"$amt%.2f"
formatDollar(1 + 2.4567)
formatDollar { val base = 1; base + 2.4567 }
{% endhighlight %}

##### recursive function - should specify return type
- stack overflow problem can be handled by tail recursion
- with tail-recursion-optimized functions, recursive invocation doesn’t create new stack space but instead uses the current function’s stack space
- only functions whose last statement is the recursive invocation can be optimized for tail-recursion by the Scala compiler
- use function annotation: @annotation.tailrec


{% highlight r %}
// error: multiplication is the last statement, not the recursive call
object tailRecError{
  @annotation.tailrec
  def power1(x: Int, n: Int): Long = {
  	if (n >= 1) x * power1(x, n-1)
  	else 1
  }

  def power2(x: Int, n: Int): Long = {
  	if (n < 1) 1
  	else x * power2(x, n-1)
  }
}
{% endhighlight %}


{% highlight r %}
object tailRec{
  @annotation.tailrec
  def power(x: Int, n: Int, t: Int=1): Long = {
  	if(n >= 1) power(x, n-1, x*t)
  	else t
  }
  
  def add(x: Int, n: Int, t: Int=0): Long = {
  	if(n >= 1) add(x, n-1, x+t)
  	else t
  }
}
tailRec.power(2, 4)
tailRec.add(2, 4)
{% endhighlight %}

##### nested functions


{% highlight r %}
def max(a: Int, b: Int, c: Int) = {
// nested one takes precedence
	def max(x: Int, y: Int) = if(x > y) x else y
	max(a, max(b, c))
}
{% endhighlight %}

##### function can be invoked by named parameters


{% highlight r %}
def greet(name: String, prefix: String = "") = if(prefix.length()>0) s"$prefix $name" else s"$name"
greet(prefix = "Mr", name = "Brown")
greet("Brown")
{% endhighlight %}

##### variable number of input arguments


{% highlight r %}
def sum(items: Int*): Int = {
	var total = 0
	for(i <- items) total += i
	total
}
sum(10, 20, 30)
{% endhighlight %}

##### parameter groups


{% highlight r %}
def max1(x: Int)(y: Int) = if(x > y) x else y
val larger = max1(20)(39)
{% endhighlight %}

##### type parameters


{% highlight r %}
def identityS(s: String): String = s
def identityI(i: Int): Int = i

def identity[A](a: A): A = a // return type optional
val s = identity[String]("Hello")
val d = identity(2.717)
{% endhighlight %}

##### a method is a function defined in a class and available from any instance of the class


{% highlight r %}
d.round
d.ceil
d.round
d.compare(3.2) /* -1 0 1 */
d compare 3.2
d.+(3.2) /* d + 3.2 */
"Hello".substring(0, 2)
"Hello" substring(0, 2)
{% endhighlight %}

##### function comment example


{% highlight r %}
/**
* Returns the input string without leading or trailing
* whitespace, or null if the input string is null.
* @param s the input string to trim, or null
*/
def safeTrm(s: String): String = if(s==null) null else s.trim()
{% endhighlight %}

#### Exercises

##### 1. Write a function that computes the area of a circle given its radius.


{% highlight r %}
def area(r: Double) = Math.PI * Math.sqrt(r)
area(1)
{% endhighlight %}

##### 2. Provide an alternate form of the function in #1 that takes the radius as a String. What happens if your function is invoked with an emptyString ?


{% highlight r %}
def area1(r: String) = Math.PI * Math.sqrt(r.toDouble)
area1("") // java.lang.NumberFormatException: empty String
{% endhighlight %}

##### 3. Write a recursive function that prints the values from 5 to 50 by fives, without using for or while loops. Can you make it tail-recursive?


{% highlight r %}
object three {
	@annotation.tailrec
	def printNum(from: Int, to: Int): Unit = {
		if(from <= to) {
			println(from)
			printNum(from + 1, to)
		}
	}
}
three.printNum(5, 10)
{% endhighlight %}

##### 4. Write a function that takes a milliseconds value and returns a string describing the value in days, hours, minutes and seconds. What’s the optimal type for the input value?


{% highlight r %}
def convert(milliSec: Long) = {
	val rem = milliSec % 1000
	val sec = (milliSec / 1000) % 60
	val min = (milliSec / (1000 * 60)) % 60
	val hrs = (milliSec / (1000 * 60 * 60)) % 24
	val day = (milliSec / (1000 * 60 * 60 * 24))
	val str = (if(day>0) s"${day}d " else "") + (if(hrs>0) s"${hrs}h " else "") + (if(min>0) s"${min}m " else "") + (if(sec>0) s"${sec}s " else "")  + (if(rem>0) s"${rem}ms" else "")
println(str)
}
convert(123456789)
{% endhighlight %}

##### 5. Write a function that calculates the first value raised to the exponent of the second value. Try writing this first using math.pow, then with your own calculation. Did you implement it with variables? Is there a solution available that only uses immutable data? Did you choose a numeric type that is large enough for your uses?


{% highlight r %}
def pow1(base: Double, power: Double) = Math.pow(base, power)

def pow2(base: Double, power: Int) = {
	var accum = 1.0
	if(power <= 0) accum = 0
	else {
		for (i <- 1 to power) accum *= base
	}
	accum
}

object five {
  @annotation.tailrec
  def pow(base: Double, power: Int, initial: Double = 1.0): Double = {
  	if(power >= 1) pow(base, power - 1, base * initial)
  	else initial
  }
}
five.pow(2,4)
{% endhighlight %}

##### 6. Write a function that calculates the difference between a pair of 2d points (x and y) and returns the result as a point. Hint: this would be a good use for tuples (*Tuples*).


{% highlight r %}
def diff(first: (Int, Int), second: (Int, Int)) = {
	((first._1 - second._1), (first._2 - second._2))
}
val point = diff((1,0),(2,3))
{% endhighlight %}

##### 7. Write a function that takes a 2-sized tuple and returns it with the Int value (if included) in the first position. Hint: this would be a good use for type parameters and the isInstanceOf type operation.


{% highlight r %}
def intFirst[A,B](src: (A, B)) = {
	def isInt(a: Any) = a.isInstanceOf[Int]
	(isInt(src._1), isInt(src._2)) match {
		case (false, true) => (src._2, src._1)
		case _ => src
	}
}
intFirst("a",1)
{% endhighlight %}

##### 8. Write a function that takes a 3-sized tuple and returns a 6-sized tuple, with each original parameter followed by its String representation. For example, invoking the function with (true, 22.25, "yes") should return (true, "true", 22.5, "22.5", "yes", "yes"). Can you ensure that tuples of all possible types are compatible with your function? When you invoke this function, can you do so with explicit types not only in the function result but in the value that you use to store the result?


{% highlight r %}
def expand[A,B,C](src: (A, B, C)) = {
	(src._1, src._1.toString, src._2, src._2.toString, src._3, src._3.toString)
}
expand((true,"a",3.2))
{% endhighlight %}
