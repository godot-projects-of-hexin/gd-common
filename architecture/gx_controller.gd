class_name GxController
extends RefCounted
## Presentation-layer helper for nodes that cannot extend [GxControllerNode].
##
## A node that must already extend [CharacterBody2D], [Control] or any other
## engine type holds one of these instead of inheriting:
## [codeblock]
## extends CharacterBody2D
##
## var _ctrl: GxController
##
## func _ready() -> void:
##     _ctrl = GxController.new(self)
##     var player := _ctrl.get_model(PlayerModel) as PlayerModel
##     _ctrl.bind(player.score, _on_score_changed)
##     _ctrl.register_event(GameOverEvent, _on_game_over)
##
## func _on_hit() -> void:
##     _ctrl.send_command(TakeDamageCommand.new(10))
## [/codeblock]
## The presentation layer may read state and declare intent. It may not change
## state directly: there is no [code]get_utility()[/code] here, and the only
## write path is [method send_command].
##
## Event registrations and property bindings made through this helper are
## released automatically when the owner leaves the scene tree.

var _architecture: GxArchitecture = null
var _owner: Node = null
var _event_registrations: Array[Array] = []
var _property_bindings: Array[Array] = []
var _disposed := false


## [param owner] is the node that owns this helper, used for automatic cleanup.
## [param architecture] defaults to [method GxArchitecture.get_default].
## Set [param auto_dispose] to false when the owner is removed from the tree
## and re-added later, and call [method dispose] yourself instead.
func _init(owner: Node, architecture: GxArchitecture = null, auto_dispose: bool = true) -> void:
	_owner = owner
	_architecture = architecture if architecture != null else GxArchitecture.get_default()
	if _architecture == null:
		push_error(
			"GxController: no architecture given and no default is set. "
			+ "Call GxArchitecture.set_default() during startup."
		)
	if auto_dispose and _owner != null and not _owner.tree_exiting.is_connected(dispose):
		_owner.tree_exiting.connect(dispose)


## The architecture this helper talks to.
func get_architecture() -> GxArchitecture:
	return _architecture


## Resolve a registered System for reading. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	if not _check_usable("get_system"):
		return null
	return _architecture.get_system(system_script)


## Resolve a registered Model for reading. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	if not _check_usable("get_model"):
		return null
	return _architecture.get_model(model_script)


## Declare an intent to change state. The only write path available here.
func send_command(command: GxCommand) -> void:
	if not _check_usable("send_command"):
		return
	_architecture.send_command(command)


## Ask a read-only question and get the answer.
func send_query(query: GxQuery) -> Variant:
	if not _check_usable("send_query"):
		return null
	return _architecture.send_query(query)


## React to an event class. Released automatically on [method dispose].
## Registering the same (event class, handler) pair twice is a no-op, so the
## bookkeeping array always matches the real connection count.
func register_event(event_script: Script, handler: Callable) -> void:
	if not _check_usable("register_event"):
		return
	for entry in _event_registrations:
		if entry[0] == event_script and (entry[1] as Callable) == handler:
			return
	_architecture.register_event(event_script, handler)
	_event_registrations.append([event_script, handler])


## Stop reacting to an event class before disposal.
func unregister_event(event_script: Script, handler: Callable) -> void:
	if _architecture != null:
		_architecture.unregister_event(event_script, handler)
	for index in range(_event_registrations.size() - 1, -1, -1):
		var entry := _event_registrations[index]
		if entry[0] == event_script and (entry[1] as Callable) == handler:
			_event_registrations.remove_at(index)


## Mirror a [GxBindableProperty]. The handler receives the current value
## immediately, then on every change. Released automatically on [method dispose].
## Duplicate (property, handler) pairs are ignored — prop.bind() would connect
## only once but still fire the immediate callback on every call.
func bind(property: GxBindableProperty, handler: Callable) -> void:
	if property == null:
		push_error("GxController.bind: property is null")
		return
	for entry in _property_bindings:
		if entry[0] == property and (entry[1] as Callable) == handler:
			return
	property.bind(handler)
	_property_bindings.append([property, handler])


## Remove one property binding before disposal.
func unbind(property: GxBindableProperty, handler: Callable) -> void:
	if property != null:
		property.unbind(handler)
	for index in range(_property_bindings.size() - 1, -1, -1):
		var entry := _property_bindings[index]
		if entry[0] == property and (entry[1] as Callable) == handler:
			_property_bindings.remove_at(index)


## Release every event registration and property binding made through this
## helper. Safe to call more than once.
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	# Drop our own tree_exiting connection: on re-entry the node builds a fresh
	# controller, and a stale Callable to this disposed one would pile up.
	if _owner != null and is_instance_valid(_owner) and _owner.tree_exiting.is_connected(dispose):
		_owner.tree_exiting.disconnect(dispose)
	if _architecture != null:
		for entry in _event_registrations:
			_architecture.unregister_event(entry[0] as Script, entry[1] as Callable)
	for entry in _property_bindings:
		var property := entry[0] as GxBindableProperty
		if property != null:
			property.unbind(entry[1] as Callable)
	_event_registrations.clear()
	_property_bindings.clear()


## True once [method dispose] has run.
func is_disposed() -> bool:
	return _disposed


func _check_usable(method_name: String) -> bool:
	if _disposed:
		push_error("GxController.%s: controller is already disposed" % method_name)
		return false
	if _architecture == null:
		push_error("GxController.%s: no architecture available" % method_name)
		return false
	return true
