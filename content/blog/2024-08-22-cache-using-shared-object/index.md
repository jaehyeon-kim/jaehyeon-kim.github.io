---
title: Cache Data on Apache Beam Pipelines Using a Shared Object
date: 2024-08-22
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Apache Beam Python Examples
categories:
  - Apache Beam
tags: 
  - Apache Beam
  - Python
authors:
  - JaehyeonKim
images: []
description:
---

I recently contributed to Apache Beam by adding a common pipeline pattern - [*Cache data using a shared object*](https://beam.apache.org/documentation/patterns/shared-class/). Both batch and streaming pipelines are introduced, and they utilise the [`Shared` class](https://beam.apache.org/releases/pydoc/current/_modules/apache_beam/utils/shared.html#Shared) of the Python SDK to enrich `PCollection` elements. This pattern can be more memory-efficient than side inputs, simpler than a stateful `DoFn`, and more performant than calling an external service, because it does not have to access an external service for every element or bundle of elements. In this post, we discuss this pattern in more details with batch and streaming use cases. For the latter, we configure the cache gets refreshed periodically.

<!--more-->

## Create a cache on a batch pipeline

Two data sets are used in the pipelines: _order_ and _customer_. The order records include customer IDs that customer attributes are added to by mapping the customer records. In this batch example, the customer cache is loaded as a dictionary in the `setup` method of the `EnrichOrderFn`. The cache is used to add customer attributes to the order records. Note that we need to create a wrapper class (`WeakRefDict`) because the Python dictionary doesn't support weak references while a `Shared` object encapsulates a weak reference to a singleton instance of the shared resource.

```python
import argparse
import random
import string
import logging
import time
from datetime import datetime

import apache_beam as beam
from apache_beam.utils import shared
from apache_beam.options.pipeline_options import PipelineOptions


def gen_customers(version: int, num_cust: int = 1000):
    d = dict()
    for r in range(num_cust):
        d[r] = {"version": version}
    return d


def gen_orders(ts: float, num_ord: int = 5, num_cust: int = 1000):
    orders = [
        {
            "order_id": "".join(random.choices(string.ascii_lowercase, k=5)),
            "customer_id": random.randrange(1, num_cust),
            "timestamp": int(ts),
        }
        for _ in range(num_ord)
    ]
    for o in orders:
        yield o


# The wrapper class is needed for a dictionary, because it does not support weak references.
class WeakRefDict(dict):
    pass


class EnrichOrderFn(beam.DoFn):
    def __init__(self, shared_handle):
        self._version = 1
        self._customers = {}
        self._shared_handle = shared_handle

    def setup(self):
        self._customer_lookup = self._shared_handle.acquire(self.load_customers)

    def load_customers(self):
        time.sleep(2)
        self._customers = gen_customers(version=self._version)
        return WeakRefDict(self._customers)

    def process(self, element):
        attr = self._customer_lookup.get(element["customer_id"], {})
        yield {**element, **attr}


def run(argv=None):
    parser = argparse.ArgumentParser(
        description="Shared class demo with a bounded PCollection"
    )
    _, pipeline_args = parser.parse_known_args(argv)
    pipeline_options = PipelineOptions(pipeline_args)

    with beam.Pipeline(options=pipeline_options) as p:
        shared_handle = shared.Shared()
        (
            p
            | beam.Create(gen_orders(ts=datetime.now().timestamp()))
            | beam.ParDo(EnrichOrderFn(shared_handle))
            | beam.Map(print)
        )

        logging.getLogger().setLevel(logging.INFO)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

When we execute the pipeline, we see that the customer attribute (`version`) is added to the order records.

```bash
INFO:root:Building pipeline ...
INFO:apache_beam.runners.worker.statecache:Creating state cache with size 104857600
{'order_id': 'lgkar', 'customer_id': 175, 'timestamp': 1724099730, 'version': 1}
{'order_id': 'ylxcf', 'customer_id': 785, 'timestamp': 1724099730, 'version': 1}
{'order_id': 'ypsof', 'customer_id': 446, 'timestamp': 1724099730, 'version': 1}
{'order_id': 'aowzu', 'customer_id': 41, 'timestamp': 1724099730, 'version': 1}
{'order_id': 'bbssb', 'customer_id': 194, 'timestamp': 1724099730, 'version': 1}
```

## Create a cache and update it regularly on a streaming pipeline

Because the customer records are assumed to change over time, you need to refresh it periodically. To reload the shared object, change the `tag` argument of the `acquire` method. In this example, the refresh is implemented in the `start_bundle` method, where it compares the current tag value to the value that is associated with the existing shared object. The `set_tag` method returns a tag value that is the same within the maximum seconds of staleness. Therefore, if a tag value is greater than the existing tag value, it triggers a refresh of the customer cache.

```python
import argparse
import random
import string
import logging
import time
from datetime import datetime

import apache_beam as beam
from apache_beam.utils import shared
from apache_beam.transforms.periodicsequence import PeriodicImpulse
from apache_beam.options.pipeline_options import PipelineOptions


def gen_customers(version: int, tag: float, num_cust: int = 1000):
    d = dict()
    for r in range(num_cust):
        d[r] = {"version": version}
    d["tag"] = tag
    return d


def gen_orders(ts: float, num_ord: int = 5, num_cust: int = 1000):
    orders = [
        {
            "order_id": "".join(random.choices(string.ascii_lowercase, k=5)),
            "customer_id": random.randrange(1, num_cust),
            "timestamp": int(ts),
        }
        for _ in range(num_ord)
    ]
    for o in orders:
        yield o


# wrapper class needed for a dictionary since it does not support weak references
class WeakRefDict(dict):
    pass


class EnrichOrderFn(beam.DoFn):
    def __init__(self, shared_handle, max_stale_sec):
        self._max_stale_sec = max_stale_sec
        self._version = 1
        self._customers = {}
        self._shared_handle = shared_handle

    def setup(self):
        self._customer_lookup = self._shared_handle.acquire(
            self.load_customers, self.set_tag()
        )

    def set_tag(self):
        current_ts = datetime.now().timestamp()
        return current_ts - (current_ts % self._max_stale_sec)

    def load_customers(self):
        time.sleep(2)
        self._customers = gen_customers(version=self._version, tag=self.set_tag())
        return WeakRefDict(self._customers)

    def start_bundle(self):
        if self.set_tag() > self._customers["tag"]:
            logging.info(
                f"refresh customer cache, current tag {self.set_tag()}, existing tag {self._customers['tag']}..."
            )
            self._version += 1
            self._customer_lookup = self._shared_handle.acquire(
                self.load_customers, self.set_tag()
            )

    def process(self, element):
        attr = self._customer_lookup.get(element["customer_id"], {})
        yield {**element, **attr}


def run(argv=None):
    parser = argparse.ArgumentParser(
        description="Shared class demo with an unbounded PCollection"
    )
    parser.add_argument(
        "--fire_interval",
        "-f",
        type=int,
        default=2,
        help="Interval at which to output elements.",
    )
    parser.add_argument(
        "--max_stale_sec",
        "-m",
        type=int,
        default=5,
        help="Maximum second of staleness.",
    )
    known_args, pipeline_args = parser.parse_known_args(argv)
    pipeline_options = PipelineOptions(pipeline_args)

    with beam.Pipeline(options=pipeline_options) as p:
        shared_handle = shared.Shared()
        (
            p
            | PeriodicImpulse(
                fire_interval=known_args.fire_interval, apply_windowing=False
            )
            | beam.FlatMap(gen_orders)
            | beam.ParDo(EnrichOrderFn(shared_handle, known_args.max_stale_sec))
            | beam.Map(print)
        )

        logging.getLogger().setLevel(logging.INFO)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

The pipeline output shows the order records are enriched with updated customer attributes (`version`). By default, the pipeline creates 5 order records in every 2 seconds, and the maximum seconds of staleness is 5 seconds. Therefore, we have 2.5 sets of order records in a particular version on average, which causes 10 to 15 records are mapped to a single version.

```python
INFO:root:Building pipeline ...
INFO:apache_beam.runners.worker.statecache:Creating state cache with size 104857600
{'order_id': 'rqicm', 'customer_id': 841, 'timestamp': 1724099759, 'version': 1}
{'order_id': 'xjjnj', 'customer_id': 506, 'timestamp': 1724099759, 'version': 1}
{'order_id': 'iuiua', 'customer_id': 612, 'timestamp': 1724099759, 'version': 1}
{'order_id': 'yiwtq', 'customer_id': 486, 'timestamp': 1724099759, 'version': 1}
{'order_id': 'aolsp', 'customer_id': 839, 'timestamp': 1724099759, 'version': 1}
{'order_id': 'kkldd', 'customer_id': 223, 'timestamp': 1724099761, 'version': 1}
{'order_id': 'pxbyr', 'customer_id': 262, 'timestamp': 1724099761, 'version': 1}
{'order_id': 'yhsrx', 'customer_id': 899, 'timestamp': 1724099761, 'version': 1}
{'order_id': 'elcqj', 'customer_id': 726, 'timestamp': 1724099761, 'version': 1}
{'order_id': 'echap', 'customer_id': 32, 'timestamp': 1724099761, 'version': 1}
{'order_id': 'swhgo', 'customer_id': 98, 'timestamp': 1724099763, 'version': 1}
{'order_id': 'flcoq', 'customer_id': 6, 'timestamp': 1724099763, 'version': 1}
{'order_id': 'erhed', 'customer_id': 116, 'timestamp': 1724099763, 'version': 1}
{'order_id': 'mcupo', 'customer_id': 589, 'timestamp': 1724099763, 'version': 1}
{'order_id': 'vbvgu', 'customer_id': 870, 'timestamp': 1724099763, 'version': 1}
INFO:root:refresh customer cache, current tag 1724099765.0, existing tag 1724099760.0...
{'order_id': 'solvl', 'customer_id': 186, 'timestamp': 1724099765, 'version': 2}
{'order_id': 'ingmb', 'customer_id': 483, 'timestamp': 1724099765, 'version': 2}
{'order_id': 'gckfl', 'customer_id': 194, 'timestamp': 1724099765, 'version': 2}
{'order_id': 'azatw', 'customer_id': 995, 'timestamp': 1724099765, 'version': 2}
{'order_id': 'ngivi', 'customer_id': 62, 'timestamp': 1724099765, 'version': 2}
{'order_id': 'czzdh', 'customer_id': 100, 'timestamp': 1724099767, 'version': 2}
{'order_id': 'xdadk', 'customer_id': 485, 'timestamp': 1724099767, 'version': 2}
{'order_id': 'sytfd', 'customer_id': 845, 'timestamp': 1724099767, 'version': 2}
{'order_id': 'ckkvc', 'customer_id': 278, 'timestamp': 1724099767, 'version': 2}
{'order_id': 'vchzr', 'customer_id': 535, 'timestamp': 1724099767, 'version': 2}
{'order_id': 'fxhvd', 'customer_id': 37, 'timestamp': 1724099769, 'version': 2}
{'order_id': 'lbncv', 'customer_id': 774, 'timestamp': 1724099769, 'version': 2}
{'order_id': 'ljdrc', 'customer_id': 823, 'timestamp': 1724099769, 'version': 2}
{'order_id': 'jsuvb', 'customer_id': 943, 'timestamp': 1724099769, 'version': 2}
{'order_id': 'htuxz', 'customer_id': 287, 'timestamp': 1724099769, 'version': 2}
INFO:root:refresh customer cache, current tag 1724099770.0, existing tag 1724099765.0...
{'order_id': 'pxhxp', 'customer_id': 309, 'timestamp': 1724099771, 'version': 3}
{'order_id': 'qawyw', 'customer_id': 551, 'timestamp': 1724099771, 'version': 3}
{'order_id': 'obcxg', 'customer_id': 995, 'timestamp': 1724099771, 'version': 3}
{'order_id': 'ymfbz', 'customer_id': 614, 'timestamp': 1724099771, 'version': 3}
{'order_id': 'bauwp', 'customer_id': 420, 'timestamp': 1724099771, 'version': 3}
{'order_id': 'iidmf', 'customer_id': 570, 'timestamp': 1724099773, 'version': 3}
{'order_id': 'lijfn', 'customer_id': 86, 'timestamp': 1724099773, 'version': 3}
{'order_id': 'fuqkc', 'customer_id': 206, 'timestamp': 1724099773, 'version': 3}
{'order_id': 'wywat', 'customer_id': 501, 'timestamp': 1724099773, 'version': 3}
{'order_id': 'umude', 'customer_id': 986, 'timestamp': 1724099773, 'version': 3}
INFO:root:refresh customer cache, current tag 1724099775.0, existing tag 1724099770.0...
{'order_id': 'jssia', 'customer_id': 757, 'timestamp': 1724099775, 'version': 4}
{'order_id': 'igjsb', 'customer_id': 129, 'timestamp': 1724099775, 'version': 4}
{'order_id': 'mzhnc', 'customer_id': 589, 'timestamp': 1724099775, 'version': 4}
{'order_id': 'hgldm', 'customer_id': 22, 'timestamp': 1724099775, 'version': 4}
{'order_id': 'srpus', 'customer_id': 275, 'timestamp': 1724099775, 'version': 4}
{'order_id': 'vdxuk', 'customer_id': 985, 'timestamp': 1724099777, 'version': 4}
{'order_id': 'zykon', 'customer_id': 309, 'timestamp': 1724099777, 'version': 4}
{'order_id': 'utulz', 'customer_id': 930, 'timestamp': 1724099777, 'version': 4}
{'order_id': 'dngqv', 'customer_id': 806, 'timestamp': 1724099777, 'version': 4}
{'order_id': 'bvsmi', 'customer_id': 248, 'timestamp': 1724099777, 'version': 4}
{'order_id': 'nljnh', 'customer_id': 680, 'timestamp': 1724099779, 'version': 4}
{'order_id': 'qlkui', 'customer_id': 481, 'timestamp': 1724099779, 'version': 4}
{'order_id': 'rmaci', 'customer_id': 301, 'timestamp': 1724099779, 'version': 4}
{'order_id': 'ndlyp', 'customer_id': 351, 'timestamp': 1724099779, 'version': 4}
{'order_id': 'znvlx', 'customer_id': 546, 'timestamp': 1724099779, 'version': 4}
INFO:root:refresh customer cache, current tag 1724099780.0, existing tag 1724099775.0...
{'order_id': 'nyvjt', 'customer_id': 527, 'timestamp': 1724099781, 'version': 5}
{'order_id': 'wfsls', 'customer_id': 495, 'timestamp': 1724099781, 'version': 5}
{'order_id': 'pkbuq', 'customer_id': 315, 'timestamp': 1724099781, 'version': 5}
{'order_id': 'gpmqi', 'customer_id': 9, 'timestamp': 1724099781, 'version': 5}
{'order_id': 'sqone', 'customer_id': 943, 'timestamp': 1724099781, 'version': 5}
{'order_id': 'lbvyd', 'customer_id': 311, 'timestamp': 1724099783, 'version': 5}
{'order_id': 'gmmnk', 'customer_id': 839, 'timestamp': 1724099783, 'version': 5}
{'order_id': 'vibyr', 'customer_id': 462, 'timestamp': 1724099783, 'version': 5}
{'order_id': 'bqlia', 'customer_id': 320, 'timestamp': 1724099783, 'version': 5}
{'order_id': 'uqywb', 'customer_id': 926, 'timestamp': 1724099783, 'version': 5}
```