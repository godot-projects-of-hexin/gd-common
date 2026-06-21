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
| | UIManager | `core/ui_manager.gd` | Control 面板栈（瞬态模态弹窗） |
| **状态机** | GxStateMachine / GxState | `fsm/` | 最小状态机（控场景/关卡/流程，也可用于 AI） |
| **组件** | GxGaugeComponent | `components/gauge_component.gd` | 有界数值条（耐心/血量/体力/读条） |
| | GxFloatingNumber | `components/gx_floating_number.gd` | 浮动数字显示（伤害/暴击/治疗/得分弹出） |
| **工具** | GxMath / GxCooldown / GxObjectPool | `utils/` | 数学工具 / 冷却计时 / 对象池 |

### 2.1 服务（Autoload 全局单例）—— 处处可调的全局服务

#### 2.1.1 EventBus —— 跨模块通信
```gdscript
EventBus.subscribe(&"tokens_changed", _on_tokens)   # 消费者订阅
EventBus.emit_event(&"tokens_changed", 120)          # 产者广播（payload 一个参数）
EventBus.unsubscribe(&"tokens_changed", _on_tokens)
```
- 回调签名固定收 1 个 payload；失效监听者在 emit 时自动清理。
- 其它：`has_subscribers / clear_event / clear_all`。

#### 2.1.2 SaveSystem —— 存档
```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "tokens": 120})   # 你组好 dict
var data := SaveSystem.load_from_slot(0)                    # 没有则返回 {}
SaveSystem.has_slot(0); SaveSystem.delete_slot(0); SaveSystem.list_slots()
SaveSystem.set_version(2); SaveSystem.set_migrator(回调)    # 版本迁移
```
- 存到 `user://saves/slot_N.cfg`，带 `__version`。
- 「存什么」由项目的 GameData 决定；SaveSystem 只负责落盘/读盘。

#### 2.1.3 AudioManager —— 音频
```gdscript
AudioManager.play_sfx(stream, -3.0, 1.1)   # 流, 音量dB, 音高
AudioManager.play_music(stream, 1.5)        # 淡入 1.5s
AudioManager.stop_music(1.0)                # 淡出
```
音频**资源（.wav/.ogg）留在项目里**，把 stream 传进来。

#### 2.1.4 UIManager —— 模态面板栈
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

#### 2.3.2 GxFloatingNumber —— 浮动数字
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

### 2.4 工具 —— 无状态/轻量，不进场景树

#### GxMath（静态函数）
```gdscript
var v := GxMath.approach(5.0, 10.0, delta * 3.0)          # 朝 10 靠拢，每帧+3
var r := GxMath.remap_clamped(0.5, 0.0, 1.0, 0.0, 100.0)   # → 50.0
if GxMath.chance(0.2): print("20% 概率命中")
var pick = GxMath.pick_random(["a", "b", "c"])             # 随机取一个
```

#### GxCooldown（手动计时器）
```gdscript
var cd := GxCooldown.new(2.0)     # 2 秒冷却
cd.start()                        # 开始计时
cd.update(delta)                  # 每帧推进
if cd.is_ready(): print("好了")   # 或连 cd.finished 信号
print(cd.progress())              # 0.0~1.0 进度
```

#### GxObjectPool（对象池）
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

