extends SceneTree

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures: int = 0
	failures += _t_is_in_state_exact()
	failures += _t_is_in_state_false_until_start()
	failures += _t_attach_to_records_host()
	failures += _t_guard_blocks_transition()
	failures += _t_guard_allows_transition()
	failures += _t_try_transition_end_to_end()
	failures += _t_unhandled_event_signal()
	failures += _t_self_transition_warns_no_op()
	failures += _t_add_transition_unknown_state_drops()
	failures += _t_context_passthrough()
	if failures > 0:
		print("STATE_MACHINE_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("STATE_MACHINE_TEST: all passed")
		quit(0)
	return true


class _S extends GxState:
	var entered: int = 0
	var exited: int = 0
	func _enter() -> void: entered += 1
	func _exit() -> void: exited += 1

func _make_machine() -> GxStateMachine:
	var sm := GxStateMachine.new()
	sm.add_state(&"a", _S.new())
	sm.add_state(&"b", _S.new())
	return sm

func _t_is_in_state_exact() -> int:
	var sm := _make_machine()
	if sm.is_in_state(&"a"): return 1   # not started yet
	sm.start(&"a")
	if not sm.is_in_state(&"a"): return 1
	if sm.is_in_state(&"b"): return 1
	sm.transition_to(&"b")
	if not sm.is_in_state(&"b"): return 1
	return 0

func _t_attach_to_records_host() -> int:
	var sm := GxStateMachine.new()
	if sm.attached_host != null: return 1
	var host := Node.new()
	sm.attach_to(host)
	if sm.attached_host != host: return 1
	sm.detach()
	if sm.attached_host != null: return 1
	host.free()
	return 0

func _t_guard_blocks_transition() -> int:
	var sm := _make_machine()
	sm.start(&"a")
	sm.add_transition(&"a", &"go", &"b", func() -> bool: return false)
	if sm.try_transition(&"go"): return 1
	if not sm.is_in_state(&"a"): return 1
	return 0

func _t_guard_allows_transition() -> int:
	var sm := _make_machine()
	sm.start(&"a")
	var allowed := [false]
	sm.add_transition(&"a", &"go", &"b", func() -> bool: return allowed[0])
	if sm.try_transition(&"go"): return 1
	allowed[0] = true
	if not sm.try_transition(&"go"): return 1
	if not sm.is_in_state(&"b"): return 1
	return 0

func _t_try_transition_end_to_end() -> int:
	var sm := _make_machine()
	sm.start(&"a")
	sm.add_transition(&"a", &"go", &"b")
	if not sm.try_transition(&"go"): return 1
	if sm.current_name() != &"b": return 1
	return 0

func _t_unhandled_event_signal() -> int:
	var sm := _make_machine()
	sm.start(&"a")
	var got := [false]
	sm.unhandled_event.connect(func(_e: StringName) -> void: got[0] = true)
	sm.try_transition(&"nope")
	if not got[0]: return 1
	return 0


func _t_self_transition_warns_no_op() -> int:
	var sm := _make_machine()
	sm.start(&"a")
	# transition_to with the current name must warn and NOT re-enter.
	# We use a state subclass that counts entries.
	var a_state: _S = sm._states[&"a"]
	sm.transition_to(&"a")
	if a_state.entered != 1: return 1  # still the original entry
	if sm.current_name() != &"a": return 1
	return 0


func _t_add_transition_unknown_state_drops() -> int:
	var sm := _make_machine()
	# Unknown from_state -> push_error, returns self, but no transition is appended.
	sm.add_transition(&"ghost", &"go", &"b")
	sm.start(&"a")
	if sm.try_transition(&"go"): return 1  # no transition matched
	# Unknown target -> same behavior.
	sm.add_transition(&"a", &"go2", &"ghost")
	if sm.try_transition(&"go2"): return 1
	return 0


func _t_is_in_state_false_until_start() -> int:
	var sm := _make_machine()
	# BEFORE start(): is_in_state must always be false.
	if sm.is_in_state(&"a"): return 1
	sm.start(&"a")
	if not sm.is_in_state(&"a"): return 1
	return 0


func _t_context_passthrough() -> int:
	var sentinel := {"k": 1}
	var sm := GxStateMachine.new(sentinel)
	if sm.context != sentinel: return 1
	return 0
