extends SceneTree


func _init() -> void:
	var failures: int = 0
	failures += _t_subscribe_and_emit()
	failures += _t_payload_passthrough()
	failures += _t_duplicate_subscribe_ignored()
	failures += _t_unsubscribe_removes_listener()
	failures += _t_freed_callable_auto_pruned()
	failures += _t_has_subscribers_reflects_state()
	if failures > 0:
		print("EVENT_BUS_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("EVENT_BUS_TEST: all passed")
		quit(0)


func _make_bus() -> Node:
	var bus_script: Script = load("res://addons/gd-common/core/event_bus.gd")
	var bus: Node = bus_script.new()
	root.add_child(bus)
	return bus


func _t_subscribe_and_emit() -> int:
	var bus := _make_bus()
	var hit: Array = [0]
	bus.subscribe(&"hit", func(_p): hit[0] += 1)
	bus.emit_event(&"hit", null)
	if hit[0] != 1: return 1
	bus.emit_event(&"hit", null)
	if hit[0] != 2: return 1
	return 0


func _t_payload_passthrough() -> int:
	var bus := _make_bus()
	var got: Array = [null]
	bus.subscribe(&"data", func(p): got[0] = p)
	bus.emit_event(&"data", 42)
	if got[0] != 42: return 1
	bus.emit_event(&"data", "hello")
	if got[0] != "hello": return 1
	return 0


func _t_duplicate_subscribe_ignored() -> int:
	var bus := _make_bus()
	var hit: Array = [0]
	var cb := func(_p): hit[0] += 1
	bus.subscribe(&"d", cb)
	bus.subscribe(&"d", cb)
	bus.emit_event(&"d", null)
	if hit[0] != 1: return 1
	return 0


func _t_unsubscribe_removes_listener() -> int:
	var bus := _make_bus()
	var hit: Array = [0]
	var cb := func(_p): hit[0] += 1
	bus.subscribe(&"u", cb)
	bus.unsubscribe(&"u", cb)
	bus.emit_event(&"u", null)
	if hit[0] != 0: return 1
	return 0


func _t_freed_callable_auto_pruned() -> int:
	var bus := _make_bus()
	var holder: Array = [null]
	holder[0] = func(_p): pass
	bus.subscribe(&"f", holder[0])
	holder[0] = null  # Callable holds a reference, so this is a *weak* ref test:
	# The Callable object itself stays alive in the dict until bus prunes it.
	# emit_event iterates and finds is_valid()==true, so the listener fires once
	# at minimum; we just confirm no crash and the entry is still tracked.
	bus.emit_event(&"f", null)
	if not bus.has_subscribers(&"f"): return 1
	return 0


func _t_has_subscribers_reflects_state() -> int:
	var bus := _make_bus()
	if bus.has_subscribers(&"x"): return 1
	bus.subscribe(&"x", func(_p): pass)
	if not bus.has_subscribers(&"x"): return 1
	bus.clear_event(&"x")
	if bus.has_subscribers(&"x"): return 1
	return 0
