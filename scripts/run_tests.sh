#!/usr/bin/env bash
# Runs every gdUnit4 test under tests/ headless, with no editor open.
# Usage: scripts/run_tests.sh [extra GdUnitCmdTool args, e.g. -a res://tests/contracts]
# Godot is taken from $GODOT_BIN, else `godot` on PATH.
set -uo pipefail
cd "$(dirname "$0")/.."

godot_bin="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "$godot_bin" ]; then
	echo "Godot not found: set GODOT_BIN or put godot on PATH." >&2
	exit 1
fi

# A clean clone has no .godot/ cache yet, so class_name lookups would fail.
# Importing once builds it.
if [ ! -f .godot/global_script_class_cache.cfg ]; then
	"$godot_bin" --headless --import --path . > /dev/null 2>&1
fi

suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then
	suites=(-a res://tests)
fi

# --ignoreHeadlessMode: these tests are logic-only and need no rendering.
# -c: keep running after a failure so every failure is reported.
# --remote-debug to a closed port stops Godot dropping into its interactive
# debugger on a script error.
"$godot_bin" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c "${suites[@]}"
exit_code=$?

"$godot_bin" --headless --path . --quiet -s res://addons/gdUnit4/bin/GdUnitCopyLog.gd > /dev/null 2>&1
exit $exit_code
