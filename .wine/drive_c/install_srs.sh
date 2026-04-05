#!/bin/sh -eux

# SRS download link (most recent release known to work)
SRS_URL="https://github.com/ciribob/DCS-SimpleRadioStandalone/releases/download/2.3.6.0/SRS-Server-Commandline-Linux"

# extract version string from $SRS_URL
SRS_DLVER=${SRS_URL%/*}
SRS_DLVER=${SRS_DLVER##*/}

# install or update SRS server
SRS_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/SRS_server
SRS_VER=$(cat $SRS_DIR/version.txt 2>/dev/null || true)
if [ "$SRS_VER" != "$SRS_DLVER" ] ; then
	mkdir -p "$SRS_DIR"
	rm -f "$SRS_DIR/SRS-Server-Commandline"
	curl -fLo "$SRS_DIR/SRS-Server-Commandline" "$SRS_URL"
	chmod +x "$SRS_DIR/SRS-Server-Commandline"
	echo $SRS_DLVER >$SRS_DIR/version.txt
fi
