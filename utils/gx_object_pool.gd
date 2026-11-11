class_name GxObjectPool
extends RefCounted
## Generic object pool for reusable objects/nodes (gd-common).
## Provide a factory Callable that returns a fresh instance, and an optional
## reset callback that cleans up objects before they are returned to the pool.

var _factory: Callable
var _available: Array = []
var _on_release: Callable = Callable()


func _init(factory: Callable, prewarm: int = 0, on_release: Callable = Callable()) -> void:
	_factory = factory
	_on_release = on_release
	for i in prewarm:
		var instance := _factory.call()
		if on_release.is_valid():
			on_release.call(instance)
		_available.append(instance)


## Get an instance from the pool, creating one if none are free.
func acquire() -> Variant:
	if _available.is_empty():
		return _factory.call()
	return _available.pop_back()


## Return an instance to the pool for reuse.
## Calls the on_release callback (if set) to reset the object before pooling.
## Duplicate releases are silently ignored — releasing the same object twice
## after it was already returned is a no-op.
func release(obj: Variant) -> void:
	if obj == null:
		return
	if _available.has(obj):
		push_warning("GxObjectPool.release: object %s already in pool; ignoring duplicate" % obj)
		return
	if _on_release.is_valid():
		_on_release.call(obj)
	_available.append(obj)


func available_count() -> int:
	return _available.size()
