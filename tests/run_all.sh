#!/usr/bin/env bash
# Run every gd-common test suite against a consuming Godot project.
#
# gd-common is an addon, not a project: it has no project.godot of its own, so
# the tests run from a project that includes it as a submodule (game-template).
#
# Usage, from the consuming project root:
#   ./addons/gd-common/tests/run_all.sh
#   GODOT=/path/to/godot ./addons/gd-common/tests/run_all.sh
set -u

GODOT="${GODOT:-godot}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
SUITES=(
	test_architecture
	test_bindable_property
	test_event_bus
	test_save_system
	test_state_machine
	test_gauge
	test_cooldown
	test_audio_manager
	test_ui_manager
	test_object_pool
	test_math
	test_controller_lifecycle
)

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: '$GODOT' not found. Set GODOT=/path/to/godot and retry." >&2
	exit 127
fi

if [ ! -f "$PROJECT_DIR/project.godot" ]; then
	echo "error: no project.godot in '$PROJECT_DIR'." >&2
	echo "       Run this from the consuming project root, or set PROJECT_DIR." >&2
	exit 2
fi

failed=0
for suite in "${SUITES[@]}"; do
	printf '>> %s\n' "$suite"
	if ! "$GODOT" --headless --path "$PROJECT_DIR" \
		--script "res://addons/gd-common/tests/${suite}.gd"; then
		failed=$((failed + 1))
	fi
done

echo
if [ "$failed" -gt 0 ]; then
	echo "RESULT: $failed suite(s) failed"
	exit 1
fi
echo "RESULT: all ${#SUITES[@]} suites passed"
