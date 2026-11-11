class_name GxUtility
extends RefCounted
## Utility layer — the bottom of the architecture.
##
## A utility wraps infrastructure: file IO, serialization, HTTP, platform SDKs,
## third-party libraries. It is deliberately given **no** access to the
## architecture, so it can never reach sideways into a System or upward into a
## Controller. That is what makes it reusable across projects.
##
## [b]May do:[/b] wrap an API, compute, read and write external storage.[br]
## [b]May not do:[/b] query Models or Systems, send Commands, send Events.
## [codeblock]
## class_name JsonFileUtility
## extends GxUtility
##
## func write(path: String, data: Dictionary) -> bool:
##     var file := FileAccess.open(path, FileAccess.WRITE)
##     if file == null:
##         return false
##     file.store_string(JSON.stringify(data))
##     return true
## [/codeblock]


## Called once by [GxArchitecture] after registration. Override for setup.
func _on_init() -> void:
	pass


## Called by [method GxArchitecture.deinitialize]. Override to release resources.
func _on_deinit() -> void:
	pass
