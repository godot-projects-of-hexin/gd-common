extends SceneTree
## GxBindableProperty tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_bindable_property.gd


class Observer:
	var values: Array = []
	var call_count := 0

	func on_value(value: Variant) -> void:
		call_count += 1
		values.append(value)


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_bind_delivers_current_value()
	failures += _t_bind_without_init_skips_first_call()
	failures += _t_no_emit_when_value_unchanged()
	failures += _t_set_value_silent_does_not_emit()
	failures += _t_unbind_stops_delivery()
	failures += _t_duplicate_bind_is_ignored()
	failures += _t_custom_comparer_is_used()
	failures += _t_unbind_all_clears()
	if failures > 0:
		print("BINDABLE_PROPERTY_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("BINDABLE_PROPERTY_TEST: all passed")
		quit(0)
	return true


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _t_bind_delivers_current_value() -> int:
	var property := GxBindableProperty.new(5)
	var observer := Observer.new()
	property.bind(observer.on_value)
	if observer.values != [5]:
		return _fail("bind() should deliver the current value immediately, got %s" % str(observer.values))
	property.set_value(9)
	if observer.values != [5, 9]:
		return _fail("change was not delivered, got %s" % str(observer.values))
	return 0


func _t_bind_without_init_skips_first_call() -> int:
	var property := GxBindableProperty.new(5)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	if observer.call_count != 0:
		return _fail("bind_without_init must not call the handler immediately")
	property.set_value(6)
	if observer.values != [6]:
		return _fail("change was not delivered after bind_without_init")
	return 0


func _t_no_emit_when_value_unchanged() -> int:
	var property := GxBindableProperty.new(3)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	property.set_value(3)
	if observer.call_count != 0:
		return _fail("setting the same value must not emit")
	return 0


func _t_set_value_silent_does_not_emit() -> int:
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	property.set_value_silent(42)
	if observer.call_count != 0:
		return _fail("set_value_silent must not emit")
	if int(property.get_value()) != 42:
		return _fail("set_value_silent did not store the value")
	return 0


func _t_unbind_stops_delivery() -> int:
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	property.unbind(observer.on_value)
	if property.is_bound(observer.on_value):
		return _fail("is_bound should be false after unbind")
	property.set_value(1)
	if observer.call_count != 0:
		return _fail("handler still fired after unbind")
	return 0


func _t_duplicate_bind_is_ignored() -> int:
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	property.bind_without_init(observer.on_value)
	property.set_value(1)
	if observer.call_count != 1:
		return _fail("duplicate bind caused %d calls, expected 1" % observer.call_count)
	return 0


func _t_custom_comparer_is_used() -> int:
	var property := GxBindableProperty.new(
		1.0,
		func(a: Variant, b: Variant) -> bool: return absf(float(a) - float(b)) < 0.5,
	)
	var observer := Observer.new()
	property.bind_without_init(observer.on_value)
	property.set_value(1.2)
	if observer.call_count != 0:
		return _fail("comparer should have treated 1.2 as equal to 1.0")
	property.set_value(2.0)
	if observer.call_count != 1:
		return _fail("comparer should have treated 2.0 as different")
	return 0


func _t_unbind_all_clears() -> int:
	var property := GxBindableProperty.new(0)
	var first := Observer.new()
	var second := Observer.new()
	property.bind_without_init(first.on_value)
	property.bind_without_init(second.on_value)
	property.unbind_all()
	property.set_value(1)
	if first.call_count != 0 or second.call_count != 0:
		return _fail("unbind_all did not remove every handler")
	return 0
