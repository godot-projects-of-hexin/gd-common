extends SceneTree
## GxController lifecycle tests: automatic disposal, idempotency and cleanup
## of event registrations / property bindings.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_controller_lifecycle.gd


class ProbeEvent extends GxEvent:
	pass


class Observer extends RefCounted:
	var values: Array = []
	var events: Array = []

	func on_value(value: Variant) -> void:
		values.append(value)

	func on_event(_event: ProbeEvent) -> void:
		events.append(true)


class ReenterNode extends GxControllerNode:
	var ready_calls := 0
	var _arch: GxArchitecture

	func _init(architecture: GxArchitecture) -> void:
		_arch = architecture

	func _resolve_architecture() -> GxArchitecture:
		return _arch

	func _on_controller_ready() -> void:
		ready_calls += 1


var _done := false
var _owners: Array[Node] = []


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_tree_exiting_disposes_and_unbinds()
	failures += _t_dispose_is_idempotent()
	failures += _t_auto_dispose_false_requires_manual_dispose()
	failures += _t_event_registration_is_released_on_dispose()
	failures += _t_duplicate_registrations_are_ignored()
	failures += _t_reentering_tree_replays_ready_hook()
	_cleanup()
	if failures > 0:
		print("CONTROLLER_LIFECYCLE_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("CONTROLLER_LIFECYCLE_TEST: all passed")
		quit(0)
	return true


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _make_owner() -> Node:
	var node := Node.new()
	root.add_child(node)
	_owners.append(node)
	return node


func _cleanup() -> void:
	for node in _owners:
		if is_instance_valid(node):
			node.free()
	_owners.clear()
	GxArchitecture.clear_default()


func _t_tree_exiting_disposes_and_unbinds() -> int:
	var architecture := GxArchitecture.new()
	var owner := _make_owner()
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	var controller := GxController.new(owner, architecture, true)
	controller.bind(property, observer.on_value)
	property.set_value(5)
	# bind() calls the handler once with the current value (0) before changes.
	if observer.values != [0, 5]:
		return _fail("binding did not deliver the initial value and the first change")
	root.remove_child(owner)
	if not controller.is_disposed():
		return _fail("tree_exiting should dispose the controller")
	property.set_value(9)
	if observer.values != [0, 5]:
		return _fail("property binding survived automatic disposal")
	if property.is_bound(observer.on_value):
		return _fail("handler is still connected after disposal")
	return 0


func _t_dispose_is_idempotent() -> int:
	var architecture := GxArchitecture.new()
	var owner := _make_owner()
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	var controller := GxController.new(owner, architecture, true)
	controller.bind(property, observer.on_value)
	controller.dispose()
	controller.dispose()
	if not controller.is_disposed():
		return _fail("dispose should set the disposed flag")
	property.set_value(3)
	if observer.values != [0]:
		return _fail("a second dispose released something twice and broke cleanup")
	return 0


func _t_auto_dispose_false_requires_manual_dispose() -> int:
	var architecture := GxArchitecture.new()
	var owner := _make_owner()
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	var controller := GxController.new(owner, architecture, false)
	controller.bind(property, observer.on_value)
	root.remove_child(owner)
	if controller.is_disposed():
		return _fail("auto_dispose=false must not dispose on tree_exiting")
	property.set_value(3)
	if observer.values != [0, 3]:
		return _fail("binding should stay live until dispose() is called")
	controller.dispose()
	property.set_value(4)
	if observer.values != [0, 3]:
		return _fail("manual dispose did not release the binding")
	return 0


func _t_event_registration_is_released_on_dispose() -> int:
	var architecture := GxArchitecture.new()
	var owner := _make_owner()
	var observer := Observer.new()
	var controller := GxController.new(owner, architecture, true)
	controller.register_event(ProbeEvent, observer.on_event)
	if not architecture.has_event_handlers(ProbeEvent):
		return _fail("register_event did not reach the architecture")
	architecture.send_event(ProbeEvent.new())
	if observer.events.size() != 1:
		return _fail("event handler did not fire before disposal")
	controller.dispose()
	if architecture.has_event_handlers(ProbeEvent):
		return _fail("event registration survived disposal")
	architecture.send_event(ProbeEvent.new())
	if observer.events.size() != 1:
		return _fail("event handler still fired after disposal")
	return 0


func _t_duplicate_registrations_are_ignored() -> int:
	var architecture := GxArchitecture.new()
	var owner := _make_owner()
	var property := GxBindableProperty.new(0)
	var observer := Observer.new()
	var controller := GxController.new(owner, architecture, true)
	controller.bind(property, observer.on_value)
	controller.bind(property, observer.on_value)
	if observer.values != [0]:
		return _fail("duplicate bind fired the immediate callback twice")
	controller.register_event(ProbeEvent, observer.on_event)
	controller.register_event(ProbeEvent, observer.on_event)
	architecture.send_event(ProbeEvent.new())
	if observer.events.size() != 1:
		return _fail("duplicate register_event fired the handler twice")
	controller.dispose()
	if property.is_bound(observer.on_value):
		return _fail("dispose left a duplicate binding behind")
	if architecture.has_event_handlers(ProbeEvent):
		return _fail("dispose left a duplicate event registration behind")
	return 0


func _t_reentering_tree_replays_ready_hook() -> int:
	var architecture := GxArchitecture.new()
	var node := ReenterNode.new(architecture)
	root.add_child(node)
	_owners.append(node)
	if node.ready_calls != 1:
		return _fail("first _ready should replay the hook once")
	# 移出树 → tree_exiting 释放 controller；再加回来时 _ready() 不会重跑。
	root.remove_child(node)
	root.add_child(node)
	if node.ready_calls != 2:
		return _fail("re-entering the tree should rebuild the controller and replay the hook")
	return 0
