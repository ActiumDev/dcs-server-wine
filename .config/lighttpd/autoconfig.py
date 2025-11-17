#!/usr/bin/python3

"""
Auto-generate a Lighttpd config for all DCS writedirs ~/.wine/drive_c/DCS_configs/DCS.*
by parsing ports and settings from the relevant configuration files.
"""

import json
import pathlib
import re

path_configs = pathlib.Path.home() / ".wine/drive_c/DCS_configs"
re_webconsole_port = re.compile(r"^\s*webconsole_port\s*=\s*(-?\d+)", re.MULTILINE)
re_webgui_port = re.compile(r"^\s*webgui_port\s*=\s*(\d+)", re.MULTILINE)

# parse all server configurations
servers = {}
for path_writedir in path_configs.glob("DCS.*"):
	# ignore benchmark and backup writedirs
	if path_writedir.name == "DCS.benchmark" or path_writedir.name.endswith("~"):
		continue

	autoexec = (path_writedir / "Config/autoexec.cfg").read_text()

	# parse webgui_port from autoexec.cfg
	match = re_webgui_port.search(autoexec)
	if match:
		webgui_port = int(match.group(1))
	else:
		webgui_port = 8088

	# parse webconsole_port from autoexec.cfg
	match = re_webconsole_port.search(autoexec)
	if match:
		webconsole_port = int(match.group(1))
		if webconsole_port < 0:
			webconsole_port = None
	else:
		webconsole_port = 8089

	# parse Olympus/olympus.json
	try:
		with open(path_writedir / "Olympus/olympus.json", "rt") as fh:
			olympus_json = json.load(fh)
		olympus_port = int(olympus_json["frontend"]["port"])
	except (FileNotFoundError, KeyError):
		olympus_port = None
		pass

	servers[path_writedir.name] = {
		"webgui_port": webgui_port,
		"webconsole_port": webconsole_port,
		"olympus_port": olympus_port
	}

# assemble Lighttpd configuration
cfg = []

# aliases for WebGUI and Tacview files
cfg.append("# aliases for WebGUI and Tacview files")
cfg.append("alias.url += (")
for name, config in servers.items():
	cfg.append(f'\t"/{name}/WebGUI/" => env.HOME + "/.wine/drive_c/DCS_server/WebGUI/",')
	cfg.append(f'\t"/{name}/Tacview/" => env.HOME + "/.wine/drive_c/DCS_configs/{name}/Tacview/",')
cfg.append(")\n")

# WebGUI reverse proxy
cfg.append("# WebGUI reverse proxy")
for name, config in servers.items():
	if config["webgui_port"] is None:
		cfg.append(f"# {name} missing (valid) webgui_port")
		continue

	name_re = re.escape(name)
	cfg.append(
		f'$HTTP["url"] =~ "^/{name_re}/WebGUI/(encryptedRequest|screenshots)" {{\n'
		f'\tproxy.server = ( "" => (( "host" => "127.0.0.1", "port" => "{config["webgui_port"]}" )))\n'
		f'\tproxy.header = ( "map-urlpath" => ( "/{name}/WebGUI/" => "/" ))\n}}'
	)
cfg.append("")

# WebConsole.lua reverse proxy
cfg.append("# WebConsole.lua reverse proxy")
for name, config in servers.items():
	if config["webconsole_port"] is None:
		cfg.append(f"# {name} missing (valid) webconsole_port")
		continue

	name_re = re.escape(name)
	cfg.append(
		f'$HTTP["url"] =~ "^/{name_re}/WebConsole/" {{\n'
		f'\tproxy.server = ( "" => (( "host" => "127.0.0.1", "port" => "{config["webconsole_port"]}" )))\n'
		f'\tproxy.header = ( "map-urlpath" => ( "/{name}/WebConsole/" => "/" ))\n}}'
	)
cfg.append("")

# Olympus reverse proxy
cfg.append("# Olympus reverse proxy")
for name, config in servers.items():
	if config["olympus_port"] is None:
		cfg.append(f"# {name} missing (valid) Olympus frontend port")
		continue

	name_re = re.escape(name)
	cfg.append(
		f'$HTTP["url"] =~ "^/{name_re}/Olympus/" {{\n'
		f'\tproxy.server = ( "" => (( "host" => "127.0.0.1", "port" => "{config["olympus_port"]}" )))\n'
		f'\tproxy.header = ( "map-urlpath" => ( "/{name}/Olympus/" => "/" ))\n}}'
	)
cfg.append("")

print("\n".join(cfg))
