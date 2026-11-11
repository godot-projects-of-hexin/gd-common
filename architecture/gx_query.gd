class_name GxQuery
extends RefCounted
## Query — a read-only question that returns a value.
##
## Use a Query when a caller needs an answer that is assembled from more than
## one Model, or needs a rule applied to raw data. A Query must not change
## anything; if it does, it belongs in a [GxCommand].
##
## [b]May do:[/b] get a System, get a Model, send another Query, return a value.[br]
## [b]May not do:[/b] change state, send Events, send Commands.
## [codeblock]
## class_name CanAffordQuery
## extends GxQuery
##
## var _price: int
##
## func _init(price: int) -> void:
##     _price = price
##
## func _on_run() -> Variant:
##     var player := get_model(PlayerModel) as PlayerModel
##     return player.coins.get_value() >= _price
## [/codeblock]

var _architecture: GxArchitecture = null


## Framework internal. Called by [method GxArchitecture.send_query].
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture = architecture


## Override to produce the answer. Never call this directly — go through
## [method GxArchitecture.send_query] so the architecture is injected.
func _on_run() -> Variant:
	return null


## Resolve a registered System. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	if _architecture == null:
		push_error("GxQuery.get_system: query was not sent through an architecture")
		return null
	return _architecture.get_system(system_script)


## Resolve a registered Model. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	if _architecture == null:
		push_error("GxQuery.get_model: query was not sent through an architecture")
		return null
	return _architecture.get_model(model_script)


## Compose with another Query.
func send_query(query: GxQuery) -> Variant:
	if _architecture == null:
		push_error("GxQuery.send_query: query was not sent through an architecture")
		return null
	return _architecture.send_query(query)
