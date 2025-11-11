#!/usr/bin/python3
# (c) 2025 Actium <ActiumDev@users.noreply.github.com>
# SPDX-License-Identifier: MIT

"""
Modify DCS Dedicated Sever WebGUI/js/app.js to enable use of WebGUI through a reverse proxy:
https://forum.dcs.world/topic/378083-webgui-over-reverse-proxy-invalid-url-for-encryptedrequest/
Not feasible as a .patch, because app.js contains obfucasted/minified code without line breaks.
"""

import pathlib
import sys

path_app_js = pathlib.Path.home() / ".wine/drive_c/DCS_server/WebGUI/js/app.js"

# read current app.js
with open(path_app_js, "rb") as fh:
	app_js = fh.read()

# exit if app.js has already been modified
if b'dynamicUrl:"http://127.0.0.1\\\\:8088/encryptedRequest"' not in app_js:
	print(f"Skipping already modified {path_app_js}.")
	sys.exit(0)

# remove occurences of absolute /encryptedRequest paths
app_js = app_js.replace(b'dynamicUrl:"http://127.0.0.1\\\\:8088/encryptedRequest"',
                        b'dynamicUrl:"encryptedRequest"')
app_js = app_js.replace(b'if(e.url.includes("file:///")||e.url.includes("localhost"))',
                        b'if(true)')
app_js = app_js.replace(b'"http://".concat(e.address,":").concat(e.port,"/encryptedRequest")',
                        b'window.location.protocol==="file:"?"http://".concat(e.address,":").concat(e.port,"/encryptedRequest"):"encryptedRequest"')

# TODO: fix broken screenshot function (and remove absolute paths while at it)
# https://forum.dcs.world/topic/378723-webgui-screenshot-function-broken/

# move original file and write modified app.js
path_app_js.replace(path_app_js.with_suffix(".js~"))
with open(path_app_js, "wb") as fh:
	fh.write(app_js)
print(f"Modified {path_app_js}.")
