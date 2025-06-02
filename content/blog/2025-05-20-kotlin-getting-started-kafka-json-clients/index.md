---
title: Kafka Clients with JSON - Producing and Consuming Order Events
date: 2025-05-20
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

This post explores a Kotlin-based Kafka project, meticulously detailing the construction and operation of both a Kafka producer application, responsible for generating and sending order data, and a Kafka consumer application, designed to receive and process these orders. We'll delve into each component, from build configuration to message handling, to understand how they work together in an event-driven system.

<!--more-->

* [Kafka Clients with JSON - Producing and Consuming Order Events](#) (this post)
* [Kafka Clients with Avro - Schema Registry and Order Events](/blog/2025-05-27-kotlin-getting-started-kafka-avro-clients)
* [Kafka Streams - Lightweight Real-Time Processing for Supplier Stats](/blog/2025-06-03-kotlin-getting-started-kafka-streams)
* Flink DataStream API - Scalable Event Processing for Supplier Stats
* Flink Table API - Declarative Analytics for Supplier Stats in Real Time

## Kafka Client Applications

We will build producer and consumer apps using the [IntelliJ IDEA Community](https://www.jetbrains.com/idea/download/?section=windows) edition. The source code for the applications discussed in this post can be found in the _orders-json-clients_ folder of this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/kotlin-examples). This project demonstrates a practical approach to developing event-driven systems with Kafka and Kotlin. Below, we'll explore the key components that make up these applications.

### Build Configuration

The `build.gradle.kts` file is the cornerstone of our project, defining how the Kotlin Kafka application is built and packaged using Gradle with its Kotlin DSL. It orchestrates several key aspects:

*   **Plugins:**
    *   `kotlin("jvm")`: Provides essential support for compiling Kotlin code for the Java Virtual Machine.
    *   `com.github.johnrengelman.shadow`: Creates a "fat JAR" (or "uber JAR"), bundling the application and all its dependencies into a single, easily deployable executable file.
    *   `application`: Configures the project as a runnable application, specifying its main entry point.
*   **Dependencies:**
    *   `org.apache.kafka:kafka-clients`: The official Kafka client library for interacting with Kafka brokers.
    *   `com.fasterxml.jackson.module:jackson-module-kotlin`: Enables seamless JSON serialization and deserialization for Kotlin data classes using the Jackson library.
    *   `io.github.microutils:kotlin-logging-jvm` & `ch.qos.logback:logback-classic`: A combination for flexible and robust logging capabilities.
    *   `net.datafaker:datafaker`: Used to generate realistic mock data for the `Order` objects.
    *   `kotlin("test")`: Supports writing unit tests for the application.
*   **Key Configurations:**
    *   Specifies Java 17 as the target JVM via `jvmToolchain(17)`.
    *   Sets `me.jaehyeon.MainKt` as the `mainClass` for execution.
    *   The `shadowJar` task is configured to name the output artifact `orders-json-clients-1.0.jar` and to correctly merge service files from dependencies.

```kotlin
plugins {
    kotlin("jvm") version "2.1.20"
    id("com.github.johnrengelman.shadow") version "8.1.1"
    application
}

group = "me.jaehyeon"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    // Kafka
    implementation("org.apache.kafka:kafka-clients:3.9.0")
    // JSON (using Jackson)
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.0")
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

tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    archiveBaseName.set("orders-json-clients")
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

### Data Model

At the heart of the messages exchanged is the `me.jaehyeon.model.Order` data class. This Kotlin data class concisely defines the structure of an "order" event. It includes fields like `orderId` (a unique string), `bidTime` (a string timestamp), `price` (a double), `item` (a string for the product name), and `supplier` (a string). Importantly, all properties are declared with default values (e.g., `""` for strings, `0.0` for doubles). This design choice is crucial for JSON deserialization libraries like Jackson, which often require a no-argument constructor to instantiate objects, a feature Kotlin data classes don't automatically provide if all properties are constructor parameters without defaults.

```kotlin
package me.jaehyeon.model

// Java classes usually have a default constructor automatically, but not Kotlin data classes.
// Jackson expects a default way to instantiate objects unless you give it detailed instructions.
data class Order(
    val orderId: String = "",
    val bidTime: String = "",
    val price: Double = 0.0,
    val item: String = "",
    val supplier: String = "",
)
```

### Custom JSON (De)Serializers

To convert our Kotlin `Order` objects into byte arrays for Kafka transmission and vice-versa, the `me.jaehyeon.serializer` package provides custom implementations.

The `JsonSerializer<T>` class implements Kafka's `Serializer<T>` interface. It uses Jackson's `ObjectMapper` to transform any given object `T` into a JSON byte array. This `ObjectMapper` is specifically configured with `PropertyNamingStrategies.SNAKE_CASE`, ensuring that Kotlin's camelCase property names (e.g., `orderId`) are serialized as snake_case (e.g., `order_id`) in the JSON output.

Complementing this, the `JsonDeserializer<T>` class implements Kafka's `Deserializer<T>` interface. It takes a `targetClass` (such as `Order::class.java`) during its instantiation and uses a similarly configured `ObjectMapper` (also with `SNAKE_CASE` strategy) to convert incoming JSON byte arrays back into objects of that specified type.

**JsonSerializer.kt**

```kotlin
package me.jaehyeon.serializer

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.PropertyNamingStrategies
import org.apache.kafka.common.serialization.Serializer

class JsonSerializer<T> : Serializer<T> {
    private val objectMapper =
        ObjectMapper()
            .setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)

    override fun serialize(
        topic: String?,
        data: T?,
    ): ByteArray? = data?.let { objectMapper.writeValueAsBytes(it) }
}
```

**JsonDeserializer.kt**

```kotlin
package me.jaehyeon.serializer

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.PropertyNamingStrategies
import org.apache.kafka.common.serialization.Deserializer

class JsonDeserializer<T>(
    private val targetClass: Class<T>,
) : Deserializer<T> {
    private val objectMapper =
        ObjectMapper()
            .setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)

    override fun deserialize(
        topic: String?,
        data: ByteArray?,
    ): T? = data?.let { objectMapper.readValue(it, targetClass) }
}
```

### Kafka Admin Utilities

The `me.jaehyeon.kafka` package houses utility functions for administrative Kafka tasks, primarily topic creation and connection verification.

The `createTopicIfNotExists` function proactively ensures that the target Kafka topic (e.g., "orders-json") is available before the application attempts to use it. It uses Kafka's `AdminClient`, configured with the bootstrap server address and appropriate timeouts, to attempt topic creation with a specified number of partitions and replication factor. A key feature is its ability to gracefully handle `TopicExistsException`, allowing the application to continue smoothly if the topic already exists or was created concurrently.

The `verifyKafkaConnection` function serves as a quick pre-flight check, especially for the consumer. It also employs an `AdminClient` to try listing topics on the cluster. If this fails, it throws a `RuntimeException`, signaling a connectivity issue with the Kafka brokers and preventing the application from starting in a potentially faulty state.

```kotlin
package me.jaehyeon.kafka

import mu.KotlinLogging
import org.apache.kafka.clients.admin.AdminClient
import org.apache.kafka.clients.admin.AdminClientConfig
import org.apache.kafka.clients.admin.NewTopic
import org.apache.kafka.common.errors.TopicExistsException
import java.util.Properties
import java.util.concurrent.ExecutionException

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

### Kafka Producer

The `me.jaehyeon.ProducerApp` object is responsible for generating `Order` messages and publishing them to a Kafka topic. Its operations include:

*   **Configuration:**
    *   Reads the Kafka `BOOTSTRAP_ADDRESS` and target `TOPIC_NAME` (defaulting to "orders-json") from environment variables, allowing for flexible deployment.
    *   Defines constants like `NUM_PARTITIONS` and `REPLICATION_FACTOR` for topic creation if needed.
*   **Initialization (`run` method):**
    *   First, it calls `createTopicIfNotExists` (from the admin utilities) to ensure the output topic is ready.
    *   It then configures and instantiates a `KafkaProducer`, setting properties like bootstrap servers, using `StringSerializer` for message keys, and our custom `JsonSerializer` for the `Order` object values.
    *   Retry mechanisms and timeout settings (`REQUEST_TIMEOUT_MS_CONFIG`, `DELIVERY_TIMEOUT_MS_CONFIG`, `MAX_BLOCK_MS_CONFIG`) are configured for enhanced robustness.
*   **Message Production Loop:**
    *   Continuously generates new `Order` objects using `Datafaker` for random yet plausible data. This includes generating a UUID for `orderId` and a formatted recent timestamp via `generateBidTime()`.
        *   Note that `bidTime` is delayed by an amount of seconds configured by an environment variable named `DELAY_SECONDS`, which is useful for testing late data handling.
    *   Wraps each `Order` in a `ProducerRecord`, using the `orderId` as the message key.
    *   Sends the record using `producer.send()`. The call to `.get()` on the returned `Future` makes this send operation synchronous for this example, waiting for acknowledgment. A callback logs success (topic, partition, offset) or any exceptions.
    *   Pauses for one second between messages to simulate a steady event stream.
*   **Error Handling:** Includes `try-catch` blocks to handle potential `ExecutionException` or `KafkaException` during the send process.

```kotlin
package me.jaehyeon

import me.jaehyeon.kafka.createTopicIfNotExists
import me.jaehyeon.model.Order
import me.jaehyeon.serializer.JsonSerializer
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
    private val bootstrapAddress = System.getenv("BOOTSTRAP_ADDRESS") ?: "localhost:9092"
    private val inputTopicName = System.getenv("TOPIC_NAME") ?: "orders-json"
    private val delaySeconds = System.getenv("DELAY_SECONDS")?.toIntOrNull() ?: 5
    private const val NUM_PARTITIONS = 3
    private const val REPLICATION_FACTOR: Short = 3
    private val logger = KotlinLogging.logger { }
    private val faker = Faker()

    fun run() {
        // Create the input topic if not existing
        createTopicIfNotExists(inputTopicName, bootstrapAddress, NUM_PARTITIONS, REPLICATION_FACTOR)

        val props =
            Properties().apply {
                put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapAddress)
                put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer")
                put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer::class.java.name)
                put(ProducerConfig.RETRIES_CONFIG, "3")
                put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
                put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "6000")
                put(ProducerConfig.MAX_BLOCK_MS_CONFIG, "3000")
            }

        KafkaProducer<String, Order>(props).use { producer ->
            while (true) {
                val order =
                    Order(
                        UUID.randomUUID().toString(),
                        generateBidTime(),
                        faker.number().randomDouble(2, 1, 150),
                        faker.commerce().productName(),
                        faker.regexify("(Alice|Bob|Carol|Alex|Joe|James|Jane|Jack)"),
                    )
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

### Kafka Consumer

The `me.jaehyeon.ConsumerApp` object is designed to subscribe to the Kafka topic, fetch the `Order` messages, and process them. Its key functionalities are:

*   **Configuration:**
    *   Retrieves `BOOTSTRAP_ADDRESS` and `TOPIC_NAME` from environment variables.
*   **Initialization (`run` method):**
    *   Begins by calling `verifyKafkaConnection` (from admin utilities) to check Kafka cluster accessibility.
    *   Configures and creates a `KafkaConsumer`. Essential properties include `GROUP_ID_CONFIG` (e.g., "orders-json-group" for consumer group coordination), `StringDeserializer` for keys, and an instance of our custom `JsonDeserializer(Order::class.java)` for message values.
    *   Disables auto-commit (`ENABLE_AUTO_COMMIT_CONFIG = false`) for manual offset control and sets `AUTO_OFFSET_RESET_CONFIG = "earliest"` to start reading from the beginning of the topic for new consumer groups.
*   **Graceful Shutdown:**
    *   A `Runtime.getRuntime().addShutdownHook` is registered. On a shutdown signal (e.g., Ctrl+C), it sets a `keepConsuming` flag to `false` and calls `consumer.wakeup()`. This action causes `consumer.poll()` to throw a `WakeupException`, allowing the consumption loop to terminate cleanly.
*   **Message Consumption Loop:**
    *   The consumer subscribes to the specified topic.
    *   In a `while (keepConsuming)` loop:
        *   `pollSafely()` is called to fetch records. This wrapper robustly handles `WakeupException` for shutdown and logs other polling errors.
        *   Each received `ConsumerRecord` is processed by `processRecordWithRetry()`. This method logs the `Order` details and includes a retry mechanism for simulated errors (currently, `ERROR_THRESHOLD` is set to -1, disabling simulated errors). If an error occurs, it retries up to `MAX_RETRIES` with exponential backoff. If all retries fail, the error is logged, and the message is skipped.
        *   After processing a batch, `consumer.commitSync()` is called to manually commit offsets.
*   **Error Handling:** A general `try-catch` block surrounds the main consumption logic for unrecoverable errors.

```kotlin
package me.jaehyeon

import me.jaehyeon.kafka.verifyKafkaConnection
import me.jaehyeon.model.Order
import me.jaehyeon.serializer.JsonDeserializer
import mu.KotlinLogging
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.common.errors.WakeupException
import org.apache.kafka.common.serialization.StringDeserializer
import java.time.Duration
import java.util.Properties

object ConsumerApp {
    private val bootstrapAddress = System.getenv("BOOTSTRAP_ADDRESS") ?: "localhost:9092"
    private val topicName = System.getenv("TOPIC_NAME") ?: "orders-json"
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
                put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, Order::class.java.name)
                put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false)
                put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest")
                put(ConsumerConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, "5000")
                put(ConsumerConfig.REQUEST_TIMEOUT_MS_CONFIG, "3000")
            }

        val consumer =
            KafkaConsumer<String, Order>(
                props,
                StringDeserializer(),
                JsonDeserializer(Order::class.java),
            )

        Runtime.getRuntime().addShutdownHook(
            Thread {
                logger.info("Shutdown detected. Waking up Kafka consumer...")
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

    private fun pollSafely(consumer: KafkaConsumer<String, Order>) =
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

    private fun processRecordWithRetry(record: ConsumerRecord<String, Order>) {
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

### Application Entry Point

The `me.jaehyeon.MainKt` file provides the `main` function, serving as the application's command-line dispatcher. It examines the first command-line argument (`args.getOrNull(0)`). If it's "producer" (case-insensitive), `ProducerApp.run()` is executed. If it's "consumer", `ConsumerApp.run()` is called. For any other input, or if no argument is provided, it prints a usage message. The entire logic is enclosed in a `try-catch` block to capture and log any fatal unhandled exceptions, ensuring the application exits with an error code (`exitProcess(1)`) if such an event occurs.

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
# build/libs/orders-json-clients-1.0.jar

# 👉 Run the Fat JAR:
java -jar build/libs/orders-json-clients-1.0.jar producer
java -jar build/libs/orders-json-clients-1.0.jar consumer
```

For this post, we demonstrate starting the applications in development mode using Gradle. Once started, we see logs from both the producer sending messages and the consumer receiving them.

![](kafka-json-apps.gif#center)

With the applications running and producing/consuming data, we can inspect the messages flowing through our `orders-json` topic using Kpow. In the Kpow UI, navigate to your topic. To correctly view the messages, we should configure the deserializers: set the **Key Deserializer** to *String* and the **Value Deserializer** to *JSON*. After applying these settings, click the *Search* button to view the messages.

![](message-view-01.png#center)
![](message-view-02.png#center)

## Conclusion

This post detailed the creation of Kotlin Kafka producer and consumer applications for handling JSON order data. We covered project setup, data modeling, custom serialization, client logic with error handling, deployment against a local Kafka cluster using the *Factor House Local* project with *Kpow*.
