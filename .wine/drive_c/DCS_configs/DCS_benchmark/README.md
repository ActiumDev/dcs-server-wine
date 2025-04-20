# Dedicated Server Benchmarking

Configuration, mission, and scripts for benchmarking the DCS dedicated server.

Use the contents of this folder as a DCS *writedir* configuration template.
The [`Benchmark.lua`](./Scripts/Hooks/Benchmark.lua) script does the heavy
lifting. If configured via environment variables, it will start the benchmark
mode only when the server loads any mission. Thus, an unconfigured server will
not work. Both [`serverSettings.lua`](Config/serverSettings.lua) and
[`Empty.miz`](./Missions/Empty.miz) provide a suitable minimum configuration
(the path in `missionList` probably needs to be adjusted).

Once in benchmark mode, the server will load the mission specified in the
environment variable `BENCHMARK_MISSION` and run it `BENCHMARK_ROUNDS` times
for `BENCHMARK_RUNTIME` seconds each until it automatically exits the server
process. Benchmark results (frame times in milliseconds) are logged to
`Logs/Benchmark-*.log` along with metadata (DCS version, OS version, etc.).
This [`Missions`](./Missions) folder contains several `Benchmark_NUM_*.miz`
sample benchmark missions that throw a total of `NUM` land, sea, and air units
against each other.

This benchmark setup works on Linux and Windows alike. For Linux, see
[`benchmark.sh`](./benchmark.sh) as an example of setting the environment
variables and starting the dedicated server via Wine. For Windows, see
[`benchmark.ps1`](./benchmark.ps1) for a comparable PowerShell script. Both
scripts use `DCS.benchmark` as an appropriately configured *writedir* (see
above).

For comparison, benchmark results are best visualized as a
[complementary cumulative distribution function (CCDF)](https://en.wikipedia.org/wiki/Cumulative_distribution_function#Complementary_cumulative_distribution_function_(tail_distribution)).
The Python script [`benchmark_plot.py`](./benchmark_plot.py) takes multiple
pairs of `Benchmark-*.log` files and plot titles as CLI arguments and generates
a combined CCDF plot. Example:
`./benchmark_plot.py Benchmark-1.log.gz "1st file" Benchmark-2.log.gz "2nd file"`
