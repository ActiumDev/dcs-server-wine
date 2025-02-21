-- DCS World Mision Scripting Error Popup Server Freeze Prevention Script v0.2
-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- TL;DR: This script disables the mission scripting error message popups on
--        servers to prevent a potentially irrecoverable server-only freeze.
--        Optionally, it will send error messages to global chat.
--
-- DCS World defaults to open error message popups if an error occurs in the
-- mission scripting environment. These popups freeze the simulation until each
-- popup is closed manually. The dedicated server `DCS_server.exe` is also
-- affected. A mission scripting error triggers a popup on the server, which
-- stalls the server. From a client perspective, this freezes all units except
-- for the local client. As no client-side error messages are displayed, the
-- frozen/stalled server condition cannot be detected by clients. The WebGUI
-- will also be unresponsive. Without direct or remote (RDP/VNC) access to the
-- server, which is not available for most if not all managed servers, this 
-- issue is irrecoverable without support intervention or a server restart.
--
-- The error popups can be disabled via `env.setErrorMessageBoxEnabled(false)`
-- in the mission editor. However, this must be done in each mission with an
-- appropriate `MISSION START` trigger. As this approach hampers debugging, it
-- would necessitate separate mission files for production and debugging.
--
-- This script runs `env.setErrorMessageBoxEnabled(false)` inside the mission
-- scripting environment after a mission has been loaded via a server-side hook
-- script, obviating the need to explicitly disable the popups in each mission.
-- By default, mission scripting error messages will be sent to global chat to
-- facilitate debugging and/or to notify clients that a server-side scripting
-- error has occurred, as it may or may not affect the playability of the
-- current mission. When disabling this feature, mission scripting errors will
-- only be logged to `Logs/dcs.log` (default DCS behavior).
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`


-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
local noerrpopup = {}
noerrpopup.logidx = 0
-- send no error messages to global chat (boolean: true|false)
noerrpopup.mute = DCS.getConfigValue("noerrpopup_mute") and true or false

-- name of this script file (used as subsystem name for logging)
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "NoErrPopup.lua"

function noerrpopup.onMissionLoadEnd()
    -- NOTE: DCS.isMultiplayer() always returns false when called too early
    --if not DCS.isMultiplayer() then return end
    net.dostring_in("mission", string.format("a_do_script(%q)",
        "env.setErrorMessageBoxEnabled(false); env.warning('Disabled mission scripting error message popups via `env.setErrorMessageBoxEnabled(false)`. Check this log file for script errors!')"
    ))
end

function noerrpopup.onSimulationResume()
    -- disable again to override missions explicitly enabling in start trigger
    net.dostring_in("mission", string.format("a_do_script(%q)",
        "env.setErrorMessageBoxEnabled(false)"
    ))
end

function noerrpopup.onSimulationFrame()
    local _loghist, _logidx = DCS.getLogHistory(noerrpopup.logidx)
    if _logidx == noerrpopup.logidx then
        return
    end

    noerrpopup.logidx = _logidx
    for _idx, _log in pairs(_loghist) do
        local _abstime, _level, _subsystem, _message = unpack(_log)
        if _level == log.ERROR and _subsystem == "SCRIPTING" then
            net.send_chat(_message, true)
        end
    end
end

-- register callbacks if this is a server instance
-- NOTE: DCS.isMultiplayer() returns false on initialization
if DCS.isServer() then
    -- remove onSimulationFrame() callback when muted
    if noerrpopup.mute then
        noerrpopup.onSimulationFrame = nil
    end
    DCS.setUserCallbacks(noerrpopup)
    log.write(_name, log.WARNING, "Registered callbacks to disable mission scripting error message popups. Check this log file for script errors!")
else
    log.write(_name, log.INFO, "This is not a server. Not disabling mission scripting error message popups.")
end
