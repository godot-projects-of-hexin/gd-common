extends Node
## Global decoupled publish/subscribe event bus (gd-common).
## Autoload name: EventBus. Reference globally, e.g. EventBus.emit_event(&"player_died", id).
## Subscriber callables must accept exactly one argument (the payload).

var _subscribers: Dictionary = {}  # StringName -> Array[Callable]


## Subscribe a callable to an event. Duplicate subscriptions are ignored.
func subscribe(event: StringName, callable: Callable) -> void:
	if not _subscribers.has(event):
		_subscribers[event] = [] as Array[Callable]
	var list: Array[Callable] = _subscribers[event] as Array[Callable]
	if not list.has(callable):
		list.append(callable)


## Remove a previously subscribed callable.
func unsubscribe(event: StringName, callable: Callable) -> void:
	if not _subscribers.has(event):
		return
	var list: Array[Callable] = _subscribers[event] as Array[Callable]
	list.erase(callable)
	if list.is_empty():
		_subscribers.erase(event)


## Emit an event with an optional payload. Freed listeners are auto-pruned.
func emit_event(event: StringName, payload: Variant = null) -> void:
	if not _subscribers.has(event):
		return
	var list: Array[Callable] = _subscribers[event] as Array[Callable]
	var stale: Array[Callable] = []
	for callable: Callable in list.duplicate():
		if callable.is_valid():
			callable.call(payload)
		else:
			stale.append(callable)
	for callable: Callable in stale:
		list.erase(callable)
	if list.is_empty():
		_subscribers.erase(event)


## True if the event currently has at least one subscriber.
func has_subscribers(event: StringName) -> bool:
	return _subscribers.has(event) and not _subscribers[event].is_empty()


## Clear all subscribers of a specific event.
func clear_event(event: StringName) -> void:
	_subscribers.erase(event)


## Clear every subscription.
func clear_all() -> void:
	_subscribers.clear()
