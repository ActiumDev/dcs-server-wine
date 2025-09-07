#!/bin/sh -eu

# if DCS.benchmark writedir does not exist, initialize from template DCS_benchmark
if ! -d "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_configs/DCS.benchmark" ; then
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
export $(systemctl --user show-environment | grep -m1 ^DISPLAY=)
export $(systemctl --user show-environment | grep -m1 ^WAYLAND_DISPLAY=)

# start DCS server with suppressed log output
cd "${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_server"
wine start /b /wait bin/DCS_server.exe -w DCS.benchmark
