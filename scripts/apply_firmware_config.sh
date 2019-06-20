#!/bin/sh
set -e

source "$DIR/lfs_info.sh"
cd "$DIR/.."
git -C firmware apply < nodemcu.patch
