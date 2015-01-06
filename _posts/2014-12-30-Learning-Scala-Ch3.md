---
layout: post
title: "2014-12-30-Learning-Scala-Ch3"
description: ""
category: scala
tags: [programming]
---
{% include JB/setup %}

This post summarises notes and/or exercise solutions of _Chapter 3 Expressions and Conditionals_ of [Learning Scala](http://chimera.labs.oreilly.com/books/1234000001798/index.html) by  Jason Swartz. More complete solutions can be found [HERE](https://github.com/swartzrock/LearningScalaMaterials). Scala code is originally executed in a Eclipse Scala worksheet.

#### Notes

##### an expression is a single unit of code that returns a value

- a value can be defined using expressions

```
val x = 5 * 20
val amt = x + 10
```

##### an expression block has its own scope and may contain values arne variables

```
val amount = {
	val x = 5 * 20
	x + 10
}

{ val a = 1; { val b = a * 2; { val c = b + 4; c } } }
```

##### a statement is an expression that doesn't return a value. eg println (which returns Unit), value/variable definitions

```
val y = 1
```

##### unlike switch, match can be used with types, regular expressions, numeric ranges and data structure contents as well as values

```
val maxByIf = if (x > y) x else y
val maxByMatch = x > y match {
	case true => x
	case _ => y
}

val status = 500
val message = status match {
	case 200 => "ok"
	case 400 => {
		println("ERROR - we called the service incorrectly")
		"error"
	}
	case 500 => {
		println("ERROR - the service encountered an error")
		"error"
	}
	case _ => {
		println("ERROR - the service encountered an unspecified error")
		"error"
	}
}

```

##### wildcard binding of unknown pattern

```
val day = "MOM"
val kind = day match {
	case "MON" | "TUE" | "WED" | "THU" | "FRI" => "weekday"
	case "SAT" | "SUN" => "weekend"
	case _ => {
		println(s"$day is unknown")
		"unknown"
	}
}
```

##### value binding of unknown pattern

```
val kind1 = day match {
	case "MON" => "monday"
	case other => {
		println(s"$other is unknown")
		"unknown"
	}
}
```

##### matching with pattern guards

```
val response: String = null
response match {
	case s if s != null => println(s"Received '$s'")
	case s => println("Error! Received a null response")
}
```

##### matching types with pattern variables. eg actual type can be mapped

```
val xVal: Int = 12180
val yVal: Any = xVal
yVal match {
	case x: String => s"'$x'"
	case x: Double => f"$x%.2f"
	case x: Float => f"$x%.2f"
	case x: Long => s"${x}l"
	case x: Int => s"${x}i"
	case _ => yVal
}
```

##### iterator guards

```
val timesOfThree = for (i <- 1 to 20 if i % 3 == 0) yield i
val quote = "Faith,Hope,,Charity"
for {
	q <- quote.split(",")
	if q != null
	if q.size > 0
} yield q
```

##### nested iterators

```
for {
	x <- 1 to 2
	y <- 1 to 3
} yield (x,y)
```

##### value binding

```
for (i <- 0 to 8; pow = 1 << i) yield pow
```

##### while and do/while <- only statements, no yield

```
var inc = 10
while (inc > 0) inc -= 1

do inc += 1 while (inc < 10)
inc

```

#### Exercises

##### 1. Given a string name, write a match expression that will return the same string if non-empty, or else the string _n/a_ if it is empty.

```
val emptyStr = ""
emptyStr match {
	case s if !s.isEmpty() => s
	case _ => "n/a"
}
```

##### 2. Given a double amount, write an expression to return _greater_ if it is more than zero, _same_ if it equals zero, and _less_ if it is less than zero. Can you write this with if..else blocks? How about with match expressions?

```
val dblAmt = 0.1
if (dblAmt < 0) "less" else if (dblAmt == 0) "same" else "greater"
dblAmt match {
case a if a < 0 => "less"
case a if a == 0 => "same"
case a if a > 0 => "greater"
}
```

##### 3. Write an expression to convert one of the input values _cyan_, _magenta_, _yellow_ to their 6-char hexadecimal equivalents in string form. What can you do to handle error conditions?

```
val color = "magenta"
color match {
	case "cyan" => "00ffff"
	case "magenta" => "00ff00"
	case "yellow" => "ffff00"
	case other => {
		println(s"Cannot convert $other")
		"n/a"
	}
}

```
##### 4. Print the numbers 1 to 10, with each line containing a group of 5 numbers.

```
for (i <- 1 to 10; if i % 5 == 0) { println(s"${i-4}, ${i-3}, ${i-2}, ${i-1}, ${i}") }
for (i <- 1 to 10 by 5) {
	for (j <- i to (i + 4)) print(s"$j, ")
	println("")
}

```
##### 5. There is a popular coding interview question I’ll call _typesafe_, in which the numbers 1 - 100 must be printed one per line. The catch is that multiples of 3 must replace the number with the word _type_, while multiples of 5 must replace the number with the word _safe_. Of course, multiples of 15 must print _typesafe_.

```
for {
	i <- 1 to 16
	value = if (i % 3 == 0 && i % 5 == 0) "typesafe"
	        else if (i % 3 == 0) "type"
	        else if (i % 5 == 0) "safe"
	        else i.toString
} println(value)

for (i <- 1 to 16) {
	i match {
		case x if x % 15 == 0 => println("typesafe")
		case x if x % 3 == 0 => println("type")
		case x if x % 5 == 0 => println("safe")
		case x => println(x)
	}
}

```

##### 6. Can you rewrite the answer to question 6 to fit on one line? It probably won’t be easier to read, but reducing code to its shortest form is an art, and a good exercise to learn the language.

```
for (i <- 1 to 16) { var s = ""; if(i % 3 == 0) s += "type"; if(i % 5 == 0) s += "safe"; if(s.isEmpty()) s += i; println(s)}
```