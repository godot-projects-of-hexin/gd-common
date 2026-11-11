# gd-common

Godot **4.4+** 的跨项目通用层，以 addon 形式发布，通过 git submodule 引入。**不含任何第三方代码。**

> **规则看 [`agent.md`](agent.md)** —— 分层约束、命名规范、通信方式选择、提交流程都在那一份里。
> 本文只回答两件事：这里有什么模块，每个模块怎么调。

---

## 安装

```bash
git submodule add https://github.com/godot-projects-of-hexin/gd-common.git addons/gd-common
git submodule update --init --recursive
```

在 Godot 里启用：**项目设置 → 插件 → gd-common**。插件会注册 4 个 autoload：

| autoload | 脚本 |
|---|---|
| `EventBus` | `core/event_bus.gd` |
| `SaveSystem` | `core/save_system.gd` |
| `AudioManager` | `audio/audio_manager.gd` |
| `UIManager` | `core/ui_manager.gd` |

插件只会移除**它自己添加过的** autoload，所以项目已有同名 autoload 时不会被覆盖或误删。

架构层（`GxArchitecture` 等）**不是 autoload** —— 原因见 `agent.md` 第 2.7 节。

---

## 模块总览

| 目录 | 内容 | 基类 |
|---|---|---|
| `architecture/` | Architecture / Model / System / Utility / Command / Query / Event / BindableProperty / Controller | `RefCounted`（Controller 节点版是 `Node`） |
| `core/` | EventBus、SaveSystem、UIManager | `Node`（autoload） |
| `audio/` | AudioManager | `Node`（autoload） |
| `components/` | GxGaugeComponent、GxFloatingNumber | `Node` / `CanvasLayer` |
| `fsm/` | GxStateMachine、GxState | `RefCounted` |
| `utils/` | GxCooldown、GxMath、GxObjectPool | `RefCounted` / `Object` |
| `tests/` | SceneTree 测试套件 + `run_all.sh` | — |

---

## 架构层

### 搭起来

项目里写一个 `GameArchitecture`，用静态访问器暴露唯一实例：

```gdscript
class_name GameArchitecture
extends GxArchitecture

static var _instance: GameArchitecture

static func get_instance() -> GameArchitecture:
	if _instance == null:
		_instance = GameArchitecture.new()
		_instance.initialize()
		GxArchitecture.set_default(_instance)
	return _instance

func _on_register() -> void:
	register_utility(SaveUtility.new())
	register_model(PlayerModel.new())
	register_system(ScoreSystem.new())
```

注册顺序无所谓，`initialize()` 保证按 **Utility → Model → System** 初始化。

### GxArchitecture

| 方法 | 说明 |
|---|---|
| `initialize()` | 跑 `_on_register()` 再自下而上初始化；重复调用会告警并忽略 |
| `is_initialized()` | 是否已初始化 |
| `register_utility / register_model / register_system(instance)` | 注册；初始化后注册的成员会被立即初始化 |
| `get_utility / get_model / get_system(script)` | 按脚本取实例，找不到时 `push_error`；需要自己 `as` 成具体类型 |
| `send_command(command)` | 执行命令，无返回值 |
| `send_query(query) -> Variant` | 执行查询并返回结果 |
| `send_event(event)` | 按事件类广播 |
| `register_event / unregister_event(script, handler)` | 订阅、退订 |
| `has_event_handlers(script)` | 该事件类当前是否有 handler |
| `deinitialize()` | 自上而下销毁并清空全部注册与订阅 |
| `GxArchitecture.set_default / get_default / clear_default()` | 表现层默认解析的架构（静态方法） |

GDScript 没有泛型，所以用脚本对象做键，取回后自己转型：

```gdscript
var player := architecture.get_model(PlayerModel) as PlayerModel
```

查询会沿继承链回退，所以注册子类、按父类取也能命中。

### 各层基类

每层只暴露该层允许的方法，完整权限表见 `agent.md` 第 3.2 节。

```gdscript
# Model：状态的唯一来源
class_name PlayerModel
extends GxModel

var score := GxBindableProperty.new(0)

func add_score(amount: int) -> void:
	score.set_value(int(score.get_value()) + amount)


# System：跨场景共享的业务规则
class_name ScoreSystem
extends GxSystem

func _on_init() -> void:
	register_event(EnemyKilledEvent, _on_enemy_killed)

func _on_enemy_killed(event: EnemyKilledEvent) -> void:
	(get_model(PlayerModel) as PlayerModel).add_score(event.reward)


# Command：唯一的写入路径，必须无状态
class_name AddScoreCommand
extends GxCommand

var _amount: int

func _init(amount: int) -> void:
	_amount = amount

func _on_execute() -> void:
	var player := get_model(PlayerModel) as PlayerModel
	player.add_score(_amount)
	send_event(ScoreChangedEvent.create(int(player.score.get_value())))


# Query：只读的问题
class_name CanAffordQuery
extends GxQuery

var _price: int

func _init(price: int) -> void:
	_price = price

func _on_run() -> Variant:
	return int((get_model(PlayerModel) as PlayerModel).coins.get_value()) >= _price


# Utility：基础设施，拿不到架构
class_name SaveUtility
extends GxUtility

func write(slot: int, data: Dictionary) -> bool:
	return SaveSystem.save_to_slot(slot, data)
```

### GxEvent

事件是**已经发生的事实**，载荷写成真实字段：

```gdscript
class_name ScoreChangedEvent
extends GxEvent

var score: int

static func create(value: int) -> ScoreChangedEvent:
	var event := ScoreChangedEvent.new()
	event.score = value
	return event
```

### GxBindableProperty

| 方法 | 说明 |
|---|---|
| `GxBindableProperty.new(initial, comparer := Callable())` | `comparer(a, b) -> bool` 判定「相等」，可选 |
| `get_value() / set_value(v)` | 读写；只有真的变了才发信号 |
| `set_value_silent(v)` | 写入不发信号（读档场景） |
| `bind(handler)` | 订阅，并**立刻**用当前值回调一次 |
| `bind_without_init(handler)` | 只订阅，不立刻回调 |
| `unbind(handler) / is_bound(handler) / unbind_all()` | 退订与查询 |
| `value_changed(new_value)` | 信号。只带新值，handler 固定一个参数 |

```gdscript
var health := GxBindableProperty.new(
	100.0,
	func(a: float, b: float) -> bool: return is_equal_approx(a, b),
)
```

### 表现层

两种接法，方法完全一样。能继承就继承，不能继承就持有。

```gdscript
# 1. 普通控制器节点
class_name HudController
extends GxControllerNode

@onready var _score_label: Label = %ScoreLabel

func _on_controller_ready() -> void:          # 不要覆写 _ready
	var player := get_model(PlayerModel) as PlayerModel
	bind(player.score, _on_score_changed)
	register_event(GameOverEvent, _on_game_over)

func _on_score_changed(value: int) -> void:
	_score_label.text = str(value)


# 2. 已经继承了别的引擎类型
extends CharacterBody2D

var _ctrl: GxController

func _ready() -> void:
	_ctrl = GxController.new(self)
	_ctrl.register_event(GameOverEvent, _on_game_over)

func _on_hit() -> void:
	_ctrl.send_command(TakeDamageCommand.new(10))
```

通过这两者注册的事件与属性绑定，在节点离开场景树时**自动解绑**。节点会被移出再加回时，用 `GxController.new(self, null, false)` 关掉自动解绑并自己管 `dispose()`。

---

## core

### EventBus（autoload）

字符串键的全局广播，用于**基础设施**消息；业务状态变化走架构 Event。

```gdscript
EventBus.subscribe(&"scene_transition_started", _on_transition)
EventBus.emit_event(&"scene_transition_started", 0.4)
EventBus.unsubscribe(&"scene_transition_started", _on_transition)
```

`subscribe / unsubscribe / emit_event / has_subscribers / clear_event / clear_all`。
handler 固定接收一个 payload；失效监听者在 emit 时自动清理；重复订阅会被忽略。

### SaveSystem（autoload）

只负责**怎么存**，不关心存什么。项目层拼好 `Dictionary` 交给它。

```gdscript
SaveSystem.set_version(2)
SaveSystem.set_migrator(_migrate)

SaveSystem.save_to_slot(0, {"level": 3, "score": 120})
var data := SaveSystem.load_from_slot(0)      # 缺档返回 {}
SaveSystem.has_slot(0)
SaveSystem.delete_slot(0)
SaveSystem.list_slots()                       # Array[int]，已排序
```

存到 `user://saves/slot_N.cfg`，带 `__version` 字段。版本不一致且设置了 migrator 时会先迁移。
读取一律用 `data.get(key, 默认值)` —— 缺档和坏档都返回 `{}`。

信号：`saved(slot)`、`loaded(slot)`。

### UIManager（autoload）

自带 `CanvasLayer` 的 **Control 模态面板栈**，push 时自动隐藏下层。

```gdscript
var panel := UIManager.push_panel(preload("res://scenes/ui/confirm_dialog.tscn"))
UIManager.push_panel_node(existing_control)
UIManager.pop_panel()              # 释放栈顶并显示下层
UIManager.get_top()
UIManager.stack_size()
UIManager.clear()                  # 整栈释放，场景切换时用
```

信号：`panel_pushed(panel)`、`panel_will_pop(panel)`、`panel_popped`。

只管临时模态框。常驻 HUD、`Node2D` 覆盖层、世界空间 UI 不要走这里。
需要从面板取结果时在 `panel_will_pop` 里取 —— `pop_panel()` 之后那个引用已经 `queue_free` 了。

---

## audio

### AudioManager（autoload）

项目拥有音频**资源**，这里拥有**播放器**。传 `AudioStream` 对象，不传路径。

```gdscript
AudioManager.play_sfx(stream, -6.0, 1.0)              # 一次性音效，8 槽池
AudioManager.play_sfx_varied(stream, 0.95, 1.05)      # 随机音高，避免机械感
AudioManager.stop_all_sfx()

AudioManager.play_music(stream, 1.5)                  # 交叉淡入
AudioManager.stop_music(1.5)
AudioManager.pause_music(0.5)                         # 淡到静音并保留播放头
AudioManager.resume_music(0.5)
AudioManager.set_music_volume_db(-3.0)
AudioManager.is_music_playing()
AudioManager.is_music_paused()
AudioManager.current_music()

AudioManager.play_ambient(stream, 2.0, &"rain")       # 循环环境音，按 key 管理
AudioManager.stop_ambient(&"rain", 1.5)
AudioManager.stop_all_ambient(1.5)
AudioManager.active_ambient_keys()

AudioManager.set_buses(&"SFX", &"Music", &"Ambient")  # 未知总线回退 Master 并告警
AudioManager.stop_all(0.5)
```

信号：`music_started(stream)`、`music_stopped`、`music_paused`、`music_resumed`。

**暂停行为**是三组播放器分开的原因：

| 节点 | process mode | 效果 |
|---|---|---|
| `SfxRoot` | `PAUSABLE` | 随场景树暂停 |
| `AmbientRoot` | `PAUSABLE` | 随场景树暂停 |
| `MusicRoot` | `ALWAYS` | 暂停菜单打开时淡出动画继续走完 |

淡变 Tween 绑在具体播放器上，因此继承该播放器的 process mode。

**已知行为：**

- SFX 共用 8 个并发槽；全忙时抢占最早的那个。长音频用 `play_ambient()`，它有独立播放器。
- `play_music()` 传入正在播的同一曲目时直接返回，所以每次切场景无脑调用是安全的。
- `play_music()` 会清除 `pause_music()` 设的暂停标记。
- 循环靠 `finished` 信号手动重播，不会去改共享的 `AudioStream` 资源。要无缝循环，同时在导入设置里开 loop。
- 环境音默认按 `resource_path` 作 key；同一个 key 再次 `play_ambient()` 会重启它。
- `play_sfx(null)` 返回 `null` 并报错 —— 传入 `null` 是加载失败，不该静默吞掉。

---

## components

### GxGaugeComponent（Node）

`[0, max_value]` 区间值，可按时间自动消耗或回复。血量、体力、护盾、耐心、充能条。

```gdscript
var gauge := GxGaugeComponent.new()
gauge.max_value = 30.0
gauge.auto_rate = 1.0       # > 0 消耗，< 0 回复，== 0 不自动变化
gauge.auto_active = false
add_child(gauge)

gauge.value_changed.connect(_on_changed)   # (current, maximum)
gauge.depleted.connect(_on_depleted)
gauge.filled.connect(_on_filled)

gauge.drain(5.0)
gauge.fill(2.0)
gauge.set_value(10.0)
gauge.reset()
gauge.ratio()               # 0.0 ~ 1.0
gauge.is_depleted()
```

导出属性：`max_value`、`start_full`、`auto_rate`、`auto_active`、`rate_scale`。
运行时改 `max_value` 会自动把 `current` 夹进新范围并发信号。

`auto_rate` 正负容易记反：**正数是消耗，负数是回复。**

### GxFloatingNumber（CanvasLayer）

伤害、治疗、金币浮字。弹出 → 上漂 → 淡出 → 自动释放。

```gdscript
var numbers := GxFloatingNumber.new()
add_child(numbers)

numbers.spawn(global_position, "-5", GxFloatingNumber.Preset.DAMAGE)
numbers.spawn(global_position, "+20", GxFloatingNumber.Preset.HEAL)
numbers.spawn(pos, "+100", GxFloatingNumber.Preset.HEAL, {"duration": 1.5})
numbers.spawn_custom(pos, "MISS", {"color": Color.GRAY, "duration": 0.6})
```

预设：`DEFAULT`、`DAMAGE`、`HEAL`、`CRITICAL`、`MUTED`。
`cfg` 支持 `color`、`font_size`、`scale_start`、`float_distance`、`wobble`、`duration`。

传入的 `pos` 是数字的**视觉中心**，不是左上角。

---

## fsm

### GxStateMachine / GxState

轻量状态机，用于场景流程和角色 AI。它是 `RefCounted`，**不会自动更新**。

```gdscript
var machine := GxStateMachine.new(self)       # 参数是 context
machine.add_state(&"idle", GxState.new())
machine.add_state(&"walk", GxState.new())
machine.add_state(&"attack", GxState.new())

# (来源状态, 事件) → (目标状态, 可选守卫)
machine.add_transition(&"idle", &"move_pressed", &"walk")
machine.add_transition(&"walk", &"attack_pressed", &"attack",
	func() -> bool: return _weapon.can_attack())

machine.state_changed.connect(_on_state_changed)
machine.guard_failed.connect(_on_guard_failed)
machine.unhandled_event.connect(_on_unhandled)

machine.start(&"idle")
machine.try_transition(&"move_pressed")
machine.transition_to(&"idle")
machine.is_in_state(&"walk")
machine.current_name()
machine.current_state()
machine.attach_to(self)                       # 只记录宿主，不会 add_child
```

必须自己驱动：

```gdscript
func _process(delta: float) -> void:
	machine.update(delta)

func _physics_process(delta: float) -> void:
	machine.physics_update(delta)
```

纯事件驱动时只调 `try_transition()`，不需要 `update()`。

- `is_in_state()` 严格名字匹配，`start()` 之前恒为 `false`。
- 自转移（目标 == 当前）会 `push_warning` 并直接返回 —— 它基本都是逻辑 bug。
- 未知状态名通过 `push_error` 报告而非 `assert`，所以 release 构建行为和 debug 一致。
- 不支持层级状态机（HSM），这是故意的。

子类化 `GxState` 时覆写 `_enter` / `_exit` / `_update` / `_physics_update`，用 `machine.context` 读共享数据。

---

## utils

### GxCooldown（RefCounted）

手动推进的冷却计时器，不依赖 `_process`。

```gdscript
var _dash := GxCooldown.new(2.0)

func _process(delta: float) -> void:
	_dash.tick(delta)

func _on_dash_input() -> void:
	if not _dash.is_ready():
		return
	_perform_dash()
	_dash.start()

func _on_died() -> void:
	_dash.cancel()        # 重置但不发 finished
```

`start(duration := -1.0)`、`tick(delta)`、`is_ready()`、`is_running()`、`progress()`、`cancel()`，信号 `finished`。
`update(delta)` 保留作向后兼容，内部转发到 `tick()`。

`cancel()` 之后 `progress()` 返回 `1.0`，所以**不能**只靠 `progress() == 1.0` 判断「自然完成」，要听 `finished`。

### GxMath（静态）

```gdscript
GxMath.approach(5.0, 10.0, 2.0)          # → 7.0，朝目标移动且不过冲
GxMath.remap_clamped(0.5, 0, 1, 0, 100)  # → 50.0
GxMath.chance(0.3)                       # 30% 概率 true
GxMath.pick_random([1, 2, 3])            # 空数组返回 null
```

只是可读性封装。`lerp`、`move_toward`、`randf` 够用时直接用引擎原生函数。

### GxObjectPool（RefCounted）

子弹、粒子、浮字这类高频创建销毁的对象。

```gdscript
var _bullets := GxObjectPool.new(
	func() -> Node: return preload("res://scenes/fx/bullet.tscn").instantiate(),
	5,                                    # 预热数量
	func(obj: Node) -> void:              # 归池时重置
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED,
)

var bullet := _bullets.acquire()
_bullets.release(bullet)
_bullets.available_count()
```

`release()` 只是**回池**，不会自动移出场景树、不会隐藏、不会停处理。
闲置对象还在树里就会继续吃 CPU —— 重置逻辑必须写在 `on_release` 里。重复归还同一对象会告警并忽略。

---

## 测试

```bash
# 在消费项目（game-template）根目录
godot --headless --path . --import       # 全新 clone 必须先跑这步
./addons/gd-common/tests/run_all.sh
GODOT=/path/to/godot ./addons/gd-common/tests/run_all.sh

# 单个套件
godot --headless --path . --script res://addons/gd-common/tests/test_architecture.gd
```

全部 8 个套件已在 **Godot 4.4 / 4.5 / 4.6 / 4.7 stable** 上逐一实跑通过，
项目启动零错误。版本基线与跨版本注意事项见 `agent.md` 第 7.0 节。
测试入口必须写成 `_process()` 而不是 `_init()`，原因见 `agent.md` 第 7.2 节。

| 套件 | 覆盖 |
|---|---|
| `test_architecture` | 注册、初始化顺序、Command / Query / Event、**分层权限断言** |
| `test_bindable_property` | 立即回调、去重、静默写入、自定义 comparer |
| `test_event_bus` | 订阅、载荷、失效清理 |
| `test_save_system` | 槽位、版本迁移、损坏存档 |
| `test_state_machine` | 转移、守卫、信号 |
| `test_gauge` | 边界、自动变化、信号 |
| `test_cooldown` | 推进、取消、finished |
| `test_audio_manager` | 播放器布线、process mode、暂停恢复、总线回退 |

`test_architecture` 里那组 `has_method()` 断言是**分层规则的守卫**：如果有人给 `GxModel` 加了 `get_system()`，它会立刻失败。

---

## 许可

MIT。全部代码自有，无第三方依赖。
