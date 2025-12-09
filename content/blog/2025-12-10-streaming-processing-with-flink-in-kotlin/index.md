---
title: Stream Processing with Flink in Kotlin
date: 2025-12-10
draft: false
featured: true
comment: true
toc: false
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
categories:
  - Data Streaming
tags:
  - Apache Flink
  - Kotlin
  - Stream Processing
  - Gradle
  - Ktor
authors:
  - JaehyeonKim
images: []
description: 
---

A couple of years ago, I read [Stream Processing with Apache Flink](https://www.oreilly.com/library/view/stream-processing-with/9781491974285/) and worked through the examples using PyFlink. While the book offered a solid introduction to Flink, I frequently hit limitations with the Python API, as many features from the book weren't supported. This time, I decided to revisit the material, but using Kotlin. The experience has been much more rewarding and fun.

In porting the examples to Kotlin, I also took the opportunity to align the code with modern Flink practices. The complete source for this post is available in the [`stream-processing-with-flink`](https://github.com/jaehyeon-kim/flink-demos/tree/master/stream-processing-with-flink) directory of the `flink-demos` GitHub repository.

<!--more-->

### Updating the Code and APIs

The book, while conceptually valuable, is a bit dated. As I worked through the examples, I updated several deprecated features to use their modern equivalents.

*   **`ListCheckpointed` to `CheckpointedFunction`**: Replaced the older checkpointing interface with the more flexible `CheckpointedFunction`.
*   **`SourceFunction` to Source API**: Migrated from the legacy `SourceFunction` to the newer, more robust Source API.
*   **`SinkFunction` to Sink V2 API**: Updated the `SinkFunction` to the Sink V2 API.
*   **Queryable State**: Ignored as it has been deprecated since Flink 1.18. These examples are built using Flink 1.20.1.

### Optimizing the Build with Gradle

Figuring out the Gradle build was a valuable lesson in itself. I learned how to create a single `build.gradle.kts` to handle two different scenarios: producing a lean production JAR and keeping local execution simple.

For the production JAR, Flink dependencies are declared with `compileOnly`. This correctly excludes them from the final artifact, as the Flink cluster provides these libraries at runtime.

> ❗The test environment also needs the Flink APIs to compile and run. This is handled by `testImplementation`. This standard Gradle configuration provides the Flink libraries *only* to the test classpath, keeping them completely separate from the production JAR and the local `run` task.

```kotlin
dependencies {
    // Flink Dependencies are not bundled into the JAR
    compileOnly("org.apache.flink:flink-streaming-java:$flinkVersion")
    compileOnly("org.apache.flink:flink-clients:$flinkVersion")

    // Flink is available for test compilation and execution
    testImplementation("org.apache.flink:flink-streaming-java:$flinkVersion")
    testImplementation("org.apache.flink:flink-clients:$flinkVersion")
}
```

However, this creates a problem for local development, as the Flink libraries are now missing from the default runtime classpath. The key technique I learned was how to solve this by creating a custom configuration, `localRunClasspath`.

This configuration rebuilds the full classpath specifically for the `run` task by adding the `compileOnly` dependencies back in, along with the standard `implementation` and `runtimeOnly` scopes. This makes local development seamless.

```kotlin
val localRunClasspath by configurations.creating {
    extendsFrom(configurations.implementation.get(), configurations.compileOnly.get(), configurations.runtimeOnly.get())
}

// ...

tasks.named<JavaExec>("run") {
    classpath = localRunClasspath + sourceSets.main.get().output
}
```

### Main Chapters

So far, I have translated the examples from the following main chapters:

*   **Chapter 5: Basic and Keyed Transformations**: Covers fundamental data manipulation, including `map`, `filter`, `keyBy`, and rolling sum aggregations, as well as multi-stream transformations.
*   **Chapter 6: Event Time and Windowing**: Focuses on time-based operations, including `ProcessFunction` timers, watermark generation strategies, window functions, custom window logic, and side outputs for late data handling.
*   **Chapter 7: State Management**: Explores different types of state in Flink, such as `ValueState`, `ListState`, `MapState`, and `BroadcastState`, along with operator state.
*   **Chapter 8: Asynchronous I/O and Custom Connectors**: Demonstrates how to interact with external systems asynchronously and build custom sources and sinks.

### How to Build and Run the Examples

The Flink applications can be run directly from the command line for local testing and development. This is useful for quick debugging without needing a full Flink cluster. Moreover, each Flink app has detailed documentation so it is easy to understand, for example:

```kotlin
/**
 * This Flink job demonstrates transformations on a `KeyedStream`.
 *
 * It showcases the `reduce` operator, a powerful tool for maintaining running aggregates
 * for each key in a stream.
 *
 * The pipeline is as follows:
 * 1. **Source**: Ingests a stream of `SensorReading` events.
 * 2. **KeyBy**: Partitions the stream by the `id` of each sensor. All subsequent
 *    operations will run independently for each sensor.
 * 3. **Reduce**: For each key, this operator maintains a running state of the `SensorReading`
 *    with the maximum temperature seen so far. For every new reading that arrives, it
 *    compares it to the current maximum and emits the new maximum downstream.
 * 4. **Sink**: Prints the continuous stream of running maximums for each sensor to the console.
 */
object KeyedTransformations {
    // ...
}
```

To launch the apps, use the `run` task and set the desired main class with the `-PmainClass` project property. Here are the full examples:

**1. Run the Chapter 5 examples.**

```bash
./gradlew run -PmainClass=me.jaehyeon.chapter5.BasicTransformations
./gradlew run -PmainClass=me.jaehyeon.chapter5.KeyedTransformations
./gradlew run -PmainClass=me.jaehyeon.chapter5.RollingSum
./gradlew run -PmainClass=me.jaehyeon.chapter5.MultiStreamTransformations
```

**2. Run the Chapter 6 examples.**

```bash
./gradlew run -PmainClass=me.jaehyeon.chapter6.ProcessFunctionTimers
./gradlew run -PmainClass=me.jaehyeon.chapter6.PeriodicWatermarkGeneration
./gradlew run -PmainClass=me.jaehyeon.chapter6.MarkerBasedWatermarkGeneration
./gradlew run -PmainClass=me.jaehyeon.chapter6.CoProcessFunctionTimers
./gradlew run -PmainClass=me.jaehyeon.chapter6.WindowFunctions --args="min1" # min2, avg, minmax1, or minmax2
./gradlew run -PmainClass=me.jaehyeon.chapter6.CustomWindows
./gradlew run -PmainClass=me.jaehyeon.chapter6.SideOutputs
./gradlew run -PmainClass=me.jaehyeon.chapter6.LateDataHandling --args="filter" # sideout or update
```

**3. Run the Chapter 7 examples.**

```bash
./gradlew run -PmainClass=me.jaehyeon.chapter7.KeyedStateFunction
./gradlew run -PmainClass=me.jaehyeon.chapter7.StatefulProcessFunction
./gradlew run -PmainClass=me.jaehyeon.chapter7.BroadcastStateFunction
./gradlew run -PmainClass=me.jaehyeon.chapter7.OperatorStateFunction
./gradlew run -PmainClass=me.jaehyeon.chapter7.KeyedAndOperatorStateFunction
```

**4. Run the Chapter 8 examples.**

```bash
./gradlew run -PmainClass=me.jaehyeon.chapter8.AsyncFunction
./gradlew run -PmainClass=me.jaehyeon.chapter8.CustomConnectors
```

### Conclusion

Working through the examples in Kotlin has been an effective way to dive deeper into Apache Flink. Translating the examples to Kotlin not only forced me to understand the concepts more thoroughly but also provided a great opportunity to get hands-on with the latest APIs and build practices. For those looking to learn Apache Flink through up-to-date examples, I hope sharing my experience and code proves helpful. It's been a fun and effective learning journey.
