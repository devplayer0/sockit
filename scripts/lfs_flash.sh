#!/bin/sh
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$DIR/lfs_info.sh"
cd "$DIR/../firmware"
build_lfs
esptool --baud 460800 write_flash --flash_mode dout $LFS_BASE $LFS_FILE
