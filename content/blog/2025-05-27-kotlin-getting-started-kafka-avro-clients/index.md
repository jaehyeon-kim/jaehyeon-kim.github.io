---
title: Kafka Clients with Avro - Schema Registry and Order Events
date: 2025-05-27
draft: false
featured: false
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
  - Kotlin
  - Docker
  - Kpow
  - Factor House Local
authors:
  - JaehyeonKim
images: []
description:
---

In this post, we'll explore a practical example of building Kafka client applications using Kotlin, Apache Avro for data serialization, and Gradle for build management. We'll walk through the setup of a Kafka producer that generates mock order data and a consumer that processes these orders. This example highlights best practices such as schema management with Avro, robust error handling, and graceful shutdown, providing a solid foundation for your own Kafka-based projects. We'll dive into the build configuration, the Avro schema definition, utility functions for Kafka administration, and the core logic of both the producer and consumer applications.

<!--more-->

* [Kafka Clients with JSON - Producing and Consuming Order Events](/blog/2025-05-20-kotlin-getting-started-kafka-json-clients)
* [Kafka Clients with Avro - Schema Registry and Order Events](#) (this post)
* [Kafka Streams - Lightweight Real-Time Processing for Supplier Stats](/blog/2025-06-03-kotlin-getting-started-kafka-streams)
* Flink DataStream API - Scalable Event Processing for Supplier Stats
* Flink Table API - Declarative Analytics for Supplier Stats in Real Time

## Kafka Client Applications

This project demonstrates two primary Kafka client applications:
*   A **Producer Application** responsible for generating `Order` messages and publishing them to a Kafka topic using Avro serialization.
*   A **Consumer Application** designed to subscribe to the same Kafka topic, deserialize the Avro messages, and process them, including retry logic and graceful handling of shutdowns.

Both applications are packaged into a single executable JAR, and their execution mode (producer or consumer) is determined by a command-line argument. The source code for the applications discussed in this post can be found in the _orders-avro-clients_ folder of this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples).

### The Build Configuration

The `build.gradle.kts` file is the heart of our project's build process, defining plugins, dependencies, and custom tasks.

*   **Plugins:**
    *   `kotlin("jvm")`: Enables Kotlin language support for the JVM.
    *   `com.github.davidmc24.gradle.plugin.avro`: Manages Avro schema compilation into Java classes.
    *   `com.github.johnrengelman.shadow`: Creates a "fat JAR" or "uber JAR" containing all dependencies, making the application easily deployable.
    *   `application`: Configures the project as a runnable application, specifying the main class.
*   **Repositories:**
    *   `mavenCentral()`: The standard Maven repository.
    *   `maven("https://packages.confluent.io/maven/")`: The Confluent repository, necessary for Confluent-specific dependencies like the Avro serializer.
*   **Dependencies:**
    *   **Kafka:** `org.apache.kafka:kafka-clients` for core Kafka producer/consumer APIs.
    *   **Avro:**
        *   `org.apache.avro:avro` for the Avro serialization library.
        *   `io.confluent:kafka-avro-serializer` for Confluent's Kafka Avro serializer/deserializer, which integrates with Schema Registry.
    *   **Logging:** `io.github.microutils:kotlin-logging-jvm` (a Kotlin-friendly SLF4J wrapper) and `ch.qos.logback:logback-classic` (a popular SLF4J implementation).
    *   **Faker:** `net.datafaker:datafaker` for generating realistic mock data for our orders.
    *   **Testing:** `kotlin("test")` for unit testing with Kotlin.
*   **Kotlin Configuration:**
    *   `jvmToolchain(17)`: Specifies Java 17 as the target JVM.
*   **Application Configuration:**
    *   `mainClass.set("me.jaehyeon.MainKt")`: Sets the entry point of the application.
*   **Shadow JAR Configuration:**
    *   The `tasks.withType<ShadowJar>` block customizes the fat JAR output, setting its base name, classifier (empty, so no classifier), and version.
    *   `mergeServiceFiles()`: Important for merging service provider configuration files (e.g., for SLF4J) from multiple dependencies.
    *   The `build` task is configured to depend on `shadowJar`, ensuring the fat JAR is created during a standard build.

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
    // AVRO
    implementation("org.apache.avro:avro:1.11.4")
    implementation("io.confluent:kafka-avro-serializer:7.9.0")
    // Logging
    implementation("io.github.microutils:kotlin-logging-jvm:3.0.5")
    implementation("ch.qos.logback:logback-classic:1.5.13")
    // Faker
    implementation("net.datafaker:datafaker:2.1.0")
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
    setCreateSetters(true)
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
    archiveBaseName.set("orders-avro-clients")
    archiveClassifier.set("")
    archiveVersion.set("1.0")
    mergeServiceFiles()
}

tasks.named("build") {
    dependsOn("shadowJar")
}

tasks.test {
    useJUnitPlatform()
}
```

### Avro Schema and Code Generation

Apache Avro is used for data serialization, providing schema evolution and type safety.

*   **Schema Definition (`Order.avsc`):**
    Located in `src/main/avro/Order.avsc`, this JSON file defines the structure of our `Order` messages:
    ```json
    {
      "namespace": "me.jaehyeon.avro",
      "type": "record",
      "name": "Order",
      "fields": [
        { "name": "order_id", "type": "string" },
        { "name": "bid_time", "type": "string" },
        { "name": "price", "type": "double" },
        { "name": "item", "type": "string" },
        { "name": "supplier", "type": "string" }
      ]
    }
    ```
    This schema will generate a Java class `me.jaehyeon.avro.Order`.
*   **Gradle Avro Plugin Configuration:**
    The `avro` block in `build.gradle.kts` configures the Avro code generation:
    ```kotlin
    avro {
        setCreateSetters(true) // Generates setter methods for fields
        setFieldVisibility("PRIVATE") // Makes fields private
    }
    ```
*   **Integrating Generated Code:**
    *   `tasks.named("compileKotlin") { dependsOn("generateAvroJava") }`: Ensures Avro Java classes are generated before Kotlin code is compiled.
    *   `sourceSets { named("main") { java.srcDirs("build/generated/avro/main") ... } }`: Adds the directory containing generated Avro Java classes to the main source set, making them available for Kotlin compilation.

### Kafka Admin Utilities

The `me.jaehyeon.kafka` package provides helper functions for interacting with Kafka's administrative features using the `AdminClient`.

*   **`createTopicIfNotExists(...)`:**
    *   Takes topic name, bootstrap server address, number of partitions, and replication factor as input.
    *   Configures an `AdminClient` with appropriate timeouts and retries.
    *   Attempts to create a new topic.
    *   Gracefully handles `TopicExistsException` if the topic already exists or is created concurrently, logging a warning.
    *   Throws a runtime exception for other unrecoverable errors.
*   **`verifyKafkaConnection(...)`:**
    *   Takes the bootstrap server address as input.
    *   Configures an `AdminClient`.
    *   Attempts to list topics as a simple way to check if the Kafka cluster is reachable.
    *   Throws a runtime exception if the connection fails.

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

fun verifyKafkaConnection(bootstrapAddress: String) {
    val props =
        Properties().apply {
            put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
            put(AdminClientConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, "5000")
            put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
            put(AdminClientConfig.RETRIES_CONFIG, "1")
        }

    AdminClient.create(props).use { client ->
        try {
            client.listTopics().names().get()
        } catch (e: Exception) {
            throw RuntimeException("Failed to connect to Kafka at'$bootstrapAddress'.", e)
        }
    }
}
```

### The Kafka Producer

The `ProducerApp` object is responsible for generating and sending `Order` messages to Kafka.

*   **Configuration:**
    *   Reads `BOOTSTRAP` (Kafka brokers), `TOPIC_NAME`, and `REGISTRY_URL` (Schema Registry) from environment variables, with sensible defaults.
    *   Defines constants for `NUM_PARTITIONS` and `REPLICATION_FACTOR` for topic creation.
*   **Initialization:**
    *   Calls `createTopicIfNotExists` to ensure the target topic exists before producing.
*   **Producer Properties:**
    *   `BOOTSTRAP_SERVERS_CONFIG`: Kafka broker addresses.
    *   `KEY_SERIALIZER_CLASS_CONFIG`: `StringSerializer` for message keys.
    *   `VALUE_SERIALIZER_CLASS_CONFIG`: `io.confluent.kafka.serializers.KafkaAvroSerializer` for Avro-serializing message values. This serializer automatically registers schemas with the Schema Registry.
    *   `schema.registry.url`: URL of the Confluent Schema Registry.
    *   `basic.auth.credentials.source` & `basic.auth.user.info`: Configuration for basic authentication with Schema Registry.
    *   Retry and timeout configurations (`RETRIES_CONFIG`, `REQUEST_TIMEOUT_MS_CONFIG`, etc.) for resilience.
*   **Message Generation and Sending:**
    *   Enters an infinite loop to continuously produce messages.
    *   Uses `net.datafaker.Faker` to generate random data for each field of the `Order` object (order ID, bid time, price, item, supplier).
        * Note that *bid time* is delayed by an amount of seconds configured by an environment variable named `DELAY_SECONDS`, which is useful for testing late data handling.
    *   Creates a `ProducerRecord` with the topic name, order ID as key, and the `Order` object as value.
    *   Sends the record asynchronously using `producer.send()`.
        *   A callback logs success (topic, partition, offset) or logs errors.
        *   `.get()` is used to make the send synchronous for this example, simplifying error handling but reducing throughput in a real high-volume scenario.
    *   Handles `ExecutionException` and `KafkaException` during sending.
    *   Pauses for 1 second between sends using `Thread.sleep()`.

```kotlin
package me.jaehyeon

import me.jaehyeon.avro.Order
import me.jaehyeon.kafka.createTopicIfNotExists
import mu.KotlinLogging
import net.datafaker.Faker
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerConfig
import org.apache.kafka.clients.producer.ProducerRecord
import org.apache.kafka.common.KafkaException
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

object ProducerApp {
    private val bootstrapAddress = System.getenv("BOOTSTRAP") ?: "localhost:9092"
    private val inputTopicName = System.getenv("TOPIC_NAME") ?: "orders-avro"
    private val registryUrl = System.getenv("REGISTRY_URL") ?: "http://localhost:8081"
    private val delaySeconds = System.getenv("DELAY_SECONDS")?.toIntOrNull() ?: 5
    private const val NUM_PARTITIONS = 3
    private const val REPLICATION_FACTOR: Short = 3
    private val logger = KotlinLogging.logger {}
    private val faker = Faker()

    fun run() {
        // Create the input topic if not existing
        createTopicIfNotExists(inputTopicName, bootstrapAddress, NUM_PARTITIONS, REPLICATION_FACTOR)

        val props =
            Properties().apply {
                put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
                put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")
                put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "io.confluent.kafka.serializers.KafkaAvroSerializer")
                put("schema.registry.url", registryUrl)
                put("basic.auth.credentials.source", "USER_INFO")
                put("basic.auth.user.info", "admin:admin")
                put(ProducerConfig.RETRIES_CONFIG, "3")
                put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
                put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "6000")
                put(ProducerConfig.MAX_BLOCK_MS_CONFIG, "3000")
            }

        KafkaProducer<String, Order>(props).use { producer ->
            while (true) {
                val order =
                    Order().apply {
                        orderId = UUID.randomUUID().toString()
                        bidTime = generateBidTime()
                        price = faker.number().randomDouble(2, 1, 150)
                        item = faker.commerce().productName()
                        supplier = faker.regexify("(Alice|Bob|Carol|Alex|Joe|James|Jane|Jack)")
                    }
                val record = ProducerRecord(inputTopicName, order.orderId, order)
                try {
                    producer
                        .send(record) { metadata, exception ->
                            if (exception != null) {
                                logger.error(exception) { "Error sending record" }
                            } else {
                                logger.info {
                                    "Sent to ${metadata.topic()} into partition ${metadata.partition()}, offset ${metadata.offset()}"
                                }
                            }
                        }.get()
                } catch (e: ExecutionException) {
                    throw RuntimeException("Unrecoverable error while sending record.", e)
                } catch (e: KafkaException) {
                    throw RuntimeException("Kafka error while sending record.", e)
                }

                Thread.sleep(1000L)
            }
        }
    }

    private fun generateBidTime(): String {
        val randomDate = faker.date().past(delaySeconds, TimeUnit.SECONDS)
        val formatter =
            DateTimeFormatter
                .ofPattern("yyyy-MM-dd HH:mm:ss")
                .withZone(ZoneId.systemDefault())
        return formatter.format(randomDate.toInstant())
    }
}
```

### The Kafka Consumer

The `ConsumerApp` object consumes `Order` messages from Kafka, deserializes them, and processes them.

*   **Configuration:**
    *   Reads `BOOTSTRAP` (Kafka brokers), `TOPIC` (input topic), and `REGISTRY_URL` (Schema Registry) from environment variables, with defaults.
*   **Initialization:**
    *   Calls `verifyKafkaConnection` to check connectivity to Kafka brokers.
*   **Consumer Properties:**
    *   `BOOTSTRAP_SERVERS_CONFIG`: Kafka broker addresses.
    *   `GROUP_ID_CONFIG`: Consumer group ID, ensuring messages are distributed among instances of this consumer.
    *   `KEY_DESERIALIZER_CLASS_CONFIG`: `StringDeserializer` for message keys.
    *   `VALUE_DESERIALIZER_CLASS_CONFIG`: `io.confluent.kafka.serializers.KafkaAvroDeserializer` for deserializing Avro messages.
    *   `ENABLE_AUTO_COMMIT_CONFIG`: Set to `false` for manual offset management.
    *   `AUTO_OFFSET_RESET_CONFIG`: `earliest` to start consuming from the beginning of the topic if no offset is found.
    *   `specific.avro.reader`: Set to `false`, meaning the consumer will deserialize Avro messages into `GenericRecord` objects rather than specific generated Avro classes. This offers flexibility if the exact schema isn't compiled into the consumer.
    *   `schema.registry.url`: URL of the Confluent Schema Registry.
    *   `basic.auth.credentials.source` & `basic.auth.user.info`: Configuration for basic authentication with Schema Registry.
    *   Timeout configurations (`DEFAULT_API_TIMEOUT_MS_CONFIG`, `REQUEST_TIMEOUT_MS_CONFIG`).
*   **Graceful Shutdown:**
    *   A `ShutdownHook` is registered with `Runtime.getRuntime()`.
    *   When a shutdown signal (e.g., Ctrl+C) is received, `keepConsuming` is set to `false`, and `consumer.wakeup()` is called. This causes the `consumer.poll()` method to throw a `WakeupException`, allowing the consumer loop to terminate cleanly.
*   **Consuming Loop:**
    *   Subscribes to the specified topic.
    *   Enters a `while (keepConsuming)` loop.
    *   `pollSafely()`: A helper function that calls `consumer.poll()` and handles potential `WakeupException` (exiting loop if shutdown initiated) or other polling errors.
    *   Iterates through received records.
    *   `processRecordWithRetry()`:
        *   Processes each `GenericRecord`.
        *   Includes a retry mechanism (`MAX_RETRIES = 3`).
        *   Simulates processing errors using `(0..99).random() < ERROR_THRESHOLD` (currently `ERROR_THRESHOLD = -1`, so no errors are simulated by default).
        *   If an error occurs, it logs a warning and retries with an exponential backoff (`Thread.sleep(500L * attempt.toLong())`).
        *   If all retries fail, it logs an error and skips the record.
        *   Successfully processed records are logged.
    *   `consumer.commitSync()`: Manually commits offsets synchronously after a batch of records has been processed.
*   **Error Handling:**
    *   General `Exception` handling around the main consumer loop.

```kotlin
package me.jaehyeon

import me.jaehyeon.kafka.verifyKafkaConnection
import mu.KotlinLogging
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.common.errors.WakeupException
import java.time.Duration
import java.util.Properties
import kotlin.use

object ConsumerApp {
    private val bootstrapAddress = System.getenv("BOOTSTRAP") ?: "localhost:9092"
    private val topicName = System.getenv("TOPIC") ?: "orders-avro"
    private val registryUrl = System.getenv("REGISTRY_URL") ?: "http://localhost:8081"
    private val logger = KotlinLogging.logger { }
    private const val MAX_RETRIES = 3
    private const val ERROR_THRESHOLD = -1

    @Volatile
    private var keepConsuming = true

    fun run() {
        // Verify kafka connection
        verifyKafkaConnection(bootstrapAddress)

        val props =
            Properties().apply {
                put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
                put(ConsumerConfig.GROUP_ID_CONFIG, "$topicName-group")
                put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer")
                put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "io.confluent.kafka.serializers.KafkaAvroDeserializer")
                put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false)
                put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest")
                put("specific.avro.reader", false)
                put("schema.registry.url", registryUrl)
                put("basic.auth.credentials.source", "USER_INFO")
                put("basic.auth.user.info", "admin:admin")
                put(ConsumerConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, "5000")
                put(ConsumerConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
            }

        val consumer = KafkaConsumer<String, GenericRecord>(props)

        Runtime.getRuntime().addShutdownHook(
            Thread {
                logger.info { "Shutdown detected. Waking up Kafka consumer..." }
                keepConsuming = false
                consumer.wakeup()
            },
        )

        try {
            consumer.use { c ->
                c.subscribe(listOf(topicName))
                while (keepConsuming) {
                    val records = pollSafely(c)
                    for (record in records) {
                        processRecordWithRetry(record)
                    }
                    consumer.commitSync()
                }
            }
        } catch (e: Exception) {
            RuntimeException("Unrecoverable error while consuming record.", e)
        }
    }

    private fun pollSafely(consumer: KafkaConsumer<String, GenericRecord>) =
        runCatching { consumer.poll(Duration.ofMillis(1000)) }
            .getOrElse { e ->
                when (e) {
                    is WakeupException -> {
                        if (keepConsuming) throw e
                        logger.info { "ConsumerApp wakeup for shutdown." }
                        emptyList()
                    }
                    else -> {
                        logger.error(e) { "Unexpected error while polling records" }
                        emptyList()
                    }
                }
            }

    private fun processRecordWithRetry(record: ConsumerRecord<String, GenericRecord>) {
        var attempt = 0
        while (attempt < MAX_RETRIES) {
            try {
                attempt++
                if ((0..99).random() < ERROR_THRESHOLD) {
                    throw RuntimeException(
                        "Simulated error for ${record.value()} from partition ${record.partition()}, offset ${record.offset()}",
                    )
                }
                logger.info { "Received ${record.value()} from partition ${record.partition()}, offset ${record.offset()}" }
                return
            } catch (e: Exception) {
                logger.warn(e) { "Error processing record (attempt $attempt of $MAX_RETRIES)" }
                if (attempt == MAX_RETRIES) {
                    logger.error(e) { "Failed to process record after $MAX_RETRIES attempts, skipping..." }
                    return
                }
                Thread.sleep(500L * attempt.toLong()) // exponential backoff
            }
        }
    }
}
```

### The Application Entry Point

The `Main.kt` file contains the `main` function, which serves as the entry point for the packaged application.

*   It checks the first command-line argument (`args.getOrNull(0)`).
*   If the argument is `"producer"` (case-insensitive), it runs `ProducerApp.run()`.
*   If the argument is `"consumer"` (case-insensitive), it runs `ConsumerApp.run()`.
*   If no argument or an invalid argument is provided, it prints usage instructions.
*   A top-level `try-catch` block handles any uncaught exceptions from the producer or consumer, logs a fatal error, and exits the application with a non-zero status code (`exitProcess(1)`).

```kotlin
package me.jaehyeon

import mu.KotlinLogging
import kotlin.system.exitProcess

private val logger = KotlinLogging.logger {}

fun main(args: Array<String>) {
    try {
        when (args.getOrNull(0)?.lowercase()) {
            "producer" -> ProducerApp.run()
            "consumer" -> ConsumerApp.run()
            else -> println("Usage: <producer|consumer>")
        }
    } catch (e: Exception) {
        logger.error(e) { "Fatal error in ${args.getOrNull(0) ?: "app"}. Shutting down." }
        exitProcess(1)
    }
}
```

## Run Kafka Applications

We begin by setting up our local Kafka environment using the [Factor House Local](https://github.com/factorhouse/factorhouse-local) project. This project conveniently provisions a Kafka cluster along with Kpow, a powerful tool for Kafka management and control, all managed via Docker Compose. Once our Kafka environment is running, we will start our Kotlin-based producer and consumer applications.

### Factor House Local

To get our Kafka cluster and Kpow up and running, we'll first need to clone the project repository and navigate into its directory. Then, we can start the services using Docker Compose as shown below. **Note that we need to have a community license for Kpow to get started.** See [this section](https://github.com/factorhouse/factorhouse-local?tab=readme-ov-file#update-kpow-and-flex-licenses) of the project *README* for details on how to request a license and configure it before proceeding with the `docker compose` command.

```bash
git clone https://github.com/factorhouse/factorhouse-local.git
cd factorhouse-local
docker compose -f compose-kpow-community.yml up -d
```

Once the services are initialized, we can access the Kpow user interface by navigating to `http://localhost:3000` in the web browser, where we observe the provisioned environment, including three Kafka brokers, one schema registry, and one Kafka Connect instance.

![](kpow-overview.png#center)

### Launch Applications

Our Kotlin Kafka applications can be launched in a couple of ways, catering to different stages of development and deployment:

1. **With Gradle (Development Mode)**: This method is convenient during development, allowing for quick iterations without needing to build a full JAR file each time.
2. **Running the Shadow JAR (Deployment Mode)**: After building a "fat" JAR (also known as a shadow JAR) that includes all dependencies, the application can be run as a standalone executable. This is typical for deploying to non-development environments.

> 💡 To build and run the application locally, ensure that **JDK 17** and **Gradle 7.0+** are installed.

```bash
# 👉 With Gradle (Dev Mode)
./gradlew run --args="producer"
./gradlew run --args="consumer"

# 👉 Build Shadow (Fat) JAR:
./gradlew shadowJar

# Resulting JAR:
# build/libs/orders-avro-clients-1.0.jar

# 👉 Run the Fat JAR:
java -jar build/libs/orders-avro-clients-1.0.jar producer
java -jar build/libs/orders-avro-clients-1.0.jar consumer
```

For this post, we demonstrate starting the applications in development mode using Gradle. Once started, we see logs from both the producer sending messages and the consumer receiving them.

![](kafka-avro-apps.gif#center)

Within the Kpow interface, we can check that a new schema, `orders-avro-value`, is now registered with the *Local Schema Registry*.

![](schema-registry.png#center)

With the applications actively producing and consuming Avro data, Kpow enables inspection of messages on the `orders-avro` topic. In the Kpow UI, navigate to this topic. To correctly view the Avro messages, configure the deserialization settings as follows: set the **Key Deserializer** to *String*, choose *AVRO* for the **Value Deserializer**, and ensure the **Schema Registry** selection is set to *Local Schema Registry*. After applying these configurations, click the Search button to display the messages.

![](message-view-01.png#center)
![](message-view-02.png#center)

## Conclusion

In this post, we successfully built robust Kafka producer and consumer applications in Kotlin, using Avro for schema-enforced data serialization and Gradle for an efficient build process. We demonstrated practical deployment with a local Kafka setup via the *Factor House Local* project with Kpow, showcasing a complete workflow for developing type-safe, resilient data pipelines with Kafka and a Schema Registry.
