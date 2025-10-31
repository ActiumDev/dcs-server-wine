# disable core parking (requires reboot)
#powercfg.exe -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
#powercfg.exe -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

# server process priority: Normal, Idle, High, RealTime, BelowNormal, AboveNormal
$proc_priority = "Normal"

# export environment variables required by Benchmark.lua
$gci = Get-ComputerInfo
$env:BENCHMARK_MISSION = "Benchmark_200_v2024.11.23.miz"
$env:BENCHMARK_ROUNDS = 10
$env:BENCHMARK_RUNTIME = 300
$env:OS_NAME = $gci.OsName
$env:OS_VERSION = $gci.OsVersion
$env:WINE_VERSION = ""
$env:CPU_NAME = $gci.CsProcessors.Name
$env:PROC_PRIORITY = $proc_priority
# FIXME: output requires interpretation on non-VM systems, see:
#        https://stackoverflow.com/questions/59489885/identify-if-windows-hosted-on-physical-or-virtual-machine-powershell
$env:VIRTUALIZATION = $gci.CsModel
$env:TACVIEW_ENABLE = 0

# start dedicated server and wait until it exits
$proc = Start-Process .\bin\DCS_server.exe -ArgumentList "-w","DCS.benchmark" -NoNewWindow -PassThru
$proc.PriorityClass = $proc_priority
while (!$proc.WaitForExit(1000)) {
    # periodically cache stats (null after $proc exits)
    $cpu_sys = $proc.PrivilegedProcessorTime.TotalSeconds
    $cpu_user = $proc.UserProcessorTime.TotalSeconds
    $wss = $proc.PeakWorkingSet64
    $cpu_sys, $cpu_user, $wss
}

# print process statistics
# TODO: append to respective Benchmark-*.log
$stats = @{
    "CPU_TIME_SYSTEM" = $cpu_sys
    "CPU_TIME_USER" = $cpu_user
    "RAM_PEAK_BYTES" = $wss
} | ConvertTo-JSON -Compress
Write-Output "# STATS: $stats"

Read-Host "Press any key to exit ..."
