class_name GxState
extends RefCounted
## Base state for GxStateMachine (gd-common). Subclass and override the hooks.
## Read shared context via `machine.context`.

## Set automatically when the state is added to a machine.
var machine: GxStateMachine


func _enter() -> void:
	pass


func _exit() -> void:
	pass


func _update(_delta: float) -> void:
	pass


func _physics_update(_delta: float) -> void:
	pass
