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

## 2. 模块（按类别，与 §8.1 文件夹职责表对应）

约定：共享 `class_name` 一律 `Gx` 前缀；autoload 名简洁（`EventBus`/`SaveSystem`/`AudioManager`/`UIManager`）。启用插件后 4 个 autoload 自动注册。

| 类别 | 模块 | 文件 | 是什么 |
|---|---|---|---|
| **服务** | EventBus | `core/event_bus.gd` | 全局发布/订阅事件总线（解耦核心） |
| | SaveSystem | `core/save_system.gd` | 通用存档机制（管「怎么存」，不管「存什么」） |
| | AudioManager | `core/audio_manager.gd` | 统一音效/音乐播放（素材留项目） |
| | SoundManager [第三方吸收] | `audio/sound_manager.gd` | 音频系统——音效/UI音效/环境音/音乐 4 类独立池 + 交叉淡入（源自 nathanhoad/godot_sound_manager v2.6.2 MIT） |
| | UIManager | `core/ui_manager.gd` | Control 面板栈（瞬态模态弹窗） |
| **状态机** | GxStateMachine / GxState | `fsm/` | 最小状态机（控场景/关卡/流程，也可用于 AI） |
| **组件** | GxGaugeComponent | `components/gauge_component.gd` | 有界数值条（耐心/血量/体力/读条） |
| | GxFloatingNumber | `components/gx_floating_number.gd` | 浮动数字显示（伤害/暴击/治疗/得分弹出） |
| **工具** | GxMath / GxCooldown / GxObjectPool | `utils/` | 数学工具 / 冷却计时 / 对象池 |

### 2.1 服务（Autoload 全局单例）—— 处处可调的全局服务

#### 2.1.1 EventBus —— 跨模块通信

**是什么**：全局发布/订阅事件总线（autoload）。让模块 A 发消息时不认识模块 B——A 只管喊「事件 X 发生了」，谁关心谁订阅。

**怎么工作**：`subscribe(事件名, 回调函数)` 把回调登记到一张内部字典（事件名 → 回调数组）；`emit_event(事件名, 数据)` 遍历数组逐个调用，传一个 payload 参数；如果某个回调的对象已被 `queue_free()` 销毁，`is_valid()` 返回 false → 自动从列表里删掉，不报错。遍历时用数组副本，防止回调内部又订阅/退订导致数组变动出 bug。

**什么时候用**：
- 模块 A 变了要通知模块 B，但 A 不想引用 B（解耦）。
- 一条消息要发给多个监听者（HUD、音效、成就系统都要知道「token 变了」）。
- 替代散落的 `signal` + `connect`——用一个中心化的命名事件系统。

```gdscript
EventBus.subscribe(&"tokens_changed", _on_tokens)   # 消费者订阅
EventBus.emit_event(&"tokens_changed", 120)          # 产者广播（payload 一个参数）
EventBus.unsubscribe(&"tokens_changed", _on_tokens)
```
- 回调签名固定收 1 个 payload；失效监听者在 emit 时自动清理。
- 其它：`has_subscribers / clear_event / clear_all`。

#### 2.1.2 SaveSystem —— 存档

**是什么**：通用存档机制（autoload）。只管「**怎么存**」（序列化到磁盘、槽位管理、版本迁移），不管「**存什么**」（字段由你的 GameData 定义）。

**怎么工作**：你组好一个 `Dictionary` → `save_to_slot(N, dict)` → 内部用 `ConfigFile` 把每个键值对写入 `user://saves/slot_N.cfg`，同时写入 `__version`（你设置的版本号）。`load_from_slot(N)` 读回字典，如果文件里的版本号 ≠ 当前版本，就调用你注册的 migrator 回调做数据迁移。`has_slot(N)` 检查存档是否存在。

**什么时候用**：
- 关卡进度、玩家数据、解锁内容、设置项——任何需要跨会话持久化的数据。
- 多存档槽（不同玩家 / 不同周目）。
- 存档格式可能升级（v1→v2 加字段），需要版本迁移钩子。

```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "tokens": 120})   # 你组好 dict
var data := SaveSystem.load_from_slot(0)                    # 没有则返回 {}
SaveSystem.has_slot(0); SaveSystem.delete_slot(0); SaveSystem.list_slots()
SaveSystem.set_version(2); SaveSystem.set_migrator(回调)    # 版本迁移
```
- 存到 `user://saves/slot_N.cfg`，带 `__version`。
- 「存什么」由项目的 GameData 决定；SaveSystem 只负责落盘/读盘。

##### 2.1.2.1 SaveSystem 完整接入教程

**目标**：一个完全陌生的开发者照着做就能跑通存读档。

**步骤 1 — 注册 autoload**（如果用 game-template，已配好，跳过）
```
# project.godot [autoload]
SaveSystem="*res://addons/gd-common/core/save_system.gd"
GameData="*res://core/game_data.gd"     # 你自己写的，下面有模板
```

**步骤 2 — 写你的 GameData autoload**（管「存什么」）
```gdscript
# core/game_data.gd
extends Node

const SAVE_SLOT := 0

# --- 你的游戏数据 ---
var level: int = 0
var tokens: int = 0
var unlocked_items: Array[String] = []

signal changed


# --- 存档：组好 dict 交给 SaveSystem ---
func save() -> void:
	SaveSystem.save_to_slot(SAVE_SLOT, {
		"level": level,
		"tokens": tokens,
		"unlocked_items": unlocked_items,
	})


# --- 读档：从 SaveSystem 拿回 dict，拆到字段 ---
func load_game() -> void:
	var data := SaveSystem.load_from_slot(SAVE_SLOT)
	if data.is_empty():           # 没有存档（首次运行/删除后）
		return
	level = data.get("level", 0)
	tokens = data.get("tokens", 0)
	unlocked_items.assign(data.get("unlocked_items", []))
	changed.emit()


func has_save() -> bool:
	return SaveSystem.has_slot(SAVE_SLOT)


func new_game() -> void:
	level = 0; tokens = 0; unlocked_items.clear()
	changed.emit()
```

**步骤 3 — 在业务代码里调用**
```gdscript
# 存档（比如通关后）
GameData.level += 1
GameData.tokens += 500
GameData.save()                        # 一行存盘

# 读档（比如标题画面「继续」按钮）
if GameData.has_save():
	GameData.load_game()

# 删档
SaveSystem.delete_slot(0)
```

**步骤 4 — 版本迁移（当你的存档格式升级时）**
```gdscript
# 比如你的游戏从 v1 升级到 v2，加了个 "difficulty" 字段：
func _ready() -> void:
	SaveSystem.set_version(2)
	SaveSystem.set_migrator(_migrate)

func _migrate(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
	if from_v < 2:
		data["difficulty"] = "normal"   # 老存档补默认值
	return data
```

**要点**：
- SaveSystem **不认识你的字段**——它只存/读一个 dict。`data.get("key", default)` 是安全的取法（键不存在时返回默认值）。
- `load_from_slot` 返回 `{}`（空字典）= 没有存档，用 `is_empty()` 判断。
- 存档存在 `user://saves/` 下——不同操作系统路径不同，但 Godot 的 `user://` 统一处理了。
- ConfigFile 能存嵌套 Dictionary 和 Array，但**不能存 Object 实例**——存之前把自定义对象转成 dict/数组。

#### 2.1.3 SoundManager —— 音频系统（音效/UI/环境/音乐）[第三方吸收]

> 源自 nathanhoad/godot_sound_manager（MIT License，吸收版本 v2.6.2）。原始 LICENSE 见 `audio/LICENSE`。冻结在当前版本——如需更新，从此版本手动重拉重拷。

**是什么**：autoload `SoundManager`，完整的 2D 音频系统。内部管理 **4 个独立播放器池**：普通音效（8 个）、UI 音效（8 个，暂停时也响）、环境音（1 个，支持淡入淡出）、音乐（2 个，支持交叉淡入）。每个池自动按名字找对应的音频总线（Music/Sounds/UI），找不到回落 Master。音量用 0~1 线性值（内部转 dB）。

**怎么工作**：
- **音效池**（`sound_effects` / `ui_sound_effects`）：每次调用从池里取空闲播放器，全忙时扩容；播放完自动归还。UI 音效池设置 `PROCESS_MODE_ALWAYS`——游戏暂停（如打开设置）时 UI 音效仍然响。
- **环境音池**（`ambient_sounds`）：`play_ambient_sound` 带淡入、`stop_ambient_sound` 带淡出；同一资源重复播放不会叠加（复用已播放的）。
- **音乐池**（`music`）：2 个播放器实现交叉淡入——`play_music` 先淡出旧音乐再淡入新音乐。维护 50 条音轨历史，支持暂停/恢复、查询当前播放、指定起始位置和初始音量。

**什么时候用**：
- 任何音效、UI 音效、环境音、背景音乐播放。比散落 `AudioStreamPlayer` 好在一套 API 统一管理、自动池化、自动淡入淡出。
- 需要 UI 音效（菜单/按钮）不受暂停影响。
- 需要音乐交叉淡入切换、音轨历史、暂停/恢复。

```gdscript
# 音效
SoundManager.play_sound(load("res://sfx/hit.wav"))
SoundManager.play_sound_with_pitch(load("res://sfx/hit.wav"), 1.2)
SoundManager.stop_sound(load("res://sfx/hit.wav"))

# UI 音效（暂停时也响）
SoundManager.play_ui_sound(load("res://sfx/click.wav"))

# 环境音（淡入淡出）
SoundManager.play_ambient_sound(load("res://sfx/rain.wav"), 2.0)   # 淡入 2s
SoundManager.stop_ambient_sound(load("res://sfx/rain.wav"), 2.0)   # 淡出 2s

# 音乐（交叉淡入）
SoundManager.play_music(load("res://bgm/field.wav"), 1.5)           # 交叉淡入 1.5s
SoundManager.play_music_at_volume(bgm, 0.8, 2.0)                    # 指定初始音量+淡入
SoundManager.pause_music(); SoundManager.resume_music()
SoundManager.stop_music(2.0)                                        # 淡出 2s 后停
SoundManager.is_music_playing()                                     # 有音乐在响吗
SoundManager.get_music_track_history()                              # 最近 50 首

# 音量（0~1 线性，接设置滑块直接绑）
SoundManager.set_sound_volume(0.8)
SoundManager.set_music_volume(slider.value)
```

##### 2.1.3.1 SoundManager 完整接入教程

**步骤 1 — 准备音频总线**（用 game-template 自带的总线布局，或手动加）
- 打开 `Audio` 面板，确保有以下总线：`Music`、`Sounds`、`UI`（名字大小写不敏感，自动匹配）。没有就新建空总线。
- 如果缺这些总线，SoundManager 会回落 `Master` 并打印警告——功能正常，但无法独立控制分类音量。

**步骤 2 — autoload 注册**（如果用 game-template/gd-common，已配好，跳过）
```
# project.godot [autoload]
SoundManager="*res://addons/gd-common/audio/sound_manager.gd"
```

**步骤 3 — 调整默认总线（可选）**
```gdscript
func _ready() -> void:
	SoundManager.set_default_sound_bus("Sounds")
	SoundManager.set_default_music_bus("Music")
	SoundManager.set_default_ui_sound_bus("UI")
```
如果不调，SoundManager 自动按 `["Sounds","SFX"]` / `["UI","Interface","Sounds","SFX"]` / `["Music"]` 顺序找第一个存在的总线。

**步骤 4 — 设置面板接音量**
```gdscript
# 你的设置 UI
func _on_music_slider_changed(value: float) -> void:
	SoundManager.set_music_volume(value)      # value 0~1

func _on_sfx_slider_changed(value: float) -> void:
	SoundManager.set_sound_volume(value)
```


#### 2.1.4 UIManager —— 模态面板栈

**是什么**：通用 Control 面板栈管理器（autoload）。在自带的 CanvasLayer 上管理一堆弹窗，按栈式（后进先出）打开/关闭。

**怎么工作**：`_ready` 创建一个 `CanvasLayer`（默认 layer=100，在游戏内容之上）。`push_panel(packed_scene)` 实例化一个 Control 场景叠上去，同时**自动隐藏栈中上一个面板**（只显示最顶层）；`pop_panel()` 销毁顶部面板并恢复下一个可见。`clear()` 一次性清空所有面板。栈为空时什么都不显示。

**什么时候用**：
- 瞬态模态弹窗：设置面板、确认对话框、结算面板、暂停菜单。
- 需要多个弹窗叠加（设置 → 二级确认框），自动管理显隐。
- ⚠️ **不**适合常驻 HUD（那是 always-on，不是栈式弹出）或 Node2D 面板（`push_panel` 要求场景根是 `Control`）。

```gdscript
var p := UIManager.push_panel(packed_scene)   # 场景根必须是 Control
UIManager.pop_panel(); UIManager.get_top(); UIManager.clear()
```
> ⚠️ 仅用于 **Control 瞬态弹窗**。不适合常驻 HUD 或 Node2D 面板（CyberCookV3 的弹窗是 Node2D、HUD 是常驻 autoload，所以 V3 没用它——它留给新项目的 Control 式 UI）。

### 2.2 状态机框架 —— 不挂节点、纯逻辑的状态管理

#### 2.2.1 GxStateMachine / GxState —— 流程/场景状态机
```gdscript
const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")

var sm := GxStateMachine.new(self)               # self = context
sm.add_state(&"prep", GxState.new())
sm.add_state(&"service", GxState.new())
sm.state_changed.connect(func(from, to): ...)    # 监听切换做场景切换等
sm.transition_to(&"prep")
```
- 两种用法：子类化 `GxState`（重写 `_enter/_exit/_update`），或用纯 State + 监听 `state_changed`（详见下方 §2.2.2 完整教程）。
- 头部用 `preload` 引用可避开「全局类缓存」依赖（headless/CI 更稳）。

##### 2.2.2 状态机完整教程

GxStateMachine 有**两种典型场景**，选适合你的。

---

##### A. 纯 State + 监听信号 —— 适合「游戏流程 / 场景切换」

**什么时候用**：阶段之间只是「换个场景 / 显示不同面板」，每个阶段本身没有复杂逻辑。CyberCookV3 的「备餐→营业→结算」就是这套。

**完整步骤（复制可跑）**：

```gdscript
# -- autoload game_flow.gd （或挂在你自己的场景控制器上）--
extends Node

const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")

var _sm


func _ready() -> void:
	# 1. 创建机器，self 作为 context（状态里可通过 machine.context 访问本节点）
	_sm = GxStateMachine.new(self)

	# 2. 给每个阶段注册一个「裸」GxState（不子类化，纯标记）
	_sm.add_state(&"title", GxState.new())
	_sm.add_state(&"prep", GxState.new())
	_sm.add_state(&"service", GxState.new())

	# 3. 监听切换信号——什么时候切了，就干什么事
	_sm.state_changed.connect(_on_phase_changed)


# 4. 对外暴露几个「一键切」的方法（业务层只调这几个）
func go_prep() -> void:
	_sm.transition_to(&"prep")

func go_service() -> void:
	_sm.transition_to(&"service")


# 5. 切换时做的事（比如换场景）
func _on_phase_changed(_from: StringName, to: StringName) -> void:
	match to:
		&"prep":    get_tree().change_scene_to_file("res://scenes/prep.tscn")
		&"service": get_tree().change_scene_to_file("res://scenes/service.tscn")
		&"title":   get_tree().change_scene_to_file("res://scenes/title.tscn")
```

**要点**：
- 状态只是「名字」，行为全写在 `state_changed` 监听里——切换时做什么一目了然。
- `add_state` 支持链式写一条。
- 如果你想每帧驱动当前状态（比如营业阶段要跑计时），在 `_process` 里调 `_sm.update(delta)`。

---

##### B. 子类化 GxState —— 适合「角色 AI / 带行为的状态」

**什么时候用**：每个状态有**自己的 `_enter` 逻辑 + `_update` 每帧行为**，需要在状态内部切换。比如 NPC 巡逻 → 追击 → 返回。

**完整步骤（以巡逻/追击为例）**：

```gdscript
# -- patrol_state.gd --
class_name PatrolState
extends GxState

func _enter() -> void:
	print("开始巡逻")
	machine.context.sprite.modulate = Color.GREEN   # 通过 context 访问宿主


func _update(delta: float) -> void:
	# 每帧：如果看到玩家 → 切换到追击
	if machine.context.sees_player():
		machine.transition_to(&"chase")


func _exit() -> void:
	print("离开巡逻")


# -- chase_state.gd --
class_name ChaseState
extends GxState

var _chase_speed: float = 200.0


func _enter() -> void:
	print("开始追击！")
	machine.context.sprite.modulate = Color.RED


func _update(delta: float) -> void:
	# 朝玩家移动
	var dir := machine.context.player.global_position - machine.context.global_position
	machine.context.global_position += dir.normalized() * _chase_speed * delta

	# 如果玩家跑远了 → 回巡逻
	if dir.length() > 500.0:
		machine.transition_to(&"patrol")
```

**宿主脚本（挂机器人/角色身上）**：

```gdscript
extends CharacterBody2D

var _sm: GxStateMachine

func _ready() -> void:
	_sm = GxStateMachine.new(self)                       # self = context
	_sm.add_state(&"patrol", PatrolState.new())
	_sm.add_state(&"chase", ChaseState.new())
	_sm.start(&"patrol")                                  # 从巡逻开始


func _process(delta: float) -> void:
	_sm.update(delta)                                     # 每帧驱动当前状态


func sees_player() -> bool:
	return false  # 实际判定逻辑
```

**要点**：
- **`machine.context`** 就是 `GxStateMachine.new(self)` 里的 `self`——这里就是角色自己，所以状态里 `machine.context.sprite` 访问得到宿主的节点。
- **在状态内部切状态**：`machine.transition_to(...)`。状态不需要知道状态机「在哪」，只要知道 `machine` 是自己的机器即可调用。
- **`_enter` / `_exit`** 只执行一次，非常适合放「进入巡逻时播放音效」「退出追击时重置速度」这类一次性操作。
- **`start(initial)`** 用于首次进入（没有旧状态可退出），和 `transition_to` 的区别就在这。

---

##### C. 和 `godot_state_charts` 的分工（如果你两个都用）

| 场景 | 用什么 | 原因 |
|---|---|---|
| 游戏主流程/关卡切换（标题→备餐→营业→结算） | `GxStateMachine`（方式 A） | 简单线性流程，不需要条件守卫/并行/历史状态 |
| 角色 AI / 复杂状态图（巡逻→追击→攻击，带条件分支） | `godot_state_charts` 插件 | 状态图（StateChart）支持守卫、并行、子状态，适合 AI |
| 有每帧行为的简单状态 | `GxStateMachine`（方式 B） | 如果不想依赖外部插件，GxStateMachine 子类化够用 |

两者**不冲突**——CyberCookV3 里 `GameFlow`（GxStateMachine）管流程，`robot.tscn`（godot_state_charts）管机器人 AI，各管各的。

### 2.3 组件（挂节点的）—— extends Node，给对象拼装能力

#### 2.3.1 GxGaugeComponent —— 数值条组件

**是什么**：一个有界数值条（`extends Node`），挂在任意节点上。值在 `[0, max_value]` 范围内，可随时间自动消耗/恢复，也可手动加减。

**怎么工作**：`_ready` 初始化为满或空（由 `start_full` 决定）。如果 `auto_rate > 0`，`_process` 每帧自动减值（`auto_rate × rate_scale × delta`）；`auto_rate < 0` 自动恢复。`drain(n)` / `fill(n)` 手动加减，值变化时发 `value_changed(current, max)` 信号，归零发 `depleted`，满发 `filled`。`auto_active` 开关控制是否随时间变化（false = 暂停自动消耗）。`rate_scale` 做倍率（急单 ×1.5、冰冻 ×0.5 等）。

**什么时候用**：
- 任何「有上下限、会随时间或事件变化的数值」——机器人耐心、角色血量、体力条、技能充能/读条、经验条。
- 需要在 UI 上显示进度条 + 值归零时触发事件（比如耐心耗尽 → 机器人离开）。

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

**完整示例**（给机器人挂一个「耐心」条：随时间耗尽 → 耗尽就离开）：
```gdscript
extends Node2D

const GAUGE := preload("res://addons/gd-common/components/gauge_component.gd")
var _patience: Node

func _ready() -> void:
	_patience = GAUGE.new()
	_patience.max_value = 30.0       # 30 点耐心
	_patience.auto_rate = 1.0        # 每秒 -1
	_patience.auto_active = true     # 开始倒数
	add_child(_patience)
	_patience.value_changed.connect(_on_patience_changed)
	_patience.depleted.connect(_on_patience_empty)

func _on_patience_changed(current: float, maximum: float) -> void:
	$ProgressBar.value = current / maximum * 100.0   # 更新 UI 进度条

func _on_patience_empty() -> void:
	print("耐心耗尽，离开！")
	queue_free()
```
> 完整实例见 CyberCookV3 `scripts/gameplay/robot.gd`（机器人耐心就是这么做的）。

#### 2.3.2 GxFloatingNumber —— 浮动数字

**是什么**：浮动数字显示组件（`extends CanvasLayer`）。每次 `spawn` 弹出一个会自动消失的数字（伤害、得分等）。

**怎么工作**：`spawn(位置, 文本, 预设)` 创建一个 Label，播放「弹出放大 → 上浮 + 水平微晃 + 渐隐」动画，结束后 `queue_free` 自动销毁（无需你手动清理）。内置 5 种预设（DEFAULT/DAMAGE/HEAL/CRITICAL/MUTED），预配好了颜色/字号/缩放/位移/晃动；可用第 4 个参数覆盖个别值，或用 `spawn_custom` 完全自定义。

**什么时候用**：伤害数字、暴击弹出、得分/扣分、治疗数字、Miss 提示、Combo 文字。

```gdscript
const GxFloatingNumber := preload("res://addons/gd-common/components/gx_floating_number.gd")

var fn := GxFloatingNumber.new()
fn.layer = 100       # 确保在所有 UI 之上
add_child(fn)

# 5 种预设 ——— 颜色、缩放、字体、位移、晃动都已配好
fn.spawn(pos, "+80",   GxFloatingNumber.Preset.HEAL)       # 绿, 回复/得分
fn.spawn(pos, "-30",   GxFloatingNumber.Preset.DAMAGE)      # 红, 伤害/损失
fn.spawn(pos, "CRIT!", GxFloatingNumber.Preset.CRITICAL)    # 金, 暴击/大招(大字大弹)
fn.spawn(pos, "MISS",  GxFloatingNumber.Preset.MUTED)       # 灰, 未命中/低调提示
fn.spawn(pos, "1402",  GxFloatingNumber.Preset.DEFAULT)     # 白, 通用

# 预设 + 覆盖个别参数（不破坏预设的其他默认值）
fn.spawn(pos, "999", GxFloatingNumber.Preset.CRITICAL, {font_size = 36})

# 完全自定义
fn.spawn_custom(pos, "???", {color = Color.VIOLET, font_size = 24, scale_start = 3.0, wobble = 20})
```
- 每个 `spawn()` 调用的 Label **自动销毁**（动画结束 `queue_free`），无需手动清理。
- 动画序列：弹出放大→正常(0.12s) → 上浮 + 水平微晃 + 渐隐(0.8s) → 销毁。
- `spawn(pos, text, preset, overrides)` — 用预设；`spawn_custom(pos, text, cfg)` — 完全手写。
- cfg 键：`color`(Color), `font_size`(int), `scale_start`(float), `float_distance`(float), `wobble`(float), `duration`(float)。
- 用途：伤害数字、暴击弹出、得分/扣分、治疗数字、Miss 提示、Combo 文字。

**完整示例**（整个场景共用一个 GxFloatingNumber，敌人被击中时弹伤害数字）：
```gdscript
extends Node2D

const FloatNum := preload("res://addons/gd-common/components/gx_floating_number.gd")
var _fn: Node

func _ready() -> void:
	_fn = FloatNum.new()
	_fn.layer = 100          # 盖在所有 UI 之上
	add_child(_fn)

# 敌人被击中时调用：在它头上弹一个伤害数字
func _on_enemy_hit(enemy: Node2D, damage: int, is_crit: bool) -> void:
	var preset = FloatNum.Preset.CRITICAL if is_crit else FloatNum.Preset.DAMAGE
	_fn.spawn(enemy.global_position, "-%d" % damage, preset)

# 玩家回血时
func _on_player_heal(pos: Vector2, amount: int) -> void:
	_fn.spawn(pos, "+%d" % amount, FloatNum.Preset.HEAL)
```
> CyberCookV3 暂未接入此组件——以上即完整用法（通用组件，给新项目用）。

### 2.4 工具 —— 无状态/轻量，不进场景树

#### GxMath（静态函数）

**是什么**：静态数学工具类（`extends Object`），所有方法都是 `static func`，无状态，直接 `GxMath.xxx()` 调用，不需要实例化。

**怎么工作**：纯函数——输入参数，返回结果，不持有任何状态、不依赖场景树。

**什么时候用**：省得每次手写那些常见的小计算。
- `approach`：平滑趋近一个目标值（每帧靠近但不越过），用于镜头跟随、数值平滑过渡。
- `remap_clamped`：把一个值从一个范围映射到另一个范围（带钳制），用于进度条百分比、颜色插值。
- `chance`：按概率返回 true/false（0~1），用于随机事件触发（20% 掉落）。
- `pick_random`：从数组随机取一个元素，用于随机选择。
```gdscript
var v := GxMath.approach(5.0, 10.0, delta * 3.0)          # 朝 10 靠拢，每帧+3
var r := GxMath.remap_clamped(0.5, 0.0, 1.0, 0.0, 100.0)   # → 50.0
if GxMath.chance(0.2): print("20% 概率命中")
var pick = GxMath.pick_random(["a", "b", "c"])             # 随机取一个
```

#### GxCooldown（手动计时器）

**是什么**：手动倒计时器（`extends RefCounted`，不是 Node——不进场景树，更轻量）。

**怎么工作**：`start()` 把 `time_left` 设为 `duration`；`update(delta)` 每帧递减；`time_left` 归零时触发 `finished` 信号一次；`is_ready()` 判断是否到 0；`progress()` 返回 0.0~1.0 的进度比。你需要自己在外部调 `update(delta)`——它不会自动运行（因为没有 `_process`）。

**什么时候用**：
- 技能冷却、生成间隔、防抖——任何「等 N 秒就好了」的需求。
- 和 Godot 内置 `Timer` 节点的区别：`GxCooldown` 是 RefCounted（不进场景树、不自动跑），适合在非 Node 上下文里用（比如纯逻辑类里计时），或者你想要手动控制推进时机时。如果你已经在场景树里且想要自动计时，直接用 `Timer` 节点更方便。
```gdscript
var cd := GxCooldown.new(2.0)     # 2 秒冷却
cd.start()                        # 开始计时
cd.update(delta)                  # 每帧推进
if cd.is_ready(): print("好了")   # 或连 cd.finished 信号
print(cd.progress())              # 0.0~1.0 进度
```

#### GxObjectPool（对象池）

**是什么**：通用对象池（`extends RefCounted`），基于工厂回调创建实例，`acquire` 取用 / `release` 归还复用。

**怎么工作**：构造时传入一个 `factory` Callable（负责创建新实例）和可选预热数量（提前创建 N 个放池里）。`acquire()` 从池里取一个——池空就调 factory 新建；`release(obj)` 把对象还回池里等下次复用。池本身不关心对象是什么类型，只管存取。

**什么时候用**：
- 频繁创建/销毁的对象：子弹、粒子、特效实例、敌人——避免反复 `instantiate()` + `queue_free()` 的开销。
- 对象构造代价大（复杂场景、带初始化逻辑），复用比重建划算。
```gdscript
var pool := GxObjectPool.new(func(): return Bullet.new(), 10)  # 工厂 + 预热 10 个
var b = pool.acquire()    # 取一个（池空就新建）
pool.release(b)           # 还回去复用
```

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

---

## 8. 如何新增一个通用模块（贡献指南）

> 先问一句：**这功能跨游戏通用吗？** 通用 → 进 gd-common；带游戏专属假设 → 放项目 `modules/`，别污染共享层。
> 提示「三次法则」：同一个东西在 2~3 个地方用过、形态稳定了再抽进来，别过早抽象。

### 8.1 文件夹职责表（**先看这个，防乱放**）

| 文件夹 | 放什么 | 用来做什么 | 什么时候用 | ❌ 不该放（反例） |
|---|---|---|---|---|
| `core/` | 全局服务单例（autoload 脚本，**不写 class_name**） | 提供「全局唯一、处处可访问」的跨模块服务 | 事件总线 / 存档 / 音频 / UI 管理 / 日志 等需要全局一份的 | 挂节点的组件→`components`；纯函数→`utils` |
| `audio/` | 音频系统（第三方吸收，5 文件子系统） | 音效/UI音效/环境音/音乐 4 类独立播放器池 + 交叉淡入（源自 nathanhoad/godot_sound_manager v2.6.2 MIT） | 需要音频时 | 单文件服务→`core`；组件→`components` |
| `components/` | 继承 `Node` 或 `CanvasLayer` 的可复用组件 | 给任意游戏对象「拼装」一种能力/行为，或充当独立 UI 覆盖层，随节点实例存在 | 功能是「某对象的一种能力」、有自己状态/信号、要进场景树（血量/耐心/移动/拾取/计时；UI控件如浮动数字也放这） | 全局单例→`core`；无状态计算→`utils`；状态机→`fsm` |
| `fsm/` | 状态机基类/框架 | 管理状态切换（流程/关卡/AI） | 需要有限状态机、或扩展 FSM 能力时 | 非状态相关逻辑 |
| `utils/` | 无状态工具类（多为静态函数） | 通用计算/小助手，不进场景树 | 纯逻辑：数学/随机/计时/对象池/字符串 | 要进场景树→`components`；全局服务→`core` |
| 根 `plugin.gd` / `plugin.cfg` | 插件入口 | 启用时注册 autoload | **仅当新增/删除 autoload 时**才改 | 业务逻辑 |

> 新增大类（如可复用 Control 控件）可建新子文件夹（如 `ui_base/`），但**必须在本表登记 + 在 `README.md` 加契约条目**，保持本表是唯一权威映射。

### 8.2 选放哪的决策流（一句话判定）

```
全局唯一、到处可调？ ───────────────── 是 → core/  (autoload)
挂在节点上、随实例存在、给对象加能力？ ── 是 → components/
是状态机？ ─────────────────────────── 是 → fsm/
纯函数 / 不进场景树的工具？ ─────────── 是 → utils/
都不是 / 带游戏专属假设？ ───────────── 不进 gd-common，放项目 modules/
```

### 8.3 命名 / 类型规范

- 普通类/组件：`class_name GxXxx`（**Gx 前缀**）。
- autoload 脚本：用简洁全局名（如 `Logger`），脚本里**不要写 class_name**（会与 autoload 全局名冲突）。
- 信号、文件名：`snake_case`（如 `value_changed`、`gx_timer.gd`）。
- 头部引用其它 Gx 类优先 `preload(...)`，headless/CI 更稳。

### 8.4 两种添加流程 + 手把手示例

#### A. 普通类 / 组件（不需要全局单例）——**最常见，不用改 plugin.gd**

1) 新建 `components/gx_timer.gd`：
```gdscript
class_name GxTimer
extends Node
## 可复用倒计时组件。挂在任意节点上。

signal timeout

@export var duration: float = 1.0
@export var autostart: bool = false

var _left: float = 0.0
var _running: bool = false


func _ready() -> void:
	if autostart:
		start()


func start(d: float = -1.0) -> void:
	if d > 0.0:
		duration = d
	_left = duration
	_running = true


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	if not _running:
		return
	_left -= delta
	if _left <= 0.0:
		_running = false
		timeout.emit()
```

2) 在 `README.md` 文件夹表/契约里登记一条。

3) 调用（任意项目，pull 到最新后）：
```gdscript
const GxTimer := preload("res://addons/gd-common/components/gx_timer.gd")

var t := GxTimer.new()
add_child(t)
t.timeout.connect(func(): print("时间到"))
t.start(3.0)
```
> 编辑器里全局类缓存生效后，也可直接 `GxTimer.new()`。

#### B. 新 autoload 服务（需要全局单例）——**多两步注册**

1) 新建 `core/logger.gd`（**不写 class_name**）：
```gdscript
extends Node
## 全局日志服务（autoload: Logger）。

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: int = Level.DEBUG


func info(msg: String) -> void:
	_log(Level.INFO, msg)


func warn(msg: String) -> void:
	_log(Level.WARN, msg)


func error(msg: String) -> void:
	_log(Level.ERROR, msg)


func _log(level: int, msg: String) -> void:
	if level < min_level:
		return
	print("[%s] %s" % [Level.keys()[level], msg])
```

2) 在 `plugin.gd` 的 `AUTOLOADS` 里加一条：
```gdscript
const AUTOLOADS := {
	"EventBus": "res://addons/gd-common/core/event_bus.gd",
	# ... 既有的 ...
	"Logger": "res://addons/gd-common/core/logger.gd",   # 新增
}
```

3) 在消费项目 `project.godot` 的 `[autoload]` 注册（或在编辑器里禁用再启用插件，让它自动写入）：
```
Logger="*res://addons/gd-common/core/logger.gd"
```

4) 调用（全局，任何地方）：
```gdscript
Logger.info("开张了")
Logger.error("出错了")
```

### 8.5 每个模块必交付 / 发布 / 验证

- **必交付**：① 遵守 §6 军规；② 在 `README.md` 加契约条目（API + 一段最小用法）；③ §8.1 表里能对上号的归属。
- **发布链路**：
  ```
  # 在源仓库 D:\GitRepos\gd-common
  git add -A && git commit -m "feat: GxTimer"
  # 在每个消费项目
  git -C addons/gd-common pull origin main
  ```
- **验证**：`godot --headless --path <项目> --quit`，确认 0 SCRIPT/Parse ERROR。

