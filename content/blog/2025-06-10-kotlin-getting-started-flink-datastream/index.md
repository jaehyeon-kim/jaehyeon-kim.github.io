---
title: Flink DataStream API - Scalable Event Processing for Supplier Stats
date: 2025-06-10
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

Building on our exploration of stream processing, we now transition from Kafka's native library to **Apache Flink**, a powerful, general-purpose distributed processing engine. In this post, we'll dive into Flink's foundational **DataStream API**. We will tackle the same supplier statistics problem - analyzing a stream of Avro-formatted order events - but this time using Flink's robust features for stateful computation. This example will highlight Flink's sophisticated event-time processing with watermarks and its elegant, built-in mechanisms for handling late-arriving data through side outputs.

<!--more-->

* [Kafka Clients with JSON - Producing and Consuming Order Events](/blog/2025-05-20-kotlin-getting-started-kafka-json-clients)
* [Kafka Clients with Avro - Schema Registry and Order Events](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients)
* [Kafka Streams - Lightweight Real-Time Processing for Supplier Stats](/blog/2025-06-03-kotlin-getting-started-kafka-streams)
* [Flink DataStream API - Scalable Event Processing for Supplier Stats](#) (this post)
* [Flink Table API - Declarative Analytics for Supplier Stats in Real Time](/blog/2025-06-17-kotlin-getting-started-flink-table)

## Flink DataStream Application

We develop a Flink DataStream application designed for scalable, real-time event processing. The application:
*   Consumes Avro-formatted order events from a Kafka topic.
*   Assigns event-time timestamps and watermarks to handle out-of-order data.
*   Aggregates order data into 5-second tumbling windows to calculate total price and order counts for each supplier.
*   Leverages Flink's side-output mechanism to gracefully handle and route late-arriving records to a separate topic.
*   Serializes the resulting supplier statistics and late records back to Kafka, using Avro and JSON respectively.

The source code for the application discussed in this post can befound in the _orders-stats-flink_ folder of this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples).

### The Build Configuration

The `build.gradle.kts` file sets up the project, its dependencies, and packaging. It's shared between the DataStream and Table API applications - The Flink application that uses the Table API will be covered in the next post.

*   **Plugins:**
    *   `kotlin("jvm")`: Enables Kotlin language support.
    *   `com.github.davidmc24.gradle.plugin.avro`: Compiles Avro schemas into Java classes.
    *   `com.github.johnrengelman.shadow`: Creates an executable "fat JAR" with all dependencies.
    *   `application`: Configures the project to be runnable via Gradle.
*   **Dependencies:**
    *   **Flink Core & APIs:** `flink-streaming-java`, `flink-clients`.
    *   **Flink Connectors:** `flink-connector-kafka` for Kafka integration.
    *   **Flink Formats:** `flink-avro` and `flink-avro-confluent-registry` for handling Avro data with Confluent Schema Registry.
    *   **Note on Dependency Scope:** The Flink dependencies are declared with `implementation`. This allows the application to be run directly with `./gradlew run`. For production deployments on a Flink cluster (where the Flink runtime is already provided), these dependencies should be changed to `compileOnly` to significantly reduce the size of the final JAR.
*   **Application Configuration:**
    *   The `application` block sets the `mainClass` and passes necessary JVM arguments for Flink's runtime. The `run` task is configured with environment variables to specify Kafka and Schema Registry connection details.
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

The `SupplierStats.avsc` file defines the structure for the aggregated output data. This schema is used by the Flink Kafka sink to serialize the `SupplierStats` objects into Avro format, ensuring type safety and enabling schema evolution for downstream consumers.

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

This file centralizes the creation of Flink's Kafka sources and sinks.

*   **`createOrdersSource(...)`:** Configures a `KafkaSource` to consume `GenericRecord` Avro data. It uses `ConfluentRegistryAvroDeserializationSchema` to automatically deserialize messages using the schema from Confluent Schema Registry.
*   **`createStatsSink(...)`:** Configures a `KafkaSink` for the aggregated `SupplierStats`. It uses `ConfluentRegistryAvroSerializationSchema` to serialize the specific `SupplierStats` type and sets the Kafka message key to the supplier's name.
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

### DataStream Processing Logic

The following files contain the core logic specific to the DataStream API implementation.

#### Timestamp and Watermark Strategy

For event-time processing, Flink needs to know each event's timestamp and how to handle out-of-order data. This `WatermarkStrategy` extracts the timestamp from the `bid_time` field of the incoming `RecordMap`. It uses `forBoundedOutOfOrderness` with a 5-second duration, telling Flink to expect records to be at most 5 seconds late.

```kotlin
package me.jaehyeon.flink.watermark

import me.jaehyeon.flink.processing.RecordMap
import mu.KotlinLogging
import org.apache.flink.api.common.eventtime.WatermarkStrategy
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val logger = KotlinLogging.logger {}

object SupplierWatermarkStrategy {
    val strategy: WatermarkStrategy<RecordMap> =
        WatermarkStrategy
            .forBoundedOutOfOrderness<RecordMap>(Duration.ofSeconds(5)) // Operates on RecordMap
            .withTimestampAssigner { recordMap, _ ->
                val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                try {
                    val bidTimeString = recordMap["bid_time"]?.toString()
                    if (bidTimeString != null) {
                        val ldt = LocalDateTime.parse(bidTimeString, formatter)
                        ldt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    } else {
                        logger.warn { "Missing 'bid_time' field in RecordMap: $recordMap. Using processing time." }
                        System.currentTimeMillis()
                    }
                } catch (e: Exception) {
                    logger.error(e) { "Error parsing 'bid_time' from RecordMap: $recordMap. Using processing time." }
                    System.currentTimeMillis()
                }
            }.withIdleness(Duration.ofSeconds(10)) // Optional: if partitions can be idle
}
```

#### Custom Aggregation and Windowing Functions

Flink's DataStream API provides fine-grained control over windowed aggregations using a combination of an `AggregateFunction` and a `WindowFunction`.

*   **`SupplierStatsAggregator`:** This `AggregateFunction` performs efficient, incremental aggregation. For each record in a window, it updates an accumulator, adding the price to `totalPrice` and incrementing the `count`. This pre-aggregation is highly optimized as it doesn't need to store all records in the window.
*   **`SupplierStatsFunction`:** This `WindowFunction` is applied once the window is complete. It receives the final accumulator from the `AggregateFunction` and has access to the window's metadata (key, start time, end time). It uses this information to construct the final `SupplierStats` Avro object.

```kotlin
package me.jaehyeon.flink.processing

import org.apache.flink.api.common.functions.AggregateFunction

typealias RecordMap = Map<String, Any?>

data class SupplierStatsAccumulator(
    var totalPrice: Double = 0.0,
    var count: Long = 0L,
)

class SupplierStatsAggregator : AggregateFunction<RecordMap, SupplierStatsAccumulator, SupplierStatsAccumulator> {
    override fun createAccumulator(): SupplierStatsAccumulator = SupplierStatsAccumulator()

    override fun add(
        value: RecordMap,
        accumulator: SupplierStatsAccumulator,
    ): SupplierStatsAccumulator =
        SupplierStatsAccumulator(
            accumulator.totalPrice + value["price"] as Double,
            accumulator.count + 1,
        )

    override fun getResult(accumulator: SupplierStatsAccumulator): SupplierStatsAccumulator = accumulator

    override fun merge(
        a: SupplierStatsAccumulator,
        b: SupplierStatsAccumulator,
    ): SupplierStatsAccumulator =
        SupplierStatsAccumulator(
            totalPrice = a.totalPrice + b.totalPrice,
            count = a.count + b.count,
        )
}
```

```kotlin
package me.jaehyeon.flink.processing

import me.jaehyeon.avro.SupplierStats
import org.apache.flink.streaming.api.functions.windowing.WindowFunction
import org.apache.flink.streaming.api.windowing.windows.TimeWindow
import org.apache.flink.util.Collector
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class SupplierStatsFunction : WindowFunction<SupplierStatsAccumulator, SupplierStats, String, TimeWindow> {
    companion object {
        private val formatter: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault())
    }

    override fun apply(
        supplierKey: String,
        window: TimeWindow,
        input: Iterable<SupplierStatsAccumulator>,
        out: Collector<SupplierStats>,
    ) {
        val accumulator = input.firstOrNull() ?: return
        val windowStartStr = formatter.format(Instant.ofEpochMilli(window.start))
        val windowEndStr = formatter.format(Instant.ofEpochMilli(window.end))

        out.collect(
            SupplierStats
                .newBuilder()
                .setWindowStart(windowStartStr)
                .setWindowEnd(windowEndStr)
                .setSupplier(supplierKey)
                .setTotalPrice(String.format("%.2f", accumulator.totalPrice).toDouble())
                .setCount(accumulator.count)
                .build(),
        )
    }
}
```

#### Not Applicable Source Code

`RowWatermarkStrategy` and `LateDataRouter` are used exclusively by the Flink Table API application and are not relevant to this DataStream implementation. The DataStream API handles late data using the built-in `.sideOutputLateData()` method, making a custom router unnecessary.

### Core DataStream Application

This is the main driver for the DataStream application. It defines and executes the Flink job topology.

1.  **Environment Setup:** It initializes the `StreamExecutionEnvironment` and creates the necessary output Kafka topics.
2.  **Source and Transformation:** It creates a Kafka source for Avro `GenericRecord`s and then maps them to a more convenient `DataStream<RecordMap>`.
3.  **Timestamping and Windowing:**
    *   `assignTimestampsAndWatermarks` applies the custom `SupplierWatermarkStrategy`.
    *   The stream is keyed by the `supplier` field.
    *   A `TumblingEventTimeWindows` of 5 seconds is defined.
    *   `allowedLateness` is set to 5 seconds, allowing the window state to be kept for an additional 5 seconds after the watermark passes to accommodate late-but-not-too-late events.
4.  **Late Data Handling:** `sideOutputLateData` is a key feature. It directs any records arriving after the `allowedLateness` period to a separate stream identified by an `OutputTag`.
5.  **Aggregation:** The `.aggregate()` call combines the efficient `SupplierStatsAggregator` with the final `SupplierStatsFunction` to produce the statistics.
6.  **Sinking:**
    *   The main `statsStream` is sent to the `statsSink`.
    *   The late data stream, retrieved via `getSideOutput`, is processed (converted to JSON with a "late" flag) and sent to the `skippedSink`.
7.  **Execution:** `env.execute()` starts the Flink job.

```kotlin
package me.jaehyeon

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import me.jaehyeon.avro.SupplierStats
import me.jaehyeon.flink.processing.RecordMap
import me.jaehyeon.flink.processing.SupplierStatsAggregator
import me.jaehyeon.flink.processing.SupplierStatsFunction
import me.jaehyeon.flink.watermark.SupplierWatermarkStrategy
import me.jaehyeon.kafka.createOrdersSource
import me.jaehyeon.kafka.createSkippedSink
import me.jaehyeon.kafka.createStatsSink
import me.jaehyeon.kafka.createTopicIfNotExists
import me.jaehyeon.kafka.getLatestSchema
import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.flink.api.common.eventtime.WatermarkStrategy
import org.apache.flink.api.common.typeinfo.TypeHint
import org.apache.flink.api.common.typeinfo.TypeInformation
import org.apache.flink.streaming.api.datastream.DataStream
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows
import org.apache.flink.util.OutputTag
import java.time.Duration

object DataStreamApp {
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
        val outputTopicName = "$inputTopicName-kds-stats"
        val skippedTopicName = "$inputTopicName-kds-skipped"
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

        val inputAvroSchema = getLatestSchema(INPUT_SCHEMA_SUBJECT, registryUrl, registryConfig)
        val ordersGenericRecordSource =
            createOrdersSource(
                topic = inputTopicName,
                groupId = "$inputTopicName-flink-ds",
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

        // 4. Process the RecordMap stream
        val statsStreamOperator: SingleOutputStreamOperator<SupplierStats> =
            recordMapStream
                .assignTimestampsAndWatermarks(SupplierWatermarkStrategy.strategy)
                .keyBy { recordMap -> recordMap["supplier"].toString() }
                .window(TumblingEventTimeWindows.of(Duration.ofSeconds(5)))
                .allowedLateness(Duration.ofSeconds(5))
                .sideOutputLateData(lateMapOutputTag)
                .aggregate(SupplierStatsAggregator(), SupplierStatsFunction())
        val statsStream: DataStream<SupplierStats> = statsStreamOperator

        // 5. Handle late data as a pair of key and value
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

        if (!toSkipPrint) {
            statsStream
                .print()
                .name("SupplierStatsPrint")
            lateKeyPairStream
                .map { it.second }
                .print()
                .name("LateDataPrint")
        }

        val statsSink =
            createStatsSink(
                topic = outputTopicName,
                bootstrapAddress = bootstrapAddress,
                registryUrl = registryUrl,
                registryConfig = registryConfig,
                outputSubject = "$outputTopicName-value",
            )

        val skippedSink =
            createSkippedSink(
                topic = skippedTopicName,
                bootstrapAddress = bootstrapAddress,
            )

        statsStream.sinkTo(statsSink).name("SupplierStatsSink")
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

To observe our Flink DataStream application in action, we'll follow the essential steps: setting up a local Kafka environment, generating a stream of test data, and then executing the Flink job.

### Factor House Local Setup

A local Kafka environment is a prerequisite. If you don't have one running, use the [Factor House Local](https://github.com/factorhouse/factorhouse-local) project to quickly get started:
1.  Clone the repository:
    ```bash
    git clone https://github.com/factorhouse/factorhouse-local.git
    cd factorhouse-local
    ```
2.  Configure your Kpow community license as detailed in the project's [README](https://github.com/factorhouse/factorhouse-local?tab=readme-ov-file#update-kpow-and-flex-licenses).
3.  Start the Docker services:
    ```bash
    docker compose -f compose-kpow-community.yml up -d
    ```
Once running, the Kpow UI at `http://localhost:3000` will provide visibility into your Kafka cluster.

![](kpow-overview.png#center)

### Start the Kafka Order Producer

Our Flink application is designed to consume order data from the `orders-avro` topic. We'll use the Kafka producer developed in [Part 2 of this series](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients/) to generate this data. To properly test Flink's event-time windowing, we'll configure the producer to add a randomized delay (up to 30 seconds) to the `bid_time` field.

Navigate to the directory of the producer application (_orders-avro-clients_ from the [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples)) and run:

```bash
# Assuming you are in the root of the 'orders-avro-clients' project
DELAY_SECONDS=30 ./gradlew run --args="producer"
```

This will start populating the `orders-avro` topic with Avro-encoded order messages. You can inspect these messages in Kpow. Ensure Kpow is configured with Key Deserializer: *String*, Value Deserializer: *AVRO*, and Schema Registry: *Local Schema Registry*.

![](orders-01.png#center)
![](orders-02.png#center)

### Launch the Flink Application

With a steady stream of order events being produced, we can now launch our `orders-stats-flink` application. Navigate to its project directory. The application's entry point is designed to run different jobs based on a command-line argument; for this post, we'll use `datastream`.

The application can be run in two main ways:

1.  **With Gradle (Development Mode)**:
    ```bash
    ./gradlew run --args="datastream"
    ```
2.  **Running the Shadow JAR (Deployment Mode)**:
    ```bash
    # First, build the fat JAR
    ./gradlew shadowJar

    # Then run it
    java --add-opens=java.base/java.util=ALL-UNNAMED \
      -jar build/libs/orders-stats-flink-1.0.jar datastream
    ```

> 💡 To build and run the application locally, ensure that **JDK 17** is installed.

For this demonstration, we'll use Gradle to run the application in development mode. Upon starting, you'll see logs indicating the Flink application has initialized and is processing records from the `orders-avro` topic.

### Observing the Output

Our Flink DataStream job writes its results to two distinct Kafka topics:
*   `orders-avro-kds-stats`: Contains the aggregated supplier statistics as Avro records.
*   `orders-avro-kds-skipped`: Contains records identified as "late," serialized as JSON.

**1. Supplier Statistics (`orders-avro-kds-stats`):**

In Kpow, navigate to the `orders-avro-kds-stats` topic. Configure Kpow to view these messages:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *AVRO*
*   **Schema Registry:** *Local Schema Registry*

You should see `SupplierStats` messages, each representing the total price and count of orders for a supplier within a 5-second window. Notice the `window_start` and `window_end` fields.

![](stats-01.png#center)
![](stats-02.png#center)

**2. Skipped (Late) Records (`orders-avro-kds-skipped`):**

Next, inspect the `orders-avro-kds-skipped` topic in Kpow. Configure Kpow as follows:
*   **Key Deserializer:** *String*
*   **Value Deserializer:** *JSON*

These records are the ones that arrived too late to be included in their windows, even after the `allowedLateness` period. They were captured using Flink's powerful `.sideOutputLateData()` function and then converted to JSON with a `"late": true` field for confirmation.

![](skipped-01.png#center)
![](skipped-02.png#center)

## Conclusion

In this post, we've built a powerful, real-time analytics job using Apache Flink's DataStream API. We demonstrated how to implement a complete stateful pipeline in Kotlin, from consuming Avro records to performing windowed aggregations with a custom `AggregateFunction` and `WindowFunction`. We saw how Flink's `WatermarkStrategy` provides a robust foundation for event-time processing and how the `.sideOutputLateData()` operator offers a clean, first-class solution for isolating late records. This approach showcases the fine-grained control and high performance the DataStream API offers for complex stream processing challenges. Next, we will see how to solve the same problem with a much more declarative approach using Flink's Table API.
