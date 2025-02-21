#!/bin/sh -eux

# DCS updater download link
DCS_UPDATER_URL="https://cdn.digitalcombatsimulator.com/files/DCS_updater_64bit.zip"

# need headless GUI session to run DCS installer
if ! systemctl --user --quiet is-active sway ; then
	exit 1
fi

# redirect new windows to headless GUI session
export $(systemctl --user show-environment | grep ^DISPLAY=)
export $(systemctl --user show-environment | grep ^WAYLAND_DISPLAY=)

# configure Wine
wine winecfg -v win10
cat <<-EOF >${WINEPREFIX:-$HOME/.wine}/drive_c/wineconfig.reg
	REGEDIT4

	# suppress winedbg window (would inhibit automatic post-crash service restart)
	# defaults to "winedbg --auto %ld %ld" as of Wine 8.0, which shows crash trace
	# in a new window. alternatively, could be disabled with "false".
	[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug]
	"Debugger"="winedbg --minidump %ld"

	# never show crash dialog (would inhibit automatic post-crash service restart)
	[HKEY_CURRENT_USER\\Software\\Wine\\WineDbg]
	"ShowCrashDialog"=dword:00000000

	# disable Wine services not required by DCS or SRS
	[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\PlugPlay]
	"Start"=dword:00000004
	[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\RpcSs]
	"Start"=dword:00000004

	# NOTE: explorer.exe is required to open new windows
	[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
	"winedevice.exe"="disabled"
	#"rpcss.exe"="disabled"
	#"services.exe"="disabled"
	#"svchost.exe"="disabled"

	# bypass built-in DLLs that cause issues with DCS_server.exe
	[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\DCS_server.exe\\DllOverrides]
	# Wine built-in wbemprox.dll causes DCS crash (as of Wine 8.0 and 9.0)
	"wbemprox"="disabled"
	# bin/zlib1.dll shipped with DCS contains zlib1.ZipOpen2(), which is
	# missing from Wine built-in zlib1 (as of Wine 8.0 and 9.0)
	"zlib1"="native"
EOF
wine reg import ${WINEPREFIX:-$HOME/.wine}/drive_c/wineconfig.reg
rm ${WINEPREFIX:-$HOME/.wine}/drive_c/wineconfig.reg

# symlink Saved Games folder to C:\DCS_configs for easy access
DCS_SAV_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/users/$USER/Saved\ Games
if [ ! -h "$DCS_SAV_DIR" -a -d "$DCS_SAV_DIR" ] ; then
	# will fail intentionally if directory is non-empty
	rmdir "$DCS_SAV_DIR"
fi
if [ ! -h "$DCS_SAV_DIR" ] ; then
	ln -s ../../DCS_configs "$DCS_SAV_DIR"
fi

# if configuration directory is missing, populate it with defaults
# TODO: support this for multiple server instances (including port setup)
DCS_CFG_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_configs
if [ ! -e $DCS_CFG_DIR/DCS.server1 ] ; then
	cp -a $DCS_CFG_DIR/DCS_defaults $DCS_CFG_DIR/DCS.server1
fi

# populate $DCS_SRV_DIR like the modular dedicated server installer would:
#   * https://www.digitalcombatsimulator.com/en/downloads/world/server/
#   * https://forum.dcs.world/topic/324040-eagle-dynamics-modular-dedicated-server-installer/
DCS_SRV_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/DCS_server
mkdir -p $DCS_SRV_DIR/bin $DCS_SRV_DIR/Config
cd $DCS_SRV_DIR

# download DCS updater binary if needed
if [ ! -e $DCS_SRV_DIR/bin/DCS_updater.exe ] ; then
	DCS_UPDATER_ZIP=${DCS_UPDATER_URL##*/}
	curl -fOL "$DCS_UPDATER_URL"
	unzip $DCS_UPDATER_ZIP -d $DCS_SRV_DIR/bin
	rm $DCS_UPDATER_ZIP
fi

# (over)write static config files
echo -n "EN" >$DCS_SRV_DIR/Config/lang.txt
echo -n "dcs_server.release" >$DCS_SRV_DIR/dcs_variant.txt

# initialize autoupdate.cfg
# NOTE: do not overwrite existing autoupdate.cfg as it will contain "version"
#       and "timestamp" keys presumably relevant for the updater
if [ ! -e $DCS_SRV_DIR/autoupdate.cfg ] ; then
	# assemble list of terrains to install (default to installing Caucasus)
	TERRAINS_JSON=""
	for TERRAIN in ${DCS_TERRAINS:-CAUCASUS_terrain} ; do
		TERRAINS_JSON="$TERRAINS_JSON, \"$TERRAIN\""
	done

	# set "launch" key to null to prevent updater from starting server
	cat <<-EOF >$DCS_SRV_DIR/autoupdate.cfg
		{
		 "WARNING": "DO NOT EDIT this file. You may break your install!",
		 "branch": "dcs_server.release",
		 "arch": "x86_64",
		 "lang": "EN",
		 "modules": [
		  "WWII-ARMOUR", "SUPERCARRIER", "WORLD"$TERRAINS_JSON
		 ],
		 "launch": null
		}
	EOF
fi

# install DCS by running the updater: `wine bin/DCS_updater.exe --quiet update`
# updater is executed as background service (immune to SSH connection loss)
# for more information on DCS updater and its arguments, see:
#   * https://forum.dcs.world/topic/94816-guide-info-dcs-updater-usage-version-numbers-module-ids/
if ! systemctl --user start dcs-updater.service ; then
	systemctl --user --lines=100 status dcs-updater.service
	exit 1
fi

# enable and start DCS server
systemctl --user enable --now dcs-server@server1.service
# verify it started successfully (may take a few seconds to fail)
# FIXME: systemd restarts faster than this
sleep 10
if ! systemctl --user --quiet is-active dcs-server@server1.service ; then
	systemctl --user --lines=100 status dcs-server@server1.service
	exit 1
fi
