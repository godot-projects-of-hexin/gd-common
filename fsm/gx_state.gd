class_name GxState
extends RefCounted
## Base state for GxStateMachine (gd-common). Subclass and override the hooks.
## Read shared context via `machine.context`.

## 状态机的弱引用。
##
## 状态机通过 _states 强引用 State，所以反向**必须**是弱引用：两个 RefCounted
## 互相强引用会让引用计数永远归不了零，退出时报
## 「ObjectDB instances were leaked at exit」。
## 已在 Godot 4.7 实测确认 weakref() 不会增加目标的 get_reference_count()。
var _machine_ref: WeakRef = null

## The machine this state belongs to, or null once that machine is gone.
## Read-only — it is set by add_state().
var machine: GxStateMachine:
	get:
		if _machine_ref == null:
			return null
		return _machine_ref.get_ref() as GxStateMachine


## Framework internal. Called by GxStateMachine.add_state().
func _bind_machine(owner_machine: GxStateMachine) -> void:
	_machine_ref = weakref(owner_machine) if owner_machine != null else null


func _enter() -> void:
	pass


func _exit() -> void:
	pass


func _update(_delta: float) -> void:
	pass


func _physics_update(_delta: float) -> void:
	pass
