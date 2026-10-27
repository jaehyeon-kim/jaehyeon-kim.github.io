---
title: "From dynamic-des to desflow: What Changed in Five Releases"
date: 2026-10-28
draft: false
featured: true
comment: true
toc: true
series:
  - Building Real-Time Digital Twins with desflow
categories:
  - Data Engineering
  - Open Source
tags:
  - Discrete Event Simulation
  - desflow
  - SimPy
  - YAML
  - Queueing Theory
  - Python
description: |
  dynamic-des is now desflow. A simulation of a small shop shows what five releases added: customers who give up waiting and machines that break, a check that a model makes sense before it runs, and an answer to a question such as "would a third packer cut the wait?" that accounts for chance.
---

A simulation is a small model of a real system that a computer plays forward in time. Take a shop that packs orders. Orders arrive at random moments, packers take one at a time, and packing takes longer for some orders than for others. When orders arrive faster than the packers can finish them, a queue forms. A simulation shows how long that queue gets and how long orders wait, without running the real shop.

The [last post](/blog/2026-10-06-simulations-in-yaml-dynamic-des/) in this series showed such a model written as a YAML file and run with one command, with dynamic-des 0.16.0 to 0.19.0. The package is now called desflow. It still sends its events to Kafka, Redis, PostgreSQL, Parquet and Iceberg, and it can now also answer the question a simulation is usually built for, such as "would a third packer keep the wait under 2 seconds?". Everything below runs on your own machine, without Docker.

<!--more-->

This post covers what is new since dynamic-des 0.19.0:

- **[A new name](#a-new-name):** why dynamic-des is now desflow, and what to change.
- **[More of a real system](#modelling-more-of-a-real-system):** customers who give up waiting, machines that break, and every feature of SimPy in YAML.
- **[Numbers you can trust](#trusting-the-numbers):** repeated runs, experiments that compare two versions of a model, and inputs fitted to measured times.
- **[A check before running](#checking-a-model-before-running-it):** 0.25.0 shows whether a model makes sense before it runs.
- **[Help with writing a model](#help-with-writing-a-model):** an editor suggests each setting as you type.

## A New Name

dynamic-des became [desflow](https://github.com/jaehyeon-kim/desflow) in 0.20.0. The new name reflects a wider scope: from sending simulated events to whole simulation studies, with a server to run them next. [Why desflow](https://jaehyeon.me/desflow/latest/about/why-desflow/) explains the name. Only the names changed in that release:

```bash
pip install desflow                     # was: pip install dynamic-des
python -c "import desflow"              # was: import dynamic_des
desflow --version                       # was: ddes --version
```

The old names still work, with a warning, until 0.30.0. The documentation moved to [jaehyeon.me/desflow](https://jaehyeon.me/desflow/). Later releases changed some behaviour as well. If you upgrade a model from dynamic-des, the Upgrading section of each release in the [Changelog](https://jaehyeon.me/desflow/latest/about/changelog/) lists what to change.

## Modelling More of a Real System

A real shop has more going on than orders, packers and a packing time: customers give up when the queue is long, machines break, and some work needs two people at once. desflow runs on [SimPy](https://simpy.readthedocs.io/), the standard Python library for this kind of simulation, so a model written in Python could always build these by hand. Since 0.22.0, a model declares each of them in a few lines of YAML or builder code, with no SimPy code to write.

Customers who give up take two settings. In this excerpt of the `patience` example, each order waits at most a set number of seconds before it leaves, and after 100 seconds the shop takes no new orders:

```yaml
arrivals:
  orders: {dist: exponential, rate: 0.5, spawn: pack, attributes: {patience: 20}}
  walk_ins: {dist: exponential, rate: 0.1, spawn: pack, attributes: {patience: 10}}

tasks:
  pack:
    service: packing
    resource: packers
    patience: attr.patience    # leave after waiting this long
    balk: t >= 100             # turn new orders away from 100 seconds
```

desflow records each order that gives up and each one turned away, as events and as counts.

A machine that breaks takes one more block. In the `breakdowns` example, a packing station fails about once a minute and takes 5 to 15 seconds to repair. The order it was packing waits and then carries on:

```yaml
resources:
  station:
    current_cap: 2
    max_cap: 3
    breakdown:
      time_to_failure: {dist: exponential, rate: 0.0167}   # about once a minute
      repair: {dist: uniform, low: 5 s, high: 15 s}
      work: interrupt

tasks:
  pack:
    service: packing
    resource: station
    on_interrupt: resume
```

Each failure and each repair is recorded as an event. That record is useful beyond the simulation: it is the known answer that a fault detection model can be trained and tested against.

Releases 0.21.0 to 0.23.0 also add:

- more ways to describe a time that varies, and durations such as `5 min` anywhere a time is set;
- stock that tasks take from and add to, such as parcels on a shelf;
- orders that go through several steps, where the next step depends on the order;
- work that interrupts other work, such as an urgent order;
- ways to end a run, such as closing the shop and finishing the orders already inside;
- replaying the arrival times of a real day from a file.

Since 0.23.0, a model can use every feature of SimPy 4.1.2 in YAML as well as in Python. The [SimPy Compatibility](https://jaehyeon.me/desflow/latest/reference/simpy-compatibility/) page lists each feature with the test that checks it against SimPy.

## Trusting the Numbers

A simulation draws its arrival and packing times at random, so two runs give different answers. One run might show a short wait by luck. To trust a result, run the model many times and look at the range the answers fall in. Releases 0.21.0 and 0.22.0 add the tools for this:

- **Statistics:** each run measures waits, queue lengths and how busy each resource was. The first minutes can be left out, because the shop starts empty and would make the wait look shorter.
- **Repeated runs:** `desflow run --replications 10` runs a model ten times and gives the average of each measure, with a range that the true average very likely falls in (a 95% confidence interval).
- **Experiments:** `desflow experiment` compares versions of a model and writes a report.
- **Fitting inputs:** `desflow fit` turns measured times into a setting for the model.

The shop of the `experiment` example has two packers. An order arrives every 2.5 seconds on average, and packing takes 4 seconds on average. The example asks whether a third packer keeps the average wait under 2 seconds. The example holds the model, the wait measured in the real shop, and the study file `experiment.yaml`. The study runs one hour of the shop 20 times with two packers and 20 times with three:

```yaml
experiment: packers
question: Does a third packer keep the mean wait under 2 seconds?
model: experiment_shop.yaml
until: 1 h
warmup: 3 min              # leave out the first 3 minutes
replications: 20
seed: 42
pairing: common            # both versions see the same orders
measures: [tasks.pack.wait_mean, resources.packers.utilization_avg]
variants:
  two: {}
  three: {Shop.resources.packers.current_cap: 3}
compare:
  - {baseline: two, variant: three}
checks:
  - {measure: tasks.pack.wait_mean, variant: three, max: 2}
observed:
  file: ../observed_waits.csv   # the mean wait measured in the real shop
  variant: two                  # the real shop has two packers
```

```text
$ desflow examples get experiment --api yaml
wrote experiment/yaml/experiment.yaml
wrote experiment/yaml/experiment_shop.yaml
wrote experiment/observed_waits.csv
...
$ cd experiment/yaml
$ desflow experiment experiment.yaml --output results/packers
Wrote the artifacts and report.md to results/packers
passed: three: tasks.pack.wait_mean max 2, checked 0.5919
```

Both versions see the same orders at the same times, so any difference comes from the third packer and not from luck. With three packers, even the top of the range of the average wait is well under 2 seconds, so the check passes. The experiment also compares two packers with the real shop: the wait measured there falls inside the range the model gives, which is evidence that the model describes the shop well.

The report, `report.md`, records the question, the model, the inputs and where they came from, every result and the limits of the study. The command fails when a check fails, so it can run in a CI pipeline.

## Checking a Model Before Running It

A model with a wrong setting still runs and gives numbers that look reasonable, so nothing in the output shows the mistake. Release 0.25.0 adds a check that compares a model with simple arithmetic before it runs.

The recording shows this on the shop in three steps. First, desflow checks the model without running it. Then it runs the model ten times to confirm the check. Last, it runs the experiment from the previous section.

![desflow explain on the shop, then explain --verify with ten one-hour runs that agree with the analysis, then desflow experiment, whose check that three packers keep the mean wait under 2 seconds passes](check-and-compare.gif)

Queueing theory, the mathematics of waiting lines, describes a line such as the shop's with a few numbers, each written as a letter. `desflow explain` works them out from the model and prints them:

- **λ (lambda), the arrival rate:** how many orders arrive a second. An order every 2.5 seconds is 0.4 a second.
- **μ (mu), the service rate:** how many orders one packer finishes a second. Packing takes 4 seconds, so one packer finishes 0.25 a second.
- **c, the capacity:** the number of packers, 2.
- **ρ (rho), the utilisation:** the share of time the packers are busy. Two packers finish c × μ = 0.5 orders a second while 0.4 arrive, so ρ = λ ÷ (c × μ) = 0.4 ÷ 0.5 = 0.8. They are busy 80% of the time.

When ρ is 1 or more, orders arrive faster than they are packed, and the queue grows for as long as the shop stays open. One packer would give ρ = 0.4 ÷ 0.25 = 1.6.

`desflow explain` works this out for every resource in a model, without running it:

```text
$ desflow explain experiment_shop.yaml
...
Resources
+---------------------------------------------------+
| resource |   λ |    μ | c |   ρ | Wq | L | status |
|----------+-----+------+---+-----+----+---+--------|
| packers  | 0.4 | 0.25 | 2 | 0.8 |  - | - | OK     |
+---------------------------------------------------+
packers by units
+-----------------------+
| c |      ρ | status   |
|---+--------+----------|
| 1 |    1.6 | UNSTABLE |
| 2 |    0.8 | OK       |
| 3 | 0.5333 | OK       |
| 4 |    0.4 | OK       |
+-----------------------+
Bottleneck: packers
```

The first table holds those four numbers for the packers, and three more columns:

- **Wq:** the average time an order waits in the queue.
- **L:** the average number of orders in the shop, waiting or being packed.
- **status:** `OK` while ρ is below 0.85, `CONGESTED` from 0.85, where the queue gets long quickly, and `UNSTABLE` from 1, where it never stops growing.

Wq and L are blank here. A formula gives them only for simpler shops, such as one with a single packer, and `explain` leaves them out rather than guess.

The second table, `packers by units`, works out ρ for one to four packers, which shows how many packers the shop needs. `Bottleneck` names the resource with the highest ρ.

The second step, `--verify`, runs the model and checks it against the arithmetic. Here it runs one hour of the shop ten times:

```text
$ desflow explain experiment_shop.yaml --verify --replications 10 --until 1h
...
+------------------------------------------------------------------------+
| node    | measure      | analysis | measured |        ± | result       |
|---------+--------------+----------+----------+----------+--------------|
| packers | utilization  |      0.8 |   0.7953 |  0.01561 | agrees       |
| packers | queue_length |        - |    1.823 |   0.2856 | not compared |
| pack    | wait         |        - |    4.505 |   0.6483 | not compared |
| orders  | throughput   |      0.4 |   0.4002 | 0.007201 | agrees       |
+------------------------------------------------------------------------+
```

Each row is one measure of one part of the model:

- **node:** the part measured: the `packers`, the `pack` task or the `orders` arrival.
- **measure:** what was measured. `throughput` is how many orders leave the shop a second.
- **analysis:** the value the arithmetic gives, or `-` where no formula applies.
- **measured:** the average over the ten runs.
- **±:** give or take: the true average very likely lies within this distance of the measured one (a 95% confidence interval).
- **result:** `agrees` when the analysis lies within that range, `differs` when it does not, and `not compared` when there is no analysis to compare.

The runs keep the packers as busy as the arithmetic says, and finish orders as fast as they arrive, so the model does what its settings describe. The runs also measure the wait that no formula gave. Whether the model matches the real shop is a different question, which the experiment answers with the wait measured there.

Two smaller commands help before a run as well. `desflow run --sample 5` prints the first five events, without sending anything to the model's destinations. `desflow dist` turns a measured average and spread of packing times into the settings a model needs.

## Help With Writing a Model

A blueprint is easier to write when the editor knows its settings. Release 0.24.0 ships a description of every setting as a JSON Schema. With the Red Hat YAML extension in VS Code, one line at the top of a blueprint makes the editor suggest settings and mark a misspelt one as you type:

```yaml
# yaml-language-server: $schema=https://jaehyeon.me/desflow/latest/schema/blueprint.schema.json
```

The same release adds a skill for AI coding assistants such as Claude Code. It teaches an assistant to write a blueprint, check it with `desflow explain`, and run it enough times to trust the result. With the GitHub CLI 2.90.0 or later, one command installs it for Claude Code:

```bash
gh skill install jaehyeon-kim/desflow desflow --agent claude-code --scope user
```

[Use an AI Assistant](https://jaehyeon.me/desflow/latest/guides/use-an-ai-assistant/) also shows how to install it by hand.

## Documentation to Learn From

The documentation now teaches simulation itself, not only the library. The [Learn](https://jaehyeon.me/desflow/latest/learn/) section explains waiting lines, why one run is not enough, how to check a model, and the steps of a simulation study, with code you can run. The tutorials build up the shop one idea at a time, from a first model to fitting measured times.

The new [Complete Model](https://jaehyeon.me/desflow/latest/tutorials/complete-model/) tutorial goes through a whole study in one page, from measured data to a recommendation. [Command Line](https://jaehyeon.me/desflow/latest/user-guide/command-line/) runs every command on one shop.

## Related Posts

* [Defining Data-Streaming Simulations in YAML, Without Writing Python](/blog/2026-10-06-simulations-in-yaml-dynamic-des/) - the YAML blueprint this post builds on
* [Change Data Capture on a Simulated Online Shop with Debezium and Kafka Connect](/blog/2026-10-01-ecommerce-cdc-debezium-kafka-connect/) - a simulated shop feeding a change data capture pipeline
* [Why Digital Twins Are Rewiring Industry 4.0](/blog/2026-04-23-digital-twin-industry-4-0/) - where a simulation like this fits in a digital twin

## Try It Out

```bash
# desflow, the library and its command
pip install desflow

# desflow fit, which needs scipy and matplotlib
pip install "desflow[fit]"

# Download the shop of this post and check it
desflow examples get experiment --api yaml
cd experiment/yaml && desflow explain experiment_shop.yaml
```

* **GitHub:** [jaehyeon-kim/desflow](https://github.com/jaehyeon-kim/desflow)
* **PyPI:** [pypi.org/project/desflow](https://pypi.org/project/desflow/)
* **Documentation:** [jaehyeon.me/desflow](https://jaehyeon.me/desflow/)
