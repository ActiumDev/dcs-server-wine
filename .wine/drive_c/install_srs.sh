#!/bin/sh -eux

# SRS depends on the .NET Framework, so install its Wine substitute Wine Mono:
#   * https://gitlab.winehq.org/mono/wine-mono
#   * https://gitlab.winehq.org/wine/wine/-/wikis/Wine-Mono
# Wine Mono is a version of Mono patched to work well with Wine and therefore
# superior to installing the native .NET Framework via `winetricks dotnet00`
# Pick Wine Mono version according to the following table:
#   * https://gitlab.winehq.org/wine/wine/-/wikis/Wine-Mono#versions
WINE_VERSION=$(wine --version)
case ${WINE_VERSION%% *} in
wine-10.0|wine-10.0-rc*)
	MONO_URL="https://dl.winehq.org/wine/wine-mono/9.4.0/wine-mono-9.4.0-x86.msi"
	break
	;;
wine-9.0)
	MONO_URL="https://dl.winehq.org/wine/wine-mono/8.1.0/wine-mono-8.1.0-x86.msi"
	break
	;;
wine-8.0)
	MONO_URL="https://dl.winehq.org/wine/wine-mono/7.4.0/wine-mono-7.4.0-x86.msi"
	break
	;;
wine-7.0)
	MONO_URL="https://dl.winehq.org/wine/wine-mono/7.0.0/wine-mono-7.0.0-x86.msi"
	break
	;;
*)
	echo "***ERROR***: Unable to determine required Wine Mono version for unknown Wine version $WINE_VERSION!"
	exit 1
esac

# SRS download link (most recent release known to work)
SRS_URL="https://github.com/ciribob/DCS-SimpleRadioStandalone/releases/download/2.1.1.0/DCS-SimpleRadioStandalone-2.1.1.0.zip"

# install or update Wine Mono
MONO_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/windows/mono
MONO_VER=$(cat $MONO_DIR/version.txt 2>/dev/null || true)
MONO_MSI=${MONO_URL##*/}
if [ -z "$MONO_VER" ] ; then
	curl -fOL "$MONO_URL"
	wine $MONO_MSI
	echo $MONO_MSI >$MONO_DIR/version.txt
	rm -f $MONO_MSI
elif [ "$MONO_VER" != "$MONO_MSI" ] ; then
	# https://gitlab.winehq.org/wine/wine/-/wikis/Wine-Mono#prefix-local-install
	echo "***ERROR***: Incorrect Wine Mono version installed. Run 'wine uninstaller' and remove 'Wine Mono Runtime' and 'Wine Mono Windows Support'!"
	exit 1
	# TODO: automatically uninstall Wine Mono
	# TODO: determine if GUIDs are constant
	#wine uninstaller --remove "{47A1FA26-B71E-5325-8161-20CF885181FF}"
	#wine uninstaller --remove "{7426CCE2-5341-534D-BAB0-1DAEDCCE76CE}"
fi

# SRS server needs a Windows core font installed or it will throw exceptions
# of type MS.Internal.Shaping.TypefaceMap.*
# NOTE: using /usr/share/wine/fonts/*.ttf from fonts-wine package fails
ARIAL_TTF="/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
FONTS_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/windows/Fonts
if [ ! -e $ARIAL_TTF ] ; then
	echo "***ERROR***: file '$ARIAL_TTF' not found!"
	exit 1
fi
if [ ! -e $FONTS_DIR/arial.ttf ] ; then
	mkdir -p $FONTS_DIR
	ln -s $ARIAL_TTF $FONTS_DIR/arial.ttf
fi
# alternatively, all corefonts can be installed via winetricks
#if [ ! -e windows/Fonts/corefonts.installed ] ; then winetricks corefonts ; fi

# install or update SRS server
SRS_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/SRS_server
SRS_VER=$(cat $SRS_DIR/version.txt 2>/dev/null || true)
SRS_ZIP=${SRS_URL##*/}
if [ "$SRS_VER" != "$SRS_ZIP" ] ; then
	curl -fOL "$SRS_URL"
	# unpack required files only
	unzip -o $SRS_ZIP SR-Server.exe -d $SRS_DIR
	echo $SRS_ZIP >$SRS_DIR/version.txt
	rm -f $SRS_ZIP
fi

# enable and start SRS server
systemctl --user enable --now srs-server@server1
# verify it started successfully (may take a few seconds to fail)
# FIXME: systemd restarts faster than this
sleep 5
if ! systemctl --user --quiet is-active srs-server@server1 ; then
	systemctl --user --lines=100 status srs-server@server1
	exit 1
fi
