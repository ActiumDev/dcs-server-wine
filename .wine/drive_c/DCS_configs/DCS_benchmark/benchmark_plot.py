#!/usr/bin/python3
# -*- coding: utf-8 -*-
# (c) 2024-2025 Actium

import json
import numpy as np
import matplotlib.pyplot as plt
import sys

def load_frametimes(path: str) -> np.ndarray:
    frame_times = []
    with open(path, "rt") as fh:
        # first line: meta data
        line = fh.readline()
        if not line.startswith("# META:"):
            raise ValueError(f"Not a Benchmark.lua log file: {path}")
        meta = json.loads(line.removeprefix("# META: "))

        # parse frame times (values in integer milliseconds)
        for line in fh:
            if not line.startswith("#"):
                frame_times.append(float(line))

    return meta, np.asarray(frame_times)

for file in sys.argv[1:]:
    # load benchmark log file
    meta, frame_times = load_frametimes(file)
    # sort and reverse times to get complementary cumulative distribution
    frame_times.sort()
    frame_times = frame_times[::-1]

    # compute cumulative sum to get CCDF over total duration and not number of
    # occurences (latter would skew CCDF with few, very large outliers)
    t = np.cumsum(frame_times)
    # normalize to relative duration (fraction of total mission runtime)
    t *= 1./t[-1]

    # plot double logarithmic CCDF
    plt.loglog(t, frame_times, label=meta["OS_NAME"])

# annotate plot
plt.title("Complementary Cumulative Distribution Function")
plt.xlabel("Relative duration of frame time exceeding value")
plt.ylabel("Frame time (ms)")
plt.xlim((1e-4, 1))
plt.ylim((1, 10000))
plt.grid()
plt.legend()
plt.show()
