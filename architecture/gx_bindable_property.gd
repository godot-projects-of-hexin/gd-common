class_name GxBindableProperty
extends RefCounted
## A single observable value, for state the presentation layer must mirror.
##
## Use this instead of a plain field plus a hand-written signal when a Model
## value drives UI. [method bind] delivers the current value immediately and
## then on every change, which removes the usual "UI shows a stale value until
## the first update" bug.
## [codeblock]
## # In the Model
## var score := GxBindableProperty.new(0)
##
## # In the Controller
## player.score.bind(_on_score_changed)
##
## func _on_score_changed(value: int) -> void:
##     label.text = str(value)
## [/codeblock]
## Pass a comparer for types where [code]==[/code] is too strict or too loose,
## for example floats that should ignore sub-epsilon jitter:
## [codeblock]
## var health := GxBindableProperty.new(
##     100.0,
##     func(a: float, b: float) -> bool: return is_equal_approx(a, b),
## )
## [/codeblock]

## Emitted after the value actually changed. Carries only the new value, so a
## handler always takes exactly one argument — mismatched argument counts are
## the most common cause of signal errors in Godot.
signal value_changed(new_value: Variant)

var _value: Variant = null
## Callable(a, b) -> bool returning true when the two values count as equal.
var _comparer: Callable = Callable()
## Set only for bindables owned by a registered Model. See [GxWriteGuard].
var _guarded := false


func _init(initial_value: Variant = null, comparer: Callable = Callable()) -> void:
	_value = initial_value
	_comparer = comparer


## Read the current value.
func get_value() -> Variant:
	return _value


## Framework internal. [GxArchitecture] marks bindables owned by a registered
## Model; see [GxWriteGuard].
func _set_guarded(value: bool) -> void:
	_guarded = value


func _check_write(method_name: String) -> void:
	if _guarded and not GxWriteGuard.allows_write():
		GxWriteGuard.report(method_name)


## Write the value. Emits [signal value_changed] only on a real change.
func set_value(new_value: Variant) -> void:
	_check_write("set_value")
	if _values_equal(_value, new_value):
		return
	_value = new_value
	value_changed.emit(_value)


## Write the value without emitting. Use when loading a save, where the UI is
## rebuilt afterwards and an extra notification would just be noise.
func set_value_silent(new_value: Variant) -> void:
	_check_write("set_value_silent")
	_value = new_value


## Re-broadcast the current value to every bound handler without changing it.
## Call this after a batch of silent writes (e.g. restoring a save) so views
## that were already bound can rebuild themselves from the new state.
func notify() -> void:
	value_changed.emit(_value)


## Subscribe and receive the current value immediately.
## Prefer a named method over a lambda so [method unbind] can find it again.
func bind(handler: Callable) -> void:
	if not handler.is_valid():
		push_error("GxBindableProperty.bind: handler is not valid")
		return
	handler.call(_value)
	_connect_handler(handler)


## Subscribe without receiving the current value.
func bind_without_init(handler: Callable) -> void:
	if not handler.is_valid():
		push_error("GxBindableProperty.bind_without_init: handler is not valid")
		return
	_connect_handler(handler)


## Remove a previously bound handler.
func unbind(handler: Callable) -> void:
	if value_changed.is_connected(handler):
		value_changed.disconnect(handler)


## True if the handler is currently bound.
func is_bound(handler: Callable) -> bool:
	return value_changed.is_connected(handler)


## Remove every bound handler.
func unbind_all() -> void:
	for connection: Dictionary in value_changed.get_connections():
		value_changed.disconnect(connection["callable"] as Callable)


func _connect_handler(handler: Callable) -> void:
	if value_changed.is_connected(handler):
		return
	value_changed.connect(handler)


func _values_equal(a: Variant, b: Variant) -> bool:
	if _comparer.is_valid():
		return bool(_comparer.call(a, b))
	return a == b
