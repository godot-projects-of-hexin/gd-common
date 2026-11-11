class_name GxStateMachine
extends RefCounted
## Minimal finite state machine (gd-common).
## Register GxState instances by name, start(), then drive via update()/physics_update().
## Reusable for game flow (prep/service/settlement) and actor AI alike.

signal state_changed(from_state: StringName, to_state: StringName)
## Emitted when try_transition()'s guard returns false.
signal guard_failed(from_state: StringName, event: StringName)
## Emitted when try_transition() finds no matching transition for the event.
signal unhandled_event(event: StringName)

## Arbitrary data object that states can read via `machine.context`.
## Set via the constructor (`GxStateMachine.new(my_data)`).
## Use this for shared gameplay data (e.g. a CharacterBody, a score dict).
## Prefer `attach_to` when you only need to record which Node owns this machine.
var context: Variant = null

## Node this machine is associated with (set via attach_to). Read-only.
## The machine itself stays a RefCounted and is NOT added as a child.
## Use this when external systems need to correlate the machine with a scene
## object (e.g. "find the FSM attached to the player") — it is a reference
## only, not a data channel. States should read `context` for game data.
var attached_host: Node = null

var _states: Dictionary = {}        # StringName -> GxState
var _current: GxState = null
var _current_name: StringName = &""
var _started: bool = false
var _transitions: Array[GxStateMachine.TransitionData] = []


# Internal typed record for one transition entry. Replaces an untyped Dictionary
# so missing fields fail at construction time instead of producing a runtime
# `KeyError` deep inside try_transition().
class TransitionData extends RefCounted:
	var from: StringName = &""
	var event: StringName = &""
	var target: StringName = &""
	var guard: Callable = Callable()


func _init(ctx: Variant = null) -> void:
	context = ctx


## Attach this machine to an optional host Node. The machine itself stays
## a RefCounted and is NOT added as a child; the host is only recorded so
## other systems can correlate the machine with its owning scene/object.
## Pass null to clear.
func attach_to(host: Node) -> GxStateMachine:
	attached_host = host
	return self


## Detach from the previously attached host.
func detach() -> GxStateMachine:
	attached_host = null
	return self


## Register a state under a name. Returns self for chaining.
func add_state(state_name: StringName, state: GxState) -> GxStateMachine:
	state.machine = self
	_states[state_name] = state
	return self


## Register a transition that fires on `event` from state `from_state`,
## landing in `target`. `guard` is an optional Callable returning bool;
## if it returns false, the transition is rejected and `guard_failed` is emitted.
## Unknown state names are reported via push_error() and the entry is dropped
## (mirrors add_state's error policy; does not use assert so release builds behave
## the same as debug builds).
func add_transition(
		from_state: StringName,
		event: StringName,
		target: StringName,
		guard: Callable = Callable()) -> GxStateMachine:
	if not _states.has(from_state):
		push_error("GxStateMachine.add_transition: unknown from_state '%s'" % from_state)
		return self
	if not _states.has(target):
		push_error("GxStateMachine.add_transition: unknown target '%s'" % target)
		return self
	var t := GxStateMachine.TransitionData.new()
	t.from = from_state
	t.event = event
	t.target = target
	t.guard = guard
	_transitions.append(t)
	return self


## True if the machine's current state name equals `state_name` exactly.
## Returns false until start() has been called.
## Hierarchical / ancestor matching is intentionally NOT supported — if
## you need HSM semantics, add a `parent` map in a follow-up PR.
func is_in_state(state_name: StringName) -> bool:
	return _started and _current_name == state_name


## Try to fire `event`. Looks up a registered transition whose `from` matches
## the current state, evaluates its `guard` (if any), and on success performs
## the transition. Returns true iff a transition was actually performed.
func try_transition(event: StringName) -> bool:
	for t in _transitions:
		if t.from != _current_name or t.event != event:
			continue
		if t.guard.is_valid():
			var allowed: Variant = t.guard.call()
			if not bool(allowed):
				guard_failed.emit(_current_name, event)
				return false
		transition_to(t.target)
		return true
	unhandled_event.emit(event)
	return false


## Enter the initial state.
func start(initial: StringName) -> void:
	if not _states.has(initial):
		push_error("GxStateMachine.start: unknown state '%s'" % initial)
		return
	_current_name = initial
	_current = _states[initial]
	_current._enter()
	_started = true


## Transition to another state (exit current, enter target).
## Logs a warning and returns early if `target` equals the current state
## (self-transitions are almost always a logic bug, not an intent).
func transition_to(target: StringName) -> void:
	if not _states.has(target):
		push_error("GxStateMachine.transition_to: unknown state '%s'" % target)
		return
	if target == _current_name:
		push_warning("GxStateMachine.transition_to: target '%s' equals current state" % target)
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
