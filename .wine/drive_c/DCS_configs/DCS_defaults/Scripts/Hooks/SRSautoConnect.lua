-- DCS World Simplified SRS Server-Side Autoconnect Script v2025.11.01
-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- This script implements the server-side autoconnect messages for SRS. It
-- parses the SRS server port from the SRS config file and thus requires no
-- configuration.
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`

-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
_G.srsauto = {}
srsauto.port = nil

-- name of this script file (used as logging subsystem name)
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "SRSautoConnect.lua"

-- send auto connect message when player connects or changes slot
local _host_player_id = net.get_server_id and net.get_server_id() or 1
function srsauto.onPlayerConnect(id)
    if type(srsauto.port) == "number" and id ~= _host_player_id then
        net.send_chat_to(string.format("SRS Running on %d", srsauto.port), id)
    end
end
srsauto.onPlayerChangeSlot = srsauto.onPlayerConnect

if DCS.isServer() then
    -- parse SRS server port from its config
    local _fh = io.open(lfs.writedir() .. "SRS\\server.cfg", "r")
    if _fh ~= nil then
        for line in _fh:lines() do
            port = line:match("^%s*SERVER_PORT=(%d+)")
            if port ~= nil then
                srsauto.port = tonumber(port)
            end
        end
        _fh:close()
    end

    -- register callback
    if srsauto.port ~= nil then
        DCS.setUserCallbacks(srsauto)
        log.write(_name, log.INFO, "Enabled SRS auto connect messages.")
    else
        log.write(_name, log.ERROR, "Disabled SRS auto connect messages. Failed to parse SERVER_PORT in SRS/server.cfg.")
    end
else
    log.write(_name, log.WARNING, "Disabled SRS auto connect messages. Not a server instance.")
end
