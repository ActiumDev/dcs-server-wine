-- DCS World Benchmark Mode v2025.05.31
-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- TL;DR: This script implements a benchmark mode for the DCS dedicated server.
--        The server must be pre-configured to load any mission for this script
--        to work. If so, this script will load and start a benchmark mission
--        and run it for several rounds until a configurable runtime expires.
--        While the mission runs, the script logs all simulation frame times to
--        %USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Logs\Benchmark-*.log.
--        The mission file, round count and round runtime must be configured
--        via environment variables.
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`

-- get configuration from environment variables
local BENCHMARK_MISSION = os.getenv("BENCHMARK_MISSION")
local BENCHMARK_ROUNDS  = tonumber(os.getenv("BENCHMARK_ROUNDS")) or 10
local BENCHMARK_RUNTIME = tonumber(os.getenv("BENCHMARK_RUNTIME")) or 300

-- get file name of this script
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "nil"

-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
_G.benchmark = {}
-- count of completed benchmark rounds
benchmark.round = 0
-- absolute path of benchmark mission file
benchmark.mission_path = lfs.writedir() .. "Missions\\" .. (BENCHMARK_MISSION or "")
-- restart flag (set when restarting mission for next benchmark round)
benchmark.restart = false

function benchmark.onSimulationStart()
    log.write(_name, log.INFO, string.format("Starting benchmark round %d of %d.", benchmark.round + 1, BENCHMARK_ROUNDS))
    benchmark.logfile:write(string.format("# START: %s,%.03f\n", os.date("!%Y%m%d-%H%M%SZ"), DCS.getRealTime()))

    -- abort if wrong mission is still running after a restart
    if benchmark.restart and DCS.getMissionFilename() ~= benchmark.mission_path then
        log.write(_name, log.ERROR, "Aborting. Invalid mission loaded: " .. DCS.getMissionFilename())
        benchmark.logfile:write(string.format("# FAILED: %s,%.03f\n", os.date("!%Y%m%d-%H%M%SZ"), DCS.getRealTime()))
        DCS.exitProcess()
        return
    end

    -- force load benchmark mission if not currently running
    if DCS.getMissionFilename() ~= benchmark.mission_path then
        benchmark.restart = true
        net.load_mission(benchmark.mission_path)
        return
    end

    -- restart concluded, clear flag
    benchmark.restart = false

    -- unpause server if currently paused
    if DCS.getPause() then
        DCS.setPause(false)
    end

    -- initialize time of previous frame
    benchmark.prev_frame = math.floor(DCS.getRealTime() * 1e3 + 0.5)
    benchmark.time_stop = DCS.getRealTime() + BENCHMARK_RUNTIME
end

function benchmark.onSimulationStop()
    benchmark.logfile:write(string.format("# STOP: %s,%.03f\n", os.date("!%Y%m%d-%H%M%SZ"), DCS.getRealTime()))
    benchmark.logfile:flush()

    -- exit server if not restarting for next benchmark round
    -- NOTE: net.load_mission() incurs onSimulationStop() on running mission
    if not benchmark.restart then
        if benchmark.round >= BENCHMARK_ROUNDS then
            benchmark.logfile:write(string.format("# COMPLETE: %s\n", os.date("!%Y%m%d-%H%M%SZ")))
        end
        benchmark.logfile:close()
        log.write(_name, log.INFO, "Closed benchmark log file: " .. benchmark.logfile_name)
        DCS.exitProcess()
    end
end

function benchmark.onSimulationPause()
    benchmark.logfile:write(string.format("# PAUSE: %s,%.03f\n", os.date("!%Y%m%d-%H%M%SZ"), DCS.getRealTime()))
    benchmark.logfile:flush()

    -- unpause if benchmark runtime has not yet elapsed
    if DCS.getRealTime() < benchmark.time_stop then
        DCS.setPause(false)
        return
    end

    -- increment repetition counter and either restart mission or stop server
    benchmark.round = benchmark.round + 1
    if benchmark.round < BENCHMARK_ROUNDS then
        log.write(_name, log.INFO, "Reloading mission for next benchmark round.")
        benchmark.restart = true
        net.load_mission(benchmark.mission_path)
    else
        log.write(_name, log.INFO, "Benchmark complete. Exiting server.")
        -- NOTE: DCS.stopMission() is irrecoverable before DCS 2.9.12.5336, see:
        --       https://forum.dcs.world/topic/362757-error-asyncnet-server_start-failed-game-already-started/
        --       http://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.12.5336/
        DCS.stopMission()
    end
end

function benchmark.onSimulationResume()
    benchmark.logfile:write(string.format("# RESUME: %s,%.03f\n", os.date("!%Y%m%d-%H%M%SZ"), DCS.getRealTime()))
end

function benchmark.onSimulationFrame()
    local now = DCS.getRealTime()
    if benchmark.prev_frame then
        local now_ms = math.floor(now * 1e3 + 0.5)
        benchmark.logfile:write(string.format("%.0f\n", now_ms - benchmark.prev_frame))
        benchmark.prev_frame = now_ms
    end

    -- pause mission when benchmark runtime has elapsed
    if benchmark.time_stop and now >= benchmark.time_stop and not DCS.getPause() then
        log.write(_name, log.INFO, "Benchmark runtime elapsed. Pausing mission.")
        DCS.setPause(true)
    end
end

-- setup benchmark if enabled via environment variable BENCHMARK_MISSION
if BENCHMARK_MISSION ~= nil then
    -- check if mission file exists
    local mission_file = io.open(benchmark.mission_path, "r")
    if mission_file then
        mission_file:close()
    else
        log.write(_name, log.ERROR, "Aborting. BENCHMARK_MISSION not found: " .. benchmark.mission_path)
        DCS.exitProcess()
        return
    end

    -- open benchmark log file
    local timestamp = os.date("!%Y%m%d-%H%M%SZ")
    benchmark.logfile_name = lfs.writedir() .. "Logs\\Benchmark-" .. timestamp .. ".log"
    benchmark.logfile = io.open(benchmark.logfile_name, "a")
    log.write(_name, log.INFO, "Opened benchmark log file: " .. benchmark.logfile_name)

    -- write benchmark log file header
    local meta = {
        ["TIMESTAMP"] = timestamp,
        ["OS_NAME"] = os.getenv("OS_NAME") or "",
        ["OS_VERSION"] = os.getenv("OS_VERSION") or "",
        ["WINE_VERSION"] = os.getenv("WINE_VERSION") or "",
        ["CPU_NAME"] = os.getenv("CPU_NAME") or "",
        ["PROC_PRIORITY"] = os.getenv("PROC_PRIORITY") or "",
        ["VIRTUALIZATION"] = os.getenv("VIRTUALIZATION") or "",
        ["DCS_VERSION"] = __DCS_VERSION__ or "",
        ["MISSION_FILE"] = benchmark.mission_path,
        ["MISSION_MD5SUM"] = lfs.md5sum(benchmark.mission_path),
        ["TACVIEW_ENABLE"] = os.getenv("TACVIEW_ENABLE") or "",
        ["BENCHMARK_ROUNDS"] = BENCHMARK_ROUNDS,
        ["BENCHMARK_RUNTIME"] = BENCHMARK_RUNTIME
    }
    benchmark.logfile:write("# META: " .. net.lua2json(meta) .. "\n")

    -- register callbacks
    DCS.setUserCallbacks(benchmark)
    log.write(_name, log.WARNING, "Starting server in benchmark mode. Server will exit automatically after last benchmark round.")
    -- NOTE: net.load_mission() has no effect here
    --net.load_mission(benchmark.mission_path)
else
    log.write(_name, log.ERROR, "Skipping benchmark: Environment variable BENCHMARK_MISSION is unset.")
end
