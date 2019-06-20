#!/bin/sh
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$DIR/lfs_info.sh"
cd "$DIR/../firmware"
make
./luac.cross.int -a $LFS_MAPPED -o bin/lfs.img local/lua/*.lua
srec_cat -output bin/nodemcu.bin -binary bin/0x00000.bin -binary -fill 0xff 0x00000 0x10000 bin/0x10000.bin -binary -offset 0x10000 -exclude -within bin/lfs.img -binary -offset $LFS_BASE bin/lfs.img -binary -offset $LFS_BASE
