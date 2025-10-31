#!/bin/sh -eu

# if DCS.benchmark writedir does not exist, initialize from template DCS_benchmark
if [ ! -d "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_configs/DCS.benchmark" ] ; then
	cp -a "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_configs/DCS_benchmark" "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_configs/DCS.benchmark"
fi

# retrieve system information
. /etc/os-release
CPU_NAME=$(grep -m1 "^model name" /proc/cpuinfo)
CPU_NAME=${CPU_NAME#*: }

# export environment variables required by Benchmark.lua
export BENCHMARK_MISSION="Benchmark_200_v2024.11.23.miz"
export BENCHMARK_ROUNDS=10
export BENCHMARK_RUNTIME=300
export OS_NAME=$PRETTY_NAME
export OS_VERSION=$(uname -s -r -v)
export WINE_VERSION=$(wine --version)
export CPU_NAME=$CPU_NAME
export PROC_PRIORITY="SCHED_OTHER nice=0"
export VIRTUALIZATION=$(systemd-detect-virt)
export TACVIEW_ENABLE=0

# need headless GUI session to run DCS server
if ! systemctl --user --quiet is-active sway ; then
	exit 1
fi

# redirect new windows to headless GUI session
export $(systemctl --user show-environment | grep -m1 ^WAYLAND_DISPLAY=)

# start DCS server with suppressed log output
cd "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_server"
wine start /b /wait bin/DCS_server.exe -w DCS.benchmark &
sleep 10

# record CPU and RAM usage
python3 <<EOF
import os
from pathlib import Path
import time

SC_CLK_TCK   = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
SC_PAGE_SIZE = os.sysconf(os.sysconf_names["SC_PAGE_SIZE"])

# find process
path_stat = None
for path_pid in Path("/proc").iterdir():
        if not path_pid.stem.isdecimal():
                continue
        cmdline = (path_pid / "cmdline").read_bytes()
        if cmdline.startswith(b"C:\\\\DCS_server\\\\bin\\\\DCS_server.exe\\0-w\\0DCS.benchmark\\0"):
                path_stat = path_pid / "stat"

# poll /proc/PID/stat
rss_max = 0
while path_stat.exists():
	# https://www.man7.org/linux/man-pages/man5/proc_pid_stat.5.html
        stat = path_stat.read_text().split()
        cpu_user = int(stat[13]) / SC_CLK_TCK
        cpu_sys  = int(stat[14]) / SC_CLK_TCK
        rss      = int(stat[23]) * SC_PAGE_SIZE
        if rss > rss_max:
                rss_max = rss
        print(f'# STATS: {{"CPU_TIME_SYSTEM":{cpu_sys},"CPU_TIME_USER":{cpu_user},"RAM_PEAK_BYTES":{rss_max}}}')
        time.sleep(1)
EOF
