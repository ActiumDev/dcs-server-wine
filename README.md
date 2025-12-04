# Dedicated DCS Server w/ SRS on Linux

Currently *experimental* repository of configs and scripts intended to
automatically install and manage multiple DCS and SRS server instances
on a single headless Linux server.


## Features

* Fully automatic installation and upgrades of DCS and SRS
* Plug & Play: DCS and SRS are usable immediately after installation
  * Pre-configured with [reasonable defaults](./.wine/drive_c/DCS_configs/DCS_defaults/Config/)
  * Auto-starts a default mission (Caucasus with dynamic spawns)
  * Ships with [useful helper scripts](./.wine/drive_c/DCS_configs/DCS_defaults/Scripts/Hooks/)
* Minimal overhead: ~200M RAM on Debian 13.0 (kernel + user-space)
  * Built for headless (non-GUI) Linux servers:
    No desktop environment required (e.g., Gnome, KDE, XFCE, ...)
  * Runs Caucasus and Marianas on servers with 8G RAM (more for other terrains)
* Convenient management of all server processes through systemd user services
  (`systemctl --user start|stop|status (dcs-server|srs-server)@serverN`) and
  automatic restart of failed services (including detection and forced restart
  of frozen servers with an unresponsive WebGUI).
* Auto-configured webserver for hassle-free access to DCS windows for
  authentication and updating via [noVNC](https://github.com/novnc/noVNC).
  Also provides direct access to the DCS WebGUI of each server.
* Supports multiple DCS server instances (`DCS_server.exe -w DCS.*`) through
  systemd unit [instances](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#Description)


## Requirements

You must be familiar with Linux command line usage and server administration.
Do not attempt the installation if you lack the required fundamentals!

### Server Hardware

* CPU: Depends. `DCS_server.exe` is multi-threaded but heavily bottlenecked by
  its primary thread. Almost any CPU will do for basic missions, but its
  single-thread performance is of utmost importance to maximize the performance
  ceiling. The included [`FPSmon.lua`](.wine/drive_c/DCS_configs/DCS_defaults/Scripts/Hooks/FPSmon.lua)
  script will warn about performance issues in global chat by default.
* RAM: 8G or **more**. 8G should suffice for a single server instance without
  mods on Caucasus. The sky is the limit once multiple instances, mods, and
  larger terrains are involved. Do not use a disk-backed swap partition, use
  [zram](https://packages.debian.org/stable/systemd-zram-generator) instead.
* Disk: NVMe SSD with >40 GB usable space for a Caucasus-only install.
  Additional terrains will need more space. If you're disk space constrained,
  [transparent file compression](https://btrfs.readthedocs.io/en/latest/Compression.html)
  may be an option.
* Network: 1 Gbps link in a datacenter. At least 100 Mbps at home.

Dedicated server module names and respective installed and download sizes as of
DCS 2.9.22.17913. Note that to install a module, you will temporarily need free
disk space for the sum of both sizes as `DCS_updater.exe` will first download
all files and then unpack the module.

| Module ID                    | Installed (GB) | Download (GB) |
| ---------------------------- | -------------- | ------------- |
| `AFGHANISTAN_terrain`        |           59.7 |          20.7 |
| `CAUCASUS_terrain`           |           11.1 |           4.0 |
| `FALKLANDS_terrain`          |           37.7 |          10.8 |
| `GERMANYCW_terrain`          |           92.1 |          30.5 |
| `IRAQ_terrain`               |           69.3 |          22.8 |
| `KOLA_terrain`               |           66.7 |          19.1 |
| `MARIANAISLANDSWWII_terrain` |            6.4 |           2.2 |
| `MARIANAISLANDS_terrain`     |            9.8 |           2.8 |
| `NEVADA_terrain`             |            7.1 |           2.3 |
| `NORMANDY_terrain`           |           38.4 |          12.7 |
| `PERSIANGULF_terrain`        |           22.7 |           7.9 |
| `SINAIMAP_terrain`           |           45.3 |          15.5 |
| `SUPERCARRIER`               |            0.2 |           0.1 |
| `SYRIA_terrain`              |           37.3 |          12.5 |
| `THECHANNEL_terrain`         |           18.0 |           6.6 |
| `WORLD`                      |           19.2 |          10.3 |
| `WWII-ARMOUR`                |            1.1 |           0.5 |
| **Σ**                        |      **542.4** |     **181.5** |

### Operating System

This has been developed and tested on a Debian 13 "Trixie" server install.
Most Linux distributions that use systemd should work as well, but changes to
accomodate the respective package manager, package names, etc. may be required.
You should enable [automatic updates](https://wiki.debian.org/UnattendedUpgrades)
to keep your server secure.


## Usage Instructions

For brevity, the following instructions rely on these conventions:

* `root@server` is either the root user of the target Linux server or a user
  account with sudo proviliges. Substitute `root` and `server` as required.
* `dcs@server` is a non-privileged user account on the target Linux server that
  will be used to run the DCS and SRS servers. Substitute `dcs` and `server`.

### Local Requirements (for Windows users)

First, install the following software on your local computer (the applications
are suggestions; any program implementing the respective protocol should work):

* Terminal: Do not use the legacy command prompt. Install the official
  [Windows Terminal App](https://aka.ms/terminal).
* SSH client: Recent versions of Windows 10/11 include a
  [built-in SSH client](https://learn.microsoft.com/en-us/windows/terminal/tutorials/ssh).
  Use it. Do not install PuTTY or other 3rd-party SSH clients.
* SFTP client: Required to transfer files (e.g., missions). Windows includes
  [scp](https://learn.microsoft.com/en-us/azure/virtual-machines/copy-files-to-vm-using-scp)
  as a command line client.

### Linux Server Prerequisites (root/sudo privileges required)

Run via `ssh root@server`:

```sh
# Activate i386 architecture (required by Wine) and install dependencies
# TODO: adjust this if your server does not run Debian
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install --no-install-recommends \
	curl git git-lfs lighttpd python3-minimal sway unzip wayvnc wine wine32:i386 wine64
sudo systemctl disable --now lighttpd
# Create a separate user account for the DCS server and enable persistent
# systemd user services for it (exemplary user name, change at will)
sudo useradd -m -s /bin/bash -G render,video dcs
sudo loginctl enable-linger dcs
```

### Installation

Run via `ssh -L 8080:127.0.0.1:8080 dcs@server` (see below for meaning of `-L`):

```sh
# use Git to download all scripts and config files into the home directory
cd ~
git init -b main ~
git remote add origin https://github.com/ActiumDev/dcs-server-wine.git
git pull origin main
git submodule update --init --recursive
# start basic services: minimal GUI, VNC server, webserver
# TODO: replace 5900 with your desired, locally bound VNC port
# TODO: replace 8080 with your desired, locally bound HTTP port
systemctl --user daemon-reload
systemctl --user enable --now sway wayvnc@5900 webserver@8080
```

`dcs@server` now runs the minimal, headless GUI, a VNC server, and a webserver
that provides straightforward VNC and DCS WebGUI access. The connection is
securely authenticated and encrypted via SSH static port forwarding (`-L`).
Open <http://127.0.0.1:8080/vnc/> in a webbrowser to access the VNC server that
should now show an empty desktop with a clock in the top right corner.

Everything is ready for the actual installation. First, decide which terrains
to install from above module table or [this list](https://forum.dcs.world/topic/324040-eagle-dynamics-modular-dedicated-server-installer/).
Then, adjust the `export DCS_TERRAINS=` in below code snippet to contain a
space-separated list of *Install/Uninstall id* from the list, e.g.,
`export DCS_TERRAINS="CAUCASUS_terrain MARIANAISLANDS_terrain"`. The updater
will show an error message popup if the available disk space is insufficient.
Now run via the already open SSH session (`dcs@server`):

```sh
# install DCS
# TODO: set DCS_TERRAINS to space separated list of terrains to install
export DCS_TERRAINS="CAUCASUS_terrain"
~/.wine/drive_c/install_dcs.sh
# optional: install SRS
~/.wine/drive_c/install_srs.sh
```

Via VNC: Watch the DCS Updater progress through the installation and confirm
the final success message. The DCS server will start automatically. When shown
the "DCS Login" window, enter your credentials (best practice: use separate
server account with [purchases restricted](https://forum.dcs.world/topic/338207-restrict-purchases-on-server-account-option/#comment-5347613))
and check both "Save password" and "Auto login" options to enable the DCS
server to start non-interactively in the future.

The VNC session should now show the DCS splash screen. The SRS server should
run as a windowless background service. The DCS server defaults to port 10308
and SRS defaults to port 5002. The server is unlisted (not public) by default.

You can connect to the server by IP address and port. The default mission will
start automatically once the first player connects.

### Access to DCS WebGUI

The webserver also provides remote access to the DCS WebGUI. Simply open
<http://127.0.0.1:8080/DCS.server1/WebGUI/index.html> in your browser.

### Optional: Configuration

Modify `~/.wine/drive_c/DCS_configs/DCS.server1/Config/autoexec.cfg` to suit
your requirements. Additionally, use the WebGUI to conveniently configure the
server settings. Then restart the server for all changes to take effect:
```sh
systemctl --user restart dcs-server@server1
```


## Troubleshooting

### Installation fails with `wine: could not load kernel32.dll, status c0000135`

The WINEPREFIX directory `~/.wine` is broken. Reinitialize and then re-run the
installer as follows:
```sh
export $(systemctl --user show-environment | grep -m1 ^WAYLAND_DISPLAY=)
rm ~/.wine/.update-timestamp
wineboot --init
~/.wine/drive_c/install_dcs.sh
```
