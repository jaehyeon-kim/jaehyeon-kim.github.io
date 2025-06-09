---
title: Kafka Streams - Lightweight Real-Time Processing for Supplier Stats
date: 2025-06-03
draft: false
featured: true
comment: true
toc: false
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Getting Started with Real-Time Streaming in Kotlin
categories:
  - Data Streaming
tags: 
  - Apache Kafka
  - Kafka Streams
  - Kotlin
  - Docker
  - Kpow
  - Factor House Local
authors:
  - JaehyeonKim
images: []
description:
---

In this post, we shift our focus from basic Kafka clients to real-time stream processing with **Kafka Streams**. We'll explore a Kotlin application designed to analyze a continuous stream of Avro-formatted order events, calculate supplier statistics in tumbling windows, and intelligently handle late-arriving data. This example demonstrates the power of Kafka Streams for building lightweight, yet robust, stream processing applications directly within your Kafka ecosystem, leveraging event-time processing and custom logic.

<!--more-->

* [Kafka Clients with JSON - Producing and Consuming Order Events](/blog/2025-05-20-kotlin-getting-started-kafka-json-clients)
* [Kafka Clients with Avro - Schema Registry and Order Events](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients)
* [Kafka Streams - Lightweight Real-Time Processing for Supplier Stats](#) (this post)
* [Flink DataStream API - Scalable Event Processing for Supplier Stats](/blog/2025-06-10-kotlin-getting-started-flink-datastream)
* Flink Table API - Declarative Analytics for Supplier Stats in Real Time

## Kafka Streams Application for Supplier Statistics

This project showcases a Kafka Streams application that:
*   Consumes Avro-formatted order data from an input Kafka topic.
*   Extracts event timestamps from the order data to enable accurate time-based processing.
*   Proactively identifies and separates late-arriving records.
*   Aggregates order data to compute supplier statistics (total price and count) within defined time windows.
*   Outputs the calculated statistics and late records to separate Kafka topics.

The source code for the application discussed in this post can be found in the _orders-stats-streams_ folder of this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples).

### The Build Configuration

The `build.gradle.kts` file orchestrates the build, dependencies, and packaging of our Kafka Streams application.

*   **Plugins:**
    *   `kotlin("jvm")`: Enables Kotlin language support for the JVM.
    *   `com.github.davidmc24.gradle.plugin.avro`: Manages Avro schema compilation into Java classes.
    *   `com.github.johnrengelman.shadow`: Creates a "fat JAR" containing all dependencies.
    *   `application`: Configures the project as a runnable application.
*   **Repositories:**
    *   `mavenCentral()`: Standard Maven repository.
    *   `maven("https://packages.confluent.io/maven/")`: Confluent repository for Kafka Streams Avro SerDes and other Confluent components.
*   **Dependencies:**
    *   **Kafka:** `org.apache.kafka:kafka-clients` and importantly, `org.apache.kafka:kafka-streams` for the stream processing DSL and Processor API.
    *   **Avro:**
        *   `org.apache.avro:avro` for the core Avro library.
        *   `io.confluent:kafka-streams-avro-serde` for Confluent's Kafka Streams Avro SerDes, which integrate with Schema Registry.
    *   **JSON:** `com.fasterxml.jackson.module:jackson-module-kotlin` for serializing late records to JSON.
    *   **Logging:** `io.github.microutils:kotlin-logging-jvm` and `ch.qos.logback:logback-classic`.
*   **Application Configuration:**
    *   `mainClass.set("me.jaehyeon.MainKt")`: Defines the application's entry point.
    *   The `run` task is configured with environment variables (`BOOTSTRAP`, `TOPIC`, `REGISTRY_URL`) for Kafka connection details, simplifying local execution.
*   **Avro Configuration:**
    *   The `avro` block customizes Avro code generation (e.g., `setCreateSetters(false)`).
    *   `tasks.named("compileKotlin") { dependsOn("generateAvroJava") }` ensures Avro classes are generated before Kotlin compilation.
    *   Generated Avro Java sources are added to the `main` source set.
*   **Shadow JAR Configuration:**
    *   Configures the output fat JAR name (`orders-stats-streams`) and version.
    *   `mergeServiceFiles()` handles merging service provider files from dependencies.

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    id("com.github.davidmc24.gradle.plugin.avro") version "1.9.1"
    id("com.github.johnrengelman.shadow") version "8.1.1"
    application
}

group = "me.jaehyeon"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
    maven("https://packages.confluent.io/maven/")
}

dependencies {
    // Kafka
    implementation("org.apache.kafka:kafka-clients:3.9.0")
    implementation("org.apache.kafka:kafka-streams:3.9.0")
    // AVRO
    implementation("org.apache.avro:avro:1.11.4")
    implementation("io.confluent:kafka-streams-avro-serde:7.9.0")
    // Json
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.13.0")
    // Logging
    implementation("io.github.microutils:kotlin-logging-jvm:3.0.5")
    implementation("ch.qos.logback:logback-classic:1.5.13")
    // Test
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

application {
    mainClass.set("me.jaehyeon.MainKt")
}

avro {
    setCreateSetters(false)
    setFieldVisibility("PRIVATE")
}

tasks.named("compileKotlin") {
    dependsOn("generateAvroJava")
}

sourceSets {
    named("main") {
        java.srcDirs("build/generated/avro/main")
        kotlin.srcDirs("src/main/kotlin")
    }
}

tasks.withType<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar> {
    archiveBaseName.set("orders-stats-streams")
    archiveClassifier.set("")
    archiveVersion.set("1.0")
    mergeServiceFiles()
}

tasks.named("build") {
    dependsOn("shadowJar")
}

tasks.named<JavaExec>("run") {
    environment("BOOTSTRAP", "localhost:9092")
    environment("TOPIC", "orders-avro")
    environment("REGISTRY_URL", "http://localhost:8081")
}

tasks.test {
    useJUnitPlatform()
}
```

### Avro Schema for Aggregated Statistics

The `SupplierStats.avsc` file defines the Avro schema for the output of our stream aggregation. This ensures type safety and schema evolution for the processed statistics.

*   **Type:** A `record` named `SupplierStats` within the `me.jaehyeon.avro` namespace.
*   **Fields:**
    *   `window_start` (string): Marks the beginning of the aggregation window.
    *   `window_end` (string): Marks the end of the aggregation window.
    *   `supplier` (string): The identifier for the supplier.
    *   `total_price` (double): The sum of order prices for the supplier within the window.
    *   `count` (long): The number of orders for the supplier within the window.
*   **Usage:** This schema is used by the `SpecificAvroSerde` to serialize the aggregated `SupplierStats` objects before they are written to the output Kafka topic.

```json
{
  "type": "record",
  "name": "SupplierStats",
  "namespace": "me.jaehyeon.avro",
  "fields": [
    { "name": "window_start", "type": "string" },
    { "name": "window_end", "type": "string" },
    { "name": "supplier", "type": "string" },
    { "name": "total_price", "type": "double" },
    { "name": "count", "type": "long" }
  ]
}
```

### Kafka Admin Utilities

The `Utils.kt` file provides a helper function for Kafka topic management, ensuring that necessary topics exist before the stream processing begins.

*   **`createTopicIfNotExists(...)`:**
    *   This function uses Kafka's `AdminClient` to programmatically create Kafka topics.
    *   It takes the topic name, bootstrap server address, number of partitions, and replication factor as parameters.
    *   It's designed to be idempotent: if the topic already exists (due to prior creation or concurrent attempts), it logs a warning and proceeds without error, preventing application startup failures.
    *   For other errors during topic creation, it throws a runtime exception.

```kotlin
package me.jaehyeon.kafka

import mu.KotlinLogging
import org.apache.kafka.clients.admin.AdminClient
import org.apache.kafka.clients.admin.AdminClientConfig
import org.apache.kafka.clients.admin.NewTopic
import org.apache.kafka.common.errors.TopicExistsException
import java.util.Properties
import java.util.concurrent.ExecutionException
import kotlin.use

private val logger = KotlinLogging.logger { }

fun createTopicIfNotExists(
    topicName: String,
    bootstrapAddress: String,
    numPartitions: Int,
    replicationFactor: Short,
) {
    val props =
        Properties().apply {
            put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
            put(AdminClientConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, "5000")
            put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
            put(AdminClientConfig.RETRIES_CONFIG, "1")
        }

    AdminClient.create(props).use { client ->
        val newTopic = NewTopic(topicName, numPartitions, replicationFactor)
        val result = client.createTopics(listOf(newTopic))

        try {
            logger.info { "Attempting to create topic '$topicName'..." }
            result.all().get()
            logger.info { "Topic '$topicName' created successfully!" }
        } catch (e: ExecutionException) {
            if (e.cause is TopicExistsException) {
                logger.warn { "Topic '$topicName' was created concurrently or already existed. Continuing..." }
            } else {
                throw RuntimeException("Unrecoverable error while creating a topic '$topicName'.", e)
            }
        }
    }
}
```

### Custom Timestamp Extraction

For accurate event-time processing, Kafka Streams needs to know the actual time an event occurred, not just when it arrived at Kafka. The `BidTimeTimestampExtractor` customizes this logic.

*   **Implementation:** Implements the `TimestampExtractor` interface.
*   **Logic:**
    *   It attempts to parse a `bid_time` field (expected format: "yyyy-MM-dd HH:mm:ss") from the incoming Avro `GenericRecord`.
    *   The parsed string is converted to epoch milliseconds.
*   **Error Handling:**
    *   If the `bid_time` field is missing, blank, or cannot be parsed (e.g., due to `DateTimeParseException`), the extractor logs the issue and gracefully falls back to using the `partitionTime` (the timestamp assigned by Kafka, typically close to ingestion time). This ensures the stream doesn't halt due to malformed data.
*   **Significance:** Using event time extracted from the data payload allows windowed operations to be based on when events truly happened, leading to more meaningful aggregations, especially in systems where data might arrive out of order or with delays.

```kotlin
package me.jaehyeon.streams.extractor

import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.streams.processor.TimestampExtractor
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

class BidTimeTimestampExtractor : TimestampExtractor {
    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val logger = KotlinLogging.logger { }

    override fun extract(
        record: ConsumerRecord<Any, Any>,
        partitionTime: Long,
    ): Long =
        try {
            val value = record.value() as? GenericRecord
            val bidTime = value?.get("bid_time")?.toString()
            when {
                bidTime.isNullOrBlank() -> {
                    logger.warn { "Missing or blank 'bid_time'. Falling back to partitionTime: $partitionTime" }
                    partitionTime
                }
                else -> {
                    val parsedTimestamp =
                        LocalDateTime
                            .parse(bidTime, formatter)
                            .atZone(ZoneId.systemDefault())
                            .toInstant()
                            .toEpochMilli()
                    logger.debug { "Extracted timestamp $parsedTimestamp from bid_time '$bidTime'" }
                    parsedTimestamp
                }
            }
        } catch (e: Exception) {
            when (e.cause) {
                is DateTimeParseException -> {
                    logger.error(e) { "Failed to parse 'bid_time'. Falling back to partitionTime: $partitionTime" }
                    partitionTime
                }
                else -> {
                    logger.error(e) { "Unexpected error extracting timestamp. Falling back to partitionTime: $partitionTime" }
                    partitionTime
                }
            }
        }
}
```

### Proactive Late Record Handling

![](late-record-processor.png#center)

The `LateRecordProcessor` is a custom Kafka Streams `Processor` (using the lower-level Processor API) designed to identify records that would arrive too late to be included in their intended time windows.

*   **Parameters:** Initialized with the `windowSize` and `gracePeriod` durations used by downstream windowed aggregations.
*   **Logic:** For each incoming record:
    1.  It retrieves the record's event timestamp (as assigned by `BidTimeTimestampExtractor`).
    2.  It calculates the `windowEnd` time for the window this record *should* belong to.
    3.  It then determines the `windowCloseTime` (window end + grace period), which is the deadline for records to be accepted into that window.
    4.  It compares the current `streamTime` (the maximum event time seen so far by this processing task) against the record's `windowCloseTime`.
    5.  If `streamTime` is already past `windowCloseTime`, the record is considered "late."
*   **Output:** The processor forwards a `Pair` containing the original `GenericRecord` and a `Boolean` flag indicating whether the record is late (`true`) or not (`false`).
*   **Purpose:** This allows the application to explicitly route late records to a separate processing path (e.g., a "skipped" topic) *before* they are simply dropped by downstream stateful windowed operators. This provides visibility into late data and allows for alternative handling strategies.

```kotlin
package me.jaehyeon.streams.processor

import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.streams.processor.api.Processor
import org.apache.kafka.streams.processor.api.ProcessorContext
import org.apache.kafka.streams.processor.api.Record
import java.time.Duration

class LateRecordProcessor(
    private val windowSize: Duration,
    private val gracePeriod: Duration,
) : Processor<String, GenericRecord, String, Pair<GenericRecord, Boolean>> {
    private lateinit var context: ProcessorContext<String, Pair<GenericRecord, Boolean>>
    private val windowSizeMs = windowSize.toMillis()
    private val gracePeriodMs = gracePeriod.toMillis()
    private val logger = KotlinLogging.logger {}

    override fun init(context: ProcessorContext<String, Pair<GenericRecord, Boolean>>) {
        this.context = context
    }

    // The main processing method for the Processor API
    override fun process(record: Record<String, GenericRecord>) {
        val key = record.key()
        val value = record.value()

        // 1. Get the timestamp assigned to this specific record.
        //    This comes from your BidTimeTimestampExtractor.
        val recordTimestamp = record.timestamp()

        // Handle cases where timestamp extraction might have failed.
        // These records can't be placed in a window correctly anyway.
        if (recordTimestamp < 0) {
            logger.warn { "Record has invalid timestamp $recordTimestamp. Cannot determine window. Forwarding as NOT LATE. Key=$key" }
            // Explicitly forward the result using the context
            context.forward(Record(key, Pair(value, false), recordTimestamp))
            return
        }

        // 2. Determine the time window this record *should* belong to based on its timestamp.
        //    Calculate the END time of that window.
        //    Example: If window size is 5s and recordTimestamp is 12s, it belongs to
        //             window [10s, 15s). The windowEnd is 15s (15000ms).
        //             Calculation: ((12000 / 5000) + 1) * 5000 = (2 + 1) * 5000 = 15000
        val windowEnd = ((recordTimestamp / windowSizeMs) + 1) * windowSizeMs

        // 3. Calculate when this specific window "closes" for accepting late records.
        //    This is the window's end time plus the allowed grace period.
        //    Example: If windowEnd is 15s and gracePeriod is 0s, windowCloseTime is 15s.
        //             If windowEnd is 15s and gracePeriod is 2s, windowCloseTime is 17s.
        val windowCloseTime = windowEnd + gracePeriodMs

        // 4. Get the current "Stream Time".
        //    This represents the maximum record timestamp seen *so far* by this stream task.
        //    It indicates how far along the stream processing has progressed in event time.
        val streamTime = context.currentStreamTimeMs()

        // 5. THE CORE CHECK: Is the stream's progress (streamTime) already past
        //    the point where this record's window closed (windowCloseTime)?
        //    If yes, the record is considered "late" because the stream has moved on
        //    past the time it could have been included in its window (+ grace period).
        //    This mimics the logic the downstream aggregate operator uses to drop late records.
        val isLate = streamTime > windowCloseTime

        if (isLate) {
            logger.debug {
                "Tagging record as LATE: RecordTime=$recordTimestamp belongs to window ending at $windowEnd (closes at $windowCloseTime), but StreamTime is already $streamTime. Key=$key"
            }
        } else {
            logger.trace {
                "Tagging record as NOT LATE: RecordTime=$recordTimestamp, WindowCloseTime=$windowCloseTime, StreamTime=$streamTime. Key=$key"
            }
        }

        // 6. Explicitly forward the result (key, tagged value, timestamp) using the context
        // Ensure you preserve the original timestamp if needed downstream
        context.forward(Record(key, Pair(value, isLate), recordTimestamp))
    }

    override fun close() {
        // No resources to close
    }
}
```

### Core Stream Processing Logic

The `StreamsApp.kt` object defines the Kafka Streams topology, orchestrating the flow of data from input to output.

*   **Configuration:**
    *   Environment variables (`BOOTSTRAP`, `TOPIC`, `REGISTRY_URL`) configure Kafka and Schema Registry connections.
    *   `windowSize` (5 seconds) and `gracePeriod` (5 seconds) are defined for windowed aggregations.
    *   Output topic names are derived from the input topic name.
*   **Setup:**
    *   Calls `createTopicIfNotExists` to ensure the statistics output topic and the late/skipped records topic are present.
    *   Configures `StreamsConfig` properties, including application ID, bootstrap servers, default SerDes, and importantly, sets `BidTimeTimestampExtractor` as the default timestamp extractor.
    *   Sets up Avro SerDes (`GenericAvroSerde` for input, `SpecificAvroSerde<SupplierStats>` for output) with Schema Registry configuration.
*   **Topology Definition (`StreamsBuilder`):**
    1.  **Source:** Consumes `GenericRecord` Avro messages from the `inputTopicName` (*orders-avro-stats*).
    2.  **Late Record Tagging:** The stream is processed by `LateRecordProcessor` to tag each record with a boolean indicating if it's late.
    3.  **Branching:** The stream is split based on the "late" flag:
        *   `validSource`: Records not marked as late.
        *   `lateSource`: Records marked as late.
    4.  **Handling Late Records:**
        *   Records in `lateSource` are transformed: an extra `"late": true` field is added to their content, and they are serialized to JSON.
        *   These JSON strings are then sent to the `skippedTopicName` (*orders-avro-skipped*).
    5.  **Aggregating Valid Records:**
        *   Records in `validSource` are re-keyed by `supplier` (extracted from the record) and their `price` becomes the value.
        *   A `groupByKey` operation is performed.
        *   `windowedBy(TimeWindows.ofSizeAndGrace(windowSize, gracePeriod))` defines 5-second tumbling windows with a 5-second grace period.
        *   An `aggregate` operation computes `SupplierStats` (total price and count) for each supplier within each window.
    6.  **Outputting Statistics:**
        *   The aggregated `SupplierStats` stream is further processed to populate `window_start` and `window_end` fields from the window metadata.
        *   These final `SupplierStats` objects are sent to the `outputTopicName`.
*   **Execution:** A `KafkaStreams` instance is created with the topology and properties, then started. A shutdown hook ensures graceful closing.

```kotlin
package me.jaehyeon

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import io.confluent.kafka.streams.serdes.avro.GenericAvroSerde
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde
import me.jaehyeon.avro.SupplierStats
import me.jaehyeon.kafka.createTopicIfNotExists
import me.jaehyeon.streams.extractor.BidTimeTimestampExtractor
import me.jaehyeon.streams.processor.LateRecordProcessor
import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.common.serialization.Serdes
import org.apache.kafka.streams.KafkaStreams
import org.apache.kafka.streams.KeyValue
import org.apache.kafka.streams.StreamsBuilder
import org.apache.kafka.streams.StreamsConfig
import org.apache.kafka.streams.kstream.Branched
import org.apache.kafka.streams.kstream.Consumed
import org.apache.kafka.streams.kstream.Grouped
import org.apache.kafka.streams.kstream.KStream
import org.apache.kafka.streams.kstream.KTable
import org.apache.kafka.streams.kstream.Materialized
import org.apache.kafka.streams.kstream.Named
import org.apache.kafka.streams.kstream.Produced
import org.apache.kafka.streams.kstream.TimeWindows
import org.apache.kafka.streams.kstream.Windowed
import org.apache.kafka.streams.processor.api.ProcessorSupplier
import java.time.Duration
import java.util.Properties

object StreamsApp {
    private val bootstrapAddress = System.getenv("BOOTSTRAP") ?: "kafka-1:19092"
    private val inputTopicName = System.getenv("TOPIC") ?: "orders-avro"
    private val registryUrl = System.getenv("REGISTRY_URL") ?: "http://schema:8081"
    private val registryConfig =
        mapOf(
            "schema.registry.url" to registryUrl,
            "basic.auth.credentials.source" to "USER_INFO",
            "basic.auth.user.info" to "admin:admin",
        )
    private val windowSize = Duration.ofSeconds(5)
    private val gracePeriod = Duration.ofSeconds(5)
    private const val NUM_PARTITIONS = 3
    private const val REPLICATION_FACTOR: Short = 3
    private val logger = KotlinLogging.logger {}

    // ObjectMapper for converting late source to JSON
    private val objectMapper: ObjectMapper by lazy {
        ObjectMapper().registerKotlinModule()
    }

    fun run() {
        // Create output topics if not existing
        val outputTopicName = "$inputTopicName-stats"
        val skippedTopicName = "$inputTopicName-skipped"
        listOf(outputTopicName, skippedTopicName).forEach { name ->
            createTopicIfNotExists(
                name,
                bootstrapAddress,
                NUM_PARTITIONS,
                REPLICATION_FACTOR,
            )
        }

        val props =
            Properties().apply {
                put(StreamsConfig.APPLICATION_ID_CONFIG, "$outputTopicName-kafka-streams")
                put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
                put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String()::class.java.name)
                put(StreamsConfig.consumerPrefix(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG), "earliest")
                put(StreamsConfig.DEFAULT_TIMESTAMP_EXTRACTOR_CLASS_CONFIG, BidTimeTimestampExtractor::class.java.name)
                put("schema.registry.url", registryUrl)
                put("basic.auth.credentials.source", "USER_INFO")
                put("basic.auth.user.info", "admin:admin")
            }

        val keySerde = Serdes.String()
        val valueSerde =
            GenericAvroSerde().apply {
                configure(registryConfig, false)
            }
        val supplierStatsSerde =
            SpecificAvroSerde<SupplierStats>().apply {
                configure(registryConfig, false)
            }

        val builder = StreamsBuilder()
        val source: KStream<String, GenericRecord> = builder.stream(inputTopicName, Consumed.with(keySerde, valueSerde))

        val taggedStream: KStream<String, Pair<GenericRecord, Boolean>> =
            source.process(
                ProcessorSupplier {
                    LateRecordProcessor(windowSize, gracePeriod)
                },
                Named.`as`("process-late-records"),
            )

        val branches: Map<String, KStream<String, Pair<GenericRecord, Boolean>>> =
            taggedStream
                .split(Named.`as`("branch-"))
                .branch({ _, value -> !value.second }, Branched.`as`("valid"))
                .branch({ _, value -> value.second }, Branched.`as`("late"))
                .noDefaultBranch()

        val validSource: KStream<String, GenericRecord> =
            branches["branch-valid"]!!
                .mapValues { _, pair -> pair.first }

        val lateSource: KStream<String, GenericRecord> =
            branches["branch-late"]!!
                .mapValues { _, pair -> pair.first }

        lateSource
            .mapValues { _, genericRecord ->
                val map = mutableMapOf<String, Any?>()
                genericRecord.schema.fields.forEach { field ->
                    val value = genericRecord.get(field.name())
                    map[field.name()] = if (value is org.apache.avro.util.Utf8) value.toString() else value
                }
                map["late"] = true
                map
            }.peek { key, mapValue ->
                logger.warn { "Potentially late record - key=$key, value=$mapValue" }
            }.mapValues { _, mapValue ->
                objectMapper.writeValueAsString(mapValue)
            }.to(skippedTopicName, Produced.with(keySerde, Serdes.String()))

        val aggregated: KTable<Windowed<String>, SupplierStats> =
            validSource
                .map { _, value ->
                    val supplier = value["supplier"]?.toString() ?: "UNKNOWN"
                    val price = value["price"] as? Double ?: 0.0
                    KeyValue(supplier, price)
                }.groupByKey(Grouped.with(keySerde, Serdes.Double()))
                .windowedBy(TimeWindows.ofSizeAndGrace(windowSize, gracePeriod))
                .aggregate(
                    {
                        SupplierStats
                            .newBuilder()
                            .setWindowStart("")
                            .setWindowEnd("")
                            .setSupplier("")
                            .setTotalPrice(0.0)
                            .setCount(0L)
                            .build()
                    },
                    { key, value, aggregate ->
                        val updated =
                            SupplierStats
                                .newBuilder(aggregate)
                                .setSupplier(key)
                                .setTotalPrice(aggregate.totalPrice + value)
                                .setCount(aggregate.count + 1)
                        updated.build()
                    },
                    Materialized.with(keySerde, supplierStatsSerde),
                )
        aggregated
            .toStream()
            .map { key, value ->
                val windowStart = key.window().startTime().toString()
                val windowEnd = key.window().endTime().toString()
                val updatedValue =
                    SupplierStats
                        .newBuilder(value)
                        .setWindowStart(windowStart)
                        .setWindowEnd(windowEnd)
                        .build()
                KeyValue(key.key(), updatedValue)
            }.peek { _, value ->
                logger.info { "Supplier Stats: $value" }
            }.to(outputTopicName, Produced.with(keySerde, supplierStatsSerde))

        val streams = KafkaStreams(builder.build(), props)
        try {
            streams.start()
            logger.info { "Kafka Streams started successfully." }

            Runtime.getRuntime().addShutdownHook(
                Thread {
                    logger.info { "Shutting down Kafka Streams..." }
                    streams.close()
                },
            )
        } catch (e: Exception) {
            streams.close(Duration.ofSeconds(5))
            throw RuntimeException("Error while running Kafka Streams", e)
        }
    }
}
```

### Application Entry Point

The `Main.kt` file provides the `main` function, which is the starting point for the Kafka Streams application.

*   **Execution:** It simply calls `StreamsApp.run()` to initialize and start the stream processing topology.
*   **Error Handling:** A global `try-catch` block wraps the execution. If any unhandled exception propagates up from the `StreamsApp`, it's caught here, logged as a fatal error, and the application exits with a non-zero status code (`exitProcess(1)`).

```kotlin
package me.jaehyeon

import mu.KotlinLogging
import kotlin.system.exitProcess

private val logger = KotlinLogging.logger {}

fun main() {
    try {
        StreamsApp.run()
    } catch (e: Exception) {
        logger.error(e) { "Fatal error in the streams app. Shutting down." }
        exitProcess(1)
    }
}
```

## Run Kafka Streams Application

To see our Kafka Streams application in action, we first need a running Kafka environment. We'll use the [Factor House Local](https://github.com/factorhouse/factorhouse-local) project, which provides a Docker Compose setup for a Kafka cluster and Kpow for monitoring. Then, we'll start a data producer (from our previous blog post example) to generate input order events, and finally, launch our Kafka Streams application.

### Factor House Local Setup

If you haven't already, set up your local Kafka environment:
1.  Clone the Factor House Local repository:
    ```bash
    git clone https://github.com/factorhouse/factorhouse-local.git
    cd factorhouse-local
    ```
2.  Ensure your Kpow community license is configured (see the [README](https://github.com/factorhouse/factorhouse-local?tab=readme-ov-file#update-kpow-and-flex-licenses) for details).
3.  Start the services:
    ```bash
    docker compose -f compose-kpow-community.yml up -d
    ```
Once initialized, Kpow will be accessible at `http://localhost:3000`, showing Kafka brokers, schema registry, and other components.

![](kpow-overview.png#center)

### Start the Kafka Order Producer

Our Kafka Streams application consumes order data from the `orders-avro` topic. We'll use the Kafka producer developed in [Part 2 of this series](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients/) to generate this data. To effectively test our stream application's handling of event time and late records, we'll configure the producer to introduce a variable delay (up to 15 seconds) in the `bid_time` of the generated orders.

Navigate to the directory of the producer application (_orders-avro-clients_ from the [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples)) and run:

```bash
# Assuming you are in the root of the 'orders-avro-clients' project
DELAY_SECONDS=15 ./gradlew run --args="producer"
```

This will start populating the `orders-avro` topic with Avro-encoded order messages. You can inspect these messages in Kpow. For the `orders-avro` topic, ensure Kpow is configured with Key Deserializer: *String*, Value Deserializer: *AVRO*, and Schema Registry: *Local Schema Registry*.

![](orders-01.png#center)
![](orders-02.png#center)

### Launch the Kafka Streams Application

With input data flowing, we can now launch our `orders-stats-streams` Kafka Streams application. Navigate to its project directory (_orders-stats-streams_ from the [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples)).

The application can be run in two main ways:

1.  **With Gradle (Development Mode)**: Ideal for development and quick testing.
    ```bash
    ./gradlew run
    ```
2.  **Running the Shadow JAR (Deployment Mode)**: For deploying the application as a standalone unit. First, build the fat JAR:
    ```bash
    ./gradlew shadowJar
    ```
    This creates `build/libs/orders-stats-streams-1.0.jar`. Then run it:
    ```bash
    java -jar build/libs/orders-stats-streams-1.0.jar
    ```

> 💡 To build and run the application locally, ensure that **JDK 17** and a recent version of Gradle (e.g., **7.6+** or **8.x**) are installed.

For this demonstration, we'll use Gradle to run the application in development mode. Upon starting, you'll see logs indicating the Kafka Streams application has initialized and is processing records from the `orders-avro` topic.

### Observing the Output

Our Kafka Streams application produces results to two topics:
*   `orders-avro-stats`: Contains the aggregated supplier statistics as Avro records.
*   `orders-avro-skipped`: Contains records identified as "late," serialized as JSON.

**1. Supplier Statistics (`orders-avro-stats`):**

In Kpow, navigate to the `orders-avro-stats` topic. Configure Kpow to view these messages:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *AVRO*
*   **Schema Registry:** *Local Schema Registry*

You should see `SupplierStats` messages, each representing the total price and count of orders for a supplier within a 5-second window. Notice the `window_start` and `window_end` fields.

![](stats-01.png#center)
![](stats-02.png#center)

**2. Skipped (Late) Records (`orders-avro-skipped`):**

Next, inspect the `orders-avro-skipped` topic in Kpow. Configure Kpow as follows:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *JSON*

Here, you'll find the original order records that were deemed "late" by our `LateRecordProcessor`. These messages have an additional `late: true` field, confirming they were routed by our custom logic.

![](skipped-01.png#center)
![](skipped-02.png#center)

We can also track the performance of the application by filtering its consumer group (`orders-avro-stats-kafka-streams`) in the **Consumers** section. This displays key metrics like group state, assigned members, read throughput, and lag:

![](consumer-group-01.png#center)

## Conclusion

In this post, we've dived into Kafka Streams, building a Kotlin application that performs real-time aggregation of supplier order data. We've seen how to leverage event-time processing with a custom `TimestampExtractor` and how to proactively manage late-arriving data using the Processor API with a custom `LateRecordProcessor`. By routing late data to a separate topic and outputting clean, windowed statistics, this application demonstrates a practical approach to building resilient and insightful stream processing pipelines directly with Kafka. The use of Avro ensures data integrity, while Kpow provides excellent visibility into the streams and topics.