# retrieve system information
$gci = Get-ComputerInfo

# export environment variables required by Benchmark.lua
$env:BENCHMARK_MISSION = "Benchmark_200.miz"
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

# server process priority: Normal, Idle, High, RealTime, BelowNormal, AboveNormal
$proc_priority = "Normal"

# start dedicated server and wait until it exits
$proc = Start-Process .\bin\DCS_server.exe -ArgumentList "-w","DCS.benchmark" -NoNewWindow -PassThru
$proc.PriorityClass = $proc_priority
$proc.WaitForExit()
