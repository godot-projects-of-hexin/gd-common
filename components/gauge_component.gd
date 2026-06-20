class_name GxGaugeComponent
extends Node
## Generic bounded gauge component (gd-common).
## Models a value in [0, max_value] with optional time-based drain/refill.
## Use cases: customer patience, health, stamina, loading/charge bars.
## Mount as a child node of an actor; the host listens to the signals.

signal value_changed(current: float, maximum: float)
signal depleted   ## current reached 0
signal filled     ## current reached max_value

@export var max_value: float = 100.0
@export var start_full: bool = true
## Units per second. Positive = drain toward 0, negative = refill toward max. 0 = manual only.
@export var auto_rate: float = 0.0
@export var auto_active: bool = true
## Multiplier applied to auto_rate (e.g. rush customers = 1.5).
@export var rate_scale: float = 1.0

var current: float = 0.0


func _ready() -> void:
	current = max_value if start_full else 0.0
	value_changed.emit(current, max_value)


func _process(delta: float) -> void:
	if auto_rate == 0.0 or not auto_active:
		return
	_apply(-auto_rate * rate_scale * delta)


## Reduce the value (clamped). Emits signals on change.
func drain(amount: float) -> void:
	_apply(-absf(amount))


## Increase the value (clamped). Emits signals on change.
func fill(amount: float) -> void:
	_apply(absf(amount))


## Set the value directly (clamped).
func set_value(value: float) -> void:
	var clamped := clampf(value, 0.0, max_value)
	if is_equal_approx(clamped, current):
		return
	current = clamped
	value_changed.emit(current, max_value)
	_check_bounds()


func reset() -> void:
	set_value(max_value if start_full else 0.0)


func ratio() -> float:
	if max_value <= 0.0:
		return 0.0
	return current / max_value


func is_depleted() -> bool:
	return current <= 0.0


func _apply(amount: float) -> void:
	var before := current
	current = clampf(current + amount, 0.0, max_value)
	if not is_equal_approx(before, current):
		value_changed.emit(current, max_value)
		_check_bounds()


func _check_bounds() -> void:
	if current <= 0.0:
		depleted.emit()
	elif current >= max_value:
		filled.emit()
