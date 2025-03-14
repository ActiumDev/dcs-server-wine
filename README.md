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
* Minimal overhead: ~200M RAM on Debian 12.9 (kernel + user-space)
  * Built for headless (non-GUI) Linux servers:
    Does not require a desktop environment (e.g., Gnome, KDE, XFCE, ...)
  * DCS and SRS windows accessible via VNC (serves minimal GUI)
  * Runs Caucasus, Marianas, and Syria on servers with 16G RAM (other terrains unverified)
* Convenient management of all server processes through systemd user services
  (`systemctl --user start|stop|status dcs-server|srs-server`) and automatic
  restart of failed services (to the extent DCS enables it ...).
* Supports multiple DCS server instances (`DCS_server.exe -w DCS.*`) through
  systemd unit [instances](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#Description1~https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#Description1~https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#Description)


## Requirements

You must be familiar with Linux command line usage and server administration.
Do not attempt the installation if you lack the required fundamentals!

### Server Hardware

* CPU: Depends. `DCS_server.exe` is multi-threaded but heavily bottlenecked by
  its primary thread. Almost any CPU will do for basic missions, but its
  single-thread performance is of utmost importance to maximize the performance
  ceiling. The included `FPSmon.lua` script will warn about performance issues.
* RAM: 16G or **more**. 16G should suffice for a single server instance without
  mods on Caucasus. The sky is the limit once multiple instances, mods, and
  larger terrains are involved.
* Disk: NVMe SSD with >40 GB usable space for a Caucasus-only install.
  Additional terrains will need more space. If you're disk space constrained,
  [transparent file compression](https://btrfs.readthedocs.io/en/latest/Compression.html)
  may be an option.
* Network: 1 Gbps link in a datacenter. At least 100 Mbps at home.
  The CDN used by `DCS_updater.exe` currently throttles downloads at ~25 MB/s.

### Operating System

This has been developed and tested on a Debian 12 "Bookworm" server install
and will be upgraded the Debian 13 "Trixie" when it releases in ~Q3/25. Most
Linux distributions that use systemd should work as well, but changes to
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
* VNC client: [UltraVNC](https://github.com/ultravnc/UltraVNC/)
* SFTP client: Required to transfer files (e.g., missions). Windows includes
  [scp](https://learn.microsoft.com/en-us/azure/virtual-machines/copy-files-to-vm-using-scp)
  as a command line client. Alternatively, install a GUI client like
  [FileZilla](https://filezilla-project.org/download.php?show_all=1)
  (do not download the version with "bundled offers", verify the filename does
  not include "sponsored"!).

### Linux Server Prerequisites (root/sudo privileges required)

Run via `ssh root@server`:

```sh
# Activate i386 architecture (required by Wine) and install dependencies
# TODO: adjust this if your server does not run Debian
sudo dpkg --add-architecture i368 && sudo apt update
sudo apt install --no-install-recommends \
	curl fonts-liberation git wine wine32 wine64 python3-minimal \
	sway unzip wayvnc xwayland
# Create a separate user account for the DCS server and enable persistent
# systemd user services for it (exemplary user name, change at will)
sudo useradd -m -s /bin/bash -G render,video dcs
sudo loginctl enable-linger dcs
```

### Installation

Run via `ssh dcs@server`: 

```sh
# use Git to download all scripts and config files into the home directory
cd ~
git init -b main ~
git remote add origin https://github.com/ActiumDev/dcs-server-wine.git
git fetch origin main
git reset --mixed origin/main
# start basic services: minimal GUI, VNC server, Wine server
# TODO: replace 5900 with your desired, locally bound VNC port
systemctl --user daemon-reload
systemctl --user enable --now sway wayvnc@5900 wine-session@.wine
```

The DCS user account should now be running the minimal GUI, which is accessible
via a VNC server bound to localhost (not accessible remotely). Close the open
SSH session and reconnect via `ssh -L 5900:127.0.0.1:5900 dcs@server` to set
up static port forwarding from your local machine that you run `ssh` on to the
`dcs@server`. This enables securely authenticated and encrypted VNC access.
You can now open `127.0.0.1:5900` via your local VNC client and should see an
empty desktop.

Everything is ready for the actual installation. First, decide which terrains
to install from [this list](https://forum.dcs.world/topic/324040-eagle-dynamics-modular-dedicated-server-installer/).
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

The VNC session should now show the DCS splash screen and the SRS server window
(the SRS window may be hidden behind the DCS window). If so, the DCS server
should run be running on port 10308 (default) and SRS on port 5002 (default).
The server is unlisted (not public) by default.

You can connect to the server by IP address and port. The default mission will
start automatically once the first player connects.

### Access to DCS WebGUI

Just like the VNC port, forward the DCS WebGUI port (see `autoexec.cfg`) via
SSH: `ssh -L 5900:127.0.0.1:5900 -L 8088:127.0.0.1:8088 dcs@server`.
Then, use a local browser to open `WebGUI/index.html` from your local DCS
client(!) installation directory. The WebGUI should detect the server
automatically.

### Optional: Configuration

Modify `~/.wine/drive_c/DCS_configs/DCS.server1/Config/autoexec.cfg` to suit
your requirements. Additionally, use the WebGUI to conveniently configure the
server settings. Then restart the server for all changes to take effect:
```sh
systemctl --user restart dcs-server@server1
```


## Known Issues

* DCS window hides SRS window: You need to move the DCS window to reveal the SRS window. Should be fixed by switching from sway to labwc once Debian 13 "Trixie" has been released (~Q3/25).
* VNC screen is sluggish: The used VNC server (wayvnc v0.5) has limited compression support. Should improve once a newer wayvnc version becomes available with Debian 13 "Trixie" release (~Q3/25).
* Some DCS windows contain HTML code: Could possibly be fixed by installing [Wine Gecko](https://gitlab.winehq.org/wine/wine/-/wikis/Gecko).
