---
title: Apache Beam Python Examples - Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn
date: 2024-12-05
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
series:
  - Apache Beam Python Examples
categories:
  - Apache Beam
tags: 
  - Apache Beam
  - Apache Flink
  - gRPC
  - Python
  - Docker
  - Docker Compose
authors:
  - JaehyeonKim
images: []
description: 
---

A [*Splittable DoFn (SDF)*](https://beam.apache.org/documentation/programming-guide/#splittable-dofns) is a generalization of a *DoFn* that enables Apache Beam developers to create modular and composable I/O components. Also, it can be applied in advanced non-I/O scenarios such as Monte Carlo simulation. In this post, we develop two Apache Beam pipelines. The first pipeline is an example I/O connector, and it reads a list of files in a folder followed by processing each of the file objects in parallel. The second pipeline estimates the value of $\pi$ by performing Monte Carlo simulation.

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-18-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* [Part 7 Separate Droppable Data into Side Output](/blog/2024-10-24-beam-examples-7)
* [Part 8 Enhance Sport Activity Tracker with Runner Motivation](/blog/2024-11-21-beam-examples-8)
* [Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn](#) (this post)
* Part 10 Develop Streaming File Reader using Splittable DoFn

## Splittable DoFn

A [*Splittable DoFn (SDF)*](https://beam.apache.org/documentation/programming-guide/#splittable-dofns) is a generalization of a *DoFn* that enables Apache Beam developers to create modular and composable I/O components. Also, it can be applied in advanced non-I/O scenarios such as Monte Carlo simulation.

As described in the [Apache Beam Programming Guide](https://beam.apache.org/documentation/programming-guide/#splittable-dofns), an SDF is responsible for processing element and restriction pairs. A restriction represents a subset of work that would have been necessary to have been done when processing the element.

Executing an SDF follows the following steps:

1. Each element is paired with a restriction (e.g. filename is paired with offset range representing the whole file).
2. Each element and restriction pair is split (e.g. offset ranges are broken up into smaller pieces).
3. The runner redistributes the element and restriction pairs to several workers.
4. Element and restriction pairs are processed in parallel (e.g. the file is read). Within this last step, the element and restriction pair can pause its own processing and/or be split into further element and restriction pairs.

![](sdf_high_level_overview.png#center)

A basic SDF is composed of three parts: a restriction, a restriction provider, and a restriction tracker.

- restriction
    - It represents a subset of work for a given element.
    - No specific class needs to be implemented to represent a restriction.
- restriction provider
    - It lets developers override default implementations used to generate and manipulate restrictions. 
    - It extends from the `RestrictionProvider` base class.
- restriction tracker
    - It tracks for which parts of the restriction processing has been completed.
    - It extends from the `RestrictionTracker` base class.

The Python SDK has a built-in restriction (`OffsetRange`) and restriction tracker (`OffsetRangeTracker`), and we will use them in this post.

An advanced SDF has the following components for watermark estimation, and we will use them in the next post.

- watermark state
    - It is a user-defined object. In its simplest form it could just be a timestamp.
- watermark estimator
    - It tracks the watermark state when the processing of an element and restriction pair is in progress.
    - It extends from the `WatermarkEstimator` base class.
- watermark estimator provider
    - It lets developers define how to initialize the watermark state and create a watermark estimator.
    - It extends from the `WatermarkEstimatorProvider` base class.

For more details, visit [Splittable DoFns in Python: a hands-on workshop](https://2022.beamsummit.org/sessions/splittable-dofns-in-python/).

## Batch File Reader

This Beam pipeline reads a list of files in a folder followed by processing each of the file objects in parallel. This pipeline is slightly modified from the pipeline that was introduced in a [workshop](https://2022.beamsummit.org/sessions/splittable-dofns-in-python/) at Beam Summit 2022. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### File Generator

The batch pipeline requires input files to process, and those files can be created using a file generator (`faker_file_gen.py`). It creates a configurable number of files (default *10*) in a folder (default *fake_files*). Each file includes zero to two hundreds lines of text, which is generated by the [Faker package](https://faker.readthedocs.io/en/master/).

```python
# utils/faker_file_gen.py
import os
import time
import shutil
import argparse
import logging

from faker import Faker

file_path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "fake_files"
)


def create_folder(file_path: str):
    shutil.rmtree(file_path, ignore_errors=True)
    os.mkdir(file_path)


def write_to_file(fake: Faker, file_path: str, file_name: str):
    with open(os.path.join(file_path, file_name), "w") as f:
        f.writelines(fake.texts(nb_texts=fake.random_int(min=0, max=200)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__file__, description="Fake Text File Generator")
    parser.add_argument(
        "-p",
        "--file_path",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "fake_files"
        ),
        help="File path",
    )
    parser.add_argument(
        "-m",
        "--max_files",
        type=int,
        default=10,
        help="The amount of time that a record should be delayed.",
    )
    parser.add_argument(
        "-d",
        "--delay_seconds",
        type=float,
        default=0.5,
        help="The amount of time that a record should be delayed.",
    )

    args = parser.parse_args()

    logging.getLogger().setLevel(logging.INFO)
    logging.info(
        f"Create files: max files {args.max_files}, delay seconds {args.delay_seconds}..."
    )

    fake = Faker()
    Faker.seed(1237)

    create_folder(args.file_path)
    current = 0
    while True:
        write_to_file(
            fake,
            args.file_path,
            f"{''.join(fake.random_letters(length=10)).lower()}.txt",
        )
        current += 1
        if current % 5 == 0:
            logging.info(f"Created {current} files so far...")
        if current == args.max_files:
            break
        time.sleep(args.delay_seconds)
```

Once executed, we can check input files are created in a specified folder.

```bash
$ python utils/faker_file_gen.py --file_path fake_files --max_files 10 --delay_seconds 0.5
INFO:root:Create files: max files 10, delay seconds 0.5...
INFO:root:Created 5 files so far...
INFO:root:Created 10 files so far...

$ tree fake_files/
fake_files/
├── dhmfhxwbqd.txt
├── dzpjwroqdd.txt
├── humlastzob.txt
├── jfdlxdnsre.txt
├── qgtyykdzdk.txt
├── uxgrwaisgj.txt
├── vcqlxrcqnx.txt
├── ydlceysnkc.txt
├── ylgvjqjhrb.txt
└── zpjinqrdyw.txt

1 directory, 10 files
```

### SDF for File Processing

The pipeline has two *DoFn* objects.

- `GenerateFilesFn`
    - It reads each of the files in the input folder (*element*) followed by yielding a custom object (`MyFile`). The custom object keeps details of a file object that include the file name and start/end positions. As mentioned, we are going to use the default `OffsetRestrictionTracker` in the subsequent *DoFn*. Therefore, it is necessary to keep the start and end positions because those are used to set up the initial offset range.
- `ProcessFilesFn`
    - It begins with recovering the current restriction using the parameter of type `RestrictionParam`, which is passed as argument. Then, it tries to claim/lock the position. Once claimed, it proceeds to processing the associated element and restriction pair, which is just yielding a text that keeps the file name and current position.

```python
# chapter7/file_read.py
import os
import typing
import logging

import apache_beam as beam
from apache_beam import RestrictionProvider
from apache_beam.io.restriction_trackers import OffsetRange, OffsetRestrictionTracker


class MyFile(typing.NamedTuple):
    name: str
    start: int
    end: int


class GenerateFilesFn(beam.DoFn):
    def process(self, element: str) -> typing.Iterable[MyFile]:
        for file in os.listdir(element):
            if os.path.isfile(os.path.join(element, file)):
                num_lines = sum(1 for _ in open(os.path.join(element, file)))
                new_file = MyFile(file, 0, num_lines)
                yield new_file


class ProcessFilesFn(beam.DoFn, RestrictionProvider):
    def process(
        self,
        element: MyFile,
        tracker: OffsetRestrictionTracker = beam.DoFn.RestrictionParam(),
    ):
        restriction = tracker.current_restriction()
        for current_position in range(restriction.start, restriction.stop + 1):
            if tracker.try_claim(current_position):
                m = f"file: {element.name}, position: {current_position}"
                logging.info(m)
                yield m
            else:
                return

    def create_tracker(self, restriction: OffsetRange) -> OffsetRestrictionTracker:
        return OffsetRestrictionTracker(restriction)

    def initial_restriction(self, element: MyFile) -> OffsetRange:
        return OffsetRange(start=element.start, stop=element.end)

    def restriction_size(self, element: MyFile, restriction: OffsetRange) -> int:
        return restriction.size()
```

### Beam Pipeline

The pipeline begins with passing the input folder to the `GenerateFilesFn` *DoFn*. Then, the *DoFn* yields the custom `MyFile` objects while reading the whole list of files in the input folder. Finally, the custom objects are processed by the`ProcessFilesFn` *DoFn*. 

```python
# chapter7/batch_file_read.py
import os
import logging
import argparse

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from file_read import GenerateFilesFn, ProcessFilesFn


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "-p",
        "--file_path",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "fake_files"
        ),
        help="File path",
    )

    known_args, pipeline_args = parser.parse_known_args(argv)

    # # We use the save_main_session option because one or more DoFn's in this
    # # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    print(f"known args - {known_args}")
    print(f"pipeline options - {pipeline_options.display_data()}")

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | beam.Create([known_args.file_path])
            | beam.ParDo(GenerateFilesFn())
            | beam.ParDo(ProcessFilesFn())
        )

        logging.getLogger().setLevel(logging.INFO)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

We can create input files and run the pipeline using the *Direct Runner* as shown below.

```bash
python utils/faker_file_gen.py -m 1000 -d 0
python chapter7/batch_file_read.py \
    --direct_num_workers=3 --direct_running_mode=multi_threading
```

![](batch-reader-demo.gif#center)

## PI Sampler

This pipeline performs a Monte Carlo simulation to estimate $\pi$. Let say we have a square that is centered at the origin of a two-dimensional space. If the length of its side is two, its area is four. Now we draw a circle that is centered at the origin as well where its radius is one. Then, its area becomes $\pi$. In this circumstance, if we randomly place a dot within the square, the probability that we place the dot within the circle is $\pi$/4. To estimate this probability empirically, we can place many dots in the square. If we label the case as *positive* when a dot is placed within the circle and as *negative* otherwise, we have the following empirical relationship.

- $\pi$/4 $\approx$ `# positive`/`# total`

Therefore, we can estimate the value of $\pi$ with one of the following formulas.

- $\pi$ $\approx$ 4 x `# positive`/`# total` or 4 x (1 - `# negative`/`# total`)

The pipeline has two *DoFn* objects as shown below.

- `GenerateExperiments`
    - It yields a fixed number of samples (`num_samples`) to simulate in each experiment (`parallelism`). Therefore, it ends up creating `num_samples` * `parallelism` simulations in total.
- `PiSamplerDoFn`
    - Similar to the earlier pipeline, it begins with recovering the current restriction using the parameter of type `RestrictionParam`, which is passed as argument. Then, it tries to claim/lock the position. Once claimed, it generates two random numbers between zero and one followed by yielding one if their squired sum is greater than one. i.e. It tracks *negative* cases.

After completing all simulations, the resulting values are added, which calculates the number of all *negative* cases. Finally, the value of $\pi$ is estimated by applying the second formula mentioned above.

```python
import random
import logging
import argparse

import apache_beam as beam
from apache_beam import RestrictionProvider
from apache_beam.io.restriction_trackers import OffsetRange, OffsetRestrictionTracker
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions


class GenerateExperiments(beam.DoFn):
    def __init__(self, parallelism: int, num_samples: int):
        self.parallelism = parallelism
        self.num_samples = num_samples

    def process(self, ignored_element):
        for i in range(self.parallelism):
            if (i + 1) % 10 == 0:
                logging.info(f"sending {i + 1}th experiment")
            yield self.num_samples


class PiSamplerDoFn(beam.DoFn, RestrictionProvider):
    def process(
        self,
        element: int,
        tracker: OffsetRestrictionTracker = beam.DoFn.RestrictionParam(),
    ):
        restriction = tracker.current_restriction()
        for current_position in range(restriction.start, restriction.stop + 1):
            if tracker.try_claim(current_position):
                x, y = random.random(), random.random()
                if x * x + y * y > 1:
                    yield 1
            else:
                return

    def create_tracker(self, restriction: OffsetRange) -> OffsetRestrictionTracker:
        return OffsetRestrictionTracker(restriction)

    def initial_restriction(self, element: int) -> OffsetRange:
        return OffsetRange(start=0, stop=element)

    def restriction_size(self, element: int, restriction: OffsetRange) -> int:
        return restriction.size()


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser(description="Beam pipeline arguments")
    parser.add_argument(
        "-p", "--parallelism", type=int, default=100, help="Number of parallelism"
    )
    parser.add_argument(
        "-n", "--num_samples", type=int, default=10000, help="Number of samples"
    )

    known_args, pipeline_args = parser.parse_known_args(argv)

    # # We use the save_main_session option because one or more DoFn's in this
    # # workflow rely on global context (e.g., a module imported at module level).
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    print(f"known args - {known_args}")
    print(f"pipeline options - {pipeline_options.display_data()}")

    with beam.Pipeline(options=pipeline_options) as p:
        (
            p
            | beam.Create([0])
            | beam.ParDo(
                GenerateExperiments(
                    parallelism=known_args.parallelism,
                    num_samples=known_args.num_samples,
                )
            )
            | beam.ParDo(PiSamplerDoFn())
            | beam.CombineGlobally(sum)
            | beam.Map(
                lambda e: 4
                * (1 - e / (known_args.num_samples * known_args.parallelism))
            )
            | beam.Map(print)
        )

        logging.getLogger().setLevel(logging.INFO)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

In the following example, the value of $\pi$ is estimated by 6,000,000 simulations (*parallelism*: 200, *num_samples*: 30,000). We see that the pipeline estimates $\pi$ correctly to three decimal places.

```bash
python chapter7/pi_sampler.py -p 200 -n 30000 \
    --direct_num_workers=3 --direct_running_mode=multi_threading
```

![](pi-sampler-demo.gif#center)