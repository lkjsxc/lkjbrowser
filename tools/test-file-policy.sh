#!/bin/sh
# Synthetic files only. Called by tools/test.sh with its disposable fixture server.
set -eu
base=$1
run=$2
font_dir=$3
printf '%s\n' '<html><head><title>LOCAL FILE MARKER</title></head><body><h1>Only explicitly opened local data</h1></body></html>' >"$run/local.html"
cp fixtures/workshop.png "$run/local.png"
printf '%s\n' '<html><head><title>Local image policy</title></head><body><img src="local.png" width="320" height="100"></body></html>' >"$run/local-page.html"
mkfifo "$run/blocked.fifo"
ln -s local.html "$run/leaf-symlink"
render() {
 name=$1; url=$2; shift 2
 timeout 3s target/lkjbrowser --headless --font-dir "$font_dir" --layout "$run/policy-$name.layout" "$@" "$url" >"$run/policy-$name.log"
}
error_page() { grep -Fx "TITLE Unable to open this page" "$run/policy-$1.layout" >/dev/null; }
local_page() { grep -Fx "TITLE LOCAL FILE MARKER" "$run/policy-$1.layout" >/dev/null; }
render typed "file://$run/local.html"
local_page typed
printf 'follow file://%s/local.html\n' "$run" >"$run/local-follow.script"
render local-follow "file://$PWD/fixtures/article.html" --script "$run/local-follow.script"
local_page local-follow
render fifo "file://$run/blocked.fifo"
error_page fifo
render symlink "file://$run/leaf-symlink"
error_page symlink
render redirect "$base/file-redirect?to=file://$run/local.html"
error_page redirect
render remote-follow "$base/article.html" --script "$run/local-follow.script"
error_page remote-follow
grep -Fx "URL file://$run/local.html" "$run/policy-remote-follow.layout" >/dev/null
printf 'follow /file-redirect?to=file://%s/local.html\n' "$run" >"$run/redirect-follow.script"
render redirected-follow "$base/article.html" --script "$run/redirect-follow.script"
error_page redirected-follow
printf 'follow file://%s/local.html\ndown 29\nkey 19\nup 29\n' "$run" >"$run/reload-policy.script"
render reload "$base/article.html" --script "$run/reload-policy.script"
error_page reload
printf 'follow file://%s/local.html\nfollow about:welcome\nback\n' "$run" >"$run/history-policy.script"
render history "$base/article.html" --script "$run/history-policy.script"
error_page history
render local-image "file://$run/local-page.html"
grep -Fx "IMAGES 1" "$run/policy-local-image.layout" >/dev/null
render remote-image "$base/file-image?to=file://$run/local.png"
grep -Fx "IMAGES 0" "$run/policy-remote-image.layout" >/dev/null
.toolchain/lkjscript build src/config_probe.lkj -o target/config-probe
printf 'nameserver 127.0.0.1\n' >"$run/resolver-config"
ln -s resolver-config "$run/resolver-link"
target/config-probe "$run" resolver-link >"$run/resolver-config.log"
grep -Fx "read regular configuration: 21 bytes" "$run/resolver-config.log" >/dev/null
render config-page "file://$run/resolver-link"
error_page config-page
head -c 70000 /dev/zero >"$run/large-config"
if target/config-probe "$run" large-config >"$run/large-config.log" 2>&1; then
 echo "Oversized configuration was unexpectedly accepted" >&2; exit 1
fi
rm "$run/blocked.fifo" "$run/leaf-symlink" "$run/resolver-link"
printf 'PASS: typed/local links, regular-file checks, remote file redirects/links/images, reload and history authority.\n'
