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

## 架构的弱引用。
##
## 架构通过容器强引用 System，所以反向**必须**是弱引用：两个 RefCounted 互相
## 强引用会让引用计数永远归不了零，退出时报
## 「ObjectDB instances were leaked at exit」。
## 已在 Godot 4.7 实测确认 weakref() 不会增加目标的 get_reference_count()。
var _architecture_ref: WeakRef = null


## Framework internal. Called by [GxArchitecture] on registration.
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture_ref = weakref(architecture) if architecture != null else null


## Called once by [GxArchitecture] after registration. Register events here.
func _on_init() -> void:
	pass


## Called by [method GxArchitecture.deinitialize]. Override to release resources.
func _on_deinit() -> void:
	pass


## Resolve another registered System. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxSystem.get_system: system is not registered to a live architecture")
		return null
	return architecture.get_system(system_script)


## Resolve a registered Model. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxSystem.get_model: system is not registered to a live architecture")
		return null
	return architecture.get_model(model_script)


## Resolve a registered Utility. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxSystem.get_utility: system is not registered to a live architecture")
		return null
	return architecture.get_utility(utility_script)


## Broadcast a fact that already happened.
func send_event(event: Object) -> void:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxSystem.send_event: system is not registered to a live architecture")
		return
	architecture.send_event(event)


## React to an event class. Systems live as long as the architecture, so there
## is no automatic unregister — call [method unregister_event] in
## [method _on_deinit] if the handler must stop earlier.
func register_event(event_script: Script, handler: Callable) -> void:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxSystem.register_event: system is not registered to a live architecture")
		return
	architecture.register_event(event_script, handler)


## Stop reacting to an event class.
func unregister_event(event_script: Script, handler: Callable) -> void:
	var architecture := _resolve_architecture()
	if architecture == null:
		return
	architecture.unregister_event(event_script, handler)


func _resolve_architecture() -> GxArchitecture:
	if _architecture_ref == null:
		return null
	return _architecture_ref.get_ref() as GxArchitecture
