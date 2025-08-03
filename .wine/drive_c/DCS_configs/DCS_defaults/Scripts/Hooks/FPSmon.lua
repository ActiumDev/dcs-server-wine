-- DCS World Server Simulation Frame Rate Monitoring Script v2025.08.03
-- (c) 2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- TL;DR: This script sends warnings messages to global chat if the server
--        simulation frame rate or peak frame time falls below or exceeds
--        configurable thresholds to help identify situations where low server
--        performance may cause excessive lag.
--
-- The simulation frame rate of the DCS server may deteriorate rapidly when the
-- server is overloaded. Particularly missions with many actively engaged units
-- exchanging shots may cause extreme frame times (far) in excess of 1 second.
-- Low server simulation frame rates will limit the update rate of units other
-- than the own on every client. While DCS clients extrapolate server frames
-- for smooth movement of other units, extrapolation has its limits. When the
-- DCS extrapolator is pushed beyond its limits, units move smoothly (on a
-- continuously differentiable line), then jump suddenly, only to move smoothly
-- again afterwards. Reasons include network issues (high ping or packet loss)
-- or excessive server simulation frame times. Whereas ping is shown in the
-- player list, DCS includes no metric or mechanism to warn about server
-- performance issues (low frame rate and high frame times). The WebGUI does
-- not issue direct warnings either. However, it does serve as a canary by
-- updating/responding sluggishly if the server is extremely overloaded.
--
-- This script periodically checks the average server simulation frame rate and
-- peak frame time within a configurable interval (defaults to 30 seconds).
-- If the frame rate falls below or the frame time exceeds their respective,
-- configurable threshold, a warning message including both values is sent to
-- global chat and also logged to the default DCS log file (`Logs/dcs.log`).
-- The chat messages are also visible in the WebGUI. Optionally, every periodic
-- measurement can be logged by enabling FPSMON_VERBOSE (see below).
--
-- The intention behind this script is to help both mission development and
-- deployment. During development, mission designers and server administrators
-- to identify performance bottlenecks early on. If frame times grow too high,
-- the mission must be simplified or the server hardware must be upgraded.
-- In deployment, the script transparently informs and warns players of server
-- performance issues, to faciliate pinpointing the cause of laggy units.
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`

-- configuration via autoexec.cfg or the value after "or" as fallback:
-- measurement and message interval (seconds), use zero (0) to disable
local FPSMON_INTERVAL = tonumber(DCS.getConfigValue("fpsmon_interval") or nil) or 30
-- always log frame rate and peak frame time (even when within threshold)
local FPSMON_VERBOSE = DCS.getConfigValue("fpsmon_verbose") and true or false
-- FPS (Hz) and frame time (seconds) thresholds to send and log warning messages
local FPSMON_WARN_FPS = tonumber(DCS.getConfigValue("fpsmon_warn_fps") or nil) or 5
local FPSMON_WARN_TIME = tonumber(DCS.getConfigValue("fpsmon_warn_time") or nil) or 0.5


-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
local fpsmon = {}
-- DCS.getRealTime() of first frame in averaging interval
fpsmon.time_first_frame = math.huge
-- DCS.getRealTime() of previous frame in averaging interval
fpsmon.time_prev_frame = math.huge
-- peak frame time encountered in averaging interval (seconds)
fpsmon.peak_frame_time = 0
-- number of simulation frames since time_first_frame
fpsmon.num_frames = 0

-- name of this script file (used for automatically prefixing log entries)
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "FPSmon.lua"

-- reset averaging interval when starting or resuming mission
function fpsmon.onSimulationStart()
    fpsmon.num_frames = 0
    fpsmon.peak_frame_time = 0
    fpsmon.time_first_frame = DCS.getRealTime()
    fpsmon.time_prev_frame = fpsmon.time_first_frame
end
fpsmon.onSimulationResume = fpsmon.onSimulationStart

function fpsmon.onSimulationFrame()
    local _time_now = DCS.getRealTime()

    -- increment frame counter
    fpsmon.num_frames = fpsmon.num_frames + 1

    -- compute _frame_time
    local _frame_time = _time_now - fpsmon.time_prev_frame
    -- ignore peak frame time immediately after game start
    if _frame_time > fpsmon.peak_frame_time and DCS.getModelTime() > 10 then
        fpsmon.peak_frame_time = _frame_time
    end
    fpsmon.time_prev_frame = _time_now

    -- process results only every FPSMON_INTERVAL seconds
    -- NOTE: onSimulationFrame() may fire while mission is still paused
    if _time_now > fpsmon.time_first_frame + FPSMON_INTERVAL and not DCS.getPause() then
        local _avg_fps = fpsmon.num_frames / (_time_now - fpsmon.time_first_frame)

        -- send chat message and log warning when above/below threshold
        if _avg_fps < FPSMON_WARN_FPS or fpsmon.peak_frame_time > FPSMON_WARN_TIME then
            net.send_chat(string.format("FPSmon WARNING: avg_fps=%.02f peak_frame_time=%.03f", _avg_fps, fpsmon.peak_frame_time), true)
            log.write(_name, log.WARNING, "avg_fps=%.02f peak_frame_time=%.3f", _avg_fps, fpsmon.peak_frame_time)
        -- always write log entry when verbose
        elseif FPSMON_VERBOSE then
            log.write(_name, log.INFO, "avg_fps=%.02f peak_frame_time=%.3f", _avg_fps, fpsmon.peak_frame_time)
        end

        -- restart averaging interval
        fpsmon.num_frames = 0
        fpsmon.peak_frame_time = 0
        fpsmon.time_first_frame = _time_now
    end
end

-- register callbacks if this is a server/singleplayer instance
if DCS.isServer() and FPSMON_INTERVAL >= 1 then
    DCS.setUserCallbacks(fpsmon)
    log.write(_name, log.INFO, "Enabled simulation frame rate monitoring.")
elseif not DCS.isServer() then
    log.write(_name, log.INFO, "Not enabling simulation frame rate monitoring: Not a server or a singleplayer instance.")
else
    log.write(_name, log.INFO, "Not enabling simulation frame rate monitoring: Disabled via fpsmon_interval variable in autoexec.cfg.")
end
