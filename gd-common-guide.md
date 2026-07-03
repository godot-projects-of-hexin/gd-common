# gd-common 通用层 / 跨项目复用指南

> 本文是整套复用系统的**权威总览**（随 gd-common 仓库走）。各模块的英文 API 速查见同目录 `README.md`。
> 适用引擎：Godot 4.x（已在 4.7 验证）。

---

## 1. 总览：三个仓库

```
gd-common        共享通用层（Godot 插件，纯 GDScript）
game-template    新项目模板（已接好 gd-common + GameData/GameManager 桩）
CyberCookV3      首个消费项目（演示如何接入与使用）
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

约定：共享 `class_name` 一律 `Gx` 前缀；autoload 名简洁（`EventBus`/`SaveSystem`/`SoundManager`/`UIManager`）。启用插件后 4 个 autoload 自动注册。

| 模块 | 文件 | 类型 | 是什么 |
|---|---|---|---|
| EventBus | `core/event_bus.gd` | autoload | 全局发布/订阅事件总线（解耦核心） |
| SaveSystem | `core/save_system.gd` | autoload | 通用存档机制（管「怎么存」，不管「存什么」） |
| SoundManager | `audio/sound_manager.gd` | autoload | 统一音效/音乐/环境音播放（素材留项目） |
| UIManager | `core/ui_manager.gd` | autoload | Control 面板栈（瞬态模态弹窗） |
| GxStateMachine / GxState | `fsm/` | 类 | 最小状态机（控场景/关卡/流程，也可用于 AI） |
| GxGaugeComponent | `components/gauge_component.gd` | Node | 有界数值条（耐心/血量/体力/读条） |
| GxFloatingNumber | `components/gx_floating_number.gd` | Control | 浮字：伤害/得分数字漂起淡出 |
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

### 2.3 SoundManager —— 音频
**为什么需要 process-mode 拆分**：当 `get_tree().paused = true` 打开暂停菜单时，SFX 应该噤声但 BGM 的淡出动画不能卡在半路——否则恢复时音量跳变。Music root 用 `PROCESS_MODE_ALWAYS` 保证 tween 始终运行。

```gdscript
# 实际用法：载入音频资源，传进来
var stream := load("res://sfx/ui_click.wav")
SoundManager.play_sound(stream)             # 单次 SFX（8 通道池）
SoundManager.play_ui_sound(stream)          # 同上

SoundManager.play_music(load("res://bgm/service.wav"), 1.5)  # BGM 淡入
SoundManager.stop_music(1.5)                # 淡出

SoundManager.play_ambient_sound(load("res://sfx/kitchen.wav"), 2.0)
SoundManager.stop_all_ambient_sounds(1.5)   # 场景切换时清理

# 暂停恢复（不打断播放位置）
SoundManager.pause_music(0.5)               # 淡到静音
SoundManager.resume_music(0.5)              # 淡回上次音量
```
- `pause_music()` 才是正确选择 —— `set_bus_volume_db("Music", -60)` 在 pause 时 bus 不 tick，tween 失效。
- SFX 池 8 通道：全忙时**抢占最旧**通道（短 UI 反馈设计；长 ambience 用 `play_ambient_sound`）。
- `play_music(新歌)` 清掉 pause 内部状态，防止 `resume_music` 误恢复旧歌音量。

### 2.4 UIManager —— 模态面板栈
**为什么**：手动 `add_child` 弹出对话框时要记住"底下是谁"、恢复谁的 `visible`——面板二层三层嵌套时极其脆弱。UIManager 自动 hide 下层、show 上层，你只需 push/pop。

```gdscript
UIManager.push_panel(preload("res://ui/settings.tscn"))   # 打开设置
# 用户在设置里点「改键位」→ push 键位面板：
UIManager.push_panel(preload("res://ui/keybind.tscn"))
# 关闭键位面板 → 自动显示回设置：
UIManager.pop_panel()
UIManager.get_top()    # 取最上层面板（或 null）
UIManager.clear()      # 场景切换时全清
```
> ⚠️ 仅用于 **Control 瞬态弹窗**。不适合常驻 HUD 或 Node2D 面板（CyberCookV3 的弹窗是 Node2D、HUD 是常驻 autoload，所以 V3 没用它——它留给新项目的 Control 式 UI）。

### 2.5 GxStateMachine / GxState —— 流程/场景状态机
**基础流（保留）**:
```gdscript
const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")

var sm := GxStateMachine.new(self)               # self = context
sm.add_state(&"prep", GxState.new())
sm.add_state(&"service", GxState.new())
sm.state_changed.connect(func(from, to): ...)    # 监听切换做场景切换等
sm.transition_to(&"prep")
```

**事件驱动 + 守卫**（PR-0001 新增）:
```gdscript
var sm := GxStateMachine.new()
sm.attach_to(self)                                # 记 host（.attached_host 只读）
sm.add_state(&"idle",    GxState.new())
sm.add_state(&"walk",    GxState.new())
sm.add_state(&"attack",  GxState.new())

# 表驱动：(from, event) → (target, guard?)
sm.add_transition(&"idle",   &"move_pressed",   &"walk")
sm.add_transition(&"walk",   &"attack_pressed", &"attack",
    func() -> bool: return $Weapon.can_attack())   # 守卫

sm.start(&"idle")
sm.try_transition(&"move_pressed")                # → walk
sm.try_transition(&"attack_pressed")              # 守卫放行 → attack
```

**查询 & 信号**（PR-0001 新增）:
```gdscript
sm.is_in_state(&"walk")                           # 严格名匹配（不引入 HSM）
sm.guard_failed.connect(func(from, ev): ...)      # 守卫拒绝
sm.unhandled_event.connect(func(ev): ...)         # 事件无匹配转换
```

- 两种用法：子类化 `GxState`（重写 `_enter/_exit/_update`），或用纯 State + 监听 `state_changed`。
- 头部用 `preload` 引用可避开「全局类缓存」依赖（headless/CI 更稳）。
- `attach_to` 只记引用、**不 add_child**，状态机仍 `extends RefCounted`，生命周期由 `update()` / `physics_update()` 的外部驱动者负责。
- `is_in_state` 是精确匹配；`start()` 之前永远返回 `false`。HSM 父态继承是后续 PR。
- `add_transition` 错误策略：`push_error + return self`（不 `assert`，release 不剥）。`transition_to` 自转移走 `push_warning` + 静默。

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

### 2.7 GxCooldown —— 冷却计时器
```gdscript
var _dash_cd := GxCooldown.new(2.0)           # 2 秒冷却

func _process(delta: float) -> void:
    _dash_cd.update(delta)                    # 手动推进

func _on_dash_input() -> void:
    if not _dash_cd.is_ready(): return        # 冷却中
    _perform_dash()
    _dash_cd.start()                          # 重新计时

func _on_player_died() -> void:
    _dash_cd.cancel()                         # 中断 — 不发 finished 信号
```
- `start(秒?) / update(delta) / is_ready() / progress() / cancel()`
- 信号 `finished` — 归零时发一次。`cancel()` 不发。
- 用于：技能冷却、冲刺间隔、攻击间隔。

### 2.8 GxMath —— 数学工具（纯静态）
```gdscript
GxMath.approach(5.0, 10.0, 2.0)         # → 7.0
GxMath.remap_clamped(0.5, 0, 1, 0, 100) # → 50.0
GxMath.chance(0.3)                       # 30% 概率 true
GxMath.pick_random([1, 2, 3])            # 随机一个
```
- `approach(当前, 目标, 步长)` — 平滑逼近，不越界。
- `remap_clamped(值, 入min, 入max, 出min, 出max)` — 线性重映射。
- `chance(概率)` — `randf() < 概率`。
- `pick_random(arr)` — 空则 `null`。

### 2.9 GxObjectPool —— 对象池
```gdscript
var _pool := GxObjectPool.new(func():
    return preload("res://bullet.tscn").instantiate(), 5)  # 预热 5 个

func _fire() -> void:
    var b := _pool.acquire()        # 从池取（不够才 new）
    add_child(b)

func _on_impact(bullet) -> void:
    _pool.release(bullet)           # 归还复用
```
- `acquire()` — 获取实例。`release(obj)` — 归还。`available_count()` — 池中数量。
- ⚠️ `release` 不防重：同一对象 release 两次会重复入池。

### 2.10 GxFloatingNumber —— 浮字
```gdscript
var fn := GxFloatingNumber.new()
fn.text = "-5"
fn.color = Color.RED
fn.duration = 1.2
add_child(fn)
fn.show_at(global_position)
```
- 自动漂起 + 淡出，动画结束后 `queue_free`。
- 用于：伤害数字、得分弹出、金币 +N 等即时反馈。

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
| 数值条组件 | `scripts/gameplay/robot.gd`（耐心用 GxGaugeComponent） |
| EventBus 桥接+订阅 | `autoload/state.gd`（桥接）+ `scripts/ui/global_hud.gd`（订阅） |
| SaveSystem 用法 | `autoload/state.gd`（`save_game`/`load_game`） |

---

## 5. 接入 / 更新共享库

接入到任意项目：
```
git submodule add <gd-common-remote-url> addons/gd-common
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
- ⚠️ **别对 CyberCookV3 跑 `--import` / `--editor`**：会触发内置 CSV 翻译导入器把数据 CSV 回退（覆盖 csv-data 导入器）。GUI 编辑器正常用没问题。
- **本地仓库 → 远程**：gd-common 本地仓库准备好后，`git remote add origin <url>` 并推上 GitHub，消费项目改 `.gitmodules` 的 url 为远程地址。
- **headless 引用类**：用 `preload(".../xxx.gd")` 而非全局 `class_name`，避免依赖编辑器的全局类缓存。

---

## 8. 如何新增一个通用模块（贡献指南）

> 先问一句：**这功能跨游戏通用吗？** 通用 → 进 gd-common；带游戏专属假设 → 放项目 `modules/`，别污染共享层。
> 提示「三次法则」：同一个东西在 2~3 个地方用过、形态稳定了再抽进来，别过早抽象。

### 8.1 文件夹职责表（**先看这个，防乱放**）

| 文件夹 | 放什么 | 用来做什么 | 什么时候用 | ❌ 不该放（反例） |
|---|---|---|---|---|
| `core/` | 全局服务单例（autoload 脚本，**不写 class_name**） | 提供「全局唯一、处处可访问」的跨模块服务 | 事件总线 / 存档 / 音频 / UI 管理 / 日志 等需要全局一份的 | 挂节点的组件→`components`；纯函数→`utils` |
| `components/` | 继承 `Node` 的可复用组件 | 给任意游戏对象「拼装」一种能力/行为，随节点实例存在 | 功能是「某对象的一种能力」、有自己状态/信号、要进场景树（血量/耐心/移动/拾取/计时） | 全局单例→`core`；无状态计算→`utils`；状态机→`fsm` |
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
  # 在源仓库 gd-common
  git add -A && git commit -m "feat: GxTimer"
  git push origin main
  # 在每个消费项目
  git -C addons/gd-common pull origin main
  ```
- **验证**：`godot --headless --path <项目> --quit`，确认 0 SCRIPT/Parse ERROR。

