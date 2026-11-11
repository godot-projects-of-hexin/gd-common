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

## 架构的弱引用。
##
## 架构通过容器强引用 Model，所以反向**必须**是弱引用：两个 RefCounted 互相
## 强引用会让引用计数永远归不了零，退出时报
## 「ObjectDB instances were leaked at exit」。
## 已在 Godot 4.7 实测确认 weakref() 不会增加目标的 get_reference_count()。
var _architecture_ref: WeakRef = null


## Framework internal. Called by [GxArchitecture] on registration.
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture_ref = weakref(architecture) if architecture != null else null


## Called once by [GxArchitecture] after registration. Override for setup.
func _on_init() -> void:
	pass


## Called by [method GxArchitecture.deinitialize]. Override to release resources.
func _on_deinit() -> void:
	pass


## Resolve a registered Utility. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxModel.get_utility: model is not registered to a live architecture")
		return null
	return architecture.get_utility(utility_script)


## Broadcast a fact that already happened. Never used to ask for work.
func send_event(event: Object) -> void:
	var architecture := _resolve_architecture()
	if architecture == null:
		push_error("GxModel.send_event: model is not registered to a live architecture")
		return
	architecture.send_event(event)


func _resolve_architecture() -> GxArchitecture:
	if _architecture_ref == null:
		return null
	return _architecture_ref.get_ref() as GxArchitecture
