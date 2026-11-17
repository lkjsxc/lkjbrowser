#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
.toolchain/lkjscript build src/fixture_server.lkj -o target/fixture-server
exec target/fixture-server "$@"
