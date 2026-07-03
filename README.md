# gd-common

Reusable **generic layer** for Godot 4 projects, shipped as an addon and consumed via Git submodule.

> 中文完整指南（总览 / 各模块用法 / 接入 / 军规 / 踩坑）见 [gd-common-guide.md](gd-common-guide.md)。


> Scope: genre-agnostic infrastructure only. **No game-specific gameplay.**
> Convention: shared `class_name` prefix `Gx`; autoload names plain (`EventBus`, `SaveSystem`, `SoundManager`, `UIManager`).

## Install

```
git submodule add <gd-common-repo-url> addons/gd-common
```

Enable **gd-common** in Project Settings → Plugins. The plugin registers its
autoload singletons (`EventBus`, `SaveSystem`, `SoundManager`, `UIManager`).

> In headless/CI you can reference scripts via `preload("res://addons/gd-common/...")`
> to avoid depending on the editor's global class cache.

---

## Decoupling rules (军规)

1. No hardcoded node paths (`get_node("/root/...")`).
2. No hardcoded `res://` asset paths inside logic — inject instead.
3. Inject dependencies; do not `load()` project assets internally.
4. Communicate via signals / `EventBus`, never hard-reference other systems.
5. Self-contained: each module ships its own scripts/scenes/default resources.
6. Do not depend on project-specific autoloads.

---

## Modules & contracts

### `core/event_bus.gd` — autoload `EventBus`
Global decoupled publish/subscribe. Subscribers must accept exactly one argument
(the payload). Type-safe internally (`Array[Callable]`, not untyped `Array`).

**Why**: Decouple modules that should not hold references to each other.
A score system can emit `&"enemy_killed"` without knowing what UI/audio/achievement
systems are listening.

```gdscript
# Producer — any module, no import needed:
EventBus.emit_event(&"tokens_changed", 120)

# Consumer — subscribe in _ready, unsubscribe if it leaves the tree:
func _ready() -> void:
    EventBus.subscribe(&"tokens_changed", _on_tokens)

func _on_tokens(v: int) -> void:
    $Label.text = str(v)
```
- `subscribe / unsubscribe / emit_event / has_subscribers / clear_event / clear_all`
- Freed listeners are auto-pruned on emit.
- Subscriber callables take exactly **one** arg (payload).

### `core/save_system.gd` — autoload `SaveSystem`
Persistence mechanism (knows *how*, not *what*). Project builds a flat Dictionary.
```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "tokens": 120})
var data := SaveSystem.load_from_slot(0)            # {} if missing
SaveSystem.has_slot(0); SaveSystem.delete_slot(0); SaveSystem.list_slots()
SaveSystem.set_version(2); SaveSystem.set_migrator(my_migrate_callable)
# Observability signals:
SaveSystem.saved.connect(func(slot): ...)            # save confirmed
SaveSystem.loaded.connect(func(slot): ...)           # load succeeded
```
Stores `user://saves/slot_N.cfg` with a `__version` for migration.

### `audio/sound_manager.gd` — autoload `SoundManager`
Generic playback; audio **assets stay in the project** — pass `AudioStream` objects in.

**Why process-mode split matters**: When `get_tree().paused = true` (e.g.
opening a pause menu), SFX should silence but BGM fade should keep ticking,
otherwise the fade-out animation freezes mid-way.

- SFX/Ambient roots: `PROCESS_MODE_INHERIT` — pause with the tree.
- Music root: `PROCESS_MODE_ALWAYS` — tween keeps running; use `pause_music()` to silence.

**Practical usage** (see `audio_lib.gd` for the full pattern):
```gdscript
# Load once, cache, call anywhere:
var stream := load("res://sfx/ui_click.wav")
SoundManager.play_sound(stream)               # one-shot SFX, 8-slot pool
SoundManager.play_ui_sound(stream)            # alias — same pool

SoundManager.play_music(load("res://bgm/service.wav"), 1.5)  # crossfade in
SoundManager.stop_music(1.5)                                  # fade out

SoundManager.play_ambient_sound(load("res://sfx/kitchen.wav"), 2.0)  # looping
SoundManager.stop_all_ambient_sounds(1.5)      # scene transition cleanup

# PR-0002: pause/resume without stopping the playhead
SoundManager.pause_music(0.5)                 # fade to silence
SoundManager.resume_music(0.5)                # fade back to last volume
SoundManager.is_music_paused() -> bool
```

**Known behaviors / contracts:**
- `play_sound()` / `play_ui_sound()` share 8 concurrent SFX slots. When all are busy, the **oldest** (index 0) is preempted — fine for short UI feedback clips. Long ambiences should use `play_ambient_sound()` which gets a dedicated player.
- `play_music()` clears the API-pause flag. After `pause_music()` → `play_music(new_track)`, `is_music_paused()` returns `false` and `resume_music()` would restore `new_track`'s default volume (not the old track's).
- `pause_music()` / `resume_music()` are idempotent: a second `pause_music()` while paused is a no-op.
- Ambient sounds are keyed by the stream's `resource_path` (or `get_instance_id()` for generated streams). Two calls to `load()` the same file share the same ambient slot — calling `play_ambient_sound()` again for an already-playing ambient with the same resource path will stop and restart it.

### `core/ui_manager.gd` — autoload `UIManager`
Generic **Control** panel stack on its own CanvasLayer (for transient modals).

**Why**: Manual `add_child` for modals requires remembering what's underneath
and restoring visibility. UIManager pushes/pops panels, hiding the one beneath
automatically, so you can nest dialogs (e.g. settings → keybind) without
tracking state yourself.

```gdscript
# Push a modal dialog:
var panel := UIManager.push_panel(preload("res://ui/confirm_dialog.tscn"))
# ... user interacts, clicks "OK" ...

# Pop and auto-free the top panel, show the one underneath:
UIManager.pop_panel()
# UIManager.get_top() returns the previous panel (or null)
# UIManager.clear() frees the entire stack (e.g. scene change)

# Observability signals:
UIManager.panel_pushed.connect(func(p): ...)     # a panel was pushed
UIManager.panel_will_pop.connect(func(p): ...)   # about to pop (save state here)
UIManager.panel_popped.connect(func(): ...)      # pop completed
```
> Only for **Control**-based modals. Not for persistent HUDs, Node2D overlays,
> or in-world UI. (CyberCookV3 uses Node2D panels and skips this module.)

### `fsm/state_machine.gd` + `fsm/state.gd` — `GxStateMachine` / `GxState`
Minimal FSM for scene/level/flow control (and actor AI). Subclass `GxState` or use
plain states + the `state_changed` signal.

**Basic flow:**
```gdscript
var sm := GxStateMachine.new(self)             # self = context
sm.add_state(&"prep", GxState.new())
sm.add_state(&"service", GxState.new())
sm.state_changed.connect(func(from, to): ...)  # react to transitions
sm.transition_to(&"prep")
```

**Event-driven with guards** (PR-0001):
```gdscript
var sm := GxStateMachine.new()
sm.attach_to(self)                              # records host (read-only on .attached_host)
sm.add_state(&"idle", GxState.new())
sm.add_state(&"walk", GxState.new())
sm.add_state(&"attack", GxState.new())

# (from_state, event) -> (target, optional guard)
sm.add_transition(&"idle",   &"move_pressed",  &"walk")
sm.add_transition(&"walk",   &"attack_pressed", &"attack",
    func() -> bool: return $Weapon.can_attack())    # guard

sm.start(&"idle")
sm.try_transition(&"move_pressed")                # walks
sm.try_transition(&"attack_pressed")              # attack only if guard passes
```

**Queries & signals** (PR-0001):
```gdscript
sm.is_in_state(&"walk")                           # strict name match
sm.guard_failed.connect(func(from, ev): ...)      # guard returned false
sm.unhandled_event.connect(func(ev): ...)         # no transition matched
```

`is_in_state` is exact-match only and returns `false` until `start()` has been
called. Hierarchical (HSM) support is intentionally out of scope and would be
a separate PR.

**Error policy:** `add_transition()` reports unknown state names via
`push_error()` (not `assert`), so release builds behave like debug builds.
`transition_to()` warns via `push_warning` on a self-transition (current == target)
and is a no-op — self-transitions are almost always a logic bug.

### `components/gauge_component.gd` — `GxGaugeComponent` (Node)
Bounded value `[0, max]` with optional time-based drain/refill.
Use for patience, health, stamina, charge/loading bars.
```gdscript
var g := GxGaugeComponent.new()
g.max_value = 30.0; g.auto_rate = 1.0; g.auto_active = false
add_child(g)
g.value_changed.connect(...); g.depleted.connect(...)
g.reset(); g.drain(5); g.fill(2); g.auto_active = true
```
- Changing `max_value` at runtime auto-clamps `current` to the new bound and emits `value_changed`.

### `utils/gx_cooldown.gd` — `GxCooldown` (RefCounted)
Manual cooldown timer. Drive it yourself via `tick(delta)` — no `_process` dependency.

**Why**: Many mechanics need timed gates (attack cooldown, dash recharge,
ability cooldown) that are event-driven, not frame-driven.

```gdscript
var _dash_cooldown := GxCooldown.new(2.0)   # 2-second dash cooldown

func _process(delta: float) -> void:
    _dash_cooldown.tick(delta)

func _on_dash_input() -> void:
    if not _dash_cooldown.is_ready():
        return
    _perform_dash()
    _dash_cooldown.start()

# Interrupt without firing (player died mid-charge):
func _on_player_died() -> void:
    _dash_cooldown.cancel()    # resets to 0, no "finished" signal
```
- Methods: `start(duration?), tick(delta), is_ready(), is_running(), progress(), cancel()`
- `is_running()` returns `true` while time_left > 0 (the cooldown is active).
- Signal: `finished` — fires once when time reaches 0; won't re-fire until `start()` is called again.
- Legacy: `.update(delta)` still works (delegates to `.tick()`) for backward compatibility.

### `utils/gx_math.gd` — `GxMath` (static)
Stateless math helpers, no instantiation needed.

```gdscript
GxMath.approach(5.0, 10.0, 2.0)         # → 7.0  (moves toward target by delta)
GxMath.remap_clamped(0.5, 0, 1, 0, 100) # → 50.0 (remaps a value to new range)
GxMath.chance(0.3)                       # → true 30% of the time
GxMath.pick_random([1, 2, 3])            # → one random element
```
- `approach(current, target, delta)` — smooth movement toward target, no overshoot.
- `remap_clamped(value, in_min, in_max, out_min, out_max)` — linear remap, clamped.
- `chance(probability)` — returns `true` with the given probability (0.0–1.0).
- `pick_random(arr)` — random element from non-empty array, `null` if empty.

### `utils/gx_object_pool.gd` — `GxObjectPool` (RefCounted)
Reuse objects instead of creating/destroying them every frame (bullets, particles, popup text).

```gdscript
# Factory: a callable that creates a fresh instance
# Optional on_release: a callable that resets an object before pooling
var _bullet_pool := GxObjectPool.new(func() -> Node:
    return preload("res://bullet.tscn").instantiate(),
    5,   # prewarm 5
    func(obj): obj.visible = false)   # reset on return

func _fire_bullet() -> void:
    var b := _bullet_pool.acquire()        # take from pool (or create new)
    b.position = $Muzzle.global_position
    b.visible = true
    get_tree().current_scene.add_child(b)

func _on_bullet_impact(bullet: Node) -> void:
    _bullet_pool.release(bullet)           # return to pool for reuse
```
- `acquire()` — get an instance (pooled or new).
- `release(obj)` — return to pool. Calls `on_release` callback (if set) to reset state. Duplicate releases of the same object are detected and ignored with a warning.
- `available_count()` — how many are currently in the pool.

### `components/gx_floating_number.gd` — `GxFloatingNumber` (Control)
Floating damage/score numbers that drift upward and fade out.

```gdscript
var fn := GxFloatingNumber.new()
fn.text = "-5"
fn.color = Color.RED
fn.duration = 1.2
add_child(fn)
fn.show_at(global_position)    # animates upward, auto-frees on finish
```

---

## Reference integrations (CyberCookV3)

| Pattern | Where to copy from |
|---|---|
| Scene/flow FSM | `autoload/game_flow.gd` (GxStateMachine + scene swap) |
| Gauge component | `modules/customer/robot.gd` (patience via GxGaugeComponent) |
| EventBus bridge + subscribe | `autoload/state.gd` + `modules/global_hud/global_hud.gd` |
| SaveSystem usage | `autoload/state.gd` (`save_game`/`load_game`) |
