#!/bin/sh
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$DIR/lfs_info.sh"
cd "$DIR/../firmware"
make

CAT_COMMAND="srec_cat -output bin/sockit-esp8266.bin -binary bin/0x00000.bin -binary -fill 0xff 0x00000 0x10000 bin/0x10000.bin -binary -offset 0x10000"
if [ "$1" != "no_lfs" ]; then
	build_lfs
	build_lfs -upgrade
	CAT_COMMAND="$CAT_COMMAND -exclude -within $LFS_FILE -binary -offset $LFS_BASE $LFS_FILE -binary -offset $LFS_BASE"
fi

$CAT_COMMAND
