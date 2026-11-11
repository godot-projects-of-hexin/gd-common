class_name GxSystem
extends RefCounted
## System layer — business logic shared by more than one presentation node.
##
## Put a rule here when it is not owned by any single scene: scoring,
## achievements, quests, a shop, a day-night clock. A System reads and writes
## Models, coordinates with other Systems, and reacts to events. It must not
## touch the scene tree or any Control, because then it would be presentation.
##
## [b]May do:[/b] get a System, get a Model, get a Utility, send an Event,
## register for an Event.[br]
## [b]May not do:[/b] send a Command, hold node references, build UI.
## [codeblock]
## class_name ScoreSystem
## extends GxSystem
##
## func _on_init() -> void:
##     register_event(EnemyKilledEvent, _on_enemy_killed)
##
## func _on_enemy_killed(event: EnemyKilledEvent) -> void:
##     var player := get_model(PlayerModel) as PlayerModel
##     player.add_score(event.reward)
## [/codeblock]

var _architecture: GxArchitecture = null


## Framework internal. Called by [GxArchitecture] on registration.
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture = architecture


## Called once by [GxArchitecture] after registration. Register events here.
func _on_init() -> void:
	pass


## Called by [method GxArchitecture.deinitialize]. Override to release resources.
func _on_deinit() -> void:
	pass


## Resolve another registered System. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	if _architecture == null:
		push_error("GxSystem.get_system: system is not registered to an architecture")
		return null
	return _architecture.get_system(system_script)


## Resolve a registered Model. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	if _architecture == null:
		push_error("GxSystem.get_model: system is not registered to an architecture")
		return null
	return _architecture.get_model(model_script)


## Resolve a registered Utility. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	if _architecture == null:
		push_error("GxSystem.get_utility: system is not registered to an architecture")
		return null
	return _architecture.get_utility(utility_script)


## Broadcast a fact that already happened.
func send_event(event: Object) -> void:
	if _architecture == null:
		push_error("GxSystem.send_event: system is not registered to an architecture")
		return
	_architecture.send_event(event)


## React to an event class. Systems live as long as the architecture, so there
## is no automatic unregister — call [method unregister_event] in
## [method _on_deinit] if the handler must stop earlier.
func register_event(event_script: Script, handler: Callable) -> void:
	if _architecture == null:
		push_error("GxSystem.register_event: system is not registered to an architecture")
		return
	_architecture.register_event(event_script, handler)


## Stop reacting to an event class.
func unregister_event(event_script: Script, handler: Callable) -> void:
	if _architecture == null:
		return
	_architecture.unregister_event(event_script, handler)
