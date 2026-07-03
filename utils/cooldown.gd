class_name GxCooldown
extends RefCounted
## Lightweight manual cooldown timer (gd-common). Drive with tick(delta).

signal finished

var duration: float = 1.0
var time_left: float = 0.0


func _init(p_duration: float = 1.0) -> void:
	duration = p_duration


func start(p_duration: float = -1.0) -> void:
	if p_duration > 0.0:
		duration = p_duration
	time_left = duration


## Advance the timer by `delta` seconds. Emits `finished` when time_left reaches 0.
func tick(delta: float) -> void:
	if time_left <= 0.0:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		finished.emit()


## True while time_left > 0 (the cooldown is counting down).
func is_running() -> bool:
	return time_left > 0.0


## Reset the cooldown to 0 WITHOUT emitting the `finished` signal.
## Use when you want to abort a pending trigger (e.g. player interrupted
## the action); reach for start() when you want a fresh tick instead.
func cancel() -> void:
	time_left = 0.0


func is_ready() -> bool:
	return time_left <= 0.0


func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(1.0 - time_left / duration, 0.0, 1.0)


# -- deprecated: kept for backward compatibility with code that calls .update(delta) --
func update(delta: float) -> void:
	tick(delta)
