class_name GxCooldown
extends RefCounted
## Lightweight manual cooldown timer (gd-common). Tick with update(delta).

signal finished

var duration: float = 1.0
var time_left: float = 0.0


func _init(p_duration: float = 1.0) -> void:
	duration = p_duration


func start(p_duration: float = -1.0) -> void:
	if p_duration > 0.0:
		duration = p_duration
	time_left = duration


func update(delta: float) -> void:
	if time_left <= 0.0:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		finished.emit()


func is_ready() -> bool:
	return time_left <= 0.0


func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(1.0 - time_left / duration, 0.0, 1.0)
