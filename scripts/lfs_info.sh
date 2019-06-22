#!/bin/sh
set -e

LFS_FILE="bin/lfs.img"
LFS_UPGRADE="bin/upgrade.img"

LFS_MAPPED="0x4026a000"
LFS_BASE="0x6a000"
LFS_SIZE="0x10000"

build_lfs() {
	if [ "$1" == "-upgrade" ]; then
		./luac.cross.int -f -o $LFS_UPGRADE local/lua/*.lua
	else
		./luac.cross.int -a $LFS_MAPPED -o $LFS_FILE local/lua/*.lua
	fi
}
