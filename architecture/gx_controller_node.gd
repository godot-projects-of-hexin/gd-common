class_name GxControllerNode
extends Node
## Presentation-layer base node with a [GxController] already wired up.
##
## Extend this for plain controller nodes. When the node must already extend
## another engine type ([Control], [CharacterBody2D], ...), hold a
## [GxController] instead — the available methods are identical.
##
## Override [method _on_controller_ready] rather than [method Node._ready], so
## the helper is guaranteed to exist before your code runs:
## [codeblock]
## class_name HudController
## extends GxControllerNode
##
## @onready var _score_label: Label = %ScoreLabel
##
## func _on_controller_ready() -> void:
##     var player := get_model(PlayerModel) as PlayerModel
##     bind(player.score, _on_score_changed)
##     register_event(GameOverEvent, _on_game_over)
##
## func _on_score_changed(value: int) -> void:
##     _score_label.text = str(value)
## [/codeblock]

var _controller: GxController = null


func _ready() -> void:
	_ensure_controller()
	_on_controller_ready()


## Override instead of [method Node._ready]. Runs once, after the helper exists.
func _on_controller_ready() -> void:
	pass


## Override to use an architecture other than the project default.
func _resolve_architecture() -> GxArchitecture:
	return GxArchitecture.get_default()


## The underlying helper, for the rare case you need to pass it around.
func get_controller() -> GxController:
	_ensure_controller()
	return _controller


## Resolve a registered System for reading. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	_ensure_controller()
	return _controller.get_system(system_script)


## Resolve a registered Model for reading. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	_ensure_controller()
	return _controller.get_model(model_script)


## Declare an intent to change state. The only write path available here.
func send_command(command: GxCommand) -> void:
	_ensure_controller()
	_controller.send_command(command)


## Ask a read-only question and get the answer.
func send_query(query: GxQuery) -> Variant:
	_ensure_controller()
	return _controller.send_query(query)


## React to an event class. Released automatically when this node leaves the tree.
func register_event(event_script: Script, handler: Callable) -> void:
	_ensure_controller()
	_controller.register_event(event_script, handler)


## Mirror a [GxBindableProperty]. Released automatically when this node leaves the tree.
func bind(property: GxBindableProperty, handler: Callable) -> void:
	_ensure_controller()
	_controller.bind(property, handler)


func _ensure_controller() -> void:
	if _controller == null or _controller.is_disposed():
		_controller = GxController.new(self, _resolve_architecture())
