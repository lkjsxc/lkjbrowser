#!/bin/bash
# Ten-page proof: freeze a native executable, capture the real Weston window,
# compare compositor pixels, retain per-page logs, and reap all owned processes.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
binary=target/lkjbrowser
manifest=docs/pages/pages.tsv
round=after
source_root=$root
allow_errors=0
resume=0
expected_count=10
while (($#)); do
 case "$1" in
  --binary) binary=${2:?}; shift 2;;
  --manifest) manifest=${2:?}; shift 2;;
  --round) round=${2:?}; shift 2;;
  --source-root) source_root=${2:?}; shift 2;;
  --allow-errors) allow_errors=1; shift;;
  --resume) resume=1; shift;;
  --count) expected_count=${2:?}; shift 2;;
  *) echo "Unknown option: $1" >&2; exit 2;;
 esac
done
[[ "$round" =~ ^[A-Za-z0-9_-]+$ && "$expected_count" =~ ^[1-9][0-9]*$ ]] || exit 2
case "$binary" in /*) ;; *) binary="$root/$binary";; esac
[[ -x "$binary" && -f "$manifest" ]]
mkdir -p target shots/pages docs/pages
run=$(mktemp -d "$root/target/browser-pages-capture.XXXXXXXX")
out="$root/shots/pages/$round"
mkdir -p "$out" "$run/r"
chmod 700 "$run/r"
proof="$root/docs/pages/wayland-$round.log"
weston_pid= bridge_pid= browser_pid= shooter_pid=
cleanup() {
 local status=$?
 trap - EXIT HUP INT TERM
 set +e
 for owned in "$shooter_pid" "$browser_pid" "$bridge_pid" "$weston_pid"; do
  if [[ -n "$owned" ]]; then kill "$owned" 2>/dev/null; wait "$owned" 2>/dev/null; fi
 done
 rm -rf "$run/r"
 printf '\nFinished UTC: %s\nExit status: %s\nOwned processes reaped; private runtime removed.\n' "$(date -u +%FT%TZ)" "$status" >>"$proof"
 exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
cp "$binary" "$run/lkjbrowser"
cp "$manifest" "$run/pages.tsv"
if [[ "$resume" = 0 ]]; then : >"$proof"; fi
{
 printf 'Actual Weston compositor capture, 1000x760. Round: %s\nStarted UTC: %s\nRun: %s\n' "$round" "$(date -u +%FT%TZ)" "$run"
 sha256sum "$run/lkjbrowser" target/byte-descriptor-bridge target/pixel-compare
 cat "$source_root/toolchain.lock"
 git rev-parse HEAD
 (cd "$source_root"; while IFS= read -r source_file; do sha256sum "$source_file"; done < <(rg --files src -g '*.lkj' | sort); sha256sum program.lkj)
 printf '\nManifest:\n'
 cat "$run/pages.tsv"
} >>"$proof"
export XDG_RUNTIME_DIR="$run/r" WAYLAND_DISPLAY=pages
export LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="headless-backend.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/libweston-13/headless-backend.so;kiosk-shell.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
start_compositor() {
.deps/root/usr/bin/weston --backend=headless --renderer=pixman --width=1000 --height=760 \
 --shell="$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket=pages \
 --idle-time=0 --no-config --debug --log="$run/weston.log" >"$run/weston-stdio.log" 2>&1 &
weston_pid=$!
for ((i=0;i<150;i++)); do [[ -S "$run/r/pages" ]] && break; kill -0 "$weston_pid"; sleep .02; done
[[ -S "$run/r/pages" ]]
}
count=0
while IFS=$'\t' read -r name url scroll extra || [[ -n "${name:-}${url:-}" ]]; do
 [[ -z "$name" || "$name" = \#* ]] && continue
 scroll=${scroll:-0}
 [[ "$name" =~ ^[A-Za-z0-9_-]+$ && -n "$url" && "$scroll" =~ ^[0-9]+$ && -z "$extra" ]]
 count=$((count+1))
 if [[ "$resume" = 1 && -f "$out/$name.png" && -f "$out/$name.layout" && -f "$out/$name.log" ]]; then printf 'Retained %s %s\n' "$round" "$name"; continue; fi
 start_compositor
 dir="$run/$name"; mkdir -p "$dir"
 truncate -s 6082304 "$dir/frame.bgra"
 target/byte-descriptor-bridge "$run/r/pages" "$dir/frame.bgra" >"$dir/port" 2>"$dir/bridge.log" &
 bridge_pid=$!
 for ((i=0;i<150;i++)); do [[ -s "$dir/port" ]] && break; kill -0 "$bridge_pid"; sleep .02; done
 [[ -s "$dir/port" ]]
 "$run/lkjbrowser" --wayland "$(cat "$dir/port")" --frame-file "$dir/frame.bgra" --max-ms 1800 \
  --scroll "$scroll" --screenshot "$dir/program.png" --layout "$dir/page.layout" "$url" >"$dir/browser.log" 2>&1 &
 browser_pid=$!
 painted=0
 for ((i=0;i<2000;i++)); do
  if [[ -s "$dir/program.png" ]] && grep -q '^PAINT wayland-submit ' "$dir/browser.log"; then painted=1; break; fi
  kill -0 "$browser_pid" 2>/dev/null || break
  sleep .02
 done
 if [[ "$painted" != 1 ]]; then cat "$dir/browser.log" >&2; echo "No presented frame for $name" >&2; exit 1; fi
 sleep .2
 cp "$dir/program.png" "$dir/frozen-program.png"
 (cd "$dir"; exec "$root/.deps/root/usr/bin/weston-screenshooter") >"$dir/shooter.log" 2>"$dir/shooter.err" &
 shooter_pid=$!
 for ((i=0;i<250;i++)); do kill -0 "$shooter_pid" 2>/dev/null || break; sleep .02; done
 wait "$shooter_pid"; shooter_pid=
 captures=("$dir"/wayland-screenshot-*.png)
 [[ ${#captures[@]} = 1 ]]
 cp "${captures[0]}" "$out/$name.png"
 cp "$dir/page.layout" "$out/$name.layout"
 cp "$dir/browser.log" "$out/$name.log"
 {
  printf '\nPAGE %s %s scroll=%s\n' "$name" "$url" "$scroll"
  target/pixel-compare "$out/$name.png" "$dir/frozen-program.png"
  cat "$dir/browser.log"
  sha256sum "$out/$name.png" "$out/$name.layout"
 } >>"$proof"
 wait "$browser_pid"; browser_pid=
 wait "$bridge_pid"; bridge_pid=
 kill "$weston_pid" 2>/dev/null || true
 wait "$weston_pid" 2>/dev/null || true
 weston_pid=
 rm -f "$run/r/pages" "$run/r/pages.lock"
 if grep -Fxq 'TITLE Unable to open this page' "$dir/page.layout"; then
  printf 'PAGE_ERROR %s\n' "$name" >>"$proof"
  [[ "$allow_errors" = 1 ]] || { cat "$dir/browser.log" >&2; exit 1; }
 fi
 printf 'Captured %s %s\n' "$round" "$name"
done <"$run/pages.tsv"
[[ "$count" = "$expected_count" ]] || { echo "Expected $expected_count pages; captured $count" >&2; exit 1; }
printf 'PASS: %s actual compositor captures, native pixel comparisons, logs retained.\n' "$count" >>"$proof"
