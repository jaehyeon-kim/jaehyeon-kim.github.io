---
layout: post
title: "2015-01-18-Learning-Scala-Ch5"
description: ""
category: scala
tags: [programming]
---
This post summarises notes and/or exercise solutions of _Chapter 5 First Class Functions_ of [Learning Scala](http://chimera.labs.oreilly.com/books/1234000001798/index.html) by  Jason Swartz. More complete solutions can be found [HERE](https://github.com/swartzrock/LearningScalaMaterials). Scala code is originally executed in a Eclipse Scala worksheet.

### Notes

#### functions can be treated as data - store in values assigning static type


{% highlight r %}
def double(x: Int): Int = x*2
double(5)

val myDouble: (Int) => Int = double
myDouble(5)

val myDoubleCopy = myDouble
myDoubleCopy(5)

// if single parameter
val myDouble1 = double _
myDouble1(5)

def max(a: Int, b: Int) = if(a>b) a else b
val maximize: (Int, Int) => Int = max
maximize(50, 30)

def logStart() = "=" * 20 + "\nStarting NOW\n" + "=" * 20
var start: () => String = logStart
println(start())
{% endhighlight %}

#### higher-order functions


{% highlight r %}
def safeStringOp(s: String, f: String => String) = {
  if(s!=null) f(s) else s
}
def reverser(s: String) = s.reverse
safeStringOp(null, reverser)
safeStringOp("Ready", reverser)
{% endhighlight %}

#### function literals


{% highlight r %}
val doubler = (x: Int) => x * 2
val doubled = doubler(22)

val greeter = (name: String) => s"Hello, $name!"
val hi = greeter("World")
{% endhighlight %}

#### assigning function value vs function literal


{% highlight r %}
def max1(a: Int, b: Int) = if(a>b) a else b
val maximize1: (Int, Int) => Int = max1
val maximize2 = (a: Int, b: Int) => if(a>b) a else b

def logStart1() = "=" * 20 + "\nStarting NOW\n" + "=" * 20
val logStart2 = () => "=" * 20 + "\nStarting NOW\n" + "=" * 20
println(logStart1())
println(logStart2())

def safeStringOp1(s: String, f: String => String) = {
  if(s!=null) f(s) else s
}
safeStringOp1(null, (s: String) => s.reverse)
safeStringOp1("Ready", (s: String) => s.reverse)
safeStringOp1("Ready", s => s.reverse)
{% endhighlight %}

#### placeholder (_) syntax

- the explicit type of the function is specified outside the literal and
- the parameters are used no more than once.


{% highlight r %}
val doubler1: Int => Int = _ * 2
safeStringOp1(null, _.reverse)
safeStringOp1("Ready", _.reverse)

def combination(x: Int, y: Int, f: (Int, Int) => Int) = f(x,y)
combination(23, 12, _*_)

def tripleOp(a: Int, b: Int, c: Int, f: (Int, Int, Int) => Int) = f(a,b,c)
tripleOp(23, 92, 14, _ * _ + _)

def tripleOp1[A,B](a: A, b: A, c: A, f: (A,A,A) => B) = f(a,b,c)
tripleOp1[Int, Int](23, 92, 14, _ * _ + _)
tripleOp1[Int, Double](23, 92, 14, 1.0 * _ * _ + _)
tripleOp1[Int, Boolean](93, 92, 14, _ > _ + _)
{% endhighlight %}

#### partially-applied functions and currying


{% highlight r %}
def factorOf(x: Int, y: Int) = y % x == 0
def f = factorOf _
val x = f(7, 20)

val multipleOf3 = factorOf(3, _: Int)
val y = multipleOf3(78)

def factorOf1(x: Int)(y: Int) = y % x == 0
val isEven = factorOf1(2) _
val z = isEven(32)
{% endhighlight %}

#### by-name parameters can take either a value or a function

- if a function is entered, it'll be invoked every time that can cause a performance issue


{% highlight r %}
def doubles(x: => Int) = {
	println("Now doubling " + x)
	x * 2
}
doubles(5)
def f1(i: Int) = { println(s"Hello from f($i)"); i}
doubles(f1(8))
{% endhighlight %}

#### partial functions can only partially apply to their input data (eg div by 0)

- error if other than 200, 400, 500 is entered
- possible usage - 'collect' every item in a collection that is accepted by a given partial function


{% highlight r %}
val statusHandler: Int => String = {
	case 200 => "Ok"
	case 400 => "Your error"
	case 500 => "Our error"
}
{% endhighlight %}

#### invoking higher-order functions with function literal blocks


{% highlight r %}
def safeStringOp2(s: String, f: String => String) = {
	if(s != null) f(s) else s
}
val uuid = java.util.UUID.randomUUID.toString
val timedUUID = safeStringOp2(uuid, {s =>
	val now = System.currentTimeMillis
	val timed = s.take(24) + now
	timed.toUpperCase
})

def safeStringOp3(s: String)(f: String => String) = {
	if(s!=null) f(s) else s
}
val timedUUID1 = safeStringOp3(uuid) {s =>
	val now = System.currentTimeMillis
	val timed = s.take(24) + now
	timed.toUpperCase
}

def timer[A](f: A): A = {
	def now = System.currentTimeMillis
	val start = now; val a = f; val end = now;
	println(s"Executed in ${end - start} ms")
	a
}
val veryRandomAmount = timer {
	util.Random.setSeed(System.currentTimeMillis)
	for(i <- 1 to 100000) util.Random.nextDouble
	util.Random.nextDouble
}
{% endhighlight %}

### Exercises

#### 1. Write a function literal that takes two integers and returns the higher number. Then write a higher-order function that takes a 3-sized tuple of integers plus this function literal, and uses it to return the maximum value in the tuple.


{% highlight r %}
val maximize3 = (a: Int, b: Int) => if(a>b) a else b
def tupHF(t: (Int, Int, Int), f: (Int, Int) => Int) = {
	f(t._1, f(t._2, t._3))
}
tupHF((1,2,3), maximize3)
{% endhighlight %}

#### 2. The library function util.Random.nextInt returns a random integer. Use it to invoke the "max" function with two random integers plus a function that returns the larger of two given integers. Do the same with a function that returns the smaller of two given integers, and then a function that returns the second integer every time.


{% highlight r %}
max(util.Random.nextInt, util.Random.nextInt)
val tup = (util.Random.nextInt, util.Random.nextInt, util.Random.nextInt)
tupHF(tup, (a, b) => if(a>b) b else a)
{% endhighlight %}

#### 3. Write a higher-order function that takes an integer and returns a function. The returned function should take a single integer argument (say, "x") and return the product of x and the integer passed to the higher-order function.


{% highlight r %}
def fcn(a: Int) = (b: Int) => a * b
val tripler = fcn(3)
tripler(10)
{% endhighlight %}

#### 4. Let’s say that you happened to run across this function while reviewing another developer’s code:


{% highlight r %}
def fzero[A](x: A)(f: A => Unit): A = { f(x); x }
fzero("Hello")(s => println(s.reverse))
// invoke function and return the argument
{% endhighlight %}

#### 5. There’s a function named "square" that you would like to store in a function value. Is this the right way to do it? How else can you store a function in a value?


{% highlight r %}
def sqr(m: Double) = m * m
val sq = sqr _
val sq1: Double => Double = sqr
{% endhighlight %}

#### 6. Write a function called "conditional" that takes a value x and two functions, p and f, and returns a value of the same type as x. The p function is a predicate, taking the value x and returning a Boolean b. The f function also takes the value x and returns a new value of the same type. Your "conditional" function should only invoke the function f(x) if p(x) is true, and otherwise return x. How many type parameters will the "conditional" function require?


{% highlight r %}
def conditional[A](x: A, p: A => Boolean, f: A => A) = {
	if(p(x)) true else x
}
conditional[String]("Hello", _.size > 2, _.reverse)
{% endhighlight %}

#### 7. Do you recall the "typesafe" challenge from the exercises in Chapter 3? There is a popular coding interview question I’ll call "typesafe", in which the numbers 1 - 100 must be printed one per line. The catch is that multiples of 3 must replace the number with the word "type", while multiples of 5 must replace the number with the word "safe". Of course, multiples of 15 must print "typesafe".

Use the "conditional" function from exercise 6 to implement this challenge. Would your solution be shorter if the return type of "conditional" did not match the type of the parameter x? Experiment with an altered version of the "conditional" function that works better with this challenge.


{% highlight r %}
// ch 3
for (i <- 1 to 16) {
	i match {
		case x if x % 15 == 0 => println("typesafe")
		case x if x % 3 == 0 => println("type")
		case x if x % 5 == 0 => println("safe")
		case x => println(x)
	}
}
{% endhighlight %}


{% highlight r %}
def conditional1[A](x: A, p: A => Boolean, f: A => String): String = {
	if(p(x)) f(x) else ""
}

for (i <- 1 to 16) {
	val a1 = conditional1[Int](i, _ % 3 == 0, _ => "type")
	val a2 = conditional1[Int](i, _ % 5 == 0, _ => "safe")
	val a3 = conditional1[Int](i, _ % 3 != 0 && i % 5 != 0, x => s"$x")
	println(a1 + a2 + a3)
}
{% endhighlight %}
