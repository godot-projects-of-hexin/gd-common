# gd-common

Reusable **generic layer** for Godot 4 projects, shipped as an addon and consumed via Git submodule.

> Scope: genre-agnostic infrastructure only. **No game-specific gameplay.**
> Convention: shared `class_name` prefix `Gx`; autoload names plain (`EventBus`, `SaveSystem`, `AudioManager`, `UIManager`).

## Install

```
git submodule add file:///D:/GitRepos/gd-common addons/gd-common
```

Enable **gd-common** in Project Settings → Plugins. The plugin registers its
autoload singletons (`EventBus`, `SaveSystem`, `AudioManager`, `UIManager`).

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

### `core/audio_manager.gd` — autoload `AudioManager`
Generic playback; audio **assets stay in the project**.
```gdscript
AudioManager.play_sfx(stream, -3.0, 1.1)
AudioManager.play_music(stream, 1.5)   # fade in
AudioManager.stop_music(1.0)
```

### `core/ui_manager.gd` — autoload `UIManager`
Generic **Control** panel stack on its own CanvasLayer (for transient modals).
```gdscript
var p := UIManager.push_panel(packed_scene)   # root must be a Control
UIManager.pop_panel(); UIManager.get_top(); UIManager.clear()
```
> Not for persistent HUDs or Node2D panels.

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

### `utils/`
- `GxMath` — `approach`, `remap_clamped`, `chance`, `pick_random` (all static)
- `GxCooldown` — manual timer, `start/update(delta)/is_ready/progress`, `finished`
- `GxObjectPool` — `acquire/release`, factory-based pooling

---

## Reference integrations (CyberCookV3)

| Pattern | Where to copy from |
|---|---|
| Scene/flow FSM | `autoload/game_flow.gd` (GxStateMachine + scene swap) |
| Gauge component | `modules/customer/robot.gd` (patience via GxGaugeComponent) |
| EventBus bridge + subscribe | `autoload/state.gd` + `modules/global_hud/global_hud.gd` |
| SaveSystem usage | `autoload/state.gd` (`save_game`/`load_game`) |
