#!/bin/sh -eux

# Olympus download link (most recent release known to work)
OLYMPUS_URL="https://github.com/Pax1601/DCSOlympus/releases/download/v2.0.3/DCSOlympus_v2.0.3.zip"

# extract version string from $OLYMPUS_URL
OLYMPUS_DLVER=${OLYMPUS_URL%/*}
OLYMPUS_DLVER=${OLYMPUS_DLVER##*/}

# install or update Olympus
OLYMPUS_DIR=${WINEPREFIX:-$HOME/.wine}/drive_c/Olympus
OLYMPUS_VER=$(cat $OLYMPUS_DIR/version.txt 2>/dev/null || true)
if [ "$OLYMPUS_VER" != "$OLYMPUS_DLVER" ] ; then
	rm -rf $OLYMPUS_DIR
	mkdir -p $OLYMPUS_DIR
	curl -fLo $OLYMPUS_DIR/Olympus.zip "$OLYMPUS_URL"
	unzip $OLYMPUS_DIR/Olympus.zip -d $OLYMPUS_DIR -x "Mods/Services/Olympus/frontend/node_modules/electron/*"
	echo $OLYMPUS_DLVER >$OLYMPUS_DIR/version.txt
	rm $OLYMPUS_DIR/Olympus.zip
fi

# enable and start Olympus frontend server
#systemctl --user enable --now olympus@server1
