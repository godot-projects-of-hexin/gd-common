# gd-common 通用层 / 跨项目复用指南

> 本文是整套复用系统的**权威总览**（随 gd-common 仓库走）。各模块英文 API 速查见同目录 `README.md`。
> 适用引擎：Godot 4.x（已在 4.7 验证）。

---

## 0. 你会在什么时候用到这些模块

| 你遇到的问题 | 用这个模块 | 一句话解决 |
|---|---|---|
| 得分改变了，UI / 音效 / 成就都要知道，但我不想让它们互相引用 | EventBus | `emit_event` 广播，各自 `subscribe` |
| 需要存读档，而且以后可能改存档格式 | SaveSystem | `save_to_slot` / `load_from_slot`，自带版本迁移 |
| 要播音效、BGM、环境音，暂停菜单里 SFX 要停但 BGM 淡出不能卡 | SoundManager | 三类音频各走各的 process_mode |
| 弹窗套弹窗（设置→键位→确认），关一个自动回到上一层 | UIManager | `push_panel` / `pop_panel` |
| NPC 状态乱跳，if-else 已经看不懂了 | GxStateMachine | 状态 + 转移规则表驱动 |
| 血量/体力/耐心/充能条——到处手写 current/max/signal | GxGaugeComponent | 一个组件搞定 `[0, max]` + 自动耗尽 |
| 技能冷却、冲刺间隔——到处写 `timer -= delta` | GxCooldown | `tick(delta)` 推进，`is_ready()` 查询 |
| 镜头平滑跟随、血条%映射、暴击概率计算 | GxMath | 4 个静态函数，不用 new |
| 子弹/粒子高频创建销毁，frame 不稳定 | GxObjectPool | 预热 + acquire/release 复用 |
| 伤害数字从角色头上飘起来淡出 | GxFloatingNumber | `spawn(位置, 文本, 预设)` 一行搞定 |

---

## 1. 总览

```
gd-common       共享通用层（Godot 插件，纯 GDScript）
game-template   新项目模板（已接好 gd-common + GameData/GameManager 桩）
你的新游戏       从 game-template 克隆，改 GameData / GameManager 即可
```

关系：

```
gd-common ──submodule──> game-template ──克隆──> 你的新游戏
```

- **gd-common**：与游戏类型无关的基础设施。只放通用件，**绝不放具体玩法**。
- **game-template**：开箱即完整的项目骨架，新游戏从它克隆。

---

## 2. 模块详解

约定：`class_name` 一律 `Gx` 前缀；autoload 名简洁（`EventBus` / `SaveSystem` / `SoundManager` / `UIManager`）。启用插件后 4 个 autoload 自动注册。

---

### 2.1 EventBus —— 全局事件总线

**是什么**

全局发布/订阅系统。一个模块发射事件，任意数量的其他模块接收——发射者不需要知道谁在听，监听者之间也互不感知。订阅回调固定接收一个参数（payload），失效的监听者在 emit 时自动被清理。

**什么时候用**

- ✅ **多个无关系统需要响应同一件事**。得分增加 → UI 更新显示、音效播放叮声、成就系统检查是否解锁——这三个系统不该互相持有引用。
- ✅ **跨场景通信**。战斗场景里的角色死亡需要通知 HUD（在另一个场景树分支）更新击杀数。
- ✅ **数据桥接**。某个模块发射的值需要被另一个模块消费，但两者不应该耦合。典型的桥接：`tokens_changed.connect(func(v): EventBus.emit_event(&"tokens_changed", v))`
- ❌ **场景树内部的父子/兄弟节点通信**。Button 的 `pressed` 信号连到同场景的 `_on_button_pressed` 就是正确的做法——不用 EventBus。
- ❌ **高频逐帧数据**。每帧发射上千个事件会把系统拖慢。物理碰撞、鼠标坐标这类数据用信号或直接引用。
- 🔗 常与 **SaveSystem** 配合：存档加载完成后发射 `&"game_loaded"` 通知各模块刷新。

**3 行上手**

```gdscript
EventBus.subscribe(&"score_changed", func(v): print("得分: ", v))
EventBus.emit_event(&"score_changed", 100)   # → 得分: 100
EventBus.emit_event(&"score_changed", 250)   # → 得分: 250
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `subscribe(event, callable)` | 订阅事件。重复订阅自动忽略 |
| `unsubscribe(event, callable)` | 取消订阅。事件无订阅者时自动清理 |
| `emit_event(event, payload)` | 广播事件。payload 可选（一个 Variant）。失效监听者自动清理 |
| `has_subscribers(event)` | 该事件是否有监听者 |
| `clear_event(event)` | 清除该事件的所有订阅 |
| `clear_all()` | 清除全部订阅（场景切换用） |

```gdscript
# —— 生产者（任意模块） ——
EventBus.emit_event(&"score_changed", 100)

# —— 消费者 ——
func _ready() -> void:
    EventBus.subscribe(&"score_changed", _on_score)

func _on_score(new_score: int) -> void:
    $ScoreLabel.text = str(new_score)

# 离开场景时取消（非必须——emit 时自动清理 freed listener）
# EventBus.unsubscribe(&"score_changed", _on_score)

# 调试/查询
if EventBus.has_subscribers(&"score_changed"):
    print("有人在听 score_changed")

# 场景切换前彻底清理某个事件
EventBus.clear_event(&"score_changed")

# 或者全部清掉
EventBus.clear_all()
```

**常见误区**

> ⚠️ 在 `subscribe()` 的 lambda 里捕获了场景节点引用，场景切换后节点已 free 但 lambda 还在——emit 时调用了一个无效的 Callable。虽然 EventBus 会检测并清理 freed listener，但"静默失效"让你不知道订阅丢了。**推荐始终用具名函数而非 lambda**：`EventBus.subscribe(&"e", _on_e)`。

---

### 2.2 SaveSystem —— 存档系统

**是什么**

通用的存档/读档机制。它只管"怎么把数据写到磁盘、怎么读回来"——不关心你存的是金币还是关卡号。存读走 `user://saves/slot_N.cfg`，自带 `__version` 字段支持存档格式升级。

**什么时候用**

- ✅ **需要多槽位手动存档**。玩家可以选"存档 1 / 存档 2 / 存档 3"，各自独立。
- ✅ **存档格式会变**。V1 存的是 `gold`，V2 改成 `coins`——用 `set_migrator` 写一个迁移回调，老存档自动转换。
- ✅ **需要知道存档是否成功**。`saved(0)` 信号可以驱动"存档中..."→"存档成功"的 UI 指示器。
- ❌ **仅运行时配置**（音量、键位）。直接 `ConfigFile.new()` 存取 `user://settings.cfg` 更轻量。
- ❌ **纯自动存档 + 永不改格式**。`ResourceSaver.save("user://autosave.res", data)` 足够了。
- 🔗 常与 **EventBus** 配合：读档完成后发射 `&"game_loaded"` 通知 UI、音频等模块刷新。

**3 行上手**

```gdscript
SaveSystem.save_to_slot(0, {"level": 3, "coins": 120})
var data := SaveSystem.load_from_slot(0)   # {} 如果没档
print(data.get("coins", 0))                # → 120
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `set_version(v: int)` | 设置当前存档格式版本号 |
| `set_migrator(callable)` | 设置版本迁移回调：`func(data, from_version, to_version) -> Dictionary` |
| `save_to_slot(slot, data: Dictionary)` | 存到 `user://saves/slot_N.cfg`。返回 `bool` |
| `load_from_slot(slot)` | 读档。无档则返回 `{}`。版本不匹配自动调 migrator |
| `has_slot(slot)` | 该槽位是否有存档 |
| `delete_slot(slot)` | 删除指定槽位 |
| `list_slots()` | 返回所有有效槽位号（排序后的 `Array[int]`） |
| `saved(slot)` | 信号：存档成功时发射 |
| `loaded(slot)` | 信号：读档成功时发射 |

```gdscript
# —— 基础存档 ——
SaveSystem.save_to_slot(0, {"level": 3, "coins": 120})
var data := SaveSystem.load_from_slot(0)           # {} 如果没档
print(data.get("level", 1))                         # → 3

# —— 查询 ——
if SaveSystem.has_slot(0):
    print("有存档")

for slot in SaveSystem.list_slots():
    print("槽位 %d 存在" % slot)

# —— 删除 ——
SaveSystem.delete_slot(0)

# —— 可观测（auto-save 指示器） ——
SaveSystem.saved.connect(func(slot): print("存档成功 slot=%d" % slot))
SaveSystem.loaded.connect(func(slot): print("读档成功 slot=%d" % slot))

# —— 版本迁移完整示例 ——
# V1: {"gold": 100}
# V2: {"coins": 1000}  # 金币改名，数值 ×10
SaveSystem.set_version(2)
SaveSystem.set_migrator(func(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
    if from_v == 1 and to_v == 2:
        var gold: int = data.get("gold", 0)
        data.erase("gold")
        data["coins"] = gold * 10
    return data
)
# 现在 load V1 存档会自动转换
```

**常见误区**

> ⚠️ `load_from_slot(0)` 返回 `{}` 时，直接用 `data["coins"]` 会崩。**永远用 `data.get("coins", 默认值)` 读取**——你无法保证存档文件没有被玩家手动编辑损坏。

---

### 2.3 SoundManager —— 音频管理

**是什么**

统一的音效/音乐/环境音播放器。8 通道 SFX 池，BGM 独立播放支持淡入淡出，环境音循环播放——所有音频资源留在你项目里，把 `AudioStream` 传进来即可。process-mode 做了拆分：SFX 随场景暂停，BGM 永远 tick 保证淡出动画不卡。

**什么时候用**

- ✅ **三种音频各有不同的暂停行为**。暂停菜单打开：环境音和 SFX 立刻噤声，BGM 用半秒淡到静音——而不是卡在半路。
- ✅ **BGM 需要平滑切换**。从大厅 BGM 切到战斗 BGM，1.5 秒交叉淡入淡出。
- ✅ **场景切换要切断所有残留 SFX**。`stop_all_sfx()` 防止上一关的爆炸声传到下一关。
- ❌ **只有一个按钮点击音效**。直接在 Button 的 `pressed` 信号里 `$AudioStreamPlayer.play()` 即可。
- ❌ **没有暂停菜单、没有 BGM**。用 Godot 内置的 `AudioStreamPlayer` 节点就够了。
- 🔗 配合项目层的 **AudioLib 注册表模式**（见 §3.3）：集中管理资源路径，提供 `sfx("click")` / `bgm("battle")` 等语义化调用。

**3 行上手**

```gdscript
SoundManager.play_sound(load("res://sfx/hit.wav"))       # 播一个 SFX
SoundManager.play_music(load("res://bgm/battle.wav"), 1.5) # 淡入 BGM
SoundManager.stop_music(1.5)                                # 淡出
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `play_sound(stream)` | 单次 SFX。8 通道池，全忙时抢占最旧 |
| `play_ui_sound(stream)` | 同 `play_sound` 的别名 |
| `stop_all_sfx()` | 切断所有 SFX（场景切换用） |
| `play_music(stream, crossfade)` | BGM 淡入。crossfade=0 即硬切 |
| `stop_music(fade)` | 淡出 BGM |
| `pause_music(fade)` | 淡到静音，保留播放位置 |
| `resume_music(fade)` | 从暂停恢复 |
| `is_music_paused()` | 查询暂停状态 |
| `play_ambient_sound(stream, fade)` | 循环环境音。相同文件重复播放会先停旧的 |
| `stop_ambient_sound(stream, fade)` | 停止指定环境音 |
| `stop_all_ambient_sounds(fade)` | 场景切换时清理所有环境音 |
| `set_bus_volume_db(bus_name, db)` | 设置 Audio Bus 音量（Master/SFX/Music 等） |
| `music_paused` / `music_resumed` | 信号 |

```gdscript
# —— 载入音频资源（文件放你的项目里） ——
var click := load("res://sfx/ui_click.wav")
var bgm   := load("res://bgm/service.wav")
var amb   := load("res://sfx/kitchen.wav")

# —— SFX ——
SoundManager.play_sound(click)          # 单次播放
SoundManager.play_ui_sound(click)       # 同上（语义化别名）
SoundManager.stop_all_sfx()             # 切场景时切断所有 SFX

# —— BGM ——
SoundManager.play_music(bgm, 1.5)       # 1.5 秒淡入
SoundManager.stop_music(1.5)            # 淡出

# —— 暂停/恢复（不丢播放位置） ——
SoundManager.pause_music(0.5)           # 半秒淡到静音
SoundManager.resume_music(0.5)          # 半秒淡回
if SoundManager.is_music_paused():
    print("BGM 已暂停")

SoundManager.music_paused.connect(func(): print("BGM 暂停了"))
SoundManager.music_resumed.connect(func(): print("BGM 恢复了"))

# —— 环境音 ——
SoundManager.play_ambient_sound(amb, 2.0)      # 2 秒淡入循环
SoundManager.stop_ambient_sound(amb, 1.5)      # 停止这一个
SoundManager.stop_all_ambient_sounds(1.5)       # 场景切换——全部清

# —— 音量调节 ——
SoundManager.set_bus_volume_db("Master", -6.0)  # 全局降 6dB
SoundManager.set_bus_volume_db("SFX", 0.0)      # SFX 恢复 0dB
```

**常见误区**

> ⚠️ `play_sound(null)` 不会报错——如果你的 `load()` 返回了 null（文件路径拼错），音效会静默不播放。建议在开发期把路径放到 AudioLib 的 const 字典里（见 §3.3），让 Godot 编辑器在保存时做路径校验。

---

### 2.4 UIManager —— 模态面板栈

**是什么**

Control 面板的栈管理器。 `push` 推入一层面板时自动隐藏下层，`pop` 弹出时自动释放并显示下一层。适用于设置窗口、确认对话框等瞬态弹窗的嵌套管理。

**什么时候用**

- ✅ **弹窗可以嵌套**。设置面板里点"改键位"再弹一层键位面板，关闭键位自动回到设置——你不需要记住之前哪个面板是 visible。
- ✅ **场景切换需要关闭所有打开的弹窗**。`clear()` 一行扫光所有面板，防止旧场景的弹窗残留在新场景里。
- ✅ **想知道栈状态**。`stack_size()` 告诉你有几层面板，`get_top()` 返回最上层——方便实现"按 Esc 逐层关闭"。
- ❌ **常驻 HUD（血条、小地图、任务追踪）**。直接用 CanvasLayer 挂到场景根——它们不是"弹窗"。
- ❌ **Node2D 世界内 UI**（角色头顶气泡、场景中的指示牌）。这些是 2D 节点，不属于 Control 类。
- 🔗 常与 **EventBus** 配合：`&"ui_panel_opened"` / `&"ui_panel_closed"` 让游戏逻辑知道当前是否被 UI 阻挡。

**3 行上手**

```gdscript
UIManager.push_panel(preload("res://ui/settings.tscn"))  # 打开设置
UIManager.pop_panel()   # 关闭 → 回到上一层
UIManager.clear()       # 全关（场景切换用）
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `push_panel(packed: PackedScene)` | 实例化 scene 并推入栈顶。root 必须是 Control |
| `push_panel_node(panel: Control)` | 推入一个已实例化的 Control |
| `pop_panel()` | 弹出并 free 栈顶面板，显示下一层。空栈 no-op |
| `get_top()` | 返回栈顶 Control（或 null） |
| `clear()` | free 全部面板并清空栈 |
| `stack_size()` | 当前栈深度 |
| `panel_pushed(panel)` / `panel_will_pop(panel)` / `panel_popped` | 信号 |

```gdscript
# —— 弹窗 ——
var settings := UIManager.push_panel(preload("res://ui/settings.tscn"))
# 用户在设置里点「改键位」：
UIManager.push_panel(preload("res://ui/keybind.tscn"))

# —— 逐层关闭 ——
UIManager.pop_panel()           # 关闭键位 → 回到设置
print(UIManager.stack_size())   # → 1
print(UIManager.get_top())      # → settings 的 Control 引用

UIManager.pop_panel()           # 关闭设置 → 回到游戏
print(UIManager.get_top())      # → null

# —— 场景切换时全清 ——
UIManager.clear()

# —— 推入已实例化的面板 ——
var already_made := preload("res://ui/popup.tscn").instantiate()
already_made.some_data = 42
UIManager.push_panel_node(already_made)

# —— 监听 ——
UIManager.panel_pushed.connect(func(p): print("打开: ", p.name))
UIManager.panel_will_pop.connect(func(p): print("即将关闭: ", p.name))
UIManager.panel_popped.connect(func(): print("栈深度 = ", UIManager.stack_size()))
```

**常见误区**

> ⚠️ `UIManager.push_panel()` 返回的 panel 引用在 `pop_panel()` 后已经 `queue_free` 了——继续持有这个引用去读它的属性会崩。如果需要从中拿数据（如用户选了哪个选项），在 `panel_will_pop` 信号里提取，或者让面板自己在关闭前 emit 一个结果信号。

---

### 2.5 GxStateMachine / GxState —— 状态机

**是什么**

最小有限状态机框架。把对象的行为拆成独立 State 类，每个 State 有 `_enter` / `_update` / `_exit` 钩子；转移规则集中管理，支持事件驱动的表格式定义 + 守卫条件。`extends RefCounted`，不依赖 Node——可以嵌在任何地方。

**什么时候用**

- ✅ **NPC / 敌人 AI**。idle → patrol → chase → attack → die，每个状态的行为逻辑独立，新增状态不碰已有代码。
- ✅ **场景流程控制**。title → game → result 的 phase 切换，`state_changed` 信号触发 `change_scene_to_file`。
- ✅ **需要条件转移**。"只有在武器 CD 好了才能进入 attack 状态"——用 `add_transition` 的 guard 参数，而不是在每个 `if` 里写。
- ❌ **只有 2-3 种状态且逻辑简单**。比如一个门的"开/关"——`match door_state` 就够了，引入状态机是过度设计。
- ❌ **纯视觉动画切换**（idle / walk / jump 只是换 sprite）。用 `AnimationTree` 更合适——它不是行为切换，是动画混合。
- 🔗 与 **Godot State Charts 插件**对比：GxStateMachine 更轻量（纯 GDScript 代码，无可视化编辑器），适合逻辑简单于 10 个状态的场景。

**3 行上手**

```gdscript
const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")
var sm := GxStateMachine.new(self)
sm.add_state(&"prep", GxState.new()).add_state(&"game", GxState.new())
sm.state_changed.connect(func(from, to): print(from, " → ", to))
sm.start(&"prep"); sm.transition_to(&"game")
```

#### 基础用法（场景流程控制）

| API | 说明 |
|---|---|
| `_init(ctx)` | 构造。ctx 任意数据，states 通过 `machine.context` 读取 |
| `add_state(name, state)` | 注册状态。返回 self 支持链式调用 |
| `start(initial)` | 启动并进入初始状态 |
| `transition_to(target)` | 切换状态。自转移记为 warning + no-op |
| `current_name()` | 当前状态名（StringName） |
| `current_state()` | 当前 GxState 对象 |
| `state_changed(from, to)` | 信号：状态切换完成 |
| `update(delta)` | 驱动当前 State 的 `_update(delta)` |

```gdscript
var sm := GxStateMachine.new(self)          # self = 上下文
sm.add_state(&"prep",    GxState.new()) \
  .add_state(&"service", GxState.new()) \
  .add_state(&"result",  GxState.new())
sm.state_changed.connect(func(from, to): print(from, " → ", to))
sm.start(&"prep")

# 切换
sm.transition_to(&"service")
print(sm.current_name())   # → &"service"
print(sm.is_in_state(&"service"))  # → true
```

#### 子类化 GxState（重写钩子，用于 AI 等复杂行为）

```gdscript
# —— patrol_state.gd ——
class_name PatrolState
extends GxState

func _enter() -> void:
    machine.context.animation_player.play("walk")

func _update(delta: float) -> void:
    var body: CharacterBody2D = machine.context
    body.velocity = body.patrol_direction * body.speed
    body.move_and_slide()

func _exit() -> void:
    machine.context.animation_player.stop()

# —— 使用 ——
var sm := GxStateMachine.new($Enemy)
sm.add_state(&"patrol", PatrolState.new())
sm.start(&"patrol")
# 在 _process 中驱动：
func _process(delta): sm.update(delta)
```

#### 事件驱动 + 守卫（PR-0001）

| API | 说明 |
|---|---|
| `add_transition(from, event, target, guard?)` | 注册一条转移规则。guard 返回 false 则阻止 |
| `try_transition(event)` | 在当前状态上尝试匹配 event → guard → transition |
| `is_in_state(name)` | 精确匹配。start() 前永远返回 false |
| `attach_to(host)` / `detach()` | 记录/清除关联的 Node（不 add_child） |
| `guard_failed(from, event)` | 信号：守卫返回 false |
| `unhandled_event(event)` | 信号：事件无匹配转移 |
| `physics_update(delta)` | 驱动当前 State 的 `_physics_update(delta)` |

```gdscript
var sm := GxStateMachine.new()
sm.attach_to(self)
sm.add_state(&"idle",   IdleState.new()) \
  .add_state(&"walk",   WalkState.new()) \
  .add_state(&"attack", AttackState.new())

# 表驱动转移
sm.add_transition(&"idle",   &"move",  &"walk")
sm.add_transition(&"walk",   &"move",  &"idle")
sm.add_transition(&"walk",   &"attack_pressed", &"attack",
    func() -> bool: return $Weapon.can_attack())   # 守卫
sm.add_transition(&"attack", &"attack_done",  &"idle")

sm.start(&"idle")

# 在 _process 中驱动：
func _process(delta: float) -> void:
    sm.update(delta)

func _physics_process(delta: float) -> void:
    sm.physics_update(delta)

# 触发事件（替代直接调 transition_to）
func _on_move_pressed() -> void:   sm.try_transition(&"move")
func _on_attack_pressed() -> void: sm.try_transition(&"attack_pressed")

# 查询 + 信号
print(sm.is_in_state(&"walk"))
sm.guard_failed.connect(func(from, ev): print("守卫拒绝 ", from, " → ", ev))
sm.unhandled_event.connect(func(ev): print("无匹配转移: ", ev))

# detach
sm.detach()   # attached_host 变 null
```

**常见误区**

> ⚠️ 忘记在 `_process` 中调 `sm.update(delta)`。状态机是 `RefCounted`，不会自己 tick——`_update` 钩子只有在你主动调用 `sm.update(delta)` 时才会被执行。如果你的状态行为完全由外部信号驱动（`try_transition` → state 切换），不调 `update` 也行。

---

### 2.6 GxGaugeComponent —— 有界数值条

**是什么**

一个 Node 组件，维护一个 `[0, max_value]` 之间的浮点数。支持随时间自动消耗/回复、手动增减、直接设置。发射 `value_changed` / `depleted` / `filled` 三个信号——你把它挂到角色节点上，把 ProgressBar 对接到信号上即可。

**什么时候用**

- ✅ **血量 / 魔法 / 体力 / 耐力条**。"有上限、会变化、归零触发"的数值都适用。
- ✅ **随时间自动消耗的资源**。机器人耐心（每秒减 1）、水下呼吸条（每秒减 2）、护盾充能（每秒回 3）。
- ✅ **多个同类数值**。一个角色身上同时有 HP 和 MP 两条——各建一个 GxGaugeComponent，各自对接各自的 ProgressBar。
- ❌ **离散计数**（剩余弹药数、背包空格）。这不是连续数值，直接用 `int` + Label。
- ❌ **非线性进度**（Lv1→Lv2 需 100 XP，Lv2→Lv3 需 300 XP）。经验条曲线不是均匀 `[0, max]` 映射，需要自定义逻辑。
- 🔗 对接 **ProgressBar** 的标准模式见 §3.4。

**3 行上手**

```gdscript
var hp := GxGaugeComponent.new()
hp.max_value = 100.0; add_child(hp)
hp.drain(25); hp.fill(10)
hp.value_changed.connect(func(cur, mx): $ProgressBar.value = cur)
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `max_value` | 上限。运行时修改自动 clamp `current` 并 emit `value_changed` |
| `current` | 当前值（建议用 `set_value` 写入） |
| `start_full` | 初始化时是否填满（默认 true） |
| `auto_rate` | 每秒变化量。正=耗向 0，负=回向 max，0=手动 |
| `auto_active` | 是否启用自动变化 |
| `rate_scale` | `auto_rate` 的倍率（不改 auto_rate 原值） |
| `drain(amount)` | 减少 |
| `fill(amount)` | 增加 |
| `set_value(v)` | 直接设置。同值不重复 emit |
| `reset()` | 重置到初始值 |
| `ratio()` | 返回 `current / max_value`（0~1） |
| `is_depleted()` | `current <= 0` |
| `value_changed(current, max)` / `depleted` / `filled` | 信号 |

```gdscript
var patience := GxGaugeComponent.new()
patience.max_value = 30.0
patience.start_full = true
patience.auto_rate = 1.0       # 每秒减 1（耐心倒计时）
patience.auto_active = false   # 客人到达时才启动
patience.rate_scale = 1.0      # 急单客人设为 1.5
add_child(patience)

# —— 对接 ProgressBar ——
patience.value_changed.connect(func(cur, mx):
    $ProgressBar.value = cur
    $ProgressBar.max_value = mx
)

# —— 归零触发 ——
patience.depleted.connect(func():
    print("耐心耗尽，客人走了")
)

# —— 填满触发 ——
patience.filled.connect(func():
    print("充能完毕！")
)

# —— 手动操作 ——
patience.reset()               # current = max_value
patience.drain(5)              # -5
patience.fill(2)               # +2
patience.set_value(15)         # 直接设
patience.auto_active = true    # 开始自动消耗

# —— 查询 ——
print(patience.ratio())         # → 0.67 (20/30)
print(patience.is_depleted())   # → false
print(patience.current)         # → 20.0

# —— 动态加速（不污染 auto_rate） ——
patience.rate_scale = 2.0      # 消耗速度翻倍
```

**常见误区**

> ⚠️ `auto_rate` 为正时值向 0 消耗，为负时值向 max 回复。不要把 `auto_rate = 3.0` 理解成"每秒回 3"——那是 `auto_rate = -3.0`。记忆技巧：rate 的正负号 = `current` 的变化方向。

---

### 2.7 GxCooldown —— 冷却计时器

**是什么**

轻量冷却/定时器，`extends RefCounted`，不依赖 Node 生命周期。你手动调用 `tick(delta)` 推进它。归零时发射 `finished` 信号。`cancel()` 可以打断冷却而不触发信号。`progress()` 返回 0~1 进度，方便绑定到 UI 材质。

**什么时候用**

- ✅ **攻击间隔、技能冷却、冲刺冷却**。按下技能 → `start(3.0)` → 每帧 `tick(delta)` → `is_ready()` 返回 true 时才能再用。
- ✅ **冷却图标 UI**。`progress()` 的值（0→1）传给 shader 或 TextureProgressBar，画扇形/环形冷却动画。
- ✅ **可打断的等待**。玩家在蓄力中死亡 → `cancel()` 重置不触发 `finished`，复活后状态干净。
- ❌ **全局定时器**（"每隔 5 秒刷一只怪"）。用 Godot 的 `Timer` 节点，它有 `autostart` / `one_shot` / `timeout`，不需要你手动 tick。
- ❌ **动画驱动的时间**（"攻击动画第 0.3 秒判定命中"）。用 `AnimationPlayer` 的 keyframe 或 `signal` track。
- 🔗 对接 UI 的标准模式见 §3.5。

**3 行上手**

```gdscript
var dash_cd := GxCooldown.new(2.0)
func _process(delta): dash_cd.tick(delta)
func _on_dash(): if dash_cd.is_ready(): _dash(); dash_cd.start()
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `_init(duration)` | 构造。默认 1 秒 |
| `start(duration?)` | 开始计时。可选覆盖 duration |
| `tick(delta)` | 推进计时。归零时 emit `finished` |
| `is_ready()` | `time_left <= 0`（可以用） |
| `is_running()` | `time_left > 0`（正在冷却） |
| `progress()` | 返回 0~1（0=刚开始，1=已完成） |
| `cancel()` | 归零但不发 `finished` 信号（打断） |
| `update(delta)` | ⚠️ 兼容旧代码，同 `tick()` |
| `finished` | 信号：计时结束 |
| `duration` / `time_left` | 可读写属性 |

```gdscript
var dash_cd := GxCooldown.new(2.0)
var atk_cd  := GxCooldown.new(0.5)

func _process(delta: float) -> void:
    dash_cd.tick(delta)
    atk_cd.tick(delta)

func _on_dash_input() -> void:
    if not dash_cd.is_ready():
        return
    _perform_dash()
    dash_cd.start()

func _on_attack_input() -> void:
    if atk_cd.is_running():
        return
    _attack()
    atk_cd.start()

# —— UI 绑定（冷却图标进度条） ——
$CooldownIcon.material.set_shader_parameter("cooldown",
    dash_cd.progress())         # 0.0 → 1.0

# —— 信号连接 ——
atk_cd.finished.connect(func():
    print("攻击冷却完毕")
    $AttackIcon.modulate = Color.WHITE
)

# —— 打断（不触发 finished） ——
func _on_player_died() -> void:
    dash_cd.cancel()             # 静默重置，不触发 finished
    atk_cd.cancel()

# —— 查询 ——
print(dash_cd.is_running())      # → true（冷却中）
print(dash_cd.progress())        # → 0.35
print(dash_cd.time_left)         # → 1.3
```

**常见误区**

> ⚠️ `progress()` 在 `cancel()` 后返回 1.0（因为 `time_left == 0`）——这意味着冷却图标会显示"已完成"，但实际上是"被中断"。如果你需要区分"自然完成"和"被中断"，应该通过 `finished` 信号来标记，而不是依赖 `progress()` 的返回值。

---

### 2.8 GxMath —— 数学工具

**是什么**

4 个高频数学运算的静态方法集合。纯函数，不需要实例化——`GxMath.approach(...)` 直接调用。涵盖平滑追踪、数值映射、概率判定、随机抽取四种游戏开发中最常见的数学需求。

**什么时候用**

- ✅ **镜头平滑跟随**（`approach`）。`camera.x = GxMath.approach(camera.x, target.x, speed * delta)`——比手写 `lerp` 更直观，且不会越界。
- ✅ **血条百分比显示**（`remap_clamped`）。`var pct = GxMath.remap_clamped(hp, 0, max_hp, 0, 1)`。
- ✅ **暴击/掉落率判定**（`chance`）。`if GxMath.chance(0.15): drop_rare()`——比 `randf() < 0.15` 更可读。
- ✅ **随机目标选取**（`pick_random`）。`var target = GxMath.pick_random(alive_enemies)`。
- ❌ 如果 Godot 自带的 `lerp` / `move_toward` / `randf` 已经完全满足需求且你不介意代码风格——GxMath 只是语法糖，不是必需品。
- 🔗 `approach` 和 `GxGaugeComponent` 没有直接关系——前者是通用数学函数，后者是完整的数值条组件。

**3 行上手**

```gdscript
var cam_x := GxMath.approach(cam_x, player.x, 200.0 * delta)
var pct   := GxMath.remap_clamped(hp, 0.0, max_hp, 0.0, 1.0)
if GxMath.chance(0.3): drop_rare()
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `approach(current, target, delta)` | 向 target 逼近 delta 距离，不越界 |
| `remap_clamped(v, in_min, in_max, out_min, out_max)` | 线性重映射 + clamp |
| `chance(probability)` | 传入 0~1，返回 `true` 的概率 |
| `pick_random(arr: Array)` | 随机取一个元素。空数组返回 `null` |

```gdscript
# approach: 平滑追踪
var cam_x := 0.0
func _process(delta: float) -> void:
    cam_x = GxMath.approach(cam_x, player.position.x, 200.0 * delta)

# remap_clamped: 映射区间
var health_pct := GxMath.remap_clamped(hp, 0.0, max_hp, 0.0, 1.0)
var angle := GxMath.remap_clamped(mouse_x, 0.0, screen_w, -45.0, 45.0)

# chance: 概率判定
if GxMath.chance(0.3):
    drop_rare_item()           # 30% 概率

# pick_random: 随机抽取
var enemy := GxMath.pick_random(alive_enemies)   # 随机一个目标
var quote := GxMath.pick_random(["你好", "再见", "保重"])
print(quote)   # → "再见"（随机）
```

---

### 2.9 GxObjectPool —— 对象池

**是什么**

预创建一批实例放在池里，`acquire()` 取出使用，用完 `release()` 归还——避免频繁 `instantiate` + `queue_free` 造成的 GC 压力。支持预热、重置回调、重复归还不崩溃。

**什么时候用**

- ✅ **子弹/粒子/浮字**——每帧可能创建数十个又瞬间销毁的对象。
- ✅ **列表项的复用**——长列表滚动时，用池管理 item 节点的复用。
- ✅ **性能敏感的弹幕/无双类游戏**——GC 抖动会在帧时间线上凿洞。
- ❌ **单例/持久对象**。玩家角色、HUD、背景——它们不需要池。
- ❌ **对象创建/销毁频率很低**（每分钟几个）。池带来的复杂度和收益不成正比。
- 🔗 `GxFloatingNumber` 本身是一个 CanvasLayer——如果要高频 spawn 浮字，用 `GxObjectPool` 管理浮字内部的 Label 节点复用。

**3 行上手**

```gdscript
var pool := GxObjectPool.new(func(): return preload("res://bullet.tscn").instantiate(), 10)
var b := pool.acquire()
# …用完…
pool.release(b)
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `_init(factory, prewarm, on_release?)` | 工厂回调创建新实例。on_release 归池前重置 |
| `acquire()` | 从池取一个实例。池空则调 factory 新造 |
| `release(obj)` | 归还实例。先调 on_release，再入池。重复归还自动忽略并 warning |
| `available_count()` | 池中当前可用数量 |

```gdscript
var _bullet_pool := GxObjectPool.new(
    func() -> Node: return preload("res://bullet.tscn").instantiate(),
    5,                                   # 预热 5 个
    func(obj):                           # 归池前重置
        obj.visible = false
        obj.process_mode = Node.PROCESS_MODE_DISABLED
)

func _fire() -> void:
    var b := _bullet_pool.acquire()
    b.global_position = $Muzzle.global_position
    b.visible = true
    b.process_mode = Node.PROCESS_MODE_INHERIT
    get_tree().current_scene.add_child(b)

func _on_bullet_hit(bullet: Node) -> void:
    _bullet_pool.release(bullet)       # 归还（自动调 on_release）

# 重复归还不崩溃
func _bad_code() -> void:
    var b := _bullet_pool.acquire()
    _bullet_pool.release(b)
    _bullet_pool.release(b)            # → push_warning + 忽略

print(_bullet_pool.available_count())  # → 5
```

**常见误区**

> ⚠️ `release()` 回到池里的对象仍然在场景树中（如果你没在 `on_release` 里 remove_child）。如果对象是 Node，务必在重置回调中做 `visible = false` + `process_mode = DISABLED`，否则池里的"闲置"对象照样吃 CPU 时间。

---

### 2.10 GxFloatingNumber —— 浮字

**是什么**

伤害/得分/回复数字的弹出动画组件。`spawn()` 在指定位置创建数字标签，自动执行"弹出 → 上漂 → 晃动 → 淡出"动画，结束后 `queue_free`。提供 5 种预设风格（普通/伤害/回复/暴击/灰色），也可完全自定义。

**什么时候用**

- ✅ **战斗伤害数字**。`floating.spawn(pos, str(-damage), Preset.DAMAGE)`——红色大字弹出漂走。
- ✅ **回复/增益提示**。`floating.spawn(pos, "+20", Preset.HEAL)`——绿色字体飘起。
- ✅ **暴击/特殊效果**。`floating.spawn(pos, "CRIT!", Preset.CRITICAL)`——大号橙色字体弹出。
- ✅ **资源收集反馈**。`floating.spawn(pos, "+50 Gold", Preset.DEFAULT)`。
- ❌ **持久显示的文本**（角色名字、任务追踪）。浮字的生命周期是动画结束=销毁，不是持久元素。
- 🔗 需要高频 spawn 浮字时（如弹幕游戏），可以考虑用 **GxObjectPool** 管理浮字内部的 Label 节点复用——但当前版本每个 spawn 创建独立的 Label，对于大多数游戏场景足够。

**3 行上手**

```gdscript
var fn := GxFloatingNumber.new(); add_child(fn)
fn.spawn(global_position, "-5", GxFloatingNumber.Preset.DAMAGE)
fn.spawn(global_position, "+20", GxFloatingNumber.Preset.HEAL)
```

**完整 API 教学**

| API | 说明 |
|---|---|
| `spawn(pos, text, preset?, overrides?)` | 预设风格浮字。overrides 可选覆盖单个参数 |
| `spawn_custom(pos, text, cfg: Dictionary)` | 完全自定义参数 |
| `Preset.DEFAULT / DAMAGE / HEAL / CRITICAL / MUTED` | 5 种预设配色/字号/动画 |

```gdscript
# 挂在场景根节点或 HUD CanvasLayer 上
var floating := GxFloatingNumber.new()
add_child(floating)

# —— 预设风格 ——
func _on_enemy_hit(damage: int, pos: Vector2) -> void:
    floating.spawn(pos, str(-damage), GxFloatingNumber.Preset.DAMAGE)

func _on_heal(amount: int, pos: Vector2) -> void:
    floating.spawn(pos, "+%d" % amount, GxFloatingNumber.Preset.HEAL)

func _on_critical(pos: Vector2) -> void:
    floating.spawn(pos, "CRIT!", GxFloatingNumber.Preset.CRITICAL)

# —— 自定义 ——
floating.spawn_custom(pos, "MISS", {
    "color": Color.GRAY,
    "duration": 0.6,
    "font_size": 14,
    "float_distance": 20.0,
    "scale_start": 1.2,
    "wobble": 4.0,
})

# —— 预设 + 覆盖个别参数 ——
floating.spawn(pos, "+100", GxFloatingNumber.Preset.HEAL,
    {"duration": 1.5, "float_distance": 60.0})
```

**5 种预设视觉效果**

| 预设 | 颜色 | 字号 | 弹跳幅度 | 适用 |
|---|---|---|---|---|
| `DEFAULT` | 白色 | 18 | 正常 | 通用提示、金币 |
| `DAMAGE` | 红色 | 20 | 正常 | 受到伤害 |
| `HEAL` | 绿色 | 18 | 正常 | 回复、Buff |
| `CRITICAL` | 橙色 | 28 | 大 | 暴击、特殊效果 |
| `MUTED` | 灰色 | 16 | 小 | 免疫、未命中 |

**常见误区**

> ⚠️ `spawn()` 创建的 Label 起点位置是 `pos - label.size * 0.5`（居中），不是 `pos` 的左上角。如果你期望数字从点击位置精确冒出，这个偏移是正确的——它让大字号数字的视觉中心对齐传入坐标。如果你传入 `Vector2.ZERO`，小字号会正好在左上角。

---

## 3. 常见模式

以下模式不依赖任何特定项目——你可以直接复制到自己的游戏里，改掉资源路径即可。

### 3.1 场景流程控制（GxStateMachine + GameFlow）

```gdscript
# autoload: game_flow.gd
const GxStateMachine := preload("res://addons/gd-common/fsm/state_machine.gd")
const GxState := preload("res://addons/gd-common/fsm/state.gd")

var _sm

func _ready() -> void:
    _sm = GxStateMachine.new(self)
    _sm.add_state(&"title", GxState.new())
    _sm.add_state(&"game",  GxState.new())
    _sm.add_state(&"result", GxState.new())
    _sm.state_changed.connect(func(_f, to):
        var scene := {
            &"title": "res://scenes/title.tscn",
            &"game":  "res://scenes/game.tscn",
            &"result":"res://scenes/result.tscn",
        }
        get_tree().change_scene_to_file.call_deferred(scene[to])
    )
    _sm.start(&"title")

func go(phase: StringName) -> void:
    _sm.transition_to(phase)
```

### 3.2 玩家状态 + 存档（SaveSystem）

```gdscript
# autoload: game_data.gd
extends Node

const SLOT := 0

var level: int = 1
var coins: int = 0
var settings: Dictionary = {"music_vol": 1.0, "sfx_vol": 1.0}

func save() -> void:
    SaveSystem.save_to_slot(SLOT, {
        "level": level, "coins": coins, "settings": settings,
    })

func load() -> void:
    var data := SaveSystem.load_from_slot(SLOT)
    if data.is_empty(): return
    level    = data.get("level", 1)
    coins    = data.get("coins", 0)
    settings = data.get("settings", {})
    EventBus.emit_event(&"game_loaded")

func has_save() -> bool:
    return SaveSystem.has_slot(SLOT)
```

### 3.3 音效注册表（SoundManager + AudioLib 模式）

```gdscript
# autoload: audio_lib.gd
extends Node

const SFX := {
    click  = "res://sfx/ui_click.wav",
    hit    = "res://sfx/hit.wav",
}
const BGM := {
    menu   = "res://bgm/menu.wav",
    battle = "res://bgm/battle.wav",
}
const AMBIENT := {
    forest = "res://sfx/forest.wav",
}

var _cache: Dictionary = {}

func _load(path: String) -> AudioStream:
    if path.is_empty(): return null
    if _cache.has(path): return _cache[path]
    if ResourceLoader.exists(path):
        _cache[path] = load(path)
        return _cache[path]
    return null

func sfx(key: String) -> void:
    SoundManager.play_sound(_load(SFX.get(key, "")))

func bgm(key: String) -> void:
    SoundManager.play_music(_load(BGM.get(key, "")), 1.5)

func ambient(key: String) -> void:
    SoundManager.play_ambient_sound(_load(AMBIENT.get(key, "")), 2.0)

func stop_ambient(key: String) -> void:
    var s := _load(AMBIENT.get(key, ""))
    if s: SoundManager.stop_ambient_sound(s, 1.5)
```

### 3.4 耐心 / 血量条（GxGaugeComponent + ProgressBar）

```gdscript
# 挂到任意角色节点上
@onready var bar: ProgressBar = $ProgressBar
var gauge: GxGaugeComponent

func _ready() -> void:
    gauge = GxGaugeComponent.new()
    gauge.max_value = 100.0
    gauge.auto_rate = 0.0
    add_child(gauge)
    gauge.value_changed.connect(func(cur, mx):
        bar.value = cur
        bar.max_value = mx
        bar.modulate = Color.RED if gauge.ratio() < 0.3 else Color.WHITE
    )
    gauge.depleted.connect(func(): die())

func take_damage(amount: float) -> void:
    gauge.drain(amount)

func heal(amount: float) -> void:
    gauge.fill(amount)
```

### 3.5 冷却图标 UI（GxCooldown + 材质参数）

```gdscript
var skill_cd := GxCooldown.new(3.0)

func _process(delta: float) -> void:
    skill_cd.tick(delta)
    $SkillIcon.material.set_shader_parameter("cooldown", skill_cd.progress())
    $SkillIcon.modulate = Color.GRAY if skill_cd.is_running() else Color.WHITE

func use_skill() -> void:
    if skill_cd.is_running(): return
    _execute_skill()
    skill_cd.start()

func on_interrupted() -> void:
    skill_cd.cancel()   # 打断不发 finished
```

---

## 4. 接入 / 更新共享库

接入到任意项目：
```
git submodule add <gd-common-remote-url> addons/gd-common
# Godot 编辑器 → 项目设置 → 插件 → 启用 gd-common
```

更新共享库到最新：
```
git -C addons/gd-common pull origin main
git add addons/gd-common && git commit -m "bump gd-common"
```

---

## 5. 解耦军规（共享层代码必须遵守）

1. 禁写死节点路径 `get_node("/root/...")`
2. 禁在逻辑里写死 `res://` 资源路径——靠注入
3. 依赖注入，不在模块内部 `load()` 项目资源
4. 只发信号 / 走 EventBus，不硬引用别的系统
5. 自包含：模块自带脚本/场景/默认资源
6. 不依赖项目专属 autoload

---

## 6. 验证与纪律

- **CLI 验证**：`godot --headless --path <项目> --quit`，查 0 解析错误
- **headless 引用类**：用 `preload(".../xxx.gd")` 而非全局 `class_name`，避免依赖编辑器全局类缓存
- **本地仓库 → 远程**：`git remote add origin <url>` 推上远程后，消费项目改 `.gitmodules` url

---

## 7. 如何新增一个通用模块（贡献指南）

> 先问：**这功能跨游戏通用吗？** 通用 → 进 gd-common；带游戏专属假设 → 放项目里。
> 「三次法则」：同一个东西在 2~3 个地方用过、形态稳定了再抽进来。

### 7.1 文件夹职责表

| 文件夹 | 放什么 | ❌ 不该放 |
|---|---|---|
| `core/` | autoload 脚本（**不写 class_name**） | 挂节点的组件 |
| `components/` | 继承 Node/Control 的可复用组件 | 全局单例 |
| `fsm/` | 状态机基类/框架 | 非状态相关逻辑 |
| `utils/` | 无状态工具类（纯函数/RefCounted） | 要进场景树的 |
| 根 `plugin.gd` / `plugin.cfg` | 插件入口 | 业务逻辑 |

### 7.2 决策流

```
全局唯一、到处可调？ ── 是 → core/ (autoload)
挂在节点上、给对象加能力？ ── 是 → components/
是状态机？ ── 是 → fsm/
纯函数 / 不进场景树？ ── 是 → utils/
都不是？ ── 不进 gd-common，放项目
```

### 7.3 命名规范

- 普通类/组件：`class_name GxXxx`（Gx 前缀）
- autoload 脚本：简洁全局名，脚本内**不要写 class_name**
- 信号、文件名：`snake_case`
- 引用 Gx 类优先 `preload(...)`，headless/CI 更稳

### 7.4 添加新模块流程

#### A. 普通类/组件——最常见，不用改 plugin.gd

新建 `components/gx_timer.gd`，然后在 `README.md` 登记一条。调用方：

```gdscript
const GxTimer := preload("res://addons/gd-common/components/gx_timer.gd")
var t := GxTimer.new()
add_child(t)
t.timeout.connect(func(): print("时间到"))
t.start(3.0)
```

#### B. 新 autoload 服务——多两步注册

1. 新建 `core/logger.gd`（**不写 class_name**）
2. 在 `plugin.gd` 的 `AUTOLOADS` 里注册
3. 在消费项目启用插件（自动写入 `project.godot`）

### 7.5 发布链路

```
# 源仓库
git add -A && git commit -m "feat: GxTimer"
git push origin main

# 消费项目
git -C addons/gd-common pull origin main
```

验证：`godot --headless --path <项目> --quit`，确认 0 ERROR。
