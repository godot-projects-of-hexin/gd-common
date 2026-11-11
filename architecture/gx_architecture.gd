class_name GxArchitecture
extends RefCounted
## Registration center and message hub for one game's business architecture.
##
## [b]Layers[/b] (top to bottom): Controller → Command → System / Model → Utility.
## Calls go downward, notifications come back upward:
## [codeblock]
## input → Controller → Command → System / Model → Event / BindableProperty → Controller
## [/codeblock]
## Each layer base class exposes only the accessors that layer is allowed to
## use, so the rules hold at the API surface instead of depending on review.
## A [GxModel] has no [code]get_system()[/code]; a [GxController] has no
## direct write path other than a Command.
##
## Subclass this once per project, register members in [method _on_register],
## and expose a single instance through a static accessor:
## [codeblock]
## class_name GameArchitecture
## extends GxArchitecture
##
## static var _instance: GameArchitecture
##
## static func get_instance() -> GameArchitecture:
##     if _instance == null:
##         _instance = GameArchitecture.new()
##         _instance.initialize()
##         GxArchitecture.set_default(_instance)
##     return _instance
##
## func _on_register() -> void:
##     register_utility(JsonFileUtility.new())
##     register_model(PlayerModel.new())
##     register_system(ScoreSystem.new())
## [/codeblock]

## Emitted once, after every registered member has been initialized.
signal initialized

## Architecture that presentation helpers resolve when none is passed in.
## Declared on the base class, so there is exactly one default per project.
static var _default: GxArchitecture = null

var _utilities := GxIocContainer.new()
var _models := GxIocContainer.new()
var _systems := GxIocContainer.new()
var _events := GxTypeEventSystem.new()
var _is_initialized := false


## The architecture [GxControllerNode] and [GxController] fall back to.
static func get_default() -> GxArchitecture:
	return _default


## Set the architecture presentation helpers resolve by default.
static func set_default(architecture: GxArchitecture) -> void:
	_default = architecture


## Clear the default. Call between tests so one test cannot leak into another.
static func clear_default() -> void:
	_default = null


static func _script_label(script: Script) -> String:
	if script == null:
		return "<null>"
	if not script.resource_path.is_empty():
		return script.resource_path
	return str(script)


## Override to register every Utility, Model and System of the project.
## Called by [method initialize]; do not call it yourself.
func _on_register() -> void:
	pass


## Run registration, then initialize members bottom-up:
## Utilities → Models → Systems. A System may therefore safely resolve any
## Model or Utility inside its own [method GxSystem._on_init].
func initialize() -> void:
	if _is_initialized:
		push_warning("GxArchitecture.initialize: already initialized; ignoring")
		return
	GxWriteGuard.begin()
	_on_register()
	for instance in _utilities.values():
		var utility := instance as GxUtility
		if utility != null:
			utility._on_init()
	for instance in _models.values():
		var model := instance as GxModel
		if model != null:
			model._on_init()
	for instance in _systems.values():
		var system := instance as GxSystem
		if system != null:
			system._on_init()
	GxWriteGuard.end()
	_is_initialized = true
	initialized.emit()


## Mark every [GxBindableProperty] declared on a registered Model so debug
## builds can report writes that bypass a Command. Standalone bindables (unit
## tests, ad-hoc observable values) are never marked, so the guard cannot
## misfire on them.
func _mark_model_bindables(model: GxModel) -> void:
	if not GxWriteGuard.is_active():
		return
	for info: Dictionary in model.get_property_list():
		var name := String(info.get("name", ""))
		if name.is_empty() or name.begins_with("_"):
			continue
		var value: Variant = model.get(name)
		if value is GxBindableProperty:
			(value as GxBindableProperty)._set_guarded(true)


## True once [method initialize] has finished.
func is_initialized() -> bool:
	return _is_initialized


## Register a Utility. Members registered after [method initialize] are
## initialized immediately, so lazily added modules behave the same way.
func register_utility(utility: GxUtility) -> GxArchitecture:
	if utility == null:
		push_error("GxArchitecture.register_utility: utility is null")
		return self
	_utilities.add(utility)
	if _is_initialized:
		GxWriteGuard.begin()
		utility._on_init()
		GxWriteGuard.end()
	return self


## Register a Model.
func register_model(model: GxModel) -> GxArchitecture:
	if model == null:
		push_error("GxArchitecture.register_model: model is null")
		return self
	model._bind_architecture(self)
	_models.add(model)
	_mark_model_bindables(model)
	if _is_initialized:
		GxWriteGuard.begin()
		model._on_init()
		GxWriteGuard.end()
	return self


## Register a System.
func register_system(system: GxSystem) -> GxArchitecture:
	if system == null:
		push_error("GxArchitecture.register_system: system is null")
		return self
	system._bind_architecture(self)
	_systems.add(system)
	if _is_initialized:
		GxWriteGuard.begin()
		system._on_init()
		GxWriteGuard.end()
	return self


## Resolve a Utility by script. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	var found := _utilities.get_instance(utility_script) as GxUtility
	if found == null:
		_report_missing("utility", utility_script)
	return found


## Resolve a Model by script. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	var found := _models.get_instance(model_script) as GxModel
	if found == null:
		_report_missing("model", model_script)
	return found


## Resolve a System by script. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	var found := _systems.get_instance(system_script) as GxSystem
	if found == null:
		_report_missing("system", system_script)
	return found


## Execute a Command. This is the only sanctioned write path from the
## presentation layer. Commands return nothing by design — use a Query to read.
func send_command(command: GxCommand) -> void:
	if command == null:
		push_error("GxArchitecture.send_command: command is null")
		return
	command._bind_architecture(self)
	GxWriteGuard.begin()
	command._on_execute()
	GxWriteGuard.end()


## Run a Query and return its answer.
func send_query(query: GxQuery) -> Variant:
	if query == null:
		push_error("GxArchitecture.send_query: query is null")
		return null
	query._bind_architecture(self)
	return query._on_run()


## Broadcast a fact that already happened, keyed by the event's own class.
## System handlers run synchronously, so they share the caller's write scope.
func send_event(event: Object) -> void:
	GxWriteGuard.begin()
	_events.send(event)
	GxWriteGuard.end()


## React to an event class. The handler takes exactly one argument: the event.
func register_event(event_script: Script, handler: Callable) -> void:
	_events.register(event_script, handler)


## Stop reacting to an event class.
func unregister_event(event_script: Script, handler: Callable) -> void:
	_events.unregister(event_script, handler)


## True if the event class currently has at least one handler.
func has_event_handlers(event_script: Script) -> bool:
	return _events.has_handlers(event_script)


## Tear everything down: Systems → Models → Utilities, then drop all handlers.
## Call this when a whole game session ends, not on every scene change.
func deinitialize() -> void:
	for instance in _systems.values():
		var system := instance as GxSystem
		if system != null:
			system._on_deinit()
			system._bind_architecture(null)
	for instance in _models.values():
		var model := instance as GxModel
		if model != null:
			model._on_deinit()
			model._bind_architecture(null)
	for instance in _utilities.values():
		var utility := instance as GxUtility
		if utility != null:
			utility._on_deinit()
	_events.clear()
	_systems.clear()
	_models.clear()
	_utilities.clear()
	_is_initialized = false


func _report_missing(kind: String, script: Script) -> void:
	push_error("GxArchitecture: no %s registered for '%s'" % [kind, _script_label(script)])
