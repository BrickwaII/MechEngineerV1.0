#!/usr/bin/env bash
# Checks that every play screen fits the window (ui/demo/screen_fit.gd) in a
# real window under xvfb, at each supported window size, and saves a picture
# of each screen. The headless half of the same check runs with the tests
# (tests/ui/fit/); this one sees what only a display shows: the real stretch,
# fonts as drawn, the window's own size.
# Usage: scripts/check_fit.sh [out_dir] [WIDTHxHEIGHT ...]
# Needs Godot 4.6 as `godot` on PATH or in $GODOT_BIN, and xvfb-run.
set -uo pipefail
cd "$(dirname "$0")/.."

godot_bin="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "$godot_bin" ]; then
	echo "Godot not found: set GODOT_BIN or put godot on PATH." >&2
	exit 1
fi
if ! command -v xvfb-run > /dev/null; then
	echo "xvfb-run not found: install xvfb." >&2
	exit 1
fi

out_dir="${1:-reports/fit}"
shift || true
case "$out_dir" in
	/*) ;;
	*) out_dir="$(pwd)/$out_dir" ;;
esac
sizes=("$@")
if [ ${#sizes[@]} -eq 0 ]; then
	sizes=(1280x820 1366x768 1600x900 1920x1080 2560x1440 3440x1440)
fi

if [ ! -f .godot/global_script_class_cache.cfg ]; then
	"$godot_bin" --headless --import --path . > /dev/null 2>&1
fi

failed=0
for size in "${sizes[@]}"; do
	echo "== $size"
	xvfb-run -a -s "-screen 0 ${size}x24" "$godot_bin" --path . --rendering-driver opengl3 \
		--resolution "$size" --remote-debug tcp://127.0.0.1:0 \
		-s res://ui/demo/check_fit.gd -- "$out_dir/$size" 2>&1 \
		| grep -E "^[a-z0-9_]+: [0-9]+x[0-9]+ |screens fit|SCRIPT ERROR"
	if [ "${PIPESTATUS[0]}" -ne 0 ]; then
		failed=1
	fi
done
exit $failed
