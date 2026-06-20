extends Node
## Generic UI panel-stack manager (gd-common). Autoload: UIManager.
## Manages a stack of Control panels on a dedicated CanvasLayer.
## Knows nothing about specific panels; instance them and push.

const BASE_LAYER := 100

var _layer: CanvasLayer
var _stack: Array[Control] = []


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = BASE_LAYER
	add_child(_layer)


## Instance a packed scene (root must be a Control) and push it on top.
func push_panel(packed: PackedScene) -> Control:
	if packed == null:
		return null
	var panel := packed.instantiate()
	if panel is not Control:
		push_error("UIManager.push_panel: scene root is not a Control")
		panel.queue_free()
		return null
	return push_panel_node(panel as Control)


## Push an already-instanced Control on top of the stack.
func push_panel_node(panel: Control) -> Control:
	if _stack.size() > 0:
		_stack.back().visible = false
	_layer.add_child(panel)
	_stack.append(panel)
	return panel


## Pop and free the top panel; re-show the one beneath.
func pop_panel() -> void:
	if _stack.is_empty():
		return
	var top: Control = _stack.pop_back()
	if is_instance_valid(top):
		top.queue_free()
	if _stack.size() > 0:
		_stack.back().visible = true


func get_top() -> Control:
	if _stack.is_empty():
		return null
	return _stack.back()


func clear() -> void:
	for panel in _stack:
		if is_instance_valid(panel):
			panel.queue_free()
	_stack.clear()


func stack_size() -> int:
	return _stack.size()
