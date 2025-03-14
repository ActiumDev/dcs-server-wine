#!/usr/bin/python3

import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time

# first and only CLI argument: DCS writedir (DCS_server.exe -w writedir)
writedir = sys.argv[1]

# verify that writedir exists
path_wdir = Path(os.getenv("WINEPREFIX") or os.getenv("HOME") + "/.wine") \
          / "drive_c" / "users" / (os.getenv("USER") or os.getenv("USERNAME")) \
          / "Saved Games" / writedir
if not path_wdir.exists():
    raise FileNotFoundError(f"DCS writedir not found: {path_wdir!s}")

# get paths to autoexec.cfg and network.vault
path_autoexec = path_wdir / "Config" / "autoexec.cfg"
path_vault = path_wdir / "Config" / "network.vault"

# try to parse webgui_port from autoexec.cfg, fall back to 8088
try:
    m = re.match(r"^\s*webgui_port\s*=\s*(\d+)\b", path_autoexec.read_text(),
                 re.MULTILINE)
    webgui_port = int(m.group(1)) if m else 8088
except FileNotFoundError:
    webgui_port = 8088

num_failures = 0
while True:
    time.sleep(15)

    # missing network.vault implies that server will block on DCS Login
    # window and no amount of restarting will help
    if not path_vault.exists():
        continue

    # query WebGUI
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        sock.connect(("127.0.0.1", webgui_port))
        # send a valid encrypted request as issued by WebGUI/app.js.
        # NOTE: b"GET / HTTP/1.1\r\nConnection: close\r\n\r\n" will detect that
        #       a dedicated server failed to start (stuck on error popup).
        #       however, the dedicated server will continue to respond normally
        #       even if its simulation is hung/frozen (e.g., infinite loop in
        #       `onSimulationFrame()`). same applies to querying the UDP port.
        #       only valid encrypted requests time out as of DCS 2.9.13.6816.
        sock.send(b"POST /encryptedRequest HTTP/1.1\r\n" +
                  b"Connection: close\r\n" +
                  b"Content-Length: 85\r\n" +
                  b"Content-Type: application/json\r\n\r\n" +
                  b'{"ct":"/E5LnS99K/cq4BfuE9SwhgOVyvoFAD1FoJ+N0GhmhKg=","iv":"rNuGPsuOIrY4NogYU01HIw=="}')
        resp = sock.recv(128)

        # server is up and running if it replies with any HTTP response
        if resp.startswith(b"HTTP/"):
            num_failures = 0
        else:
            num_failures += 1
            print(f"Invalid response from server: {resp}", flush=True)
    except (ConnectionError, TimeoutError) as e:
        num_failures += 1
        print(f"No response from server: {e}", flush=True)
    finally:
        sock.close()

    # break after 3 consecutive failures
    if num_failures >= 3:
        print(f"Terminating after 3 missed responses.", flush=True)
        break

# we are a canary: exiting signals systemd to restart the dedicated server
