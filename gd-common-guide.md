# gd-common 通用层 / 跨项目复用指南

> 本文是整套复用系统的**权威总览**（随 gd-common 仓库走）。各模块的英文 API 速查见同目录 `README.md`。
> 适用引擎：Godot 4.x（已在 4.7 验证）。

---

## 1. 总览：三个仓库

```
D:\GitRepos\gd-common        共享通用层（Godot 插件，纯 GDScript）
D:\GitRepos\game-template    新项目模板（已接好 gd-common + GameData/GameManager 桩）
D:\GameProject\src\CyberCookV3   首个消费项目（演示如何接入与使用）
```

关系：

```
gd-common ──submodule──> game-template ──克隆──> 你的新游戏
    └──────submodule──> CyberCookV3（参考实现）
```

- **gd-common**：与游戏类型无关的基础设施。只放通用件，**绝不放具体玩法**。
- **game-template**：开箱即完整的项目骨架，新游戏从它克隆。
- **CyberCookV3**：真实接入示例，每个模块的用法都能在这里找到参考。

---

## 2. gd-common 每个模块（是什么 / 怎么用）

约定：共享 `class_name` 一律 `Gx` 前缀；autoload 名简洁（`EventBus`/`SaveSystem`/`AudioManager`/`UIManager`）。启用插件后 4 个 autoload 自动注册。

| 模块 | 文件 | 类型 | 是什么 |
|---|---|---|---|
| EventBus | `core/event_bus.gd` | autoload | 全局发布/订阅事件总线（解耦核心） |
| SaveSystem | `core/save_system.gd` | autoload | 通用存档机制（管「怎么存」，不管「存什么」） |
| AudioManager | `core/audio_manager.gd` | autoload | 统一音效/音乐播放（素材留项目） |
| UIManager | `core/ui_manager.gd` | autoload | Control 面板栈（瞬态模态弹窗） |
| GxStateMachine / GxState | `fsm/` | 类 | 最小状态机（控场景/关卡/流程，也可用于 AI） |
| GxGaugeComponent | `components/gauge_component.gd` | Node | 有界数值条（耐心/血量/体力/读条） |
| GxMath / GxCooldown / GxObjectPool | `utils/` | 类 | 数学工具 / 冷却计时 / 对象池 |

### 2.1 EventBus —— 跨模块通信
```gdscript
EventBus.subscribe(&"tokens_changed", _on_tokens)   # 消费者订阅
EventBus.emit_event(&"tokens_changed", 120)          # 产者广播（payload 一个参数）
EventBus.unsubscribe(&"tokens_changed", _on_tokens)
```
- 回调签名固定收 1 个 payload；失效监听者在 emit 时自动清理。
- 其它：`has_subscribers / clear_event / clear_all`。

### 2.2 SaveSystem —— 存档
```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "tokens": 120})   # 你组好 dict
var data := SaveSystem.load_from_slot(0)                    # 没有则返回 {}
SaveSystem.has_slot(0); SaveSystem.delete_slot(0); SaveSystem.list_slots()
SaveSystem.set_version(2); SaveSystem.set_migrator(回调)    # 版本迁移
```
- 存到 `user://saves/slot_N.cfg`，带 `__version`。
- 「存什么」由项目的 GameData 决定；SaveSystem 只负责落盘/读盘。

### 2.3 AudioManager —— 音频
```gdscript
AudioManager.play_sfx(stream, -3.0, 1.1)   # 流, 音量dB, 音高
AudioManager.play_music(stream, 1.5)        # 淡入 1.5s
AudioManager.stop_music(1.0)                # 淡出
```
音频**资源（.wav/.ogg）留在项目里**，把 stream 传进来。

### 2.4 UIManager —— 模态面板栈
```gdscript
var p := UIManager.push_panel(packed_scene)   # 场景根必须是 Control
UIManager.pop_panel(); UIManager.get_top(); UIManager.clear()
```
> ⚠️ 仅用于 **Control 瞬态弹窗**。不适合常驻 HUD 或 Node2D 面板（CyberCookV3 的弹窗是 Node2D、HUD 是常驻 autoload，所以 V3 没用它——它留给新项目的 Control 式 UI）。

### 2.5 GxStateMachine / GxState —— 流程/场景状态机
```gdscript
const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")

var sm := GxStateMachine.new(self)               # self = context
sm.add_state(&"prep", GxState.new())
sm.add_state(&"service", GxState.new())
sm.state_changed.connect(func(from, to): ...)    # 监听切换做场景切换等
sm.transition_to(&"prep")
```
- 两种用法：子类化 `GxState`（重写 `_enter/_exit/_update`），或用纯 State + 监听 `state_changed`。
- 头部用 `preload` 引用可避开「全局类缓存」依赖（headless/CI 更稳）。

### 2.6 GxGaugeComponent —— 数值条组件
```gdscript
var g := GxGaugeComponent.new()
g.max_value = 30.0
g.auto_rate = 1.0        # 每秒消耗 1（正=耗向0，负=回向max，0=纯手动）
g.auto_active = false    # 是否随时间自动变化
add_child(g)
g.value_changed.connect(_on_changed)   # (current, max)
g.depleted.connect(_on_empty)          # 归零
g.reset(); g.drain(5); g.fill(2); g.auto_active = true
```
- 用于：机器人耐心、血量、体力、读条/充能。`rate_scale` 可做急单×1.5 等加速。

### 2.7 utils
- `GxMath`（静态）：`approach / remap_clamped / chance / pick_random`
- `GxCooldown`：`start / update(delta) / is_ready / progress`，信号 `finished`
- `GxObjectPool`：`acquire / release`，工厂回调创建实例

---

## 3. game-template —— 新项目模板

结构：
```
addons/gd-common/   共享层（submodule）
core/
  game_data.gd      [autoload GameData]    你的数据+存档（调 SaveSystem）
  game_manager.gd   [autoload GameManager] 你的流程（用 GxStateMachine）
  data/             CSV/数据表
scenes/             main.tscn + levels/ actors/ ui/ fx/
assets/             美术/音频/字体
```

新项目怎么开：
```
git clone <game-template> my-game
cd my-game
git submodule update --init --recursive
# Godot 打开 → 项目设置启用 gd-common → 运行
```
GameData / GameManager 是**桩**，按你的游戏改字段和状态即可；共享层不动。

---

## 4. CyberCookV3 参考用法（想抄哪个模式就看哪个文件）

| 模式 | 参考文件 |
|---|---|
| 流程/场景状态机 | `autoload/game_flow.gd`（GxStateMachine 包裹 change_scene） |
| 数值条组件 | `modules/customer/robot.gd`（耐心用 GxGaugeComponent） |
| EventBus 桥接+订阅 | `autoload/state.gd`（桥接）+ `modules/global_hud/global_hud.gd`（订阅） |
| SaveSystem 用法 | `autoload/state.gd`（`save_game`/`load_game`） |

---

## 5. 接入 / 更新共享库

接入到任意项目：
```
git submodule add file:///D:/GitRepos/gd-common addons/gd-common
# 项目设置 → 插件 → 启用 gd-common
```
更新共享库到最新：
```
git -C addons/gd-common pull origin main
git add addons/gd-common && git commit -m "bump gd-common"
```

---

## 6. 解耦军规（任何要进共享层的代码都遵守）

1. 禁写死节点路径 `get_node("/root/...")`。
2. 禁在逻辑里写死 `res://` 资源路径——靠注入。
3. 依赖注入，不在模块内部 `load()` 项目资源。
4. 只发信号 / 走 EventBus，不硬引用别的系统。
5. 自包含：模块自带脚本/场景/默认资源。
6. 不依赖项目专属 autoload。

---

## 7. 验证与纪律（踩过的坑）

- **用 CLI 跑「运行」验证**：`godot --headless --path <项目> --quit`，可查脚本/解析错。
- ⚠️ **别对 CyberCookV3 跑 `--import` / `--editor`**：会触发内置 CSV 翻译导入器把数据 CSV 回退（覆盖 csv-data 导入器）。GUI 编辑器正常用没问题；CSV 的工作产物（9 个 `.import` + `.godot/imported` 的 `.res`）已从 V2 拷入并稳定。
- **本地仓库 → 远程**：gd-common / game-template 目前是本地仓库（`file:///`）。建好 GitHub 仓库后 `git remote add` 并把各项目 `.gitmodules` 的 url 改为远程地址。
- **headless 引用类**：用 `preload(".../xxx.gd")` 而非全局 `class_name`，避免依赖编辑器的全局类缓存。
