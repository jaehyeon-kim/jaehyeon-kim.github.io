---
title: Flink Table API - Declarative Analytics for Supplier Stats in Real Time
date: 2025-06-17
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

In the last post, we explored the fine-grained control of Flink's DataStream API. Now, we'll approach the same problem from a higher level of abstraction using the **Flink Table API**. This post demonstrates how to build a declarative analytics pipeline that processes our continuous stream of Avro-formatted order events. We will define a `Table` on top of a `DataStream` and use SQL-like expressions to perform windowed aggregations. This example highlights the power and simplicity of the Table API for analytical tasks and showcases Flink's seamless integration between its different API layers to handle complex requirements like late data.

<!--more-->

* [Kafka Clients with JSON - Producing and Consuming Order Events](/blog/2025-05-20-kotlin-getting-started-kafka-json-clients)
* [Kafka Clients with Avro - Schema Registry and Order Events](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients)
* [Kafka Streams - Lightweight Real-Time Processing for Supplier Stats](/blog/2025-06-03-kotlin-getting-started-kafka-streams)
* [Flink DataStream API - Scalable Event Processing for Supplier Stats](/blog/2025-06-10-kotlin-getting-started-flink-datastream)
* [Flink Table API - Declarative Analytics for Supplier Stats in Real Time](#) (this post)

## Flink Table Application

We develop a Flink application that uses Flink's Table API and SQL-like expressions to perform real-time analytics. This application:
*   Consumes Avro-formatted order events from a Kafka topic.
*   Uses a mix of the DataStream and Table APIs to prepare data, handle late events, and define watermarks.
*   Defines a table over the streaming data, complete with an event-time attribute and watermarks.
*   Runs a declarative, SQL-like query to compute supplier statistics (total price and count) in 5-second tumbling windows.
*   Splits the stream to route late-arriving records to a separate "skipped" topic for analysis.
*   Sinks the aggregated results to a Kafka topic using the built-in `avro-confluent` format connector.

The source code for the application discussed in this post can be found in the _orders-stats-flink_ folder of this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples).

### The Build Configuration

The `build.gradle.kts` file sets up the project, its dependencies, and packaging. It's shared between the DataStream and Table API applications - see [the previous post](/blog/2025-06-10-kotlin-getting-started-flink-datastream) for the Flink application that uses the DataStream API.

*   **Plugins:**
    *   `kotlin("jvm")`: Enables Kotlin language support.
    *   `com.github.davidmc24.gradle.plugin.avro`: Compiles Avro schemas into Java classes.
    *   `com.github.johnrengelman.shadow`: Creates an executable "fat JAR" with all dependencies.
    *   `application`: Configures the project to be runnable via Gradle.
*   **Dependencies:**
    *   **Flink Core & Table APIs:** `flink-streaming-java`, `flink-clients`, and crucially, `flink-table-api-java-bridge`, `flink-table-planner-loader`, and `flink-table-runtime` for the Table API.
    *   **Flink Connectors:** `flink-connector-kafka` for Kafka integration.
    *   **Flink Formats:** `flink-avro` and `flink-avro-confluent-registry` for handling Avro data with Confluent Schema Registry.
    *   **Note on Dependency Scope:** The Flink dependencies are declared with `implementation`. This allows the application to be run directly with `./gradlew run`. For production deployments on a Flink cluster (where the Flink runtime is already provided), these dependencies should be changed to `compileOnly` to significantly reduce the size of the final JAR.
*   **Application Configuration:**
    *   The `application` block sets the `mainClass` and passes necessary JVM arguments. The `run` task is configured with environment variables to specify Kafka and Schema Registry connection details.
*   **Avro & Shadow JAR:**
    *   The `avro` block configures code generation.
    *   The `shadowJar` task configures the output JAR name and merges service files, which is crucial for Flink connectors to work correctly.

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
    maven("https://packages.confluent.io/maven")
}

dependencies {
    // Flink Core and APIs
    implementation("org.apache.flink:flink-streaming-java:1.20.1")
    implementation("org.apache.flink:flink-table-api-java:1.20.1")
    implementation("org.apache.flink:flink-table-api-java-bridge:1.20.1")
    implementation("org.apache.flink:flink-table-planner-loader:1.20.1")
    implementation("org.apache.flink:flink-table-runtime:1.20.1")
    implementation("org.apache.flink:flink-clients:1.20.1")
    implementation("org.apache.flink:flink-connector-base:1.20.1")
    // Flink Kafka and Avro
    implementation("org.apache.flink:flink-connector-kafka:3.4.0-1.20")
    implementation("org.apache.flink:flink-avro:1.20.1")
    implementation("org.apache.flink:flink-avro-confluent-registry:1.20.1")
    // Json
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.13.0")
    // Logging
    implementation("io.github.microutils:kotlin-logging-jvm:3.0.5")
    implementation("ch.qos.logback:logback-classic:1.5.13")
    // Kotlin test
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

application {
    mainClass.set("me.jaehyeon.MainKt")
    applicationDefaultJvmArgs =
        listOf(
            "--add-opens=java.base/java.util=ALL-UNNAMED",
        )
}

avro {
    setCreateSetters(true)
    setFieldVisibility("PUBLIC")
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
    archiveBaseName.set("orders-stats-flink")
    archiveClassifier.set("")
    archiveVersion.set("1.0")
    mergeServiceFiles()
}

tasks.named("build") {
    dependsOn("shadowJar")
}

tasks.named<JavaExec>("run") {
    environment("TO_SKIP_PRINT", "false")
    environment("BOOTSTRAP", "localhost:9092")
    environment("REGISTRY_URL", "http://localhost:8081")
}

tasks.test {
    useJUnitPlatform()
}
```

### Avro Schema for Supplier Statistics

The `SupplierStats.avsc` file defines the structure for the aggregated output data. This schema is used by the Flink Table API's Kafka connector with the `avro-confluent` format to serialize the final `Row` results into Avro, ensuring type safety for downstream consumers.

*   **Type:** A `record` named `SupplierStats` in the `me.jaehyeon.avro` namespace.
*   **Fields:**
    *   `window_start` and `window_end` (string): The start and end times of the aggregation window.
    *   `supplier` (string): The supplier being aggregated.
    *   `total_price` (double): The sum of order prices within the window.
    *   `count` (long): The total number of orders within the window.

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

### Shared Utilities

These utility files provide common functionality used by both the DataStream and Table API applications.

#### Kafka Admin Utilities

This file provides two key helper functions for interacting with the Kafka ecosystem:

*   **`createTopicIfNotExists(...)`**: Uses Kafka's `AdminClient` to programmatically create topics. It's designed to be idempotent, safely handling cases where the topic already exists to prevent application startup failures.
*   **`getLatestSchema(...)`**: Connects to the Confluent Schema Registry using `CachedSchemaRegistryClient` to fetch the latest Avro schema for a given subject. This is essential for the Flink source to correctly deserialize incoming Avro records without hardcoding the schema in the application.

```kotlin
package me.jaehyeon.kafka

import io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient
import mu.KotlinLogging
import org.apache.avro.Schema
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

fun getLatestSchema(
    schemaSubject: String,
    registryUrl: String,
    registryConfig: Map<String, String>,
): Schema {
    val schemaRegistryClient =
        CachedSchemaRegistryClient(
            registryUrl,
            100,
            registryConfig,
        )
    logger.info { "Fetching latest schema for subject '$schemaSubject' from $registryUrl" }
    try {
        val latestSchemaMetadata = schemaRegistryClient.getLatestSchemaMetadata(schemaSubject)
        logger.info {
            "Successfully fetched schema ID ${latestSchemaMetadata.id} version ${latestSchemaMetadata.version} for subject '$schemaSubject'"
        }
        return Schema.Parser().parse(latestSchemaMetadata.schema)
    } catch (e: Exception) {
        logger.error(e) { "Failed to retrieve schema for subject '$schemaSubject' from registry $registryUrl" }
        throw RuntimeException("Failed to retrieve schema for subject '$schemaSubject'", e)
    }
}
```

#### Flink Kafka Connectors

This file centralizes the creation of Flink's Kafka sources and sinks. The Table API application uses `createOrdersSource` and `createSkippedSink` from this file. The sink for aggregated statistics is defined declaratively using a `TableDescriptor` instead of the `createStatsSink` function.

*   **`createOrdersSource(...)`:** Configures a `KafkaSource` to consume `GenericRecord` Avro data.
*   **`createSkippedSink(...)`:** Creates a generic `KafkaSink` for late records, which are handled as simple key-value string pairs.

```kotlin
package me.jaehyeon.kafka

import me.jaehyeon.avro.SupplierStats
import org.apache.avro.Schema
import org.apache.avro.generic.GenericRecord
import org.apache.flink.connector.base.DeliveryGuarantee
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema
import org.apache.flink.connector.kafka.sink.KafkaSink
import org.apache.flink.connector.kafka.source.KafkaSource
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer
import org.apache.flink.formats.avro.registry.confluent.ConfluentRegistryAvroDeserializationSchema
import org.apache.flink.formats.avro.registry.confluent.ConfluentRegistryAvroSerializationSchema
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.clients.producer.ProducerConfig
import java.nio.charset.StandardCharsets
import java.util.Properties

fun createOrdersSource(
    topic: String,
    groupId: String,
    bootstrapAddress: String,
    registryUrl: String,
    registryConfig: Map<String, String>,
    schema: Schema,
): KafkaSource<GenericRecord> =
    KafkaSource
        .builder<GenericRecord>()
        .setBootstrapServers(bootstrapAddress)
        .setTopics(topic)
        .setGroupId(groupId)
        .setStartingOffsets(OffsetsInitializer.earliest())
        .setValueOnlyDeserializer(
            ConfluentRegistryAvroDeserializationSchema.forGeneric(
                schema,
                registryUrl,
                registryConfig,
            ),
        ).setProperties(
            Properties().apply {
                put(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG, "500")
            },
        ).build()

fun createStatsSink(
    topic: String,
    bootstrapAddress: String,
    registryUrl: String,
    registryConfig: Map<String, String>,
    outputSubject: String,
): KafkaSink<SupplierStats> =
    KafkaSink
        .builder<SupplierStats>()
        .setBootstrapServers(bootstrapAddress)
        .setKafkaProducerConfig(
            Properties().apply {
                setProperty(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true")
                setProperty(ProducerConfig.LINGER_MS_CONFIG, "100")
                setProperty(ProducerConfig.BATCH_SIZE_CONFIG, (64 * 1024).toString())
                setProperty(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4")
            },
        ).setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
        .setRecordSerializer(
            KafkaRecordSerializationSchema
                .builder<SupplierStats>()
                .setTopic(topic)
                .setKeySerializationSchema { value: SupplierStats ->
                    value.supplier.toByteArray(StandardCharsets.UTF_8)
                }.setValueSerializationSchema(
                    ConfluentRegistryAvroSerializationSchema.forSpecific<SupplierStats>(
                        SupplierStats::class.java,
                        outputSubject,
                        registryUrl,
                        registryConfig,
                    ),
                ).build(),
        ).build()

fun createSkippedSink(
    topic: String,
    bootstrapAddress: String,
): KafkaSink<Pair<String?, String>> =
    KafkaSink
        .builder<Pair<String?, String>>()
        .setBootstrapServers(bootstrapAddress)
        .setKafkaProducerConfig(
            Properties().apply {
                setProperty(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true")
                setProperty(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4")
                setProperty(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArraySerializer")
                setProperty(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.ByteArraySerializer")
            },
        ).setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
        .setRecordSerializer(
            KafkaRecordSerializationSchema
                .builder<Pair<String?, String>>()
                .setTopic(topic)
                .setKeySerializationSchema { pair: Pair<String?, String> ->
                    pair.first?.toByteArray(StandardCharsets.UTF_8)
                }.setValueSerializationSchema { pair: Pair<String?, String> ->
                    pair.second.toByteArray(StandardCharsets.UTF_8)
                }.build(),
        ).build()
```

### Table API Processing Logic

The following files contain the core logic specific to the Table API implementation.

#### Manual Late Data Routing

Because the Table API does not have a direct equivalent to the DataStream API's `.sideOutputLateData()`, we must handle late records manually. This `ProcessFunction` is a key component. It inspects each record's timestamp against the current watermark and an `allowedLatenessMillis` threshold. Records deemed "too late" are routed to a side output, while on-time records are passed downstream to be converted into a `Table`.

```kotlin
package me.jaehyeon.flink.processing

import org.apache.flink.streaming.api.functions.ProcessFunction
import org.apache.flink.util.Collector
import org.apache.flink.util.OutputTag

class LateDataRouter(
    private val lateOutputTag: OutputTag<RecordMap>,
    private val allowedLatenessMillis: Long,
) : ProcessFunction<RecordMap, RecordMap>() {

    init {
        require(allowedLatenessMillis >= 0) {
            "allowedLatenessMillis cannot be negative. Got: $allowedLatenessMillis"
        }
    }

    @Throws(Exception::class)
    override fun processElement(
        value: RecordMap,
        ctx: ProcessFunction<RecordMap, RecordMap>.Context,
        out: Collector<RecordMap>,
    ) {
        val elementTimestamp: Long? = ctx.timestamp()
        val currentWatermark: Long = ctx.timerService().currentWatermark()

        // Element has no timestamp or watermark is still at its initial value
        if (elementTimestamp == null || currentWatermark == Long.MIN_VALUE) {
            out.collect(value)
            return
        }

        // Element has a timestamp and watermark is active.
        // An element is "too late" if its timestamp is older than current watermark - allowed lateness.
        if (elementTimestamp < currentWatermark - allowedLatenessMillis) {
            ctx.output(lateOutputTag, value)
        } else {
            out.collect(value)
        }
    }
}
```

#### Timestamp and Watermark Strategy for Rows

After the initial stream processing and before converting the `DataStream` to a `Table`, we need a watermark strategy that operates on Flink's `Row` type. This strategy extracts the timestamp from a specific field index in the `Row` (in this case, field 1, which holds the `bid_time` as a `Long`) and generates watermarks, allowing the Table API to correctly perform event-time windowing.

```kotlin
package me.jaehyeon.flink.watermark

import mu.KotlinLogging
import org.apache.flink.api.common.eventtime.WatermarkStrategy
import org.apache.flink.types.Row

object RowWatermarkStrategy {
    private val logger = KotlinLogging.logger {}

    val strategy: WatermarkStrategy<Row> =
        WatermarkStrategy
            .forBoundedOutOfOrderness<Row>(java.time.Duration.ofSeconds(5))
            .withTimestampAssigner { row: Row, _ ->
                try {
                    // Get the field by index. Assumes bid_time is at index 1 and is Long.
                    val timestamp = row.getField(1) as? Long
                    if (timestamp != null) {
                        timestamp
                    } else {
                        logger.warn { "Null or invalid timestamp at index 1 in Row: $row. Using current time." }
                        System.currentTimeMillis() // Fallback
                    }
                } catch (e: Exception) {
                    // Catch potential ClassCastException or other issues
                    logger.error(e) { "Error accessing timestamp at index 1 in Row: $row. Using current time." }
                    System.currentTimeMillis() // Fallback
                }
            }.withIdleness(java.time.Duration.ofSeconds(10)) // Same idleness
}
```

#### Not Applicable Source Code

The files `SupplierWatermarkStrategy`, `SupplierStatsAggregator`, and `SupplierStatsFunction` are used exclusively by the Flink DataStream API application for its specific watermark and aggregation logic. They are not relevant to this Table API implementation.

### Core Table API Application

This is the main driver for the Table API application. It demonstrates the powerful integration between the DataStream and Table APIs.

1.  **Environment Setup:** It initializes both a `StreamExecutionEnvironment` and a `StreamTableEnvironment`.
2.  **Data Ingestion and Preparation:**
    *   It consumes Avro `GenericRecord`s using a `KafkaSource` and maps them to a `DataStream<RecordMap>`.
    *   It applies a `WatermarkStrategy` to the `RecordMap` stream so that the subsequent `LateDataRouter` can function correctly based on event time.
3.  **Late Data Splitting:** It uses the custom `LateDataRouter` `ProcessFunction` to split the stream into an on-time stream and a late-data side output.
4.  **DataStream-to-Table Conversion:**
    *   The on-time `DataStream<RecordMap>` is converted to a `DataStream<Row>`. This step transforms the data into the structured, columnar format required by the Table API.
    *   A second `WatermarkStrategy` (`RowWatermarkStrategy`) is applied to the `DataStream<Row>`.
    *   `tEnv.createTemporaryView` registers the `DataStream<Row>` as a table named "orders". A `Schema` is defined, crucially marking the `bid_time` column as the event-time attribute (`TIMESTAMP_LTZ(3)`) and telling Flink to use the watermarks generated by the DataStream (`SOURCE_WATERMARK()`).
5.  **Declarative Query:** A high-level, declarative query is executed on the "orders" table. It uses `Tumble` to define 5-second windows and performs `groupBy` and `select` operations with aggregate functions (`sum`, `count`) to calculate the statistics.
6.  **Sinking:**
    *   A `TableDescriptor` is defined for the Kafka sink. It specifies the sink schema and, most importantly, the `avro-confluent` format, which handles serialization to Avro and integration with Schema Registry automatically.
    *   `statsTable.executeInsert()` writes the results of the query to the sink.
    *   The separate late data stream is processed and sunk to its own topic.
7.  **Execution:** `env.execute()` starts the Flink job.

```kotlin
@file:Suppress("ktlint:standard:no-wildcard-imports")

package me.jaehyeon

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import me.jaehyeon.flink.processing.LateDataRouter
import me.jaehyeon.flink.processing.RecordMap
import me.jaehyeon.flink.watermark.RowWatermarkStrategy
import me.jaehyeon.flink.watermark.SupplierWatermarkStrategy
import me.jaehyeon.kafka.createOrdersSource
import me.jaehyeon.kafka.createSkippedSink
import me.jaehyeon.kafka.createTopicIfNotExists
import me.jaehyeon.kafka.getLatestSchema
import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.flink.api.common.eventtime.WatermarkStrategy
import org.apache.flink.api.common.typeinfo.TypeHint
import org.apache.flink.api.common.typeinfo.TypeInformation
import org.apache.flink.api.java.typeutils.RowTypeInfo
import org.apache.flink.streaming.api.datastream.DataStream
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment
import org.apache.flink.streaming.connectors.kafka.table.KafkaConnectorOptions
import org.apache.flink.table.api.DataTypes
import org.apache.flink.table.api.Expressions.*
import org.apache.flink.table.api.Expressions.lit
import org.apache.flink.table.api.FormatDescriptor
import org.apache.flink.table.api.Schema
import org.apache.flink.table.api.Table
import org.apache.flink.table.api.TableDescriptor
import org.apache.flink.table.api.Tumble
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment
import org.apache.flink.types.Row
import org.apache.flink.util.OutputTag
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

object TableApp {
    private val toSkipPrint = System.getenv("TO_SKIP_PRINT")?.toBoolean() ?: true
    private val bootstrapAddress = System.getenv("BOOTSTRAP") ?: "kafka-1:19092"
    private val inputTopicName = System.getenv("TOPIC") ?: "orders-avro"
    private val registryUrl = System.getenv("REGISTRY_URL") ?: "http://schema:8081"
    private val registryConfig =
        mapOf(
            "basic.auth.credentials.source" to "USER_INFO",
            "basic.auth.user.info" to "admin:admin",
        )
    private const val INPUT_SCHEMA_SUBJECT = "orders-avro-value"
    private const val NUM_PARTITIONS = 3
    private const val REPLICATION_FACTOR: Short = 3
    private val logger = KotlinLogging.logger {}

    // ObjectMapper for converting late data Map to JSON
    private val objectMapper: ObjectMapper by lazy {
        ObjectMapper().registerKotlinModule()
    }

    fun run() {
        // Create output topics if not existing
        val outputTopicName = "$inputTopicName-ktl-stats"
        val skippedTopicName = "$inputTopicName-ktl-skipped"
        listOf(outputTopicName, skippedTopicName).forEach { name ->
            createTopicIfNotExists(
                name,
                bootstrapAddress,
                NUM_PARTITIONS,
                REPLICATION_FACTOR,
            )
        }

        val env = StreamExecutionEnvironment.getExecutionEnvironment()
        env.parallelism = 3
        val tEnv = StreamTableEnvironment.create(env)

        val inputAvroSchema = getLatestSchema(INPUT_SCHEMA_SUBJECT, registryUrl, registryConfig)
        val ordersGenericRecordSource =
            createOrdersSource(
                topic = inputTopicName,
                groupId = "$inputTopicName-flink-tl",
                bootstrapAddress = bootstrapAddress,
                registryUrl = registryUrl,
                registryConfig = registryConfig,
                schema = inputAvroSchema,
            )

        // 1. Stream of GenericRecords from Kafka
        val genericRecordStream: DataStream<GenericRecord> =
            env
                .fromSource(ordersGenericRecordSource, WatermarkStrategy.noWatermarks(), "KafkaGenericRecordSource")

        // 2. Convert GenericRecord to Map<String, Any?> (RecordMap)
        val recordMapStream: DataStream<RecordMap> =
            genericRecordStream
                .map { genericRecord ->
                    val map = mutableMapOf<String, Any?>()
                    genericRecord.schema.fields.forEach { field ->
                        val value = genericRecord.get(field.name())
                        map[field.name()] = if (value is org.apache.avro.util.Utf8) value.toString() else value
                    }
                    map as RecordMap // Cast to type alias
                }.name("GenericRecordToMapConverter")
                .returns(TypeInformation.of(object : TypeHint<RecordMap>() {}))

        // 3. Define OutputTag for late data (now carrying RecordMap)
        val lateMapOutputTag =
            OutputTag(
                "late-order-records",
                TypeInformation.of(object : TypeHint<RecordMap>() {}),
            )

        // 4. Split late records from on-time ones
        val statsStreamOperator: SingleOutputStreamOperator<RecordMap> =
            recordMapStream
                .assignTimestampsAndWatermarks(SupplierWatermarkStrategy.strategy)
                .process(LateDataRouter(lateMapOutputTag, allowedLatenessMillis = 5000))
                .name("LateDataRouter")

        // 5. Create source table (statsTable)
        val statsStream: DataStream<RecordMap> = statsStreamOperator
        val rowStatsStream: DataStream<Row> =
            statsStream
                .map { recordMap ->
                    val orderId = recordMap["order_id"] as? String
                    val price = recordMap["price"] as? Double
                    val item = recordMap["item"] as? String
                    val supplier = recordMap["supplier"] as? String

                    val bidTimeString = recordMap["bid_time"] as? String
                    var bidTimeInstant: Instant? = null // Changed from bidTimeLong to bidTimeInstant

                    if (bidTimeString != null) {
                        try {
                            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                            val localDateTime = LocalDateTime.parse(bidTimeString, formatter)
                            // Convert to Instant
                            bidTimeInstant =
                                localDateTime
                                    .atZone(ZoneId.systemDefault()) // Or ZoneOffset.UTC
                                    .toInstant()
                        } catch (e: DateTimeParseException) {
                            logger.error(e) { "Failed to parse bid_time string '$bidTimeString'. RecordMap: $recordMap" }
                        } catch (e: Exception) {
                            logger.error(e) { "Unexpected error parsing bid_time string '$bidTimeString'. RecordMap: $recordMap" }
                        }
                    } else {
                        logger.warn { "bid_time string is null in RecordMap: $recordMap" }
                    }

                    Row.of(
                        orderId,
                        bidTimeInstant,
                        price,
                        item,
                        supplier,
                    )
                }.returns(
                    RowTypeInfo(
                        arrayOf<TypeInformation<*>>(
                            TypeInformation.of(String::class.java),
                            TypeInformation.of(Instant::class.java), // bid_time (as Long milliseconds for TIMESTAMP_LTZ)
                            TypeInformation.of(Double::class.java),
                            TypeInformation.of(String::class.java),
                            TypeInformation.of(String::class.java),
                        ),
                        arrayOf("order_id", "bid_time", "price", "item", "supplier"),
                    ),
                ).assignTimestampsAndWatermarks(RowWatermarkStrategy.strategy)
                .name("MapToRowConverter")
        val tableSchema =
            Schema
                .newBuilder()
                .column("order_id", DataTypes.STRING())
                .column("bid_time", DataTypes.TIMESTAMP_LTZ(3)) // Event time attribute
                .column("price", DataTypes.DOUBLE())
                .column("item", DataTypes.STRING())
                .column("supplier", DataTypes.STRING())
                .watermark("bid_time", "SOURCE_WATERMARK()") // Use watermarks from DataStream
                .build()
        tEnv.createTemporaryView("orders", rowStatsStream, tableSchema)

        val statsTable: Table =
            tEnv
                .from("orders")
                .window(Tumble.over(lit(5).seconds()).on(col("bid_time")).`as`("w"))
                .groupBy(col("supplier"), col("w"))
                .select(
                    col("supplier"),
                    col("w").start().`as`("window_start"),
                    col("w").end().`as`("window_end"),
                    col("price").sum().round(2).`as`("total_price"),
                    col("order_id").count().`as`("count"),
                )

        // 6. Create sink table
        val sinkSchema =
            Schema
                .newBuilder()
                .column("supplier", DataTypes.STRING())
                .column("window_start", DataTypes.TIMESTAMP(3))
                .column("window_end", DataTypes.TIMESTAMP(3))
                .column("total_price", DataTypes.DOUBLE())
                .column("count", DataTypes.BIGINT())
                .build()
        val kafkaSinkDescriptor: TableDescriptor =
            TableDescriptor
                .forConnector("kafka")
                .schema(sinkSchema) // Set the schema for the sink
                .option(KafkaConnectorOptions.TOPIC, listOf(outputTopicName))
                .option(KafkaConnectorOptions.PROPS_BOOTSTRAP_SERVERS, bootstrapAddress)
                .format(
                    FormatDescriptor
                        .forFormat("avro-confluent")
                        .option("url", registryUrl)
                        .option("basic-auth.credentials-source", "USER_INFO")
                        .option("basic-auth.user-info", "admin:admin")
                        .option("subject", "$outputTopicName-value")
                        .build(),
                ).build()

        // 7. Handle late data as a pair of key and value
        val lateDataMapStream: DataStream<RecordMap> = statsStreamOperator.getSideOutput(lateMapOutputTag)
        val lateKeyPairStream: DataStream<Pair<String?, String>> =
            lateDataMapStream
                .map { recordMap ->
                    val mutableMap = recordMap.toMutableMap()
                    mutableMap["late"] = true
                    val orderId = mutableMap["order_id"] as? String
                    try {
                        val value = objectMapper.writeValueAsString(mutableMap)
                        Pair(orderId, value)
                    } catch (e: Exception) {
                        logger.error(e) { "Error serializing late RecordMap to JSON: $mutableMap" }
                        val errorJson = "{ \"error\": \"json_serialization_failed\", \"data_keys\": \"${
                            mutableMap.keys.joinToString(
                                ",",
                            )}\" }"
                        Pair(orderId, errorJson)
                    }
                }.returns(TypeInformation.of(object : TypeHint<Pair<String?, String>>() {}))
        val skippedSink =
            createSkippedSink(
                topic = skippedTopicName,
                bootstrapAddress = bootstrapAddress,
            )

        if (!toSkipPrint) {
            tEnv
                .toDataStream(statsTable)
                .print()
                .name("SupplierStatsPrint")
            lateKeyPairStream
                .map { it.second }
                .print()
                .name("LateDataPrint")
        }

        statsTable.executeInsert(kafkaSinkDescriptor)
        lateKeyPairStream.sinkTo(skippedSink).name("LateDataSink")
        env.execute("SupplierStats")
    }
}
```

### Application Entry Point

The `Main.kt` file serves as the entry point for the application. It parses a command-line argument (`datastream` or `table`) to determine which Flink application to run. A `try-catch` block ensures that any fatal error during execution is logged before the application exits.

```kotlin
package me.jaehyeon

import mu.KotlinLogging
import kotlin.system.exitProcess

private val logger = KotlinLogging.logger {}

fun main(args: Array<String>) {
    try {
        when (args.getOrNull(0)?.lowercase()) {
            "datastream" -> DataStreamApp.run()
            "table" -> TableApp.run()
            else -> println("Usage: <datastream | table>")
        }
    } catch (e: Exception) {
        logger.error(e) { "Fatal error in ${args.getOrNull(0) ?: "app"}. Shutting down." }
        exitProcess(1)
    }
}
```

## Run Flink Application

As with the DataStream job in the [previous post](/blog/2025-06-10-kotlin-getting-started-flink-datastream), running the Table API application involves setting up a local Kafka environment from the [Factor House Local](https://github.com/factorhouse/factorhouse-local) project, starting the data producer, and then launching the Flink job with the correct argument.

### Factor House Local Setup

To set up your local Kafka environment, follow these steps:
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

Next, start the Kafka data producer from the `orders-avro-clients` project (developed in [Part 2 of this series](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients/)) to populate the `orders-avro` topic. To properly test the application's handling of late events, it's crucial to run the producer with a randomized delay (up to 30 seconds).

Navigate to the producer's project directory (`orders-avro-clients`) in the [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples) and execute the following:

```bash
# Assuming you are in the root of the 'orders-avro-clients' project
DELAY_SECONDS=30 ./gradlew run --args="producer"
```

This will start populating the `orders-avro` topic with Avro-encoded order messages. You can inspect these messages in Kpow. Ensure Kpow is configured with Key Deserializer: *String*, Value Deserializer: *AVRO*, and Schema Registry: *Local Schema Registry*.

![](orders-01.png#center)
![](orders-02.png#center)

### Launch the Flink Application

With the data pipeline ready, navigate to the `orders-stats-flink` project directory of the [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples). This time, we'll launch the job by providing `table` as the command-line argument to trigger the declarative, Table API-based logic.

The application can be run in two main ways:

1.  **With Gradle (Development Mode)**: Ideal for development and quick testing.
    ```bash
    ./gradlew run --args="table"
    ```
2.  **Running the Shadow JAR (Deployment Mode)**: For deploying the application as a standalone unit. First, build the fat JAR:
    ```bash
    ./gradlew shadowJar
    ```
    This creates `build/libs/orders-stats-flink-1.0.jar`. Then run it:
    ```bash
    java --add-opens=java.base/java.util=ALL-UNNAMED \
      -jar build/libs/orders-stats-flink-1.0.jar table
    ```

> 💡 To build and run the application locally, ensure that **JDK 17** is installed.

For this demonstration, we'll use Gradle to run the application in development mode. Upon starting, you'll see logs indicating the Flink application has initialized and is processing records from the `orders-avro` topic.

### Observing the Output

Our Flink application produces results to two topics:
*   `orders-avro-ktl-stats`: Contains the aggregated supplier statistics as Avro records.
*   `orders-avro-ktl-skipped`: Contains records identified as "late," serialized as JSON.

**1. Supplier Statistics (`orders-avro-ktl-stats`):**

In Kpow, navigate to the `orders-avro-ktl-stats` topic. Configure Kpow to view these messages:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *AVRO*
*   **Schema Registry:** *Local Schema Registry*

You should see `SupplierStats` messages, each representing the total price and count of orders for a supplier within a 5-second (or 5000 millisecond) window. Notice the `window_start` and `window_end` fields.

![](stats-01.png#center)
![](stats-02.png#center)

**2. Skipped (Late) Records (`orders-avro-ktl-skipped`):**

Next, inspect the `orders-avro-ktl-skipped` topic in Kpow. Configure Kpow as follows:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *JSON*

These records were intercepted and rerouted by our custom `LateDataRouter` `ProcessFunction`. This manual step was necessary to separate late data before converting the stream to a `Table`, demonstrating a powerful pattern of blending Flink's APIs to solve complex requirements.

![](skipped-01.png#center)
![](skipped-02.png#center)

## Conclusion

In this final post of our series, we've demonstrated the power and simplicity of Flink's Table API for real-time analytics. We successfully built a pipeline that produced the same supplier statistics as our previous examples, but with a more concise and declarative query. We've seen how to define a table schema, apply event-time windowing with SQL-like expressions, and seamlessly bridge between the DataStream and Table APIs to implement custom logic like late-data routing. This journey, from basic Kafka clients to Kafka Streams and finally to the versatile APIs of Flink, illustrates the rich ecosystem available for building modern, real-time data applications in Kotlin. Flink's Table API, in particular, proves to be an invaluable tool for analysts and developers who need to perform complex analytics on data in motion.