extends SceneTree
## GxObjectPool tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_object_pool.gd


class Box extends RefCounted:
	var value := 0


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_prewarm_creates_and_resets()
	failures += _t_acquire_reuses_a_pooled_instance()
	failures += _t_acquire_creates_when_pool_is_empty()
	failures += _t_release_calls_reset_callback()
	failures += _t_duplicate_release_is_ignored()
	failures += _t_release_null_is_a_no_op()
	failures += _t_pool_works_without_reset_callback()
	if failures > 0:
		print("OBJECT_POOL_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("OBJECT_POOL_TEST: all passed")
		quit(0)
	return true


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _factory(counter: Array) -> Callable:
	return func() -> Box:
		counter[0] += 1
		return Box.new()


func _t_prewarm_creates_and_resets() -> int:
	var created: Array = [0]
	var resets: Array = [0]
	var on_release := func(_box: Box) -> void:
		resets[0] += 1
	var pool := GxObjectPool.new(_factory(created), 3, on_release)
	if created[0] != 3:
		return _fail("prewarm should call the factory 3 times, got %d" % created[0])
	if resets[0] != 3:
		return _fail("prewarm should reset each instance, got %d resets" % resets[0])
	if pool.available_count() != 3:
		return _fail("prewarm should leave 3 available instances")
	return 0


func _t_acquire_reuses_a_pooled_instance() -> int:
	var created: Array = [0]
	var pool := GxObjectPool.new(_factory(created), 1)
	var first: Box = pool.acquire()
	if created[0] != 1:
		return _fail("acquire should have reused the prewarmed instance")
	if pool.available_count() != 0:
		return _fail("acquire did not take the instance out of the pool")
	pool.release(first)
	var second: Box = pool.acquire()
	if second != first:
		return _fail("acquire did not return the released instance")
	if created[0] != 1:
		return _fail("factory ran again even though an instance was available")
	return 0


func _t_acquire_creates_when_pool_is_empty() -> int:
	var created: Array = [0]
	var pool := GxObjectPool.new(_factory(created))
	var first: Box = pool.acquire()
	var second: Box = pool.acquire()
	if first == second:
		return _fail("two acquires with an empty pool returned the same object")
	if created[0] != 2:
		return _fail("factory should have run twice, got %d" % created[0])
	if pool.available_count() != 0:
		return _fail("acquire must not leave instances in the pool")
	return 0


func _t_release_calls_reset_callback() -> int:
	var created: Array = [0]
	var resets: Array = [0]
	var on_release := func(box: Box) -> void:
		box.value = 0
		resets[0] += 1
	var pool := GxObjectPool.new(_factory(created), 0, on_release)
	var box: Box = pool.acquire()
	box.value = 7
	pool.release(box)
	if box.value != 0:
		return _fail("on_release callback did not reset the object")
	if resets[0] != 1:
		return _fail("on_release callback should run once per release")
	if pool.available_count() != 1:
		return _fail("release did not return the object to the pool")
	return 0


func _t_duplicate_release_is_ignored() -> int:
	var created: Array = [0]
	var pool := GxObjectPool.new(_factory(created))
	var box: Box = pool.acquire()
	pool.release(box)
	pool.release(box)
	if pool.available_count() != 1:
		return _fail("duplicate release appended the same object twice")
	return 0


func _t_release_null_is_a_no_op() -> int:
	var created: Array = [0]
	var pool := GxObjectPool.new(_factory(created))
	pool.release(null)
	if pool.available_count() != 0:
		return _fail("release(null) changed the pool")
	return 0


func _t_pool_works_without_reset_callback() -> int:
	var created: Array = [0]
	var pool := GxObjectPool.new(_factory(created), 2)
	var box: Box = pool.acquire()
	pool.release(box)
	if pool.available_count() != 2:
		return _fail("pool without on_release should still round-trip instances")
	return 0
