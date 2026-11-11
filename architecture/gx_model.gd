class_name GxModel
extends RefCounted
## Data layer — owns state and the methods that read or change it.
##
## A Model is the single source of truth for one slice of game state. It may
## reach *down* to a Utility and notify *up* with an event, but it must never
## query a System or another Model: that would turn the data layer into a
## second business layer.
##
## [b]May do:[/b] declare state, expose read and write methods, get a Utility,
## send an Event, expose a [GxBindableProperty].[br]
## [b]May not do:[/b] get a Model, get a System, send a Command, send a Query.
## [codeblock]
## class_name PlayerModel
## extends GxModel
##
## var score := GxBindableProperty.new(0)
##
## func add_score(amount: int) -> void:
##     score.set_value(score.get_value() + amount)
## [/codeblock]

var _architecture: GxArchitecture = null


## Framework internal. Called by [GxArchitecture] on registration.
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture = architecture


## Called once by [GxArchitecture] after registration. Override for setup.
func _on_init() -> void:
	pass


## Called by [method GxArchitecture.deinitialize]. Override to release resources.
func _on_deinit() -> void:
	pass


## Resolve a registered Utility. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	if _architecture == null:
		push_error("GxModel.get_utility: model is not registered to an architecture")
		return null
	return _architecture.get_utility(utility_script)


## Broadcast a fact that already happened. Never used to ask for work.
func send_event(event: Object) -> void:
	if _architecture == null:
		push_error("GxModel.send_event: model is not registered to an architecture")
		return
	_architecture.send_event(event)
