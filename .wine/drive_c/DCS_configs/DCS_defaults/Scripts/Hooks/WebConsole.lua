-- DCS World Standalone Web Console v2025.11.09
-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com>
-- SPDX-License-Identifier: MIT
--
-- TL;DR: This EXPERIMENTAL script implements an HTTP server that provides
--        access to an interactive web console with syntax highlighting for
--        DCS scripting. Return values are automatically serialized as JSON.
--        The HTTP server can also be used to issue DCS scripting commands
--        non-interactively.
--
-- Install by placing this script in the DCS `Scripts/Hooks` folder, e.g.:
-- `%USERPROFILE%\Saved Games\DCS.dcs_serverrelease\Scripts\Hooks`


-- load LuaSocket module
if not package.path:match("LuaSocket") then
    package.path  = package.path  .. ";.\\LuaSocket\\?.lua;"
end
if not package.cpath:match("LuaSocket") then
    package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll;"
end
local socket = require("socket")

-- callback object, see DCS API documentation for details:
--   * file:///C:/%DCS_INSTALL_PATH%/API/DCS_ControlAPI.html
--   * https://wiki.hoggitworld.com/view/Hoggit_DCS_World_Wiki
_G.webcon = {}
webcon.port = tonumber(DCS.getConfigValue("webconsole_port") or nil) or 8089
webcon.auth = DCS.getConfigValue("webconsole_auth")
webcon.max_length_uri = 512
webcon.max_length_headers = 4096
webcon.max_length_body = 1024*1024

-- name of this script file (used as logging subsystem name)
local _name = debug.getinfo(1, "S").source:match("[^\\]+%.lua$") or "WebConsole.lua"

function webcon.http_client(sock)
    -- TODO: implement as non-blocking coroutine and set zero timeout
    sock:settimeout(1)

    -- receive HTTP request line
    -- https://lunarmodules.github.io/luasocket/tcp.html#receive
    -- NOTE: receive() has no length limit and blocks until (CR)LF or timeout
    local req_line, err, partial = sock:receive()
    -- handle error
    if req_line == nil then
        if err == "timeout" then
            -- TODO: if partial == nil then coroutine.yield() end
            sock:send("HTTP/1.1 408 Request Timeout\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n408 Request Timeout")
        end

        sock:close()
        return
    end

    -- refuse excessively long URIs
    if #req_line > webcon.max_length_uri then
        sock:send("HTTP/1.1 414 URI Too Long\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n414 URI Too Long")
        sock:close()
        return
    end

    -- parse HTTP request line
    -- https://en.wikipedia.org/wiki/HTTP#HTTP/1.1_request_messages  
    local req_method, req_path, req_prot = req_line:match("^([A-Z]+) (/.*) (HTTP/.-)$")
    if req_method == nil then
        sock:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n400 Bad Request")
        sock:close()
        return
    end

    -- we only support HTTP/1.0 and HTTP/1.1
    if req_prot ~= "HTTP/1.0" and req_prot ~= "HTTP/1.1" then
        sock:send("HTTP/1.1 505 HTTP Version Not Supported\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n505 HTTP Version Not Supported")
        sock:close()
        return
    end

    -- receive and parse HTTP request headers
    -- NOTE: no reassembly of partial headers or timeout handling
    local length_headers = 0
    local req_headers = {}
    while true do
        -- receive a single line, with single trailing (CR)LF stripped
        -- https://lunarmodules.github.io/luasocket/tcp.html#receive
        local header_line, err, partial = sock:receive()
        -- handle error
        if header_line == nil then
            if err == "timeout" then
                sock:send("HTTP/1.1 408 Request Timeout\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n408 Request Timeout")
            end
            sock:close()
            return
        end
        
        -- empty line terminates headers
        if #header_line == 0 then
            break
        end

        -- refuse excessively long headers
        length_headers = length_headers + #header_line
        if length_headers > webcon.max_length_headers then
            sock:send("HTTP/1.1 431 Request Header Fields Too Large\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n431 Request Header Fields Too Large")
            sock:close()
            return
        end

        -- validate and parse headers into table
        local name, value = header_line:match("^([%w%-]+):%s*(.+)%s*$")
        if name == nil then
            sock:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n400 Bad Request")
            sock:close()
            return
        end
        -- header field names are case-insensitive, so apply :lower()
        req_headers[name:lower()] = value
    end

    -- HTTP Basic authentication
    -- https://datatracker.ietf.org/doc/html/rfc7617
    if webcon.auth and req_headers["authorization"] ~= "Basic " .. webcon.auth then
        sock:send("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"WebConsole.lua\", charset=\"UTF-8\"\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n401 Unauthorized")
        sock:close()
        return
    end

    -- prepare reponse based on request method
    local resp_code, resp_headers, resp_body = nil, nil, nil
    if req_method == "GET" then
        -- no request body with GET request
        resp_code, resp_headers, resp_body = webcon.http_get(req_path, req_headers)
    elseif req_method == "POST" then
        -- POST request must include Content-Length header
        local content_length = tonumber(req_headers["content-length"])
        if content_length == nil or content_length <= 0 then
            sock:send("HTTP/1.1 411 Length Required\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n411 Length Required")
            sock:close()
            return
        end

        -- refuse unreasonably large request body/payload
        if content_length > webcon.max_length_body then
            sock:send("HTTP/1.1 413 Content Too Large\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n413 Content Too Large")
            sock:close()
            return
        end

        -- receive POST request body
        -- TODO: make interruptible
        local req_body = sock:receive(content_length)

        resp_code, resp_headers, resp_body = webcon.http_post(req_path, req_headers, req_body)
    else
        -- FIXME: HTTP/1.1 does not allow responding 501 to HEAD request
        sock:send("HTTP/1.1 501 Not Implemented\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n501 Not Implemented")
        --sock:send("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n405 Method Not Allowed")
        sock:close()
        return
    end

    -- prepare response status and headers
    local resp_crumbs = {}
    resp_crumbs[#resp_crumbs + 1] = "HTTP/1.1 " .. resp_code
    resp_headers["Connection"] = "close"
    if resp_body ~= nil then
        resp_headers["Content-Length"] = tostring(#resp_body)
    end
    for key, value in pairs(resp_headers) do
        resp_crumbs[#resp_crumbs + 1] = string.format("%s: %s", key, value)
    end
    -- terminate headers with double CRLF
    resp_crumbs[#resp_crumbs + 1] = "\r\n"

    -- send reponse
    sock:send(table.concat(resp_crumbs, "\r\n"))
    if resp_body ~= nil then
        sock:send(resp_body)
    end
    sock:close()
end

function webcon.http_get(req_path, req_headers)
    if req_path == "/" then
        return "200 OK", {["Content-Type"] = "text/html"}, webcon.html
    else
        return "404 Not Found", {["Content-Type"] = "text/plain"}, "404 Not Found"
    end
end

function webcon.http_post(req_path, req_headers, req_body)
    if req_path ~= "/execute" then
        return "404 Not Found", {["Content-Type"] = "text/plain"}, "404 Not Found"
    end

    -- accept application/lua only
    if req_headers["content-type"] ~= "application/lua" then
        return "415 Unsupported Media Type", {["Content-Type"] = "text/plain"}, "415 Unsupported Media Type"
    end

    -- try to compile chunk regardless of execution state (checks syntax)
    local func, err = loadstring(req_body)
    if func == nil then
        return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, "SYNTAX ERROR: " .. err
    end

    -- get lua state (execution environment) from headers, default to "gui"
    local lua_state = req_headers["x-lua-state"] or "gui"

    -- get maximum serialization recursion depth from headers
    local maxdepth = math.huge
    if req_headers["x-max-depth"] ~= nil then
        local num = tonumber(req_headers["x-max-depth"])
        if num ~= nil and num >= 0 then
            maxdepth = num
        end 
    end

    -- execute in local state via pcall()
    if lua_state == "gui" or lua_state == nil then
        -- try to execute compiled function
        local success, result_or_errmsg = pcall(func)
        if success then
            return "200 OK", {["Content-Type"] = "application/json"}, webcon.dump_json(result_or_errmsg, maxdepth)
        else
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, "ERROR: " .. result_or_errmsg
        end

    -- execute in real mission scripting environment via:
    -- net.dostring_in("mission", "return a_do_script(...)")
    elseif lua_state == "*a_do_script" then
        local result, success = net.dostring_in("mission",
            string.format("a_do_script(%q)", table.concat({
                -- FIXME: workaround for broken a_do_script() return value pass-thru
                --        https://forum.dcs.world/topic/372331-a_do_script-return-value-pass-thru-broken-since-29159408/
                --"local success, result = pcall(function () ",
                --req_body,
                --"\nend)\nif success then return webcon.dump_json(result) else return 'ERROR: ' .. result end"
                "webcon.a_do_scriturn(function () ",
                req_body,
                "\nend)"
            }))
        )
        if not success then
            -- net.dostring_in() may return {nil, nil} on client(?), so result could be nil
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, "ERROR: " .. tostring(result)
        end

        -- FIXME: workaround for broken a_do_script() return value pass-thru
        -- read temporary file that contains result
        local tmp = lfs.tempdir() .. "WebConsole.a_do_script.tmp"
        local file, err = io.open(tmp, "r")
        if file == nil then
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, string.format("ERROR: Error opening file %q: %s", tmp, err)
        end
        local result = file:read("*a")
        file:close()
        -- truncate temporary file
        local file, err = io.open(tmp, "w")
        if file == nil then
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, string.format("ERROR: Error opening file %q: %s", tmp, err)
        end
        file:close()

        if not result:match("^ERROR:") then
            return "200 OK", {["Content-Type"] = "application/json"}, result
        else
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, result
        end

    -- execute in different state via net.dostring_in(lua_state, ...)
    else
        local result, success = net.dostring_in(lua_state, table.concat({
            "return webcon.dump_json((function () ",
            req_body,
            "\nend)(), ", tostring(maxdepth), ")"
        }))

        if success then
            return "200 OK", {["Content-Type"] = "application/json"}, result
        else
            -- net.dostring_in() may return {nil, nil} on client(?), so result could be nil
            return "500 Internal Server Error", {["Content-Type"] = "text/plain"}, "ERROR: " .. tostring(result)
        end
    end
end

function webcon.onSimulationResume()
    -- WARNING: !!! ONLY BIND TO 127.0.0.1 AND READ THIS WARNING !!!
    --          The WebConsole can be used to execute arbitrary shell commands
    --          via `os.execute()`. If you require remote WebConsole access,
    --          forward its port via a reverse HTTP(S) proxy or via `ssh -L`.
    --          Also be warned that local requests can originate from other
    --          users or software. Enable HTTP Basic authentication on such
    --          multi-user systems or setup appropriate firewall rules! Basic
    --          authentication is unencrypted and insecure and provides *NO*
    --          protection when used remotely over the network.
    -- WARNING: !!! ONLY BIND TO 127.0.0.1 AND READ THIS WARNING !!!
    webcon.server = assert(socket.bind("127.0.0.1", webcon.port))
    local addr, port, family = webcon.server:getsockname()
    webcon.server:setoption("reuseaddr", true)
    webcon.server:settimeout(0)
    log.write(_name, log.INFO, string.format("Opened socket %s:%d", addr, port))
end

function webcon.onSimulationPause()
    -- unable to process requests when simulation is paused. close socket so
    -- client connections are refused immediately instead of letting requests
    -- backlog, possibly until they time out eventually.
    if webcon.server ~= nil then
        local addr, port, family = webcon.server:getsockname()
        webcon.server:close()
        webcon.server = nil
        log.write(_name, log.INFO, string.format("Closed socket %s:%d", addr, port))
    end
end

-- cleanup when mission is stopped (not just when paused)
webcon.onSimulationStop = webcon.onSimulationPause

function webcon.onSimulationFrame()
    if webcon.server == nil then return end
    local sock, err = webcon.server:accept()
    if sock == nil then return end

    local success, result = pcall(webcon.http_client, sock)
    if not success then
        -- FIXME: must only send error 500 header if no header was sent before
        sock:send("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n" .. result)
        sock:close()
    end
end

function webcon.onMissionLoadEnd()
    -- directly inject code into local state (gui)
    local success, result = pcall(loadstring(webcon.inject))
    if not success then
        log.write(_name, log.ERROR, "Failed to inject code via pcall(): " .. result)
    end

    -- inject code into other states via net.dostring_in()
    for _, state in ipairs({"config", "export", "mission", "scripting", "server"}) do
        local result, success = net.dostring_in(state, webcon.inject)
        if not success then
            log.write(_name, log.ERROR, string.format("Failed to inject code via net.dostring_in(%q, ...): %s", state, result))
        end
    end

    -- inject code into mission scripting environment
    -- TODO: error handling (net.dostring_in() always returns {"", true})
    net.dostring_in("mission", string.format("a_do_script(%q)", webcon.inject))
end

-- register callbacks
if webcon.port and webcon.port >= 1024 and webcon.port <= 65535 then
    DCS.setUserCallbacks(webcon)
end

-- helper code to inject into the Lua states
webcon.inject = [[
if webcon == nil then webcon = {} end

-- mandatory JSON character escape sequences as per RFC8259:
-- https://www.rfc-editor.org/rfc/rfc8259#page-8
local json_escape = {
    ["\000"] = "\\u0000",
    ["\001"] = "\\u0001",
    ["\002"] = "\\u0002",
    ["\003"] = "\\u0003",
    ["\004"] = "\\u0004",
    ["\005"] = "\\u0005",
    ["\006"] = "\\u0006",
    ["\007"] = "\\u0007",
    ["\008"] = "\\b",
    ["\009"] = "\\t",
    ["\010"] = "\\n",
    ["\011"] = "\\u000B",
    ["\012"] = "\\f",
    ["\013"] = "\\r",
    ["\014"] = "\\u000E",
    ["\015"] = "\\u000F",
    ["\016"] = "\\u0010",
    ["\017"] = "\\u0011",
    ["\018"] = "\\u0012",
    ["\019"] = "\\u0013",
    ["\020"] = "\\u0014",
    ["\021"] = "\\u0015",
    ["\022"] = "\\u0016",
    ["\023"] = "\\u0017",
    ["\024"] = "\\u0018",
    ["\025"] = "\\u0019",
    ["\026"] = "\\u001A",
    ["\027"] = "\\u001B",
    ["\028"] = "\\u001C",
    ["\029"] = "\\u001D",
    ["\030"] = "\\u001E",
    ["\031"] = "\\u001F",
    ["\""] = "\\\"",
    ["\\"] = "\\\\"
}

function webcon.keys(_t)
    local keys = {}
    for k, v in pairs do
        keys[#keys+1] = tostring(k)
    end
    return keys
end

function webcon.dump_json(obj, maxdepth, indent, cycle)
    local _type = type(obj)
    -- TYPE: string
    if _type == "string" then
        -- apply all mandatory character escapes (U+0000 thru U+001F, ", and \)
        -- as per [RFC 8259](https://www.rfc-editor.org/rfc/rfc7159#page-8)
        -- NOTE: patterns must not contain embedded zeros (U+0000) in Lua 5.1:
        --       https://www.lua.org/manual/5.1/manual.html#5.4.1
        local escaped = tostring(obj):gsub("[%z\001-\031\"\\]", json_escape)
        -- FIXME: will return invalid JSON string if obj is not valid UTF-8
        return table.concat({'"', escaped, '"'})

    -- TYPE: number
    elseif _type == "number" then
        if obj == math.huge then
            return '[null, "math.huge"]'
        else
            return tostring(obj)
        end

    -- TYPE: boolean
    elseif _type == "boolean" then
        return tostring(obj)

    -- TYPE: nil -> JSON: null
    elseif obj == nil then
        return "null"

    -- TYPE: table -> JSON: list|object
    elseif _type == "table" then
        -- delay function argument handling until needed
        if maxdepth == nil then maxdepth = math.huge end
        if indent == nil then indent = "" end
        if cycle == nil then cycle = {} end

        -- prevent infinite recursion by skipping already dumped tables
        -- TODO: reference objects with numeric ID similarly to inspect.lua:
        --       <https://github.com/kikito/inspect.lua>
        if cycle[obj] ~= nil then
            return string.format('[null, "cycle", %q]', tostring(obj))
        end

        -- do not recurse into tables below maxdepth
        if maxdepth <= 0 then
            return '[null, "maxdepth"]'
        end

        -- will dump table, so add to cycle detection table
        cycle[obj] = true

        -- simultaneously check if table is an array and extract list of keys
        -- to prepare dumping a sorted JSON dictionary (with string-only keys)
        local islist = true
        local keys = {}
        local obj_json = {}
        for k, v in pairs(obj) do
            -- check if array (i.e., consecutive, integer indices)
            if islist and k ~= #keys + 1 then
                islist = false
            end

            -- stringify keys to prepare dumping JSON object (string keys only)
            local key = tostring(k)
            keys[#keys+1] = key
            obj_json[key] = v
        end

        -- increment indent for table contents
        local _indent = indent .. "\t"

        -- buffer for efficient string concatenation
        local buf = {}

        -- dump empty table
        -- NOTE: must be caught or below branch-free removal of trailing commas
        --       will clobber buf
        if #keys == 0 then
            return "{}"
        -- dump array
        elseif islist then
            buf[#buf+1] = "[\n"
            for k, v in ipairs(obj) do
                buf[#buf+1] = _indent .. webcon.dump_json(v, maxdepth - 1, _indent, cycle)
                buf[#buf+1] = ",\n"
            end
            -- overwrite illegal trailing comma with list terminator
            buf[#buf] = "\n" .. indent .. "]"
        -- dump table with sorted, stringified keys
        else
            table.sort(keys)
            buf[#buf+1] = "{\n"
            for k, v in ipairs(keys) do
                buf[#buf+1] = string.format("%s%q: ", _indent, tostring(v))
                buf[#buf+1] = webcon.dump_json(obj_json[v], maxdepth - 1, _indent, cycle)
                buf[#buf+1] = ",\n"
            end
            -- overwrite illegal trailing comma with list terminator
            buf[#buf] = "\n" .. indent .. "}"
        end
        
        -- TODO: benchmark if sharing buffer when recursing improves performance
        return table.concat(buf)

    -- TYPE: function, userdata, thread -> JSON: [null, "description"]
    else
        return string.format("[null, %q]", tostring(obj))
    end
end

function webcon.dump_lua(obj, maxdepth, indent, cycle)
    -- TODO: implement Lua dumping
    error("serialization in Lua format not implemented")
end
]]

webcon.html = [[
<!DOCTYPE html>
<!-- DCS World Standalone Web Console v2025.08.03 -->
<!-- (c) 2024-2025 Actium <ActiumDev@users.noreply.github.com> -->
<!-- SPDX-License-Identifier: MIT -->
<html>
<head>
    <title>DCS WebConsole.lua</title>
    <link rel="icon" type="image/png" sizes="16x16" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAABsUlEQVQ4T2NkwANeaTvwvAbKa1898AWXMkZcEjf1XKsYGRkb/oMU/P/foH5pdxs2tVgNuKvtIveXifk+AxMQgg1g+Mf077+CypVdj9ENwWrAbW1nrf8sLFdRFH/4q6X2cM91ogwAKbqp77me8d+/ALAb/v1fr3Z5VxDRXgApbGBgYNJun/r4PwMjw7XKLFkg/x9JBoAUz1i19RGIzgjzliM5FiAGbIMa4EW6AQamVgY6RqYHQQZdPX/W7vypIxeJ9oKasaUGFwvzMUYGRkFILDK8//f3n+WlM0dvYo2Fa5q2kixsXMsY//9n/cn4tzaG/VcvIyODIbLi//+Zzl84ddAEFCfI4owJCgocV8VkjvAxMBkDA5zh2/9/n34wMvKh2wSOTYb/Txn+M4INALrqyZd3zx0Z9czNZWTkNB4LS0hAkx2u8EYVf/PiOcPjRzdlwQYwM7BBkyjEHhBiAjJBVkFFILpBGQMp7f5l+CXLqG5oLcXFxgR0GlQF0PPYALJemKE//jBIgVUbmFpXMjAy1QOtYAPmwFXA3PcUqymMjNL///8PAzrj17///xovnT7aDgAbT5Km0Wfc6wAAAABJRU5ErkJggg==">
    <link rel="icon" type="image/png" sizes="32x32" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAADpElEQVRYR+WXXUhTURzA/+fcze8IVw9hEJZZjqUObKuphVRqWSARJBKUL1KQ0UNBT75Ij75FEfaQENHHU0VGmVGBLnUt3WzpTM2CoocsJTV1u+f0v/u8c9e5O7CgztO95+P///0/77kE/vIgiernRaB1z+/XA3hgOnlycLvd7klEVkIAQwXlZymQRiBkTUDpNwq8abOj/ZJaCNUAw4XljQC0SUkRY7wxb6D9ohoIVQDuwj3rCdeOAYGksBKOjwExHObZPNuU5376JV4IdQAFFScIIa2xhKPA47mOJzdWBiC/soFQiBlnwvnpXGf7lRUBGM6v2A2UvIwlnIO4a6ujo3NFADDa5H1hZTcKNysq4LwHrbdgGKTEiGuoygFJ4qhh3wZRoI+RRR/MvYCmdx6veMDg6vgUl+bAJtUA0rkP2WUp7uoyW+r3yW3S+4wu863+/nPTxvEXc2qUS3sTApAOXr370EqAWKRnDvzVqaOHitUq/5cACHqg6n/2gIA5cOQP50DztZu9VBBMUiIxUbSdrz+m3BuWyUzVVWAwGDK06brbhMBBv2wqIQDn0MbmpmqcTueMmmpQBYDKk5LSMx/hPWCvkhLG+TPvzI8ql8u1EC+EKgDjjtIWrP16v83KgzPe0m/rPJkQwOuiIm36gu6MRkOzQPSiW6lXBH5TP9AxUGgqqaGE3ELrFaADSEjF8XOIo9Zh67oTD0SEsMH88joNpdcjvyS8v1YzUcKEtFHsm+uihUrKxcimyuErFWdz7Hb77HIQIQCjqbhOB5oLa4HlAQihcx7gs+OEjaDlBeGUixYruxf5Fzl3ACMzvhyVHUTv4OWVtfbbrK3StA/AaNyZTZK1I/iImpUiHJzDro9H/NRLZUJwXrYeRQfi3IKYM9hn/eiTlW8utqzKWG3VG4uAULzvBqCjz8VwaKzMDFgqyWOMwZDjDfycnrI4e7q6QwBpKWnW7C16oDTs/lh2LhdbxXWJgIswNjwEv+Zn5QBmi4akWhHPH5SoPI/fF4t3hoMXKVYEFukBDRGsYepgHQRJ8LcDKz/MJVcTP5zcK1EAAgIQWWJFhjT8tnSoYyZdVEQiALAEjYQKfUvHVSacocVUjppQNkhlauzr7XSEfGw0lz5AUVXY6FS1Z19P9tW6QihCa7LgYiPAt7b+3s5qqSgilKEnTFiG9zBdsnxHGHgZ5c0cPJeXtHMCV4K/qIs2CVzbgA3sHE5rfIiUf/Z42WGXzWoLbv0NaLJqMDWo9KsAAAAASUVORK5CYII=">
    <style>pre:has(> code.error) { background: #402020; }</style>
    <!-- ACE is optional: remove the subsequent <script> tag to use the web console without syntax highlighting -->
    <script src="https://cdn.jsdelivr.net/npm/ace-builds@1/src-min-noconflict/ace.js"></script>
</head>
<body style="color-scheme: dark; color: #ffffff; background-color: #202020;">
<label for="lua_state" title="Environment (so called Lua state) in which code will be executed" style="text-decoration: underline; text-decoration-style: dotted;">Environment:</label>
<select name="lua_state" id="lua_state">
    <option value="*a_do_script" selected="selected">*a_do_script (mission scripting)</option>
    <option value="config">config</option>
    <option value="export">export</option>
    <option value="gui">gui (hooks)</option>
    <option value="mission">mission (editor, triggers)</option>
    <option value="scripting">scripting (undocumented)</option>
    <option value="server">server (undocumented)</option>
</select>
<label for="format" title="The return value of the executed code is serialized into this format (Lua not yet implemented)" style="text-decoration: underline; text-decoration-style: dotted;">Format:</label>
<select id="format" name="format">
    <option value="application/json">JSON</option>
    <option value="application/lua" disabled="disabled">Lua</option>
</select>
<label for="maxdepth" title="Maximum depth of return value serialization (deeper values are truncated)" style="text-decoration: underline; text-decoration-style: dotted;">Max depth:</label>
<input type="number" id="maxdepth" name="maxdepth" size="3" min="-1" value="-1">
<input type="submit" id="btn_exec" value="Execute" onclick="exec_or_cancel();" />
<br />
<textarea id="editor" rows="20" cols="100">return 42</textarea>
<br />
<label for="lua_state">Result:</label>
<input type="submit" value="Clear" onclick="set_result(&quot;&quot;, null);" title="Clear result text" />
<input type="submit" value="Open" onclick="popup();" title="Open serialized result in a new window (e.g., JSON inspector in Chrome/Firefox)" />
<input type="submit" value="Save" onclick="save();" title="Save serialized result into a file" />
<pre id="result"></pre>
<script>
const button    = document.getElementById("btn_exec");
const lua_state = document.getElementById("lua_state");
const format    = document.getElementById("format");

// attempt to replace plain <textarea> with ACE editor, but fail gracefully
const editor = typeof ace === "object" ? ace.edit("editor") : document.getElementById("editor");
if (typeof ace === "object") {
    editor.setTheme("ace/theme/tomorrow_night_bright");
    editor.session.setMode("ace/mode/lua");
    editor.setOption("maxLines", Infinity);
    editor.setOption("minLines", 20);
} else {
    console.warn("Loading ACE editor failed, falling back to plain <textarea>.");
}

// attempt to replace plain <pre> with read-only ACE for syntax highlighting
const result = typeof ace === "object" ? ace.edit("result") : document.getElementById("result");
if (typeof ace === "object") {
    result.setTheme("ace/theme/tomorrow_night_bright");
    result.session.setMode("ace/mode/json");
    result.setOption("maxLines", Infinity);
    result.setOption("minLines", 20);
    result.setReadOnly(true);
} else {
    console.warn("Loading ACE editor failed, falling back to plain <pre>.");
}

const xhr = new XMLHttpRequest();
xhr.timeout = 30000;

xhr.onprogress = function (progress) {
    button.value = "Cancel (" + (progress.loaded / 1024).toFixed() + "/"
                              + (progress.total  / 1024).toFixed() + " K)";
}

xhr.onload = function () {
    // server-side success
    if (xhr.status === 200) {
        set_result(xhr.responseText, xhr.getResponseHeader("Content-Type"));
    // network error
    } else if (xhr.status === 0) {
        console.error("XMLHttpRequest failed (network error).");
        set_result("ERROR: Unknown network error occurred (no response from server). Try to refresh (F5) and/or investiage with the developer tools of your browser (F12).", null);
    // server-side error
    } else {
        const error = xhr.status + " " + xhr.statusText
        console.error("Server-side error: " + xhr.status + " " + xhr.statusText);
        set_result("ERROR: A server-side error occurred (" + error + "). %USERPROFILE%/Saved Games/DCS.*/Logs/dcs.log may contain additional information.\n" + xhr.responseText, null);
    }
}

xhr.onaborted = function () {
    console.warn("XMLHttpRequest cancelled upon user request.");
    set_result("ERROR: Request cancelled upon user request.", null);
}

xhr.onerror = function () {
    console.error("XMLHttpRequest failed.");
    set_result("ERROR: Unknown client error. Check your browser console (Chrome/Firefox hotkey: F12).", null);
}

xhr.ontimeout = function () {
    console.error("XMLHttpRequest timed out.");
    set_result("ERROR: Request timed out", null);
}

xhr.onloadend = function () {
    // always reset button after XHR completed (regardless of success/failure)
    button.value = "Execute";
}

// get code from source code editor (ACE or <textarea>)
function get_code() {
    if (typeof ace === "object") {
        return editor.getValue();
    } else {
        return editor.value;
    }
}

// set result (read-only ACE or <pre>)
function set_result(text, type) {
    // truncate result to prevent browser stall
    if (text.length > 131072) {
        text = text.substring(0, 131072) + "\n<TRUNCATED>"
    }

    if (typeof ace === "object") {
        result.setValue("");
                if (type === "application/json") {
            result.session.setMode("ace/mode/json");
        } else if (type === "application/lua") {
            result.session.setMode("ace/mode/lua");
        } else {
            result.session.setMode("ace/mode/text");
        }
        result.setValue(text);
                result.clearSelection();
    } else {
        result.textContent = text;
    }
}

function exec_or_cancel() {
    // abort running request
    if (button.value.startsWith("Cancel")) {
        xhr.abort();
        return;
    }

    // send new request
    xhr.open("POST", "execute", true);
    xhr.setRequestHeader("Accept", format.value);
    xhr.setRequestHeader("Content-Type", "application/lua");
    xhr.setRequestHeader("X-Lua-State", lua_state.value);
    xhr.setRequestHeader("X-Max-Depth", maxdepth.value);
    xhr.send(get_code());

    button.value = "Cancel (0/?)";
    set_result("", null);
}

function popup() {
    const blob = new Blob([xhr.responseText], {type: xhr.getResponseHeader("Content-Type")});
    const url = URL.createObjectURL(blob);
    window.open(url);
    setTimeout(function () {URL.revokeObjectURL(url)}, 1000);
}

function save() {
    // create new <a> with download file name depending on reponse content-type
    const a = document.createElement("a");
    a.download = "DCS_WebConsole_result_" + Date.now().toFixed();
    if (xhr.getResponseHeader("Content-Type") === "application/json") {
        a.download += ".json";
    } else if (xhr.getResponseHeader("Content-Type") === "application/lua") {
        a.download += ".lua";
    } else {
        a.download += ".txt";
    }

    // create temporary object URL containing response
    const blob = new Blob([xhr.responseText], {type: xhr.getResponseHeader("Content-Type")});
    a.href = URL.createObjectURL(blob);
    a.click();

    // cleanup
    setTimeout(function () {URL.revokeObjectURL(a.href)}, 1000);
    delete a;
}
</script>
</body>
</html>
]]
