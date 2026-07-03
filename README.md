# gd-common

Reusable **generic layer** for Godot 4 projects, shipped as an addon and consumed via Git submodule.

> 中文完整指南（总览 / 各模块用法 / 接入 / 军规 / 踩坑）见 [gd-common-guide.md](gd-common-guide.md)。


> Scope: genre-agnostic infrastructure only. **No game-specific gameplay.**
> Convention: shared `class_name` prefix `Gx`; autoload names plain (`EventBus`, `SaveSystem`, `SoundManager`, `UIManager`).

## Install

```
git submodule add file:///D:/GitRepos/gd-common addons/gd-common
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

### Services (autoloads)

### `core/event_bus.gd` — autoload `EventBus`
Global decoupled publish/subscribe. Subscriber callables take **one** arg (payload).
```gdscript
EventBus.subscribe(&"tokens_changed", _on_tokens)   # consumer
EventBus.emit_event(&"tokens_changed", 120)         # producer
EventBus.unsubscribe(&"tokens_changed", _on_tokens)
```
- `subscribe/unsubscribe/emit_event/has_subscribers/clear_event/clear_all`
- Freed listeners are auto-pruned on emit.

### `core/save_system.gd` — autoload `SaveSystem`
Persistence mechanism (knows *how*, not *what*). Project builds a flat Dictionary.
```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "tokens": 120})
var data := SaveSystem.load_from_slot(0)            # {} if missing
SaveSystem.has_slot(0); SaveSystem.delete_slot(0); SaveSystem.list_slots()
SaveSystem.set_version(2); SaveSystem.set_migrator(my_migrate_callable)
```
Stores `user://saves/slot_N.cfg` with a `__version` for migration.

### `audio/sound_manager.gd` — autoload `SoundManager` [absorbed from nathanhoad/godot_sound_manager v2.6.2 MIT]
Split into 4 player pools: sounds (×8), UI sounds (×8, plays when paused), ambient (×1, fade in/out), music (×2, crossfade). Auto-detects audio buses by name.
```gdscript
SoundManager.play_sound(stream)
SoundManager.play_ui_sound(stream)            # plays even when paused
SoundManager.play_ambient_sound(stream, 2.0)  # fade in
SoundManager.play_music(stream, 1.5)          # crossfade
SoundManager.stop_music(2.0)                  # fade out
SoundManager.set_music_volume(0.8)            # 0–1 linear
```

### `core/ui_manager.gd` — autoload `UIManager`
Generic **Control** panel stack on its own CanvasLayer (for transient modals).
```gdscript
var p := UIManager.push_panel(packed_scene)   # root must be a Control
UIManager.pop_panel(); UIManager.get_top(); UIManager.clear()
```
> Not for persistent HUDs or Node2D panels.

### State machine framework

### `fsm/state_machine.gd` + `fsm/state.gd` — `GxStateMachine` / `GxState`
Minimal FSM for scene/level/flow control (and actor AI). Subclass `GxState` or use
plain states + the `state_changed` signal.
```gdscript
var sm := GxStateMachine.new(self)             # self = context
sm.add_state(&"prep", GxState.new())
sm.add_state(&"service", GxState.new())
sm.state_changed.connect(func(from, to): ...)  # react to transitions
sm.transition_to(&"prep")
```

### Components (node-based)

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

### `components/gx_floating_number.gd` — `GxFloatingNumber` (CanvasLayer)
Floating number display with pop→float→wobble→fade animation. Each call creates
a self-destructing Label. Use for damage numbers, score popups, crits, misses, etc.

```gdscript
var fn := GxFloatingNumber.new(); fn.layer = 100; add_child(fn)
fn.spawn(pos, "+80", GxFloatingNumber.Preset.HEAL)
fn.spawn(pos, "999", GxFloatingNumber.Preset.CRITICAL, {font_size = 36})
fn.spawn_custom(pos, "???", {color = Color.VIOLET, scale_start = 3.0})
```

**Presets:** `DEFAULT` (white) `DAMAGE` (red) `HEAL` (green) `CRITICAL` (gold, bigger)
`MUTED` (gray, smaller). Each preset controls default color / scale / font_size /
float_distance / wobble.

**Override keys** (pass as 4th arg to `spawn()` or full dict to `spawn_custom()`):

| key | type | default (preset) | description |
|-----|------|------------------|-------------|
| `color` | Color | preset | text color |
| `font_size` | int | preset | font size in px |
| `scale_start` | float | preset | initial pop scale (e.g. 2.5 → 1.0) |
| `float_distance` | float | preset | pixels to drift upward |
| `wobble` | float | preset | max horizontal random drift |
| `duration` | float | 0.8 | total animation time (seconds) |

### Utilities

#### `GxMath` (static)
```gdscript
var v := GxMath.approach(5.0, 10.0, delta * 3.0)          # toward 10, +3/frame
var r := GxMath.remap_clamped(0.5, 0.0, 1.0, 0.0, 100.0)   # → 50.0
if GxMath.chance(0.2): print("20% hit")
var pick = GxMath.pick_random(["a", "b", "c"])
```

#### `GxCooldown` (manual timer)
```gdscript
var cd := GxCooldown.new(2.0)
cd.start(); cd.update(delta)
if cd.is_ready(): print("ready")   # or connect cd.finished
print(cd.progress())               # 0.0~1.0
```

#### `GxObjectPool` (factory-based)
```gdscript
var pool := GxObjectPool.new(func(): return Bullet.new(), 10)  # prewarm 10
var b = pool.acquire(); pool.release(b)
```

---

## Reference integrations (CyberCookV3)

| Pattern | Where to copy from |
|---|---|
| Scene/flow FSM | `autoload/game_flow.gd` (GxStateMachine + scene swap) |
| Gauge component | `modules/customer/robot.gd` (patience via GxGaugeComponent) |
| EventBus bridge + subscribe | `autoload/state.gd` + `modules/global_hud/global_hud.gd` |
| SaveSystem usage | `autoload/state.gd` (`save_game`/`load_game`) |
