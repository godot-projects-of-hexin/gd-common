extends SceneTree
## UIManager panel-stack tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_ui_manager.gd
##
## Each case builds its own manager. The suite quits immediately, so nodes are
## freed explicitly in _cleanup() instead of relying on queue_free() being
## flushed at the end of a frame.

class Recorder:
	var entries: Array = []

	func on_pushed(_panel: Control) -> void:
		entries.append("pushed")

	func on_will_pop(_panel: Control) -> void:
		entries.append("will_pop")

	func on_popped() -> void:
		entries.append("popped")


var _done := false
var _managers: Array[Node] = []
var _panels: Array[Control] = []


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_layer_uses_base_layer()
	failures += _t_push_panel_node_returns_the_panel()
	failures += _t_second_push_hides_the_first()
	failures += _t_pop_restores_the_panel_beneath()
	failures += _t_pop_on_empty_stack_is_a_no_op()
	failures += _t_get_top_tracks_the_stack()
	failures += _t_push_panel_rejects_null_scene()
	failures += _t_clear_empties_the_stack()
	failures += _t_stack_signals_fire_in_order()
	failures += _t_set_layer_reconfigures_host()
	_cleanup()
	if failures > 0:
		print("UI_MANAGER_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("UI_MANAGER_TEST: all passed")
		quit(0)
	return true


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _make_manager() -> Node:
	var script: Script = load("res://addons/gd-common/core/ui_manager.gd")
	var manager: Node = script.new()
	root.add_child(manager)
	_managers.append(manager)
	return manager


func _make_panel() -> Control:
	var panel := Control.new()
	_panels.append(panel)
	return panel


func _cleanup() -> void:
	for panel in _panels:
		if is_instance_valid(panel):
			panel.free()
	_panels.clear()
	for manager in _managers:
		if is_instance_valid(manager):
			manager.free()
	_managers.clear()


func _t_layer_uses_base_layer() -> int:
	var manager := _make_manager()
	for child in manager.get_children():
		if child is CanvasLayer:
			if (child as CanvasLayer).layer != manager.BASE_LAYER:
				return _fail("CanvasLayer.layer should be BASE_LAYER (%d)" % manager.BASE_LAYER)
			return 0
	return _fail("UIManager did not create a CanvasLayer child")


func _t_push_panel_node_returns_the_panel() -> int:
	var manager := _make_manager()
	var panel := _make_panel()
	if manager.push_panel_node(panel) != panel:
		return _fail("push_panel_node should return the pushed panel")
	if manager.stack_size() != 1:
		return _fail("stack_size should be 1 after one push")
	if panel.get_parent() == null:
		return _fail("pushed panel was not added to the tree")
	return 0


func _t_second_push_hides_the_first() -> int:
	var manager := _make_manager()
	var first := _make_panel()
	var second := _make_panel()
	manager.push_panel_node(first)
	manager.push_panel_node(second)
	if first.visible:
		return _fail("lower panel should be hidden while another panel is on top")
	if not second.visible:
		return _fail("top panel should stay visible")
	return 0


func _t_pop_restores_the_panel_beneath() -> int:
	var manager := _make_manager()
	var first := _make_panel()
	var second := _make_panel()
	manager.push_panel_node(first)
	manager.push_panel_node(second)
	manager.pop_panel()
	if manager.get_top() != first:
		return _fail("get_top should return the panel beneath after pop")
	if not first.visible:
		return _fail("pop should re-show the panel beneath")
	if manager.stack_size() != 1:
		return _fail("stack_size should be 1 after pop")
	return 0


func _t_pop_on_empty_stack_is_a_no_op() -> int:
	var manager := _make_manager()
	manager.pop_panel()
	manager.pop_panel()
	if manager.stack_size() != 0 or manager.get_top() != null:
		return _fail("pop on an empty stack changed the stack")
	return 0


func _t_get_top_tracks_the_stack() -> int:
	var manager := _make_manager()
	if manager.get_top() != null:
		return _fail("get_top on an empty stack should be null")
	var first := _make_panel()
	var second := _make_panel()
	manager.push_panel_node(first)
	if manager.get_top() != first:
		return _fail("get_top did not return the first panel")
	manager.push_panel_node(second)
	if manager.get_top() != second:
		return _fail("get_top did not return the newest panel")
	return 0


func _t_push_panel_rejects_null_scene() -> int:
	var manager := _make_manager()
	if manager.push_panel(null) != null:
		return _fail("push_panel(null) should return null")
	if manager.stack_size() != 0:
		return _fail("push_panel(null) should not touch the stack")
	return 0


func _t_clear_empties_the_stack() -> int:
	var manager := _make_manager()
	for i in 3:
		manager.push_panel_node(_make_panel())
	manager.clear()
	if manager.stack_size() != 0 or manager.get_top() != null:
		return _fail("clear() did not empty the stack")
	return 0


func _t_stack_signals_fire_in_order() -> int:
	var manager := _make_manager()
	var recorder := Recorder.new()
	manager.panel_pushed.connect(recorder.on_pushed)
	manager.panel_will_pop.connect(recorder.on_will_pop)
	manager.panel_popped.connect(recorder.on_popped)
	manager.push_panel_node(_make_panel())
	manager.pop_panel()
	if recorder.entries != ["pushed", "will_pop", "popped"]:
		return _fail("unexpected signal order: %s" % str(recorder.entries))
	return 0


func _t_set_layer_reconfigures_host() -> int:
	var manager := _make_manager()
	if manager.get_layer() != manager.BASE_LAYER:
		return _fail("default layer should be BASE_LAYER")
	manager.set_layer(220)
	if manager.get_layer() != 220:
		return _fail("set_layer did not change the host layer")
	var panel := _make_panel()
	manager.push_panel_node(panel)
	var host := panel.get_parent() as CanvasLayer
	if host == null or host.layer != 220:
		return _fail("existing panels should follow the reconfigured host")
	return 0
