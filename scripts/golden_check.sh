#!/usr/bin/env bash
# Golden check: shows a change alters no behaviour. Captures fixed-seed
# outputs (fights, previews, growth, odds, tool reports, autoplay, region
# maps, saves and whole journaled runs; see tests/golden/golden_capture.gd)
# from the working tree and from a base git ref, and diffs them.
#
# Usage:
#   scripts/golden_check.sh [BASE_REF] [--quick]   compare the working tree with BASE_REF (default origin/main)
#   scripts/golden_check.sh --capture DIR [--quick] capture the working tree only
#
# Both captures use the working tree's capture script, so the base needs none.
# Exit code 0 when the outputs are identical, 1 when they differ.
# Godot is taken from $GODOT_BIN, else `godot` on PATH.
set -uo pipefail
cd "$(dirname "$0")/.."

godot_bin="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "$godot_bin" ]; then
	echo "Godot not found: set GODOT_BIN or put godot on PATH." >&2
	exit 1
fi

capture() {  # capture PROJECT_DIR OUT_DIR [--quick]
	local project="$1" out="$2"
	shift 2
	rm -rf "$out"
	if [ ! -f "$project/.godot/global_script_class_cache.cfg" ]; then
		"$godot_bin" --headless --import --path "$project" > /dev/null 2>&1
	fi
	"$godot_bin" --headless --path "$project" -s res://tests/golden/golden_capture.gd -- "$out" "$@" \
		> "$out.log" 2>&1
}

if [ "${1:-}" = "--capture" ]; then
	out="$(realpath -m "$2")"
	shift 2
	capture "$PWD" "$out" "$@"
	tail -n 1 "$out.log"
	exit 0
fi

base_ref="origin/main"
if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then
	base_ref="$1"
	shift
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/golden.XXXXXX")"
git worktree add --detach "$work/base" "$base_ref" > /dev/null 2>&1 || {
	echo "Cannot check out $base_ref" >&2
	exit 1
}
mkdir -p "$work/base/tests/golden"
cp tests/golden/golden_capture.gd "$work/base/tests/golden/golden_capture.gd"

started=$(date +%s)
capture "$work/base" "$work/out_base" "$@" &
base_pid=$!
capture "$PWD" "$work/out_head" "$@"
wait "$base_pid"
echo "Captured in $(( $(date +%s) - started )) s: $work/out_base vs $work/out_head"

git worktree remove --force "$work/base" > /dev/null 2>&1
if diff -r "$work/out_base" "$work/out_head" > "$work/diff.txt"; then
	echo "GOLDEN OK: $(find "$work/out_head" -type f | wc -l) files identical to $base_ref"
	exit 0
fi
echo "GOLDEN DIFF against $base_ref ($(grep -c '^diff ' "$work/diff.txt") files differ): $work/diff.txt"
head -n 60 "$work/diff.txt"
exit 1
