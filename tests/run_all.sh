#!/usr/bin/env bash
# Runs every headless test. Usage: tests/run_all.sh [godot-binary]
# A test fails on a non-zero exit, a timeout (script errors stall rather than quit) or a SCRIPT ERROR.
set -u
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."

failed=()
run() {
	local name="$1"; shift
	local log
	log=$(timeout 300 "$GODOT" --headless --path . "$@" 2>&1)
	local code=$?
	if [ $code -ne 0 ] || grep -q "SCRIPT ERROR" <<<"$log"; then
		echo "FAIL $name (exit $code)"
		grep -E "FAIL|ERROR" <<<"$log" | head -40
		failed+=("$name")
	else
		echo "ok   $name"
	fi
}

for scene in $(find tests -name 'test_*.tscn' | sort); do
	run "$scene" "res://$scene"
done
run tests/test_roster_ammo.gd --script res://tests/test_roster_ammo.gd

if [ ${#failed[@]} -ne 0 ]; then
	echo "${#failed[@]} failed: ${failed[*]}"
	exit 1
fi
echo "all passed"
