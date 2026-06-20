class_name GxObjectPool
extends RefCounted
## Generic object pool for reusable objects/nodes (gd-common).
## Provide a factory Callable that returns a fresh instance.

var _factory: Callable
var _available: Array = []


func _init(factory: Callable, prewarm: int = 0) -> void:
	_factory = factory
	for i in prewarm:
		_available.append(_factory.call())


## Get an instance from the pool, creating one if none are free.
func acquire() -> Variant:
	if _available.is_empty():
		return _factory.call()
	return _available.pop_back()


## Return an instance to the pool for reuse.
func release(obj: Variant) -> void:
	_available.append(obj)


func available_count() -> int:
	return _available.size()
