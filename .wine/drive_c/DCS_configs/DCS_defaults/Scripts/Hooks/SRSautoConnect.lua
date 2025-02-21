-- DCS World Simplified SRS Server-Side Autoconnect Script v0.2
-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`

-- load LuaSocket HTTP module
if not package.path:match("LuaSocket") then
    package.path  = package.path  .. ";.\\LuaSocket\\?.lua;"
end
if not package.cpath:match("LuaSocket") then
    package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll;"
end
local socket = require("socket"); require("url"); require("http")

-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
_G.srsauto = {}
srsauto.addr = DCS.getConfigValue("srsauto_addr")
srsauto.port = tonumber(DCS.getConfigValue("srsauto_port") or nil)
srsauto.lookup_url = DCS.getConfigValue("srsauto_lookup_url") or "http://checkip.amazonaws.com/"

-- name of this script file (used as logging subsystem name)
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "SRSautoConnect.lua"

-- send auto connect message when player connects or changes slot
local _host_player_id = net.get_server_id and net.get_server_id() or 1
function srsauto.onPlayerConnect(id)
    if srsauto.addr ~= nil and srsauto.addr ~= "auto" and srsauto.port ~= nil and id ~= _host_player_id then
        net.send_chat_to(string.format("SRS Running @ %s:%d", srsauto.addr, srsauto.port), id)
    end
end
srsauto.onPlayerChangeSlot = srsauto.onPlayerConnect

function srsauto.onMissionLoadBegin()
    -- retrieve public IP address. should result in a code 200 "OK" response
    -- with `Content-Type: text/plain` and a response body length of up to 15
    -- characters (IPv4 address + trailing newline)
    -- TODO: implement IPv6 support?
    local body, code, headers, status = socket.http.request(srsauto.lookup_url)
    if code == 200 and type(body) == "string" and body:len() <= 16 then
        srsauto.addr = body:match("^%d?%d?%d%.%d?%d?%d%.%d?%d?%d%.%d?%d?%d")
    else
        srsauto.addr = nil
    end

    if srsauto.addr then
        log.write(_name, log.INFO, string.format(
            "Public IP address lookup succeeded: %s",
            srsauto.addr
        ))
    else
        log.write(_name, log.ERROR, string.format(
            "Public IP address lookup failed: url=%s code=%s body=%s",
            srsauto.lookup_url, tostring(code), body or "nil"
        ))
    end
end

if DCS.isServer() and srsauto.addr ~= nil and srsauto.port ~= nil then
    -- only do public IP address lookup if explicitly enabled
    if srsauto.addr ~= "auto" then
        srsauto.onMissionLoadBegin = nil
    end

    DCS.setUserCallbacks(srsauto)
    log.write(_name, log.INFO, "Enabled SRS auto connect messages.")
else
    log.write(_name, log.WARNING, "Disabled SRS auto connect messages. Not a server instance or autoexec.cfg variables srsauto_addr and/or srsauto_port unset or invalid.")
end
