# gd-common

Reusable **generic layer** for Godot 4 projects, shipped as an addon and consumed via Git submodule.

> Scope: genre-agnostic infrastructure only. No game-specific gameplay.

## Modules

- `core/event_bus.gd` — global pub/sub (autoload `EventBus`)
- _(P1)_ `core/save_system.gd`, `core/audio_manager.gd`, `core/ui_manager.gd`
- _(P2)_ `fsm/state_machine.gd` + `fsm/state.gd`, `utils/`, `components/gauge_component.gd`

## Install

```
git submodule add file:///D:/GitRepos/gd-common addons/gd-common
```

Then enable **gd-common** in Project Settings → Plugins. The plugin registers its
autoload singletons automatically.

## Conventions

- Shared `class_name` prefix: `Gx` (e.g. `GxStateMachine`, `GxGaugeComponent`).
- Autoload names are plain: `EventBus`, `SaveSystem`, `AudioManager`, `UIManager`.

## Decoupling rules

1. No hardcoded node paths (`get_node("/root/...")`).
2. No hardcoded `res://` asset paths inside logic — inject instead.
3. Inject dependencies; do not `load()` project assets internally.
4. Communicate via signals / `EventBus`, never hard-reference other systems.
5. Self-contained: each module ships its own scripts/scenes/default resources.
6. Do not depend on project-specific autoloads.

_(Full per-module contracts are added in P4.)_
