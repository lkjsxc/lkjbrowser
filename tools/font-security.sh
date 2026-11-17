#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p target
cat src/font.lkj > target/font-security.lkj
cat >> target/font-security.lkj <<'LKJ'
fn main() -> bool {
    let mut branching = synthetic_font(12usize,true);
    let branch = branching.raster(65u32,16i32);
    let mut oversized = synthetic_font(16usize,false);
    let large = oversized.raster(65u32,512i32);
    branching.cache[branch].mask.is_empty() && oversized.cache[large].mask.is_empty()
}
LKJ
.toolchain/lkjscript run target/font-security.lkj --entry main --engine native
