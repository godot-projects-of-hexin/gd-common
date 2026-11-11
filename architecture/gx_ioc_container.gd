class_name GxIocContainer
extends RefCounted
## Type-keyed instance container used by [GxArchitecture].
##
## Instances are stored under their own [Script], so lookups read like a
## type query: [code]container.get_instance(PlayerModel)[/code]. GDScript has
## no generics, so the caller casts the result:
## [codeblock]
## var model := container.get_instance(PlayerModel) as PlayerModel
## [/codeblock]
## Lookups fall back to the inheritance chain, so querying a base script
## returns an instance registered under a derived script.

var _instances: Dictionary = {}  # Script -> Object


static func _derives_from(candidate: Script, base: Script) -> bool:
	var current := candidate
	while current != null:
		if current == base:
			return true
		current = current.get_base_script()
	return false


## Register an instance under its own script. Replacing an existing entry is
## reported, because double registration is almost always a wiring mistake.
func add(instance: Object) -> void:
	if instance == null:
		push_error("GxIocContainer.add: instance is null")
		return
	var script := instance.get_script() as Script
	if script == null:
		push_error("GxIocContainer.add: instance has no script; cannot derive a type key")
		return
	if _instances.has(script):
		push_warning("GxIocContainer.add: '%s' is already registered; replacing" % script.resource_path)
	_instances[script] = instance


## Look up an instance by script. Returns null when nothing matches.
func get_instance(script: Script) -> Object:
	if script == null:
		push_error("GxIocContainer.get_instance: script is null")
		return null
	if _instances.has(script):
		return _instances[script]
	for key: Script in _instances:
		if _derives_from(key, script):
			return _instances[key]
	return null


## True if an instance is registered for this script (directly or as a subclass).
func has_instance(script: Script) -> bool:
	return get_instance(script) != null


## Every registered instance, in registration order.
func values() -> Array:
	return _instances.values()


## Drop all registrations.
func clear() -> void:
	_instances.clear()
