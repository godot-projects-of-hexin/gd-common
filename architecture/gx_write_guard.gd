class_name GxWriteGuard
extends RefCounted
## Debug-only guard that makes unsanctioned Model writes observable (report, not block).
##
## GDScript has no private members, so a Controller can still reach a resolved
## Model's [GxBindableProperty]. A hard block needs a read-only view; this guard
## reports instead. [GxArchitecture] opens a write scope around [method initialize],
## member [code]_on_init()[/code], [method GxArchitecture.send_command] and
## [method GxArchitecture.send_event]. Only bindables owned by a registered Model
## are marked, so standalone observables are unaffected; release builds skip the check.

static var _depth: int = 0
static var _violations: int = 0


static func is_active() -> bool:
	return OS.is_debug_build() and not Engine.is_editor_hint()


static func begin() -> void:
	_depth += 1


static func end() -> void:
	_depth = maxi(0, _depth - 1)


static func allows_write() -> bool:
	return not is_active() or _depth > 0


static func report(method_name: String) -> void:
	_violations += 1
	push_warning(
		"GxWriteGuard: %s() ran outside a sanctioned write scope. " % method_name
		+ "Presentation code must change state with send_command()."
	)


## Test-only observability: how many unsanctioned writes were reported so far.
static func violation_count() -> int:
	return _violations


static func reset_violations() -> void:
	_violations = 0
