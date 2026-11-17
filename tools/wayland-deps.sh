#!/bin/sh
# Download and unpack a compositor solely inside this repository.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .deps/debs .deps/root .deps/runtime
chmod 700 .deps/runtime
(
 cd .deps/debs
 apt-get download weston libweston-13-0 libinput10 libinput-bin libmtdev1t64 libwacom9 libwacom-common wayland-protocols
 for package in ./*.deb; do dpkg-deb -x "$package" ../root; done
)
export LD_LIBRARY_PATH="$PWD/.deps/root/usr/lib/x86_64-linux-gnu:$PWD/.deps/root/usr/lib/x86_64-linux-gnu/weston"
.deps/root/usr/bin/weston --version
