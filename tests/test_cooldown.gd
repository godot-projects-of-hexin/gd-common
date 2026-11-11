extends SceneTree


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures: int = 0
	failures += _t_starts_not_ready_then_ready_after_update()
	failures += _t_finished_fires_once_at_zero()
	failures += _t_cancel_resets_without_signal()
	failures += _t_progress_linear_to_one()
	failures += _t_start_with_new_duration_overrides()
	if failures > 0:
		print("COOLDOWN_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("COOLDOWN_TEST: all passed")
		quit(0)
	return true


func _t_starts_not_ready_then_ready_after_update() -> int:
	var s: Script = load("res://addons/gd-common/utils/gx_cooldown.gd")
	var cd = s.new(1.0)
	# 刚构造出来 time_left 是 0，语义上就是「可用」——技能没在冷却。
	# 只有 start() 之后才进入冷却。
	if not cd.is_ready(): return 1
	cd.start(0.5)
	if cd.is_ready(): return 1
	cd.update(0.6)
	if not cd.is_ready(): return 1
	return 0


func _t_finished_fires_once_at_zero() -> int:
	var s: Script = load("res://addons/gd-common/utils/gx_cooldown.gd")
	var cd = s.new(0.5)
	var hits: Array = [0]
	cd.finished.connect(func(): hits[0] += 1)
	cd.start(0.5)
	cd.update(0.5)  # hits 0
	if hits[0] != 1: return 1
	cd.update(0.5)  # already at 0, update returns early
	if hits[0] != 1: return 1
	return 0


func _t_cancel_resets_without_signal() -> int:
	var s: Script = load("res://addons/gd-common/utils/gx_cooldown.gd")
	var cd = s.new(1.0)
	cd.start(1.0)
	var hits: Array = [0]
	cd.finished.connect(func(): hits[0] += 1)
	cd.cancel()
	if not cd.is_ready(): return 1
	if hits[0] != 0: return 1
	return 0


func _t_progress_linear_to_one() -> int:
	var s: Script = load("res://addons/gd-common/utils/gx_cooldown.gd")
	var cd = s.new(1.0)
	cd.start(1.0)
	if absf(cd.progress() - 0.0) > 0.001: return 1
	cd.update(0.5)
	if absf(cd.progress() - 0.5) > 0.001: return 1
	cd.update(0.5)
	if absf(cd.progress() - 1.0) > 0.001: return 1
	return 0


func _t_start_with_new_duration_overrides() -> int:
	var s: Script = load("res://addons/gd-common/utils/gx_cooldown.gd")
	var cd = s.new(1.0)
	cd.start(1.0)
	cd.start(2.0)
	if absf(cd.duration - 2.0) > 0.001: return 1
	if absf(cd.time_left - 2.0) > 0.001: return 1
	return 0
