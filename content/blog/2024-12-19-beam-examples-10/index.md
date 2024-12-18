---
title: Apache Beam Python Examples - Part 10 Develop Streaming File Reader using Splittable DoFn
date: 2024-12-19
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

In [Part 9](/blog/2024-12-05-beam-examples-9), we developed two Apache Beam pipelines using [*Splittable DoFn (SDF)*](https://beam.apache.org/documentation/programming-guide/#splittable-dofns). One of them is a batch file reader, which reads a list of files in an input folder followed by processing them in parallel. We can extend the I/O connector so that, instead of listing files once at the beginning, it scans an input folder periodically for new files and processes whenever new files are created in the folder. The techniques used in this post can be quite useful as they can be applied to developing I/O connectors that target other unbounded (or streaming) data sources (eg Kafka) using the Python SDK.

<!--more-->

* [Part 1 Calculate K Most Frequent Words and Max Word Length](/blog/2024-07-04-beam-examples-1)
* [Part 2 Calculate Average Word Length with/without Fixed Look back](/blog/2024-07-18-beam-examples-2)
* [Part 3 Build Sport Activity Tracker with/without SQL](/blog/2024-08-01-beam-examples-3)
* [Part 4 Call RPC Service for Data Augmentation](/blog/2024-08-15-beam-examples-4)
* [Part 5 Call RPC Service in Batch using Stateless DoFn](/blog/2024-09-18-beam-examples-5)
* [Part 6 Call RPC Service in Batch with Defined Batch Size using Stateful DoFn](/blog/2024-10-02-beam-examples-6)
* [Part 7 Separate Droppable Data into Side Output](/blog/2024-10-24-beam-examples-7)
* [Part 8 Enhance Sport Activity Tracker with Runner Motivation](/blog/2024-11-21-beam-examples-8)
* [Part 9 Develop Batch File Reader and PiSampler using Splittable DoFn](/blog/2024-12-05-beam-examples-9)
* [Part 10 Develop Streaming File Reader using Splittable DoFn](#) (this post)

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

The Python SDK has a built-in restriction (`OffsetRange`) and restriction tracker (`OffsetRangeTracker`). We will use both the built-in and custom components in this post.

An advanced SDF has the following components for watermark estimation, and we will use them in this post.

- watermark state
    - It is a user-defined object. In its simplest form it could just be a timestamp.
- watermark estimator
    - It tracks the watermark state when the processing of an element and restriction pair is in progress.
    - It extends from the `WatermarkEstimator` base class.
- watermark estimator provider
    - It lets developers define how to initialize the watermark state and create a watermark estimator.
    - It extends from the `WatermarkEstimatorProvider` base class.

For more details, visit [Splittable DoFns in Python: a hands-on workshop](https://2022.beamsummit.org/sessions/splittable-dofns-in-python/).

## Streaming File Reader

The pipeline scans an input folder periodically for new files and processes whenever new files are created in the folder. The source of this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/beam-demos/tree/master/beam-pipelines).

### File Generator

The pipeline requires input files to process, and those files can be created using the file generator (`faker_file_gen.py`). It creates a configurable number of files (default *10*) in a folder (default *fake_files*). Note that it generates files indefinitely if we specify the argument (`-m` or `--max_files`) to *-1*. Each file includes zero to two hundreds lines of text, which is generated by the [Faker package](https://faker.readthedocs.io/en/master/).

```python
# utils/faker_file_gen.py
import os
import time
import shutil
import argparse
import logging

from faker import Faker


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

Once executed, we can check input files are created in a specified folder continuously.

```bash
$ python utils/faker_file_gen.py --max_files -1 --delay_seconds 0.5
INFO:root:Create files: max files -1, delay seconds 0.5...
INFO:root:Created 5 files so far...
INFO:root:Created 10 files so far...
INFO:root:Created 15 files so far...

$ tree fake_files/
fake_files/
├── bcgmdarvkf.txt
├── dhmfhxwbqd.txt
├── dzpjwroqdd.txt
├── humlastzob.txt
├── jfdlxdnsre.txt
├── jpouwxftxk.txt
├── jxfgefbnsj.txt
├── lnazazhvpm.txt
├── qgtyykdzdk.txt
├── uxgrwaisgj.txt
├── vcqlxrcqnx.txt
├── ydlceysnkc.txt
├── ylgvjqjhrb.txt
├── ywwfbldecg.txt
└── zpjinqrdyw.txt

1 directory, 15 files
```

### SDF for Directory Watch

We use a custom restriction (`DirectoryWatchRestriction`) for the `DirectoryWatchFn` *DoFn* object. The details about the restriction and related components can be found below.

- `DirectoryWatchRestriction`
    - It has two fields (*already_processed* and *finished*) where the former is used to hold the file names that have processed (i.e. *claimed*) already.
    - To split the restriction into primary and residual, two methods are created - `as_primary` and `as_residual`. The `as_primary` returns itself after updating the *finished* field to *True*, and it makes the primary restriction to be *unclaimable* - see the associating tracker for details. On the other hand, the `as_residual` method returns a new instance of the restriction with the existing processed file names (*already_processed*) and the *finished* field to *False* for subsequent processing. As can be checked in the associating tracker, the residual restriction is updated by adding a new file to process, and the processed file names can be used to identify whether the new file has already been processed or not.
- `DirectoryWatchRestrictionCoder`
    - It provides a *coder* object for the custom restriction. Its `encode/decode` methods rely on the restriction's `to_json/from_json` methods.
- `DirectoryWatchRestrictionTracker`
    - It expects the custom restriction as an argument and returns it as the current restriction by the `current_restriction` method. Also, it splits the restriction into primary and residual using the `try_split` method. Once the restriction is split, it determines whether to claim it or not (`try_claim`). Specifically, it refuses to claim the restriction if it is already processed. Or it claims after adding a new file. The last part of the contract is the `is_bound` method, which signals if the current restriction represents a finite amount of work. Note that a restriction can turn from unbounded to bounded but can never turn from bounded to unbounded.
- `DirectoryWatchRestrictionProvider`
    - It intialises with the custom restriction where the *already_processed* and *finished* fields to an empty set and *False* respectively (`initial_restriction`). Also, the `create_tracker` method returns the custom restriction tracker, and the size of the restriction is returned by the `restriction_size` method. 

We also employ a custom watermark estimator provider (`DirectoryWatchWatermarkEstimatorProvider`), and it tracks the progress in the event time. It uses `ManualWatermarkEstimator` to set the watermark manually from inside the `process` method of the `DirectoryWatchFn` *DoFn* object.

The `process` method of the `DirectoryWatchFn` *DoFn* adds two new arguments (*tracker* and *watermark_estimator*), which utilised the SDF components defined earlier. Also, it is wrapped by a decorator that specifies an unbounded amount of work per input element is performed (`@beam.DoFn.unbounded_per_element()`). Within the function, it performs the following two tasks periodically, thanks to the tracker's `defer_remainder` method.

- Get new files if any
    - In the `_get_new_files_if_any` method, it creates a *MyFile* object for each of the files in the input folder if a file has not been processed already. A tuple of the file object and its last modified time is appended to a list named *new_files*, and the list is returned at the end.
- Return file objects that can be processed
    - The `_check_processible` method tries to take all the newly discovered files and tries to claim them one by one in the restriction tracker object. If the claim fails, the method returns *False* and the `process` method immediately exits. Otherwise, it updates watermark if the last modified timestamp is larger than the current watermark.
    - Once the `_check_processible` method returns *True*, individual file objects are returned.

```python
# chapter7/directory_watch.py
import os
import json
import typing

import apache_beam as beam
from apache_beam import RestrictionProvider
from apache_beam.utils.timestamp import Duration
from apache_beam.io.iobase import RestrictionTracker
from apache_beam.io.watermark_estimators import ManualWatermarkEstimator
from apache_beam.transforms.core import WatermarkEstimatorProvider
from apache_beam.runners.sdf_utils import RestrictionTrackerView
from apache_beam.utils.timestamp import Timestamp, MIN_TIMESTAMP, MAX_TIMESTAMP

from file_read import MyFile


class DirectoryWatchRestriction:
    def __init__(self, already_processed: typing.Set[str], finished: bool):
        self.already_processed = already_processed
        self.finished = finished

    def as_primary(self):
        self.finished = True
        return self

    def as_residual(self):
        return DirectoryWatchRestriction(self.already_processed, False)

    def add_new(self, file: str):
        self.already_processed.add(file)

    def size(self) -> int:
        return 1

    @classmethod
    def from_json(cls, value: str):
        d = json.loads(value)
        return cls(
            already_processed=set(d["already_processed"]), finished=d["finished"]
        )

    def to_json(self):
        return json.dumps(
            {
                "already_processed": list(self.already_processed),
                "finished": self.finished,
            }
        )


class DirectoryWatchRestrictionCoder(beam.coders.Coder):
    def encode(self, value: DirectoryWatchRestriction) -> bytes:
        return value.to_json().encode("utf-8")

    def decode(self, encoded: bytes) -> DirectoryWatchRestriction:
        return DirectoryWatchRestriction.from_json(encoded.decode("utf-8"))

    def is_deterministic(self) -> bool:
        return True


class DirectoryWatchRestrictionTracker(RestrictionTracker):
    def __init__(self, restriction: DirectoryWatchRestriction):
        self.restriction = restriction

    def current_restriction(self):
        return self.restriction

    def try_claim(self, new_file: str):
        if self.restriction.finished:
            return False
        self.restriction.add_new(new_file)
        return True

    def check_done(self):
        return

    def is_bounded(self):
        return True if self.restriction.finished else False

    def try_split(self, fraction_of_remainder):
        return self.restriction.as_primary(), self.restriction.as_residual()


class DirectoryWatchRestrictionProvider(RestrictionProvider):
    def initial_restriction(self, element: str) -> DirectoryWatchRestriction:
        return DirectoryWatchRestriction(set(), False)

    def create_tracker(
        self, restriction: DirectoryWatchRestriction
    ) -> DirectoryWatchRestrictionTracker:
        return DirectoryWatchRestrictionTracker(restriction)

    def restriction_size(self, element: str, restriction: DirectoryWatchRestriction):
        return restriction.size()

    def restriction_coder(self):
        return DirectoryWatchRestrictionCoder()


class DirectoryWatchWatermarkEstimatorProvider(WatermarkEstimatorProvider):
    def initial_estimator_state(self, element, restriction):
        return MIN_TIMESTAMP

    def create_watermark_estimator(self, watermark: Timestamp):
        return ManualWatermarkEstimator(watermark)

    def estimator_state_coder(self):
        return beam.coders.TimestampCoder()


class DirectoryWatchFn(beam.DoFn):
    # TODO: add watermark_fn to completes the process function by advancing watermark to max timestamp
    #       without such a funcition, the pipeline never completes and we cannot perform unit testing
    POLL_TIMEOUT = 1

    @beam.DoFn.unbounded_per_element()
    def process(
        self,
        element: str,
        tracker: RestrictionTrackerView = beam.DoFn.RestrictionParam(
            DirectoryWatchRestrictionProvider()
        ),
        watermark_estimater: WatermarkEstimatorProvider = beam.DoFn.WatermarkEstimatorParam(
            DirectoryWatchWatermarkEstimatorProvider()
        ),
    ) -> typing.Iterable[MyFile]:
        new_files = self._get_new_files_if_any(element, tracker)
        if self._check_processible(tracker, watermark_estimater, new_files):
            for new_file in new_files:
                yield new_file[0]
        else:
            return
        tracker.defer_remainder(Duration.of(self.POLL_TIMEOUT))

    def _get_new_files_if_any(
        self, element: str, tracker: DirectoryWatchRestrictionTracker
    ) -> typing.List[typing.Tuple[MyFile, Timestamp]]:
        new_files = []
        for file in os.listdir(element):
            if (
                os.path.isfile(os.path.join(element, file))
                and file not in tracker.current_restriction().already_processed
            ):
                num_lines = sum(1 for _ in open(os.path.join(element, file)))
                new_file = MyFile(file, 0, num_lines)
                print(new_file)
                new_files.append(
                    (
                        new_file,
                        Timestamp.of(os.path.getmtime(os.path.join(element, file))),
                    )
                )
        return new_files

    def _check_processible(
        self,
        tracker: DirectoryWatchRestrictionTracker,
        watermark_estimater: ManualWatermarkEstimator,
        new_files: typing.List[typing.Tuple[MyFile, Timestamp]],
    ):
        max_instance = watermark_estimater.current_watermark()
        for new_file in new_files:
            if tracker.try_claim(new_file[0].name) is False:
                watermark_estimater.set_watermark(max_instance)
                return False
            if max_instance < new_file[1]:
                max_instance = new_file[1]
        watermark_estimater.set_watermark(max_instance)
        return max_instance < MAX_TIMESTAMP
```

### SDF for File Processing

The `ProcessFilesFn` *DoFn* begins with recovering the current restriction using the parameter of type `RestrictionParam`, which is passed as argument. Then, it tries to claim/lock the position. Once claimed, it proceeds to processing the associated element and restriction pair, which is just yielding a text that keeps the file name and current position.

```python
# chapter7/file_read.py
import os
import typing
import logging

import apache_beam as beam
from apache_beam import RestrictionProvider
from apache_beam.io.restriction_trackers import OffsetRange, OffsetRestrictionTracker

# ...

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

The pipeline begins with passing the input folder name to the `DirectoryWatchFn` *DoFn*. Then, the *DoFn* yields the custom `MyFile` objects while scanning the input folder periodically for new files. Finally, the custom objects are processed by the `ProcessFilesFn` *DoFn*. Note that the output of the `DirectoryWatchFn` *DoFn* is shuffled using the `Reshuffle` transform to redistribute it to a random worker.

```python
# chapter7/streaming_file_read.py
import os
import logging
import argparse

import apache_beam as beam
from apache_beam.transforms.util import Reshuffle
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions

from directory_watch import DirectoryWatchFn
from file_read import ProcessFilesFn


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
            | beam.ParDo(DirectoryWatchFn())
            | Reshuffle()
            | beam.ParDo(ProcessFilesFn())
        )

        logging.getLogger().setLevel(logging.INFO)
        logging.info("Building pipeline ...")


if __name__ == "__main__":
    run()
```

We can create input files and run the pipeline using the embedded *Flink Runner* as shown below - it does not work with the Python *Direct Runner*.

```bash
python utils/faker_file_gen.py --max_files -1 --delay_seconds 0.5

python chapter7/streaming_file_read.py \
    --runner FlinkRunner --streaming --environment_type=LOOPBACK \
    --parallelism=3 --checkpointing_interval=10000
```

![](streaming-reader-demo.gif#center)
