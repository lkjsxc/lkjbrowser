#!/bin/bash
# Actual Weston captures. This script never builds, installs, or starts a public listener.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
manifest=docs/tls/public-pages.tsv
round=r1
round_set=0
trust=/etc/ssl/certs/ca-certificates.crt
motion=
start_url=
enter_still=0
frames=26
delay_ms=400
usage() {
 cat <<'USAGE'
Usage:
  bash tools/capture-https.sh [--manifest FILE.tsv] [--round NAME] [--trust-file FILE] [--enter]
  bash tools/capture-https.sh --motion EVENTS.live START_URL [--round NAME]
       [--frames 16..30] [--delay-ms 100..1000] [--trust-file FILE]

Still mode requires exactly five name<TAB>url rows (blank lines and # comments allowed).
--enter starts each still window at about:welcome and replays address replacement
at 100ms and ordinary Enter at 200ms; this mode requires HTTPS URLs.
Motion mode captures one continuous window, without fetching the five-page manifest.
Binaries must already be built. Do not rebuild the browser during a capture.
USAGE
}
while (($#)); do
 case "$1" in
  --manifest) manifest=${2:?missing manifest}; shift 2 ;;
  --enter) enter_still=1; shift ;;
  --round) round=${2:?missing round}; round_set=1; shift 2 ;;
  --trust-file) trust=${2:?missing trust file}; shift 2 ;;
  --motion) motion=${2:?missing events}; start_url=${3:?missing start URL}; shift 3 ;;
  --frames) frames=${2:?missing frame count}; shift 2 ;;
  --delay-ms) delay_ms=${2:?missing delay}; shift 2 ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
 esac
done
if [[ -n "$motion" && "$round_set" = 0 ]]; then round=motion; fi
[[ -z "$motion" || "$enter_still" = 0 ]] || { echo "--enter is a still-mode option; it cannot be combined with --motion." >&2; exit 2; }
[[ "$round" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Round must use letters, digits, _ or -" >&2; exit 2; }
[[ "$frames" =~ ^[0-9]+$ && "$delay_ms" =~ ^[0-9]+$ ]] || { echo "Numeric capture settings required" >&2; exit 2; }
((frames >= 16 && frames <= 30 && delay_ms >= 100 && delay_ms <= 1000)) || { echo "Capture settings outside documented limits" >&2; exit 2; }
for executable in target/lkjbrowser target/byte-descriptor-bridge target/pixel-compare target/animate \
 .deps/root/usr/bin/weston .deps/root/usr/bin/weston-screenshooter; do
 [[ -x "$executable" ]] || { echo "Missing $executable; build/setup before capturing." >&2; exit 1; }
done
[[ -f "$trust" ]] || { echo "Trust bundle not found: $trust" >&2; exit 1; }
case "$trust" in /*) ;; *) trust="$root/$trust" ;; esac
if [[ -n "$motion" ]]; then
 [[ -f "$motion" ]] || { echo "Motion script not found: $motion" >&2; exit 1; }
else
 [[ -f "$manifest" ]] || { echo "Manifest not found: $manifest" >&2; exit 1; }
fi

mkdir -p target shots docs/tls
run=$(mktemp -d "$root/target/https-capture.XXXXXXXX")
proof="$root/docs/tls/wayland-$round.log"
weston_pid= bridge_pid= browser_pid= shooter_pid=
cleanup() {
 local status=$?
 trap - EXIT HUP INT TERM
 set +e
 for owned_pid in "$shooter_pid" "$browser_pid" "$bridge_pid" "$weston_pid"; do
  if [[ -n "$owned_pid" ]]; then
   kill "$owned_pid" 2>/dev/null
   wait "$owned_pid" 2>/dev/null
  fi
 done
 rm -rf "$run/r"
 printf '\nFinished UTC: %s\nExit status: %s\nAll capture-owned processes stopped and reaped; private runtime removed.\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" >>"$proof"
 exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
{
 printf 'Actual Weston 13 pixman capture, 1000x760.\nStarted UTC: %s\nRound: %s\nRun: %s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$round" "$run"
 printf '\nToolchain pin:\n'
 cat toolchain.lock
 printf '\nSource and runtime inputs:\n'
 sha256sum target/lkjbrowser target/byte-descriptor-bridge target/pixel-compare target/animate \
  .toolchain/lkjscript-x86_64-linux "$trust" .deps/root/usr/bin/weston .deps/root/usr/bin/weston-screenshooter
 printf '\nSource hashes:\n'
 while IFS= read -r source_file; do sha256sum "$source_file"; done < <(rg --files src -g '*.lkj' | sort)
 sha256sum program.lkj
} >"$proof"
expected_browser=$(sha256sum target/lkjbrowser | cut -d' ' -f1)
# Frozen copies ensure all five pages and the motion use one exact executable.
cp target/lkjbrowser "$run/lkjbrowser"
cp target/byte-descriptor-bridge "$run/byte-descriptor-bridge"
cp target/pixel-compare "$run/pixel-compare"
cp target/animate "$run/animate"
[[ "$(sha256sum "$run/lkjbrowser" | cut -d' ' -f1)" = "$expected_browser" ]]
printf '\nFrozen browser SHA256: %s\n' "$expected_browser" >>"$proof"
if [[ -n "$motion" ]]; then
 cp "$motion" "$run/events.live"
 sha256sum "$run/events.live" >>"$proof"
 last_event=$(awk '!/^[[:space:]]*(#|$)/ { if ($1 !~ /^[0-9]+$/) exit 1; if ($1+0>last) last=$1+0 } END { print last+0 }' "$run/events.live")
 [[ "$last_event" =~ ^[0-9]+$ ]] || { echo "Invalid event times" >&2; exit 1; }
 ((last_event <= frames * delay_ms - 1000)) || { echo "Motion ends too late for these frame settings; increase frames/delay." >&2; exit 1; }
else
 # Parse and freeze the manifest before starting any compositor or browser.
 : >"$run/pages.tsv"
 declare -A names=()
 count=0
 while IFS=$'\t' read -r name url extra || [[ -n "${name:-}${url:-}${extra:-}" ]]; do
  [[ -z "$name" || "$name" = \#* ]] && continue
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ && -n "$url" && -z "$extra" ]] || { echo "Invalid manifest row: $name" >&2; exit 1; }
  [[ -z "${names[$name]:-}" ]] || { echo "Duplicate manifest name: $name" >&2; exit 1; }
  case "$url" in https://*|http://*|file://*) ;; *) echo "Invalid manifest URL for $name" >&2; exit 1 ;; esac
  [[ "$enter_still" = 0 || "$url" = https://* ]] || { echo "--enter requires an HTTPS URL for $name" >&2; exit 1; }
  names[$name]=1
  printf '%s\t%s\n' "$name" "$url" >>"$run/pages.tsv"
  count=$((count+1))
 done <"$manifest"
 [[ "$count" = 5 ]] || { echo "Exactly five manifest pages are required (got $count)." >&2; exit 1; }
 printf '\nManifest:\n' >>"$proof"
 cat "$run/pages.tsv" >>"$proof"
fi

mkdir -m 700 "$run/r"
export XDG_RUNTIME_DIR="$run/r"
export WAYLAND_DISPLAY=wl
export LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="headless-backend.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/libweston-13/headless-backend.so;kiosk-shell.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
"$root/.deps/root/usr/bin/weston" --backend=headless --renderer=pixman --width=1000 --height=760 \
 --shell="$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket="$WAYLAND_DISPLAY" \
 --idle-time=0 --no-config --debug --log="$run/weston.log" >"$run/weston-stdio.log" 2>&1 &
weston_pid=$!
for ((attempt=0;attempt<150;attempt++)); do
 [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
 kill -0 "$weston_pid" 2>/dev/null || { cat "$run/weston.log" >&2; exit 1; }
 sleep 0.02
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { echo "Weston startup timed out" >&2; exit 1; }

start_bridge() {
 local directory=$1
 truncate -s 6082304 "$directory/frame.bgra"
 "$run/byte-descriptor-bridge" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$directory/frame.bgra" \
  >"$directory/bridge-port" 2>"$directory/bridge.log" &
 bridge_pid=$!
 for ((attempt=0;attempt<150;attempt++)); do
  [[ -s "$directory/bridge-port" ]] && break
  kill -0 "$bridge_pid" 2>/dev/null || { cat "$directory/bridge.log" >&2; exit 1; }
  sleep 0.02
 done
 [[ -s "$directory/bridge-port" ]] || { echo "Bridge startup timed out" >&2; exit 1; }
 bridge_port=$(cat "$directory/bridge-port")
}
# Return only the first HTTPS presentation after the generated ordinary Enter event.
# Script timestamps are scheduled offsets, not wall-clock input measurements.
enter_paint_record() {
 awk '/^Script 200ms: key 28$/ { entered=1; next }
      entered && /^PAINT wayland-submit elapsed_us=[0-9]+ url=https:\/\// { print; exit }' "$1"
}
await_paint() {
 local directory=$1 require_enter=${2:-0}
 for ((attempt=0;attempt<1500;attempt++)); do
  if [[ -s "$directory/program.png" ]]; then
   if [[ "$require_enter" = 1 ]]; then
    if [[ -n "$(enter_paint_record "$directory/browser.log")" ]]; then return; fi
   elif grep -q '^PAINT wayland-submit ' "$directory/browser.log"; then return; fi
  fi
  kill -0 "$browser_pid" 2>/dev/null || { cat "$directory/browser.log" >&2; echo "Browser exited before presenting" >&2; exit 1; }
  sleep 0.02
 done
 cat "$directory/browser.log" >&2
 echo "Browser did not present within 30 seconds" >&2
 exit 1
}
capture_frame() {
 local directory=$1 output=$2
 mkdir -p "$directory"
 (cd "$directory"; exec "$root/.deps/root/usr/bin/weston-screenshooter") >"$directory/shooter.log" 2>"$directory/shooter.err" &
 shooter_pid=$!
 local finished=0
 for ((attempt=0;attempt<250;attempt++)); do
  if ! kill -0 "$shooter_pid" 2>/dev/null; then finished=1; break; fi
  sleep 0.02
 done
 [[ "$finished" = 1 ]] || { echo "Screenshooter timed out" >&2; exit 1; }
 local status=0
 wait "$shooter_pid" || status=$?
 shooter_pid=
 [[ "$status" = 0 ]] || { cat "$directory/shooter.err" >&2; exit "$status"; }
 local captures=("$directory"/wayland-screenshot-*.png)
 [[ "${#captures[@]}" = 1 && -s "${captures[0]}" ]] || { echo "Expected exactly one compositor screenshot" >&2; exit 1; }
 mv "${captures[0]}" "$output"
}
finish_browser() {
 local directory=$1 status=0
 wait "$browser_pid" || status=$?
 browser_pid=
 [[ "$status" = 0 ]] || { cat "$directory/browser.log" >&2; exit "$status"; }
 wait "$bridge_pid" || status=$?
 bridge_pid=
 [[ "$status" = 0 ]] || { cat "$directory/bridge.log" >&2; exit "$status"; }
}
still() {
 local name=$1 url=$2
 local directory="$run/$name"
 local launch_url="$url" max_ms=1500
 local live_args=()
 mkdir -p "$directory"
 if [[ "$enter_still" = 1 ]]; then
  launch_url=about:welcome
  max_ms=12000
  printf '100 address %s\n200 key 28\n' "$url" >"$directory/events.live"
  live_args=(--live-script "$directory/events.live")
  cp "$directory/events.live" "$root/shots/https-$name-$round.live"
  {
   printf '\nENTER REPLAY %s: start about:welcome in the same native window.\n' "$name"
   printf 'Input: address replacement at scheduled 100ms, ordinary Enter handler at scheduled 200ms; application-event replay, not physical typing.\n'
   printf 'Timing: browser navigation-start timer inside the Enter handler to first target Wayland submission; not compositor-display or hardware-input latency.\n'
   sha256sum "shots/https-$name-$round.live"
   cat "$directory/events.live"
  } >>"$proof"
 fi
 start_bridge "$directory"
 "$run/lkjbrowser" --wayland "$bridge_port" --frame-file "$directory/frame.bgra" --max-ms "$max_ms" \
  --trust-file "$trust" "${live_args[@]}" --screenshot "$directory/program.png" --layout "$directory/page.layout" "$launch_url" \
  >"$directory/browser.log" 2>&1 &
 browser_pid=$!
 await_paint "$directory" "$enter_still"
 sleep 0.2
 if grep -Fxq 'TITLE Unable to open this page' "$directory/page.layout"; then
  cat "$directory/browser.log" >&2; cat "$directory/page.layout" >&2
  echo "Requested page became an error page: $name" >&2; exit 1
 fi
 cp "$directory/program.png" "$directory/compared-program.png"
 capture_frame "$directory/capture" "$root/shots/https-$name-$round.png"
 {
  printf '\nPAGE %s %s\n' "$name" "$url"
  "$run/pixel-compare" "$root/shots/https-$name-$round.png" "$directory/compared-program.png"
 } >>"$proof"
 finish_browser "$directory"
 cp "$directory/page.layout" "$root/shots/https-$name-$round.layout"
 cat "$directory/browser.log" >>"$proof"
 if [[ "$enter_still" = 1 ]]; then
  grep -Fxq "Script 100ms: address $url" "$directory/browser.log" || { echo "Missing address replacement evidence for $name" >&2; exit 1; }
  local paint_record navigation_us presented_url
  paint_record=$(enter_paint_record "$directory/browser.log")
  if [[ "$paint_record" =~ ^PAINT\ wayland-submit\ elapsed_us=([0-9]+)\ url=(https://.*)$ ]]; then
   navigation_us=${BASH_REMATCH[1]}
   presented_url=${BASH_REMATCH[2]}
  else
   echo "Missing target HTTPS paint after Enter for $name" >&2; exit 1
  fi
  grep -Fxq "URL $presented_url" "$directory/page.layout" || { echo "Target paint and captured layout disagree for $name" >&2; exit 1; }
  printf 'ENTER_TO_FIRST_WAYLAND page=%s elapsed_us=%s requested_url=%s presented_url=%s\n' \
   "$name" "$navigation_us" "$url" "$presented_url" >>"$proof"
 fi
 sha256sum "shots/https-$name-$round.png" "shots/https-$name-$round.layout" >>"$proof"
 printf 'Captured %s -> shots/https-%s-%s.png\n' "$name" "$name" "$round"
}

if [[ -z "$motion" ]]; then
 while IFS=$'\t' read -r name url; do still "$name" "$url"; done <"$run/pages.tsv"
else
 directory="$run/motion"
 out="$root/shots/https-motion-$round"
 mkdir -p "$directory" "$out"
 cp "$run/events.live" "$out/events.live"
 start_bridge "$directory"
 max_ms=$((frames * delay_ms + 1500))
 "$run/lkjbrowser" --wayland "$bridge_port" --frame-file "$directory/frame.bgra" --max-ms "$max_ms" \
  --trust-file "$trust" --live-script "$run/events.live" --screenshot "$directory/program.png" \
  --layout "$directory/final.layout" "$start_url" >"$directory/browser.log" 2>&1 &
 browser_pid=$!
 await_paint "$directory"
 # Submission precedes compositor repaint; allow the first real window frame to become visible.
 sleep 0.2
 capture_started_ns=$(date +%s%N)
 : >"$out/frames.tsv"
 for ((index=0;index<frames;index++)); do
  deadline=$((capture_started_ns + index * delay_ms * 1000000))
  now=$(date +%s%N)
  if ((now<deadline)); then
   remaining=$((deadline-now))
   printf -v delay '%d.%09d' $((remaining/1000000000)) $((remaining%1000000000))
   sleep "$delay"
  fi
  kill -0 "$browser_pid" 2>/dev/null || { cat "$directory/browser.log" >&2; echo "Motion browser exited too early" >&2; exit 1; }
  printf -v number '%03d' "$index"
  capture_frame "$directory/capture-$number" "$out/frame-$number.png"
  captured=$(date +%s%N)
  printf '%s\tframe-%s.png\n' "$(((captured-capture_started_ns)/1000000))" "$number" >>"$out/frames.tsv"
 done
 # The script leaves the final page still so its native pixels can be compared too.
 sleep 0.1
 cp "$directory/program.png" "$directory/final-program.png"
 capture_frame "$directory/final-capture" "$out/final.png"
 "$run/pixel-compare" "$out/final.png" "$directory/final-program.png" >>"$proof"
 finish_browser "$directory"
 cp "$directory/final.layout" "$out/final.layout"
 cp "$directory/browser.log" "$out/browser.log"
 if grep -Fxq 'TITLE Unable to open this page' "$out/final.layout"; then echo "Motion ended on an error page" >&2; exit 1; fi
 grep -Eq '^Script [0-9]+ms: key 28$' "$out/browser.log" || { echo "Motion must submit the edited address with Enter" >&2; exit 1; }
 grep -Eq '^Script [0-9]+ms: scroll ' "$out/browser.log" || { echo "Motion must include a scroll" >&2; exit 1; }
 grep -Eq '^Script [0-9]+ms: click ' "$out/browser.log" || { echo "Motion must click a link" >&2; exit 1; }
 https_pages=$(sed -n 's/^PAINT wayland-submit .* url=\(https:\/\/.*\)$/\1/p' "$out/browser.log" | sort -u | wc -l)
 ((https_pages >= 2)) || { echo "Motion must present two distinct HTTPS URLs" >&2; exit 1; }
 {
  printf '\nMOTION: one continuous native browser process; actual compositor pixels.\n'
  printf 'Input: timestamped application-event replay, not physical hardware input.\n'
  printf 'Nominal APNG delay: %s ms; actual capture times: shots/https-motion-%s/frames.tsv\n' "$delay_ms" "$round"
  cat "$out/browser.log"
 } >>"$proof"
 frame_args=()
 for ((index=0;index<frames;index++)); do
  printf -v number '%03d' "$index"
  frame_args+=("shots/https-motion-$round/frame-$number.png")
 done
 "$run/animate" "shots/https-motion-$round.apng" "$delay_ms" "${frame_args[@]}" >>"$proof"
 cp "shots/https-motion-$round.apng" shots/https-first.apng
 cp shots/https-first.apng shots/scroll-and-link.apng
 sha256sum "shots/https-motion-$round/"*.png shots/https-first.apng shots/scroll-and-link.apng >>"$proof"
 printf 'Captured %s motion frames -> shots/https-first.apng and shots/scroll-and-link.apng\n' "$frames"
fi
[[ "$(sha256sum target/lkjbrowser | cut -d' ' -f1)" = "$expected_browser" ]] || {
 printf '\nERROR: shared browser was rebuilt during this capture; frozen binary was used throughout.\n' >>"$proof"
 echo "Browser binary changed while capturing; coordinate a stable rerun." >&2
 exit 1
}
printf '%s\n' "$run" >"target/latest-https-capture-$round"
printf '\nPASS: full compositor/native pixel comparison; original browser binary unchanged.\n' >>"$proof"
printf 'Proof: docs/tls/wayland-%s.log\n' "$round"
