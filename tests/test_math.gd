extends SceneTree
## GxMath tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_math.gd

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_approach_never_overshoots()
	failures += _t_approach_handles_equal_and_zero_delta()
	failures += _t_remap_clamped_midpoint()
	failures += _t_remap_clamped_clamps_out_of_range_input()
	failures += _t_remap_clamped_supports_reversed_output()
	failures += _t_chance_bounds()
	failures += _t_pick_random_empty_and_single()
	if failures > 0:
		print("MATH_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("MATH_TEST: all passed")
		quit(0)
	return true


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _t_approach_never_overshoots() -> int:
	if not is_equal_approx(GxMath.approach(5.0, 10.0, 3.0), 8.0):
		return _fail("approach(5, 10, 3) should be 8")
	if not is_equal_approx(GxMath.approach(5.0, 10.0, 100.0), 10.0):
		return _fail("approach must clamp to the target when delta is large")
	if not is_equal_approx(GxMath.approach(10.0, 0.0, 3.0), 7.0):
		return _fail("approach should also move downwards")
	if not is_equal_approx(GxMath.approach(10.0, 0.0, 100.0), 0.0):
		return _fail("downwards approach must not overshoot")
	return 0


func _t_approach_handles_equal_and_zero_delta() -> int:
	if not is_equal_approx(GxMath.approach(5.0, 5.0, 3.0), 5.0):
		return _fail("approach with equal endpoints should stay put")
	if not is_equal_approx(GxMath.approach(5.0, 10.0, 0.0), 5.0):
		return _fail("approach with zero delta should not move")
	return 0


func _t_remap_clamped_midpoint() -> int:
	if not is_equal_approx(GxMath.remap_clamped(5.0, 0.0, 10.0, 0.0, 100.0), 50.0):
		return _fail("midpoint should remap to the output midpoint")
	if not is_equal_approx(GxMath.remap_clamped(0.0, 0.0, 10.0, 20.0, 40.0), 20.0):
		return _fail("in_min should map to out_min")
	return 0


func _t_remap_clamped_clamps_out_of_range_input() -> int:
	if not is_equal_approx(GxMath.remap_clamped(-5.0, 0.0, 10.0, 0.0, 100.0), 0.0):
		return _fail("below in_min should clamp to out_min")
	if not is_equal_approx(GxMath.remap_clamped(15.0, 0.0, 10.0, 0.0, 100.0), 100.0):
		return _fail("above in_max should clamp to out_max")
	return 0


func _t_remap_clamped_supports_reversed_output() -> int:
	if not is_equal_approx(GxMath.remap_clamped(5.0, 0.0, 10.0, 100.0, 0.0), 50.0):
		return _fail("reversed output range should still remap linearly")
	return 0


func _t_chance_bounds() -> int:
	if GxMath.chance(0.0):
		return _fail("chance(0.0) must never succeed")
	if not GxMath.chance(1.0):
		return _fail("chance(1.0) must always succeed")
	return 0


func _t_pick_random_empty_and_single() -> int:
	if GxMath.pick_random([]) != null:
		return _fail("pick_random on an empty array should return null")
	if GxMath.pick_random([7]) != 7:
		return _fail("pick_random on a single-element array should return that element")
	var typed: Array[int] = [11]
	if int(GxMath.pick_random(typed)) != 11:
		return _fail("pick_random should accept typed arrays")
	return 0
