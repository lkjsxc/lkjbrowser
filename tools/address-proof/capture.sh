#!/bin/bash
# Real compositor proof: XTest -> isolated Xvfb -> Weston x11 -> wl_keyboard/pointer.
# Clipboard transfers use the independent source/sink, never the desktop clipboard.
set -euo pipefail
cd "$(dirname "$0")/../.."
. ./tools/wayland-auth.sh
root=$PWD
deps="$root/.deps/root"
if test "$#" -gt 0; then deps=$(realpath "$1"); fi
test -x "$deps/usr/bin/weston"
test -x target/lkjbrowser
test -x target/byte-descriptor-bridge
serial_gate=/home/coder/workspace/prompts/talk/lkjscript-gate.lock
serial_owner="$serial_gate/address-proof-$$"
serial_owned=0 serial_marked=0 serial_identity=
xpid= wpid= spid= qpid= bpid= tpid= lpid= restore_binaries=0
cleanup_width(){
    set +e
    wayland_auth_close
    for pid in "$lpid" "$qpid" "$bpid" "$tpid" "$spid" "$wpid" "$xpid"; do
        if test -n "$pid"; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
    done
    lpid= qpid= bpid= tpid= spid= wpid= xpid=
    set -e
}
release_gate(){
    if test "$serial_owned" != 1; then return 0; fi
    if test -n "$serial_identity" &&
       test "$(stat -Lc '%d:%i' "$serial_gate" 2>/dev/null)" != "$serial_identity"; then
        echo "Shared gate identity changed; refusing to remove another owner's gate" >&2
        return 1
    fi
    if test "$serial_marked" = 1 && ! test -f "$serial_owner"; then
        echo "Shared gate ownership marker changed; leaving the gate untouched" >&2
        return 1
    fi
    rm -f "$serial_owner" || return 1
    rmdir "$serial_gate" || return 1
    serial_owned=0
}
cleanup(){
    local status=$?
    trap - EXIT HUP INT TERM
    cleanup_width
    set +e
    if test "$restore_binaries" = 1; then
        cp "$run/byte-descriptor-bridge" target/byte-descriptor-bridge || status=1
        cp "$run/lkjbrowser" target/lkjbrowser || status=1
    fi
    release_gate || status=1
    exit "$status"
}
if ! mkdir "$serial_gate"; then
    echo "lkjscript serial gate is occupied" >&2
    exit 75
fi
serial_owned=1
# Install cleanup before any ownership bookkeeping or compiler invocation can fail.
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
serial_identity=$(stat -Lc '%d:%i' "$serial_gate")
printf 'pid=%s source=%s\n' "$$" "$PWD" >"$serial_owner"
serial_marked=1
gcc -std=c11 -O2 -Wall -Wextra -Werror tools/address-proof/clipboard-peer.c -o target/address-clipboard-peer
gcc -std=c11 -O2 -Wall -Wextra -Werror tools/address-proof/xinput.c -Wl,-l:libX11.so.6 -Wl,-l:libXtst.so.6 -o target/address-xinput
proof=$(mktemp -d "$root/review/address-editing.XXXXXX")
run=$(mktemp -d "$root/target/ap.XXXXXX")
printf '%s\n' "$proof" >target/address-proof-last
printf '%s\n' "$run" >"$proof/runtime-path.txt"
cp toolchain.lock "$proof/toolchain.lock"
git rev-parse HEAD >"$proof/commit.txt"
sha256sum target/lkjbrowser target/byte-descriptor-bridge .toolchain/lkjscript-x86_64-linux >"$proof/binaries.sha256"
sha256sum src/*.lkj bridge/byte_descriptor_bridge.c >"$proof/source.sha256"
sha256sum tools/wayland-auth.sh tools/wayland-run.sh tools/wayland-build-bridge.sh tools/build.sh tools/address-proof/* >"$proof/harness.sha256"
cp target/lkjbrowser target/byte-descriptor-bridge target/address-clipboard-peer target/address-xinput "$run/"
# Freeze and compile the actual pre-upgrade transport for the published-launcher regression.
git rev-parse 3025bc8^{commit} >"$proof/legacy-bridge-commit.txt"
git show 3025bc8:bridge/byte_descriptor_bridge.c >"$run/legacy-bridge.c"
gcc -O2 -std=c11 -nostdlib -static -fno-builtin -ffreestanding -fno-stack-protector -fno-pie -no-pie \
    -Wl,--build-id=none -Wall -Wextra "$run/legacy-bridge.c" -o "$run/legacy-byte-descriptor-bridge"
sha256sum "$run/legacy-bridge.c" "$run/legacy-byte-descriptor-bridge" >"$proof/legacy-bridge.sha256"
if cmp -s "$run/legacy-byte-descriptor-bridge" "$run/byte-descriptor-bridge"; then echo "Legacy transport unexpectedly equals candidate" >&2; exit 1; fi
printf '  https://example.test/\r\nalpha\tbeta \n ' >"$proof/paste-input.txt"
printf 'https://example.test/alpha beta' >"$proof/paste-expected.txt"
long='https://example.test/alpha/beta/gamma/delta/epsilon/zeta/eta/theta/iota/kappa/lambda/mu/nu/xi/omicron/pi/rho/sigma/tau/upsilon/phi/chi/psi/omega?section=address-editing&proof=keyboard-pointer-clipboard#boundary-check'
printf '%s' "$long" >"$proof/long-address.txt"
export LD_LIBRARY_PATH="$deps/usr/lib/x86_64-linux-gnu:$deps/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="x11-backend.so=$deps/usr/lib/x86_64-linux-gnu/libweston-13/x11-backend.so;kiosk-shell.so=$deps/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
wait_pattern(){
    local file=$1 pattern=$2 pid=$3
    for ((attempt=0;attempt<200;attempt++)); do
        if test -f "$file" && grep -q "$pattern" "$file"; then return; fi
        kill -0 "$pid" || { cat "$file" >&2; return 1; }
        sleep 0.05 8<&- 9<&-
    done
    echo "Timed out: $pattern in $file" >&2
    cat "$file" >&2
    return 1
}
input(){
    local label=$1
    cat >"$out/$label.input"
    "$run/address-xinput" "$out/$label.input" >"$out/$label.input.log"
}
capture(){
    local label=$1
    mkdir "$out/$label-capture"
    printf 'move %s 730\nwait 180\n' "$((width-12))" | input "$label-hide-pointer"
    (cd "$out/$label-capture"; timeout 10 "$deps/usr/bin/weston-screenshooter") >"$out/$label.capture.log" 2>"$out/$label.capture.err"
    local images=("$out/$label-capture"/wayland-screenshot-*.png)
    test "${#images[@]}" = 1
    cp "${images[0]}" "$out/$label.png"
}
sink(){
    local label=$1 expected=$2
    "$run/address-clipboard-peer" "$XDG_RUNTIME_DIR/wl" sink "$out/$label.txt" >"$out/$label.sink.log" 2>&1 &
    qpid=$!
    wait "$qpid"; qpid=
    cmp "$expected" "$out/$label.txt"
    printf 'PASS %s bytes=%s\n' "$label" "$(wc -c <"$out/$label.txt")" >>"$out/assertions.log"
    printf 'focus\nwait 140\n' | input "$label-refocus"
}
for width in 1440 480; do
    out="$proof/$width"; mkdir "$out" "$run/$width"; mkdir -m 700 "$run/$width/r"
    : >"$run/$width/r/address-proof-owned"
    export XDG_RUNTIME_DIR="$run/$width/r" WAYLAND_DISPLAY=wl
    Xvfb -displayfd 3 -screen 0 "$width"x760x24 -nolisten tcp -ac 3>"$out/display" >"$out/xvfb.log" 2>&1 &
    xpid=$!
    for ((i=0;i<100;i++));do test -s "$out/display" && break;kill -0 "$xpid";sleep 0.05 8<&- 9<&-;done
    export DISPLAY=:$(cat "$out/display")
    "$deps/usr/bin/weston" --backend=x11 --renderer=pixman --width="$width" --height=760 \
        --shell="$deps/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket=wl \
        --idle-time=0 --no-config --debug --log="$out/weston.log" >"$out/weston-stdio.log" 2>&1 &
    wpid=$!
    for ((i=0;i<100;i++));do test -S "$XDG_RUNTIME_DIR/wl" && break;kill -0 "$wpid";sleep 0.05 8<&- 9<&-;done
    "$run/address-clipboard-peer" "$XDG_RUNTIME_DIR/wl" source "$proof/paste-input.txt" >"$out/source.log" 2>&1 &
    spid=$!
    wait_pattern "$out/source.log" MAPPED "$spid"
    printf 'focus\nmove %s 380\ntap 57\nwait 100\n' "$((width/2))" | input source-selection
    wait_pattern "$out/source.log" SELECTION_SET "$spid"
    frame="$run/$width/frame.bgra"
    truncate -s "$((width*760*8+2304))" "$frame"
    wayland_auth_prepare
    "$run/byte-descriptor-bridge" "$XDG_RUNTIME_DIR/wl" "$frame" >"$out/bridge-port" 2>"$out/bridge.log" <&8 8<&- 9<&- &
    tpid=$!
    exec 8<&-
    for ((i=0;i<100;i++));do test -s "$out/bridge-port" && break;kill -0 "$tpid";sleep 0.05 8<&- 9<&-;done
    node tools/address-proof/reject-clients.cjs "$(cat "$out/bridge-port" 8<&- 9<&-)" 8<&- 9<&- >"$out/auth-rejection.log"
    kill -0 "$tpid"
    "$run/lkjbrowser" --wayland "$(cat "$out/bridge-port" 8<&- 9<&-)" --frame-file "$frame" \
        --width "$width" --height 760 --max-ms 180000 about:welcome >"$out/browser.log" 2>"$out/browser.err" <&9 8<&- 9<&- &
    bpid=$!
    wayland_auth_close
    wait_pattern "$out/browser.log" PAINT "$bpid"
    printf 'focus\nwait 180\nkey 29 1\ntap 38\nkey 29 0\nkey 29 1\ntap 47\nkey 29 0\nwait 350\n' | input paste-multiline
    capture 04-after-multiline-paste
    printf 'key 29 1\ntap 30\ntap 46\nkey 29 0\nwait 180\n' | input copy-pasted
    sink paste-exact "$proof/paste-expected.txt"
    printf 'key 29 1\ntap 38\nkey 29 0\ntext %s\ntap 102\n' "$long" >"$out/middle-caret.input"
    for ((i=0;i<120;i++));do printf 'tap 106\n' >>"$out/middle-caret.input";done
    printf 'wait 180\n' >>"$out/middle-caret.input"
    "$run/address-xinput" "$out/middle-caret.input" >"$out/middle-caret.input.log"
    capture 01-middle-caret
    { printf 'key 42 1\n';for ((i=0;i<16;i++));do printf 'tap 106\n';done;printf 'key 42 0\nwait 180\n'; } | input partial-selection
    capture 02-partial-selection
    printf 'tap 102\nwait 180\n' | input start-caret
    capture 03-start-caret
    # The first word begins at the existing 16 px inset in each approved pill.
    start=306; if test "$width" = 480;then start=140;fi
    printf 'move %s 26\nbutton 1 1\nbutton 1 0\nwait 80\nbutton 1 1\nbutton 1 0\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' "$((start+14))" | input pointer-double-word
    printf https >"$out/word-expected.txt"
    sink pointer-word "$out/word-expected.txt"
    printf 'wait 600\nmove %s 26\nbutton 1 1\nbutton 1 0\nwait 80\nbutton 1 1\nbutton 1 0\nwait 80\nbutton 1 1\nbutton 1 0\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' "$((start+14))" | input pointer-triple-all
    sink pointer-all "$proof/long-address.txt"
    printf 'tap 102\nwait 600\nmove %s 26\nbutton 1 1\nmove %s 26\nwait 9000\nbutton 1 0\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' "$start" "$((width-60))" | input pointer-drag-scroll
    sink pointer-drag-all "$proof/long-address.txt"
    printf 'tap 102\nwait 600\nmove %s 26\nbutton 1 1\nbutton 1 0\ntext X\nkey 29 1\ntap 30\ntap 46\nkey 29 0\nwait 180\n' "$start" | input pointer-insert-start
    printf 'X%s' "$long" >"$out/insert-expected.txt"
    sink pointer-insert "$out/insert-expected.txt"
    printf 'key 29 1\ntap 45\nkey 29 0\nwait 200\n' | input cut-all
    capture 05-after-cut
    sink cut-exact "$out/insert-expected.txt"
    # Cut must leave the field empty. A real paste then restores the owned source.
    printf 'key 29 1\ntap 47\nkey 29 0\nwait 300\nkey 29 1\ntap 30\ntap 46\nkey 29 0\nwait 180\n' | input self-paste-copy
    sink self-paste-exact "$out/insert-expected.txt"
    # Word movement/selection and word deletion use independent transfer oracles.
    printf 'key 29 1\ntap 38\nkey 29 0\ntext alpha.beta/gamma?delta\ntap 102\nkey 29 1\ntap 106\nkey 42 1\ntap 106\nkey 42 0\ntap 46\nkey 29 0\nwait 180\n' | input shift-ctrl-word
    printf .beta >"$out/word-range-expected.txt"
    sink shift-ctrl-word "$out/word-range-expected.txt"
    printf 'key 29 1\ntap 14\nkey 29 0\ntap 102\nkey 29 1\ntap 111\nkey 29 0\ntap 107\nkey 29 1\ntap 14\ntap 30\ntap 46\nkey 29 0\nwait 180\n' | input delete-words
    printf '/gamma?' >"$out/delete-expected.txt"
    sink delete-words "$out/delete-expected.txt"
    # Enter and Alt navigation use an ordinary local document, with no network.
    page="file://$root/fixtures/article.html"
    printf '%s' "$page" >"$out/page-expected.txt"
    printf 'about:welcome' >"$out/welcome-expected.txt"
    printf 'key 29 1\ntap 38\nkey 29 0\ntext %s\ntap 28\nwait 450\nkey 29 1\ntap 38\ntap 46\nkey 29 0\nwait 180\n' "$page" | input navigate-file
    sink enter-navigated "$out/page-expected.txt"
    # History chords must win while the field is editing.
    printf 'text pending-edit\nkey 56 1\ntap 105\nkey 56 0\nwait 350\nkey 29 1\ntap 38\ntap 46\nkey 29 0\nwait 180\n' | input alt-back
    sink alt-back "$out/welcome-expected.txt"
    printf 'key 56 1\ntap 106\nkey 56 0\nwait 350\nkey 29 1\ntap 38\ntap 46\nkey 29 0\nwait 180\n' | input alt-forward
    sink alt-forward "$out/page-expected.txt"
    # Changed Escape restores the page address AND selects it without leaving editing.
    printf 'text discarded.invalid\ntap 1\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' | input escape-changed
    sink escape-restored-selected "$out/page-expected.txt"
    # Unchanged Escape leaves editing, so X must not change the displayed address.
    printf 'tap 1\ntext X\ntap 64\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' | input escape-unchanged-f6
    sink escape-left-and-f6 "$out/page-expected.txt"
    printf 'tap 1\nkey 56 1\ntap 32\nkey 56 0\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' | input alt-d
    sink alt-d-selects "$out/page-expected.txt"
    printf 'text discarded.invalid\nmove %s 710\nbutton 1 1\nbutton 1 0\ntap 64\nkey 29 1\ntap 46\nkey 29 0\nwait 180\n' "$((width-25))" | input outside-discards
    sink outside-discards "$out/page-expected.txt"
    printf 'key 29 1\ntap 16\nkey 29 0\n' | input close-browser
    wait "$bpid";bpid=
    wait "$tpid";tpid=
    # Exercise the documented build -> launcher upgrade on the same private compositor.
    if test "$width" = 1440; then
        restore_binaries=1
        cp "$run/legacy-byte-descriptor-bridge" target/byte-descriptor-bridge
        cmp "$run/legacy-byte-descriptor-bridge" target/byte-descriptor-bridge
        sh tools/build.sh >"$out/documented-build.log" 2>"$out/documented-build.err" &
        lpid=$!
        wait "$lpid"; lpid=
        cmp "$run/legacy-byte-descriptor-bridge" target/byte-descriptor-bridge
        printf 'PASS documented browser build retained the actual legacy transport; launcher upgrade follows\n' >>"$out/assertions.log"
    fi
    sh tools/wayland-run.sh --max-ms 200 --width "$width" --height 760 about:welcome \
        >"$out/launcher-smoke.log" 2>"$out/launcher-smoke.err" &
    lpid=$!
    wait "$lpid"; lpid=
    cmp "$run/byte-descriptor-bridge" target/byte-descriptor-bridge
    cmp "$run/lkjbrowser" target/lkjbrowser
    restore_binaries=0
    grep -q "^PAINT wayland-submit " "$out/launcher-smoke.log"
    test ! -s "$out/launcher-smoke.err"
    printf 'PASS published launcher presented and exited cleanly\n' >>"$out/assertions.log"
    sha256sum "$out"/*.png >"$out/screenshots.sha256"
    cleanup_width
done
sha256sum src/*.lkj bridge/byte_descriptor_bridge.c >"$proof/source-after.sha256"
if cmp -s "$proof/source.sha256" "$proof/source-after.sha256"; then printf "Source stayed unchanged.\n" >"$proof/source-stability.txt"; else printf "Source changed during capture; frozen executable hashes identify tested code.\n" >"$proof/source-stability.txt"; fi
printf 'PASS real Weston keyboard/pointer and plain-text clipboard transfers at 1440 and 480.\nProof: %s\n' "$proof"
