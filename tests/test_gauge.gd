extends SceneTree


func _init() -> void:
	var failures: int = 0
	failures += _t_initial_value_with_start_full()
	failures += _t_drain_emits_depleted_at_zero()
	failures += _t_fill_clamps_to_max()
	failures += _t_value_signals_only_on_change()
	failures += _t_ratio_with_zero_max_returns_zero()
	failures += _t_set_value_clamps()
	if failures > 0:
		print("GAUGE_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("GAUGE_TEST: all passed")
		quit(0)


func _make_gauge(max_v: float = 100.0, start_full: bool = true) -> Node:
	var s: Script = load("res://addons/gd-common/components/gauge_component.gd")
	var g: Node = s.new()
	g.max_value = max_v
	g.start_full = start_full
	root.add_child(g)  # triggers _ready() which sets current
	return g


func _t_initial_value_with_start_full() -> int:
	var g := _make_gauge(50.0, true)
	if absf(g.current - 50.0) > 0.001: return 1
	var g2 := _make_gauge(50.0, false)
	if absf(g2.current - 0.0) > 0.001: return 1
	return 0


func _t_drain_emits_depleted_at_zero() -> int:
	var g := _make_gauge(10.0, true)
	var dep: Array = [false]
	g.depleted.connect(func(): dep[0] = true)
	g.drain(5.0)
	if dep[0]: return 1   # not depleted yet
	g.drain(5.0)
	if not dep[0]: return 1
	if not g.is_depleted(): return 1
	return 0


func _t_fill_clamps_to_max() -> int:
	var g := _make_gauge(20.0, false)
	g.fill(1000.0)
	if absf(g.current - 20.0) > 0.001: return 1
	if absf(g.ratio() - 1.0) > 0.001: return 1
	return 0


func _t_value_signals_only_on_change() -> int:
	var g := _make_gauge(10.0, true)
	var hits: Array = [0]
	g.value_changed.connect(func(_c, _m): hits[0] += 1)
	g.set_value(10.0)  # equal -> no emit
	g.set_value(9.0)
	g.set_value(9.0)  # equal -> no emit
	if hits[0] != 1: return 1
	return 0


func _t_ratio_with_zero_max_returns_zero() -> int:
	var g := _make_gauge(0.0, true)
	# _ready would set current=0 by start_full when max_value=0
	if g.ratio() != 0.0: return 1
	return 0


func _t_set_value_clamps() -> int:
	var g := _make_gauge(10.0, true)
	g.set_value(-5.0)
	if g.current != 0.0: return 1
	g.set_value(50.0)
	if g.current != 10.0: return 1
	return 0
