---
title: "Building a Real-Time Recommender: Contextual Bandits & Event-Driven Architecture"
date: 2026-03-21
# Choose theme: black, white, league, beige, night, solarized, dracula
reveal_theme: "black" 
layout: "single"
description: "A walkthrough of building and scaling a Contextual Multi-Armed Bandit recommender system."
---

<style>
  /* Global text sizing for this presentation */
  .reveal p, .reveal li {
    font-size: 0.8em;
    line-height: 1.4;
  }
  .reveal ul ul li {
    font-size: 0.9em;
  }

  #eda-slide ul, #eda-slide li, #eda-slide p {
    margin-top: 0 !important;
    margin-bottom: 0 !important;
    padding-top: 0 !important;
    padding-bottom: 0 !important;
  }

  #eda-slide ul { 
    padding-left: 0.8em !important; /* Move bullets closer to the left edge */
    margin-left: 0 !important; 
  }
  #eda-slide ul ul { 
    padding-left: 0.9em !important; /* Narrower nested indent */
  }

  #eda-slide .mjx-container { 
    margin: 0 !important; 
    padding: 0 !important; 
    display: inline-block !important; /* Prevents block-level "push" */
  }
</style>

## Building a Real-Time Product Recommender

Contextual Bandits & Event-Driven Architecture

---

## Why Contextual Bandits?

- **Problem:** Conventional recommenders (e.g., Collaborative Filtering)
  - Ignore situational context (e.g., Time of Day, Location, Device).
  - Struggle with "Cold Starts" for new items/users.
- **Solution:** Contextual Multi-Armed Bandits (CMAB).
  - **Exploitation:** Maximize immediate reward using current knowledge.
  - **Exploration:** Gather information on uncertain items to improve future performance.

[Part 1: Prototype](#prototype) | [Part 2: Productionization](#production)

---

<!-- .slide: id="prototype" -->
## Part 1: Prototype

Prototype an online product recommender with Python

--

## Python Ecosystem

- [Vowpal Wabbit](https://vowpalwabbit.org/) <!-- .element: target="_blank" --> and [River ML](https://riverml.xyz/latest/) <!-- .element: target="_blank" --> are well-known for CMAB.
  - *Gap:* Lack of end-to-end examples integrating feature engineering and offline policy evaluation.
- [Fidelity Investments Open Source](https://github.com/fidelity) <!-- .element: target="_blank" -->
  - **MABWiser:** Algorithm implementation.
  - **Mab2Rec:** Offline policy evaluation.
  - **TextWiser:** Text featurization.

--

## Prototyping Workflow

From synthetic data generation to live simulation.

<img src="prototype.gif" alt="Workflow Diagram" style="max-height: 42vh; max-width: 100%; margin: 0 auto; display: block;">

--

## Live Demo & Walkthrough

Let's dive into the code.

--

## Offline Policy Evaluation

| Model | AUC(score)@5 | CTR(score)@5 | Precision@5 | Recall@5 |
| :--- | :--- | :--- | :--- | :--- |
| Random | 0.550 | 0.102 | 0.003 | 0.019 |
| Popularity | 0.592 | 0.192 | 0.007 | 0.038 |
| LinGreedy | **0.885** | 0.117 | 0.004 | 0.023 |
| **🏆 LinUCB** | 0.860 | **0.204** | 0.006 | 0.034 |
| LinTS | 0.640 | 0.211 | **0.008** | **0.042** |
| ClustersTS | 0.550 | 0.153 | 0.004 | 0.023 |
<!-- .element: style="font-size: 0.5em; line-height: 1.2; width: 100%;" -->

<div style="text-align: left;">

Why LinUCB?

- **Best Trade-off:** High Ranking (AUC) + High Engagement (CTR).
- **Beats LinGreedy:** Explores effectively (CTR 0.20 vs 0.11).
- **Beats LinTS:** Ranks accurately (AUC 0.86 vs 0.64).

</div>

--

## LinUCB Algorithm

Balancing Exploitation and Exploration

$$ \text{Score}_a = \color{cyan}{x^T \theta_a} + \color{orange}{\alpha \sqrt{x^T A_a^{-1} x}} \color{white}{, \quad \text{where } \theta_a = A_a^{-1} b_a} $$

<div style="margin-top: 20px; font-size: 0.8em;">

- <span style="color: cyan;">●</span> **Exploitation:** Predicted reward ($x^T \theta_a$).
- <span style="color: orange;">●</span> **Exploration:** Uncertainty bonus (UCB).
- **$\theta_a = A_a^{-1} b_a$**: **Model weights** estimated via Ridge Regression.

</div>

--

## Limitations

A monolithic Python script isn't built for scale.

- **Latency:** Training blocks inference.
- **Scalability:** Matrix math in memory limits the catalog size.
- **Fault Tolerance:** If the script crashes, the learned state is lost.

[Back to Start](#/) | **[Jump to Productionization](#production)**

---

<!-- .slide: id="production" -->
## Part 2: Productionization

Scaling with an Event-Driven Architecture

--

<!-- .slide: id="eda-slide" -->
## Architecture
### Serving (Python & Redis)

<div style="display: grid; grid-template-columns: 42% 58%; gap: 10px; align-items: center; width: 106%; margin-left: -3%;">
  <!-- Left Column: Centered block, left-aligned text -->
  <div style="display: flex; justify-content: center;">
    <div style="text-align: left; font-size: 0.9em; line-height: 1.2;">

- **Stateless Inference:**
  - The client does *not* train. 
- **Low Latency:**
  - Fetches pre-computed LinUCB parameters from Redis.
- **Action:** 
  - Calculates scores,
  - Ranks items, and 
  - Sends feedback to Kafka.
    </div>
  </div>

  <!-- Right Column -->
  <div>
    <img src="featured.gif" style="width: 100%; max-height: 60vh; object-fit: contain; border: 2px solid #555; border-radius: 8px; display: block;">
  </div>
</div>

--

<!-- .slide: id="eda-slide" -->
## Architecture
### Transport (Apache Kafka)

<div style="display: grid; grid-template-columns: 42% 58%; gap: 10px; align-items: center; width: 106%; margin-left: -3%;">
  <div style="display: flex; justify-content: center;">
    <div style="text-align: left; font-size: 0.8em; line-height: 1.2;">

- **Asynchronous Buffer:**
  - Decouples user-facing app speed from backend training.
- **Durability:** 
  - Stores "Ground Truth" events safely for replay or analytics.
    </div>
  </div>

  <div>
    <img src="featured.gif" style="width: 100%; max-height: 60vh; object-fit: contain; border: 2px solid #555; border-radius: 8px; display: block;">
  </div>
</div>

--

<!-- .slide: id="eda-slide" -->
## Architecture
### Training (Apache Flink)

<!-- Math Section: Negative margin pulls the grid up to fit everything -->
<div style="font-size: 0.55em; margin-bottom: -20px !important; text-align: center; position: relative; z-index: 10;">
$$ \text{Score}_a = \color{cyan}{x^T \theta_a} + \color{orange}{\alpha \sqrt{x^T A_a^{-1} x}}, \quad \text{where } \theta_a = A_a^{-1} b_a $$
</div>

<div style="display: grid; grid-template-columns: 42% 58%; gap: 10px; align-items: center; width: 106%; margin-left: -3%;">
  <div style="display: flex; justify-content: center;">
    <div style="text-align: left; font-size: 0.75em; line-height: 1.1;">

- **Stateful Processing:**
  - Flink acts as "Online Memory".
- **Asynchronous Updates:** 
  - **Fast Path:** Updates $A$ and $b$.
    - ($A \leftarrow A + x x^T, b \leftarrow b + r x$)
  - **Slow Path:** Every 5s, computes $A^{-1}$.
- **Sync to Redis:** Emits $A^{-1}$ and $b$.
    </div>
  </div>

  <div style="text-align: center;">
    <img src="featured.gif" style="width: 100%; max-height: 52vh; object-fit: contain; border: 2px solid #555; border-radius: 8px; display: block;">
  </div>
</div>

--

## Live Demo & Walkthrough

Let's dive into the code.

[Back to Start](#/) | **[Jump to Takeaways](#takeaways)**

---

<!-- .slide: id="takeaways" -->
## Key Takeaways

Bridging the gap between Data Science and Data Engineering.

--

## Start Small, Evaluate Offline

- Before touching infrastructure, **evaluate policies**. 
- Using tools like *MABWiser* and *Mab2Rec* allows you to simulate user behavior and validate algorithms on historical data safely.

--

## Decouple to Scale

- A monolithic architecture forces a trade-off between model accuracy and user latency.
- **Event-Driven Architecture (EDA)** solves this by separating high-speed inference (Redis) from heavy stateful training (Flink).

--

## Real-Time Adaptability

- By integrating Kafka and Flink, the system learns from user behavior *instantly*.
  - **Dynamic Personalization:** Optimizes for specific real-time user context with every click.
  - **Continuous Learning:** Eliminates the "Cold Start" problem for new items without batch-job downtime.

---

# Thank You!

<div style="text-align: left;">

**Code & Resources:**

- [GitHub Repository](https://github.com/jaehyeon-kim/streaming-demos/tree/main/product-recommender) <!-- .element: target="_blank" -->
- Blog Posts: [Part 1: Prototype](https://jaehyeon.me/blog/2026-01-29-prototype-recommender-with-python/) <!-- .element: target="_blank" --> | [Part 2: Productionization](https://jaehyeon.me/blog/2026-02-23-productionize-recommender-with-eda/) <!-- .element: target="_blank" -->
- [Youtube Playlist](https://youtube.com/playlist?list=PLrISYKWzp0eTTAbkhahnuyLOBlesOY5vN&si=ML-G-oYqJaMD9fnY) <!-- .element: target="_blank" -->
</div>

[Back to Start](#/)
