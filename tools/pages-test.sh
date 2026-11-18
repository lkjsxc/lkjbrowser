#!/bin/sh
# Complete deterministic offline page, image, content and authenticated HTTPS gate.
set -eu
cd "$(dirname "$0")/.."
sh tools/https-test.sh
sh tools/image-test.sh
sh tools/content-test.sh
sh tools/styles-test.sh
printf 'PASS all offline real-page foundation gates\n'
