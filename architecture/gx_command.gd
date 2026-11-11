class_name GxCommand
extends RefCounted
## Command — the only sanctioned way for the presentation layer to change state.
##
## A Command names an *intent*: "add score", "buy item", "submit clue". It is
## created, executed once, and thrown away, so it must stay stateless: put the
## parameters in, read nothing back out. Routing every write through Commands
## is what makes logging, replay, analytics and undo possible later without
## rewriting callers.
##
## [b]May do:[/b] get a System, get a Model, get a Utility, send an Event,
## send another Command, send a Query.[br]
## [b]May not do:[/b] keep state between executions, return a value.
## Use a [GxQuery] when you need an answer.
## [codeblock]
## class_name AddScoreCommand
## extends GxCommand
##
## var _amount: int
##
## func _init(amount: int) -> void:
##     _amount = amount
##
## func _on_execute() -> void:
##     var player := get_model(PlayerModel) as PlayerModel
##     player.add_score(_amount)
##     send_event(ScoreChangedEvent.create(player.score.get_value()))
## [/codeblock]

var _architecture: GxArchitecture = null


## Framework internal. Called by [method GxArchitecture.send_command].
func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture = architecture


## Override with the actual work. Never call this directly — go through
## [method GxArchitecture.send_command] so the architecture is injected.
func _on_execute() -> void:
	pass


## Resolve a registered System. Cast the result to the concrete type.
func get_system(system_script: Script) -> GxSystem:
	if _architecture == null:
		push_error("GxCommand.get_system: command was not sent through an architecture")
		return null
	return _architecture.get_system(system_script)


## Resolve a registered Model. Cast the result to the concrete type.
func get_model(model_script: Script) -> GxModel:
	if _architecture == null:
		push_error("GxCommand.get_model: command was not sent through an architecture")
		return null
	return _architecture.get_model(model_script)


## Resolve a registered Utility. Cast the result to the concrete type.
func get_utility(utility_script: Script) -> GxUtility:
	if _architecture == null:
		push_error("GxCommand.get_utility: command was not sent through an architecture")
		return null
	return _architecture.get_utility(utility_script)


## Broadcast a fact that already happened.
func send_event(event: Object) -> void:
	if _architecture == null:
		push_error("GxCommand.send_event: command was not sent through an architecture")
		return
	_architecture.send_event(event)


## Delegate part of the work to another Command.
func send_command(command: GxCommand) -> void:
	if _architecture == null:
		push_error("GxCommand.send_command: command was not sent through an architecture")
		return
	_architecture.send_command(command)


## Ask a read-only question. Returns whatever the Query produces.
func send_query(query: GxQuery) -> Variant:
	if _architecture == null:
		push_error("GxCommand.send_query: command was not sent through an architecture")
		return null
	return _architecture.send_query(query)
