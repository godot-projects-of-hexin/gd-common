class_name GxStateMachine
extends RefCounted
## Minimal finite state machine (gd-common).
## Register GxState instances by name, start(), then drive via update()/physics_update().
## Reusable for game flow (prep/service/settlement) and actor AI alike.

signal state_changed(from_state: StringName, to_state: StringName)

## Arbitrary owner/context object states can read via machine.context.
var context: Variant = null

var _states: Dictionary = {}        # StringName -> GxState
var _current: GxState = null
var _current_name: StringName = &""


func _init(ctx: Variant = null) -> void:
	context = ctx


## Register a state under a name. Returns self for chaining.
func add_state(state_name: StringName, state: GxState) -> GxStateMachine:
	state.machine = self
	_states[state_name] = state
	return self


## Enter the initial state.
func start(initial: StringName) -> void:
	if not _states.has(initial):
		push_error("GxStateMachine.start: unknown state '%s'" % initial)
		return
	_current_name = initial
	_current = _states[initial]
	_current._enter()


## Transition to another state (exit current, enter target).
func transition_to(target: StringName) -> void:
	if not _states.has(target):
		push_error("GxStateMachine.transition_to: unknown state '%s'" % target)
		return
	if target == _current_name:
		return
	var from := _current_name
	if _current:
		_current._exit()
	_current_name = target
	_current = _states[target]
	_current._enter()
	state_changed.emit(from, target)


func update(delta: float) -> void:
	if _current:
		_current._update(delta)


func physics_update(delta: float) -> void:
	if _current:
		_current._physics_update(delta)


func current_name() -> StringName:
	return _current_name


func current_state() -> GxState:
	return _current
