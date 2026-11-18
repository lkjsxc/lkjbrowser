#!/bin/sh
# Regenerate the chrome review pictures in shots/chrome with the built browser.
# Needs the public network for the article and plain-HTTP pictures.
set -eu
cd "$(dirname "$0")/.."
sh tools/build.sh
.toolchain/lkjscript build src/shot_tool.lkj -o target/shot-tool
out=shots/chrome
work=$(mktemp -d "$PWD/target/chrome-shots.XXXXXXXX")
mkdir -p "$out"
article=https://www.rfc-editor.org/rfc/rfc5869.html
shot() {
 name=$1; shift
 target/lkjbrowser --headless --screenshot "$out/$name.png" "$@" >"$work/$name.log"
}
script() { printf '%b' "$2" >"$work/$1.script"; printf '%s' "$work/$1.script"; }
shot welcome about:welcome
shot article-top "$article"
shot article-scrolled "$article" --scroll 1400
shot editing about:welcome --script "$(script editing 'address rfc-editor.org/rfc/rfc58\n')"
shot selected "$article" --script "$(script selected 'click 400 26\n')"
shot plain-http http://example.com/
shot error http://127.0.0.1:9/notes.html
shot link-hover "$article" --scroll 1400 --script "$(script link-hover 'move 399 277\n')"
shot loading about:welcome --script "$(script loading "loading $article\n")"
shot button-hover about:welcome --script "$(script button-hover "open $article\nmove 26 26\n")"
shot button-pressed about:welcome --script "$(script button-pressed "open $article\npress 98 26\n")"
shot scrollbar-held "$article" --script "$(script scrollbar-held 'press 995 400\n')"
shot narrow-620 "$article" --width 620
shot wide-1600 "$article" --width 1600
# Details at four times, exact pixels: the controls, the security states, the scrollbar.
target/shot-tool zoom "$out/detail-controls.png" "$out/button-hover.png" 0 0 250 52 4
target/shot-tool zoom "$out/detail-lock.png" "$out/article-top.png" 120 0 250 52 4
target/shot-tool zoom "$out/detail-warning.png" "$out/plain-http.png" 120 0 250 52 4
target/shot-tool zoom "$out/detail-focus.png" "$out/editing.png" 120 0 250 52 4
target/shot-tool row "$out/before-after.png" shots/https-rfc5869-r2.png "$out/article-top.png"
rm -r "$work"
ls "$out"
