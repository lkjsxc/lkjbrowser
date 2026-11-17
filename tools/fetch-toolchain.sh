#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tag=$(awk -F= '$1=="tag" {print $2}' toolchain.lock)
commit=$(awk -F= '$1=="commit" {print $2}' toolchain.lock)
expected=$(awk -F= '$1=="sha256" {print $2}' toolchain.lock)
asset=lkjscript-x86_64-linux
test "${#commit}" = 40
test "${#expected}" = 64
mkdir -p .toolchain
if test -f ".toolchain/$asset"; then
  actual=$(sha256sum ".toolchain/$asset" | cut -d' ' -f1)
  if test "$actual" = "$expected"; then
    chmod +x ".toolchain/$asset"
    ln -sfn "$asset" .toolchain/lkjscript
    exit 0
  fi
fi
temp=$(mktemp -d .toolchain/download.XXXXXX)
trap 'rm -rf "$temp"' EXIT HUP INT TERM
base="https://github.com/lkjsxc/lkjscript/releases/download/$tag"
curl --fail --location --retry 3 "$base/SHA256SUMS" -o "$temp/SHA256SUMS"
published=$(awk '$2=="lkjscript-x86_64-linux" {print $1}' "$temp/SHA256SUMS")
test "$published" = "$expected"
curl --fail --location --retry 3 "$base/$asset" -o "$temp/$asset"
actual=$(sha256sum "$temp/$asset" | cut -d' ' -f1)
test "$actual" = "$expected"
chmod +x "$temp/$asset"
mv "$temp/$asset" ".toolchain/$asset"
mv "$temp/SHA256SUMS" .toolchain/SHA256SUMS
ln -sfn "$asset" .toolchain/lkjscript
printf 'Verified lkjscript %s (%s)\n' "$tag" "$commit"
