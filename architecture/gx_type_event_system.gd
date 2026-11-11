class_name GxTypeEventSystem
extends RefCounted
## Script-keyed event dispatch used by [GxArchitecture].
##
## Unlike the string-keyed [code]EventBus[/code] autoload, handlers here are
## registered against an event *class*, and the payload is the event object
## itself. That makes the contract explicit: the event class declares its own
## fields, so producers and consumers cannot disagree about the payload shape.
## [codeblock]
## architecture.register_event(ScoreChangedEvent, _on_score_changed)
## architecture.send_event(ScoreChangedEvent.create(120))
##
## func _on_score_changed(event: ScoreChangedEvent) -> void:
##     label.text = str(event.score)
## [/codeblock]

var _handlers: Dictionary = {}  # Script -> Array[Callable]


## Register a handler for one event class. Duplicate registrations are ignored.
func register(event_script: Script, handler: Callable) -> void:
	if event_script == null:
		push_error("GxTypeEventSystem.register: event_script is null")
		return
	if not handler.is_valid():
		push_error("GxTypeEventSystem.register: handler is not valid")
		return
	if not _handlers.has(event_script):
		_handlers[event_script] = [] as Array[Callable]
	var list: Array[Callable] = _handlers[event_script] as Array[Callable]
	if not list.has(handler):
		list.append(handler)


## Remove a previously registered handler.
func unregister(event_script: Script, handler: Callable) -> void:
	if not _handlers.has(event_script):
		return
	var list: Array[Callable] = _handlers[event_script] as Array[Callable]
	list.erase(handler)
	if list.is_empty():
		_handlers.erase(event_script)


## Dispatch an event to every handler registered for its class.
## Handlers whose target has been freed are pruned instead of crashing.
func send(event: Object) -> void:
	if event == null:
		push_error("GxTypeEventSystem.send: event is null")
		return
	var script := event.get_script() as Script
	if script == null:
		push_error("GxTypeEventSystem.send: event has no script; cannot derive a type key")
		return
	if not _handlers.has(script):
		return
	var list: Array[Callable] = _handlers[script] as Array[Callable]
	var stale: Array[Callable] = []
	for handler: Callable in list.duplicate():
		if handler.is_valid():
			handler.call(event)
		else:
			stale.append(handler)
	for handler: Callable in stale:
		list.erase(handler)
	if list.is_empty():
		_handlers.erase(script)


## True if the event class currently has at least one handler.
func has_handlers(event_script: Script) -> bool:
	return _handlers.has(event_script) and not (_handlers[event_script] as Array).is_empty()


## Drop every handler of one event class.
func clear_event(event_script: Script) -> void:
	_handlers.erase(event_script)


## Drop every handler.
func clear() -> void:
	_handlers.clear()
