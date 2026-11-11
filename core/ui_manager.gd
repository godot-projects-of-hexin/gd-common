extends Node
## Generic UI panel-stack manager (gd-common). Autoload: UIManager.
## Manages a stack of Control panels on a dedicated CanvasLayer.
## Knows nothing about specific panels; instance them and push.

signal panel_pushed(panel: Control)
## Emitted before the top panel is popped. Listeners can inspect or prevent
## neither — this is purely a notification so the panel can save state.
signal panel_will_pop(panel: Control)
signal panel_popped

## Default CanvasLayer.layer for the panel host. Projects whose own UI layers
## sit above 100 can call set_layer() at startup instead of editing this file.
const BASE_LAYER := 100

var _layer: CanvasLayer
var _stack: Array[Control] = []


func _ready() -> void:
	set_layer(BASE_LAYER)


## Configure the stacking layer of the panel host. Can be called before or
## after panels are pushed: the host moves as a whole, so existing panels keep
## their relative order.
func set_layer(layer_index: int) -> void:
	if _layer == null:
		_layer = CanvasLayer.new()
		add_child(_layer)
	_layer.layer = layer_index


func get_layer() -> int:
	return _layer.layer if _layer != null else BASE_LAYER


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
	panel_pushed.emit(panel)
	return panel


## Pop and free the top panel; re-show the one beneath.
func pop_panel() -> void:
	if _stack.is_empty():
		return
	var top: Control = _stack.back()
	panel_will_pop.emit(top)
	_stack.pop_back()
	if is_instance_valid(top):
		top.queue_free()
	if _stack.size() > 0:
		_stack.back().visible = true
	panel_popped.emit()


func get_top() -> Control:
	if _stack.is_empty():
		return null
	return _stack.back()


func clear() -> void:
	for panel in _stack:
		if is_instance_valid(panel):
			panel_will_pop.emit(panel)
			panel.queue_free()
	_stack.clear()
	panel_popped.emit()


func stack_size() -> int:
	return _stack.size()
