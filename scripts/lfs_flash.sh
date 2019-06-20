#!/bin/sh
set -e

source "$DIR/lfs_info.sh"
cd "$DIR/../firmware"
./luac.cross.int -a $LFS_MAPPED -o bin/lfs.img local/lua/*.lua
esptool --baud 460800 write_flash --flash_mode dout $LFS_BASE bin/lfs.img
