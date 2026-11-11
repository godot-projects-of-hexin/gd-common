# agent.md — gd-common 开发规则

> 这是 `gd-common` 与所有消费它的项目的**唯一规则入口**。人和 AI 都只读这一份。
> 任何与本文冲突的旧注释、旧文档、旧习惯，以本文为准。
> 新增规则写进本文，不要新建平行文档。

---

## 0. 三十秒速览

```text
gd-common  = 跨项目通用层（机制）      ← 本仓库
game-template = 项目骨架（玩法起点）    ← 消费方

分层：  Controller → Command → System / Model → Utility
通信：  向下直接调用，向上只能用 Event 或 BindableProperty
写入：  表现层改状态只能发 Command
读取：  表现层读状态用 get_model / get_system / Query
```

四条红线，违反即不予合并：

1. 共享层不写死 `/root/...` 节点路径，也不写死 `res://` 项目资源路径。
2. 表现层不直接改 Model / System 状态。
3. Model 不访问 System，Utility 不访问任何架构成员。
4. 第三方代码不进 `gd-common`。

---

## 1. 两个仓库的职责边界

| | `gd-common` | `game-template` |
|---|---|---|
| 定位 | 通用机制库（addon） | 项目骨架（可克隆工程） |
| 内容 | 架构层、事件、存档、音频、UI 栈、状态机、组件、工具 | GameArchitecture、Model、System、Command、场景 |
| 是否含玩法 | 禁止 | 这里才放玩法 |
| 是否含美术音频资源 | 禁止 | 允许，放 `assets/` |
| 引入方式 | 被 submodule 引用到 `addons/gd-common` | 克隆后改名开工 |

判断一段代码该放哪里：

```text
它在下一个完全不同题材的游戏里还成立吗？
  ├─ 是 → 并且已在 2~3 处复用 → gd-common
  ├─ 是 → 但只用过一次       → 先留在项目里（三次法则）
  └─ 否                      → 项目里，永远不要上移
```

**三次法则**：一个能力至少在 2~3 处复用、形态已经稳定、确认跨题材通用，才允许抽进 `gd-common`。只用过一次的东西留在项目层。

---

## 2. Godot 官方规范（强制）

依据 Godot 官方 [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) 与 [Project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)。这部分没有讨论空间。

### 2.1 文件与编码

| 项 | 规则 |
|---|---|
| 换行 | LF，文件末尾一个换行 |
| 编码 | UTF-8，不带 BOM |
| 缩进 | **Tab**，不用空格 |
| 行长 | 不超过 100 字符，尽量 80 以内 |
| 语句 | 一行一条，不写 `if x: return` 单行形式 |

### 2.2 命名

| 对象 | 规则 | 示例 |
|---|---|---|
| 文件与目录 | `snake_case` | `gx_state_machine.gd` |
| 类（`class_name`） | `PascalCase` | `GxStateMachine` |
| 节点名 | `PascalCase` | `ScoreLabel` |
| 函数、变量 | `snake_case` | `add_score`、`max_health` |
| 私有成员、虚方法 | 前置单下划线 | `_on_init`、`_speed` |
| 信号 | **过去式** | `score_changed`、`door_opened` |
| 常量 | `CONSTANT_CASE` | `MAX_SPEED` |
| 枚举名 | `PascalCase` 单数 | `enum Element` |
| 枚举成员 | `CONSTANT_CASE` | `EARTH, WATER` |

**`class_name` 与文件名必须一一对应**，PascalCase 转 snake_case：

```text
class_name GxStateMachine   →  gx_state_machine.gd     正确
class_name GxStateMachine   →  state_machine.gd        错误
```

> 这不是洁癖。Windows 与 macOS 默认大小写不敏感，Linux 敏感，而 Godot 导出的 PCK 虚拟文件系统是大小写敏感的 —— 命名不统一会导致**只在导出版本上出现**的资源丢失。

本库额外约定：

- 带 `class_name` 的通用类统一 `Gx` 前缀，避免污染项目全局命名空间。
- autoload 用朴素名字（`EventBus`、`SaveSystem`、`AudioManager`、`UIManager`），**脚本里不写 `class_name`**，否则同一个脚本会同时存在全局类和全局实例两个名字。

### 2.3 代码顺序

官方规定的顺序，自上而下：

```text
01  @tool / @icon / @static_unload
02  class_name
03  extends
04  ## 文档注释
05  signal
06  enum
07  const
08  static var
09  @export var
10  普通 var
11  @onready var
12  _static_init()
13  其余 static 方法
14  内置虚方法：_init → _enter_tree → _ready → _process → _physics_process → 其他
15  覆写的自定义方法
16  其余方法
17  内部类
```

同一类别内 **public 在 private 之前**。内部类用单行声明：

```gdscript
class TransitionData extends RefCounted:
	var from: StringName = &""
```

### 2.4 空行与逗号

- 函数之间、类定义之间空 **两行**；函数内部用 **一行** 分隔逻辑块。
- 多行数组、字典、枚举的最后一项**加尾逗号**；单行写法**不加**。

```gdscript
var party = [
	"Godot",
	"Godette",
]

var array = [1, 2, 3]
```

### 2.5 静态类型

本库要求**所有**公共 API 标注类型。

```gdscript
var health: int = 0                       # 显式类型
var player := PlayerModel.new()           # 同行赋值时用 :=
func heal(amount: int) -> void:            # 必须写返回类型
```

- 类型写在赋值同一行时用 `:=`，否则写完整 `: Type`。
- 集合用类型化形式：`Array[Callable]`、`Array[int]`。
- 版本基线是 **Godot 4.4+**（见第 7.0 节）。本库**不使用** 4.5+ 才有的
  `@abstract`、`@export_file_path` 等语法；`Dictionary[K, V]` 虽在 4.4 可用，
  但为保持写法统一也不使用，字典的键值类型写在注释里。

> **`:=` 推断出 Variant 会直接报错。** Godot 4.7 把 `inferred_declaration` 警告
> 当成错误处理，脚本会加载失败：
>
> ```gdscript
> var w := weakref(x)              # 报错：推断为 Variant
> var w: WeakRef = weakref(x)      # 正确
> var d := cfg.get_value("a", "b") # 报错
> var d: Variant = cfg.get_value("a", "b")   # 正确
> ```
>
> 凡是返回 `Variant` 的 API（`weakref`、`instance_from_id`、`Dictionary.get`、
> `Array` 取下标、`send_query`），一律写显式类型。

### 2.8 引用环：RefCounted 的反向引用必须是弱引用

两个 `RefCounted` 互相强引用，引用计数永远归不了零，退出时报
`ObjectDB instances were leaked at exit`。**拥有方强引用，被拥有方反向弱引用。**

```gdscript
# 错误：架构强引用 Model，Model 又强引用架构 —— 死环
var _architecture: GxArchitecture

# 正确
var _architecture_ref: WeakRef = null

func _bind_architecture(architecture: GxArchitecture) -> void:
	_architecture_ref = weakref(architecture) if architecture != null else null

func _resolve_architecture() -> GxArchitecture:
	if _architecture_ref == null:
		return null
	return _architecture_ref.get_ref() as GxArchitecture
```

本库已按此处理的两处：`GxModel` / `GxSystem` → `GxArchitecture`，
`GxState` → `GxStateMachine`。新增「容器持有成员、成员要回头找容器」的结构时照做。

`Node` 不受此限制 —— 它是手动释放的，释放时会连带放掉脚本成员。

另外，**`static var` 持有的对象不会随场景树消失**。项目用静态单例暴露架构时，
必须在退出时主动释放（见 `game-template` 的 `GameFlow._exit_tree()`），
否则引擎退出检查照样报泄漏。

### 2.6 Node 之外的基类

能不用 `Node` 就不用，官方给出的梯度：

| 基类 | 内存 | 何时用 |
|---|---|---|
| `Object` | 手动释放 | 几乎不用，容易出悬空引用 |
| `RefCounted` | 自动引用计数 | **默认选择**：数据类、状态机、工具、架构层 |
| `Resource` | 自动 + 可序列化 + Inspector | 配置、数据表、可在编辑器编辑的资源 |
| `Node` | 进场景树 | 确实需要生命周期、子节点或场景树能力 |

本库里 `GxArchitecture`、`GxModel`、`GxSystem`、`GxCommand`、`GxQuery`、`GxStateMachine`、`GxCooldown`、`GxObjectPool` 全是 `RefCounted`，只有 autoload 与 `GxGaugeComponent`、`GxFloatingNumber`、`GxControllerNode` 是 `Node`。

### 2.7 Autoload 的使用门槛

官方明确警告 autoload 带来三类问题：**全局状态**、**全局访问**、**全局资源分配**。所以：

| 允许 | 禁止 |
|---|---|
| 管理自己的数据、不侵入其他对象的广域系统 | 把玩法逻辑塞进 autoload |
| 本库的 4 个基础设施 autoload | 为了省事把 Model/System 注册成 autoload |
| 项目级的单一流程控制器 | 新增第 5、第 6 个 "XxxManager" autoload |

**架构层故意不是 autoload。** 如果 `Architecture` 全局可达，任何节点都能 `get_model()` 直接改状态，分层规则当场失效。项目用一个静态访问器暴露唯一实例，表现层只能通过 `GxController` / `GxControllerNode` 接触它。

新增 autoload 前先问：能不能用 `static func` + `class_name` 的工具类，或 `static var` 解决？能就别加。

---

## 3. 架构分层规则（核心）

### 3.1 数据流

```text
玩家输入
   │
   ▼
Controller ──────── send_command ────────▶ Command
（表现层）                                   │
   ▲                                        ├─ get_model / get_system
   │                                        ├─ send_event
   │                                        └─ send_command / send_query
   │                                             │
   │                                             ▼
   │                                    System / Model
   │                                    （业务层 / 数据层）
   │                                             │
   │                                             ├─ get_utility
   └──── Event / BindableProperty ◀──────────────┘
                                                 │
                                                 ▼
                                             Utility
                                           （基础设施）
```

一句话：**向下直接调用，向上只用事件。**

### 3.2 每层的权限

权限不是靠 review 约束的，而是**基类只暴露该层允许的方法**。`GxModel` 上根本没有 `get_system()`，写不出来。

| 层 | 基类 | 可以 | 不可以 |
|---|---|---|---|
| 表现层 | `GxControllerNode` / `GxController` | `get_system` `get_model` `send_command` `send_query` `register_event` `bind` | 直接改状态、`get_utility` |
| 命令 | `GxCommand` | `get_system` `get_model` `get_utility` `send_event` `send_command` `send_query` | 持有状态、返回值 |
| 查询 | `GxQuery` | `get_system` `get_model` `send_query` | 改任何状态、发事件 |
| 业务层 | `GxSystem` | `get_system` `get_model` `get_utility` `send_event` `register_event` | 发 Command、持有节点引用、碰 UI |
| 数据层 | `GxModel` | `get_utility` `send_event` | `get_model` `get_system` `send_command` |
| 基础设施 | `GxUtility` | 只做自己的事 | 访问任何架构成员 |

`tests/test_architecture.gd` 里有一组 `has_method()` 断言专门守这张表。**如果有人放宽了权限，那组测试会红。** 不要为了方便去改它。

### 3.3 各层职责

**Model —— 状态的唯一来源**

```gdscript
class_name PlayerModel
extends GxModel

var score := GxBindableProperty.new(0)

func add_score(amount: int) -> void:
	score.set_value(int(score.get_value()) + amount)
```

只放状态和读写状态的方法。不做业务判断（"够不够钱买" 属于 System 或 Query）。

**System —— 不属于任何单一场景的规则**

计分、成就、任务、商店、昼夜循环放这里。判断标准：**这条规则被两个以上的表现节点需要吗？** 是就进 System。

System 不许持有节点引用，不许 `get_tree()`，不许碰 `Control` —— 一旦碰了它就是表现层。

**Command —— 唯一的写入路径**

```gdscript
class_name AddScoreCommand
extends GxCommand

var _amount: int

func _init(amount: int) -> void:
	_amount = amount

func _on_execute() -> void:
	var player := get_model(PlayerModel) as PlayerModel
	player.add_score(_amount)
	send_event(ScoreChangedEvent.create(int(player.score.get_value())))
```

Command 必须**无状态**：参数进去，什么都不带出来。需要返回值就改用 Query。

把写入都收敛到 Command 的回报不是少写代码，而是日志、回放、数据埋点、撤销这些需求后来可以在一个地方统一接入，不用改调用方。

**不是所有函数都该做成 Command：**

| 适合 Command | 不适合 |
|---|---|
| 加金币、扣血、完成任务 | 播一个音效 |
| 购买物品、提交线索 | 刷新一个 Label |
| 切换关卡阶段 | 查询当前血量 |
| 消耗道具、解锁成就 | 计算一个向量 |

**Query —— 只读的问题**

需要跨多个 Model 拼装答案，或要对原始数据套规则时用 Query。Query 改任何东西就是 bug。

**Utility —— 基础设施**

文件、序列化、HTTP、平台 SDK、第三方库封装。它拿不到架构，这正是它能跨项目复用的原因。

### 3.4 初始化顺序

`initialize()` 自下而上：

```text
_on_register()  →  Utility._on_init()  →  Model._on_init()  →  System._on_init()
```

所以 `System._on_init()` 里可以安全地 `get_model()` 和 `get_utility()`，`Model._on_init()` 里可以安全地 `get_utility()`。反过来不行。

`initialize()` 之后注册的成员会被立即初始化，所以延迟加载的模块行为一致。

---

## 4. 通信方式：怎么选

四种机制，按**耦合范围**选，不要凭手感：

| 机制 | 键 | 适用 | 不要用在 |
|---|---|---|---|
| Godot `signal` | 编译期 | 同场景、父子节点、组件对外 | 跨场景、跨模块 |
| `GxBindableProperty` | 属性实例 | Model 的某个值要被 UI 镜像 | 一次性通知、无状态事件 |
| 架构 Event（类型化） | 事件类 | **业务**状态已发生变化 | 逐帧高频数据 |
| `EventBus`（字符串） | `StringName` | **基础设施**广播：音频、过场、调试 | 业务状态变化 |

硬性划分：

```text
业务状态变化  →  架构 Event 或 BindableProperty
基础设施广播  →  EventBus
```

架构 Event 用**事件类**而不是字符串，因为载荷字段写在类里，生产者和消费者不可能对不上：

```gdscript
class_name ScoreChangedEvent
extends GxEvent

var score: int

static func create(value: int) -> ScoreChangedEvent:
	var event := ScoreChangedEvent.new()
	event.score = value
	return event
```

两条额外纪律：

- 事件是**已经发生的事实**，命名用过去式，构造时填好字段，handler 里不要改它。
- 订阅一律用**具名方法**，不要用 lambda。lambda 捕获了场景节点后，节点销毁时订阅会静默失效，而你无法用 `unregister` 找回那个 Callable。

---

## 5. 目录与放置决策

```text
gd-common/
├── agent.md            ← 本文件，唯一规则入口
├── README.md           ← 模块清单与 API 速查
├── plugin.cfg
├── plugin.gd           ← 注册 4 个 autoload
├── architecture/       ← 架构层（RefCounted，无 autoload）
├── core/               ← 全局服务 autoload：EventBus / SaveSystem / UIManager
├── audio/              ← AudioManager autoload
├── components/         ← 挂到节点上的可复用组件
├── fsm/                ← 状态机框架
├── utils/              ← 纯函数与 RefCounted 工具
└── tests/              ← SceneTree 测试 + run_all.sh
```

放哪里的决策顺序：

```text
是架构层概念（Model/System/Command/Query/Event/Architecture）？
  → architecture/

全局唯一、到处要用、需要进场景树？
  → core/ 或 audio/，并在 plugin.gd 注册 autoload
  → 先确认第 2.7 节的 autoload 门槛

挂在节点上、给对象增加能力？
  → components/

状态机相关？
  → fsm/

纯函数或不进场景树的工具？
  → utils/

以上都不是？
  → 留在项目里，不要进 gd-common
```

第三方资源统一放消费项目的顶层 `addons/`，方便一眼看出哪些不是自己的代码。需要让 Godot 忽略某个目录时，在该目录放一个空的 `.gdignore`（内容被忽略，不支持 `.gitignore` 那种模式匹配）。

---

## 6. 共享层军规

`gd-common` 里的代码必须满足：

1. 不写死节点路径，不出现 `get_node("/root/...")`。
2. 不写死项目资源路径，逻辑里不出现具体的 `res://assets/...`。
3. 依赖靠注入：资源、上下文、工厂、回调都从参数进来。
4. 模块之间只通过 signal / EventBus / 架构 Event 通信，不互相硬引用。
5. 自包含：模块自带脚本、场景和默认资源。
6. 不依赖项目专属 autoload（不假设 `GameData`、`GameFlow` 存在）。
7. 不引入第三方代码。确实需要外部库时，放消费项目的 `addons/third_party/`，保留原始 LICENSE，不进本库。

核心是一句话：

> **共享层提供机制，但不能假设具体项目怎么组织玩法。**

- `SaveSystem` 不知道玩家有哪些字段。
- `AudioManager` 不知道音频文件在哪。
- `GxGaugeComponent` 不知道归零后该死亡还是离场。
- `GxStateMachine` 不知道状态对应什么行为。

---

## 7. 验证与提交

### 7.0 版本基线（4.4+）

**gd-common 支持 Godot 4.4 及以上所有 4.x 版本。** 消费项目的 `project.godot`
声明 `config/features=PackedStringArray("4.4")`，那是**项目格式下限**，不是锁定 4.4。

| 引擎版本 | 实测结果（在 game-template 全新 clone 上） |
|---|---|
| 4.4.stable | ✅ 启动 0 错误，8/8 套件通过 |
| 4.5.stable | ✅ 启动 0 错误，8/8 套件通过 |
| 4.6.stable | ✅ 启动 0 错误，8/8 套件通过 |
| 4.7.stable | ✅ 启动 0 错误 0 泄漏，8/8 套件通过 |
| 4.3 及以下 | ❌ 不支持：`.gd.uid` 是 4.4 引入的，且项目格式声明为 4.4 |
| 4.8+ | 未验证；`features=4.4` 本身不会阻止打开 |

代码里最老的语法门槛是 `static var`（4.1 引入）。**不要使用 4.5+ 才有的语法**
（`@abstract`、`@export_file_path` 等）；每次引入新 API 前先确认它在 4.4 里存在。
新增能力后，至少在 4.4 和当前最新 4.x 各跑一遍第 7.1 节的验证。

跨版本协作的两个已知现象，**都不是回归**：

- 4.7 生成的 `.import` 文件比 4.4 多几行默认参数（`compress/uastc_level`、
  `process/channel_remap/*`）。混用小版本时该文件会来回变脏；只涉及它且无其它
  改动时还原即可，不要手动升级 `config/features`。
- `--import` 会打印 4 行 `gd-common: autoload '...' already exists; keeping the
  project's own.` —— 插件保留项目自定义 autoload 的正常行为。Godot 4.4 的
  `--import` 还会额外打印 `Condition "!tasks.has(p_task)" is true`，那是 4.4
  编辑器自身的 headless 进度对话框问题，与本库无关。

### 7.1 提交前必须跑

`gd-common` 是 addon，没有自己的 `project.godot`，测试要从消费项目跑：

```bash
# 在 game-template 根目录
godot --headless --path . --import                    # 全新 clone 必须先跑这步
godot --headless --path . --quit                      # 项目能起、无解析错误、无泄漏
./addons/gd-common/tests/run_all.sh                   # 全部测试套件
```

**第一步不能省。** 全新 clone 没有 `.godot/` 缓存，全局 `class_name` 还没注册，
直接跑第二步会报 `Could not find base class "GxControllerNode"`。`--import` 会
生成 `.godot/global_script_class_cache.cfg`，之后才认得这些类。

通过标准三条，缺一不可：

| 检查项 | 通过标准 |
|---|---|
| 解析与运行 | `--quit` 这一步输出里 0 个 `ERROR`、0 个 `SCRIPT ERROR` |
| 内存 | `--quit` 这一步**没有** `ObjectDB instances were leaked at exit` |
| 测试 | 每个套件打印 `all passed`，结尾 `RESULT: all 8 suites passed` |

泄漏警告不是噪音，它基本都代表一个引用环（见第 2.8 节），必须查到底。

**两个已知的例外，只出现在测试里，不要误判成回归：**

- 测试会**故意**走错误分支（未知状态名、传 `null` 流、损坏存档），所以
  `run_all.sh` 的输出里有 `ERROR:` 行是正常的。测试只看 `all passed`。
- `test_audio_manager` 退出时固定报十几个 ObjectDB 泄漏。这是 headless 的
  dummy 音频驱动的行为：每次 `play()` 产生的 `AudioStreamPlayback` 在退出时
  都算泄漏，**纯引擎 API 也复现**（建 player → play → stop → free 仍报 2 个）。
  与 gd-common 无关。其余 7 个套件都是 0 泄漏。

真正要守住 0 泄漏的是 `--quit` 那一步，它代表玩家实际跑的链路。

> Godot 不在 `PATH` 时：`GODOT=/path/to/godot ./addons/gd-common/tests/run_all.sh`

### 7.2 测试怎么写

测试是独立的 `SceneTree` 脚本，用 `godot --headless --script` 运行。
**入口必须是 `_process()`，不能是 `_init()` 或 `_initialize()`：**

```gdscript
extends SceneTree

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var failures := 0
	failures += _t_something()
	if failures > 0:
		print("XXX_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("XXX_TEST: all passed")
		quit(0)
	return true
```

原因：`_init()` 和 `_initialize()` 执行时 `root` 还没真正进入场景树，
`root.add_child(node)` **不会触发 `node._ready()`**。任何依赖 `_ready` 的组件
（`GxGaugeComponent` 读 `@export` 初值、`AudioManager` 建播放器）都会拿到半成品，
测出来的失败全是假的。到 `_process()` 这一帧，场景树才完整。

另外两条：

- **内部类不能和项目的全局 `class_name` 同名**，否则报
  `Class "X" hides a global script class`。测试里的辅助类统一加 `Probe` 前缀。
- **用例之间要清干净共享状态**。写磁盘的测试（存档）必须在用例开头
  `_cleanup()`，否则前一个用例留下的文件会让后一个误判。

### 7.3 headless 下的类引用

headless 和 CI 不一定有编辑器的全局类缓存。在**测试和工具脚本**里优先用显式 `preload`：

```gdscript
const GxCooldown := preload("res://addons/gd-common/utils/gx_cooldown.gd")
```

库内部的互相引用可以直接用 `class_name`。

### 7.4 版本控制

Godot 4.1+ 官方只要求忽略两类文件：

```gitignore
.godot/
*.translation
```

**`*.import` 和 `*.uid` 必须提交。** 它们保存导入设置和资源 UID，漏掉会让别人
clone 之后引用断裂、或者每次导入都产生无谓 diff。老项目里从 Godot 3 抄来的
`.gitignore` 常常错误地忽略 `*.import`，看到就删掉。

换行符统一靠仓库根目录的 `.gitattributes`：

```gitattributes
* text=auto eol=lf
```

Windows 上的 Git 客户端默认 `core.autocrlf=true`，会让文件无谓地显示为已修改。
官方建议改成：

```bash
git config --global core.autocrlf input
```

有 `.gitattributes` 的情况下不改也行，但改了更省心。已经跟踪过的 CRLF 文件要用
`git add --renormalize .` 才会归一化，光加 `.gitattributes` 不会追溯处理。

### 7.5 发布链路

```bash
# 1. 改共享库
cd gd-common
git add -A && git commit -m "feat: GxTimer" && git push origin main

# 2. 消费项目更新指针
cd ../game-template
git -C addons/gd-common pull origin main
git add addons/gd-common && git commit -m "chore: bump gd-common"

# 3. 再跑一次验证
godot --headless --path . --quit
```

submodule 的指针是**一次提交**，忘记提交 `addons/gd-common` 会让别人 clone 到旧版本。

### 7.6 提交信息

```text
feat:      新能力
fix:       修 bug
refactor:  不改行为的重构
docs:      文档
test:      测试
chore:     依赖、构建、submodule 指针
```

---

## 8. 常见错误

| 现象 | 原因 | 做法 |
|---|---|---|
| `Could not find base class "GxXxx"` | 全新 clone 没有全局类缓存 | 先跑 `godot --headless --path . --import` |
| 退出时报 `ObjectDB instances were leaked` | 两个 RefCounted 互相强引用，或 `static var` 没释放 | 反向引用改 `weakref`，静态单例在退出时释放（第 2.8 节） |
| `:=` 报 `inferred from a Variant value` | Godot 4.7 把该警告当错误 | 写显式类型 `var x: T = ...`（第 2.5 节） |
| `Class "X" hides a global script class` | 内部类和全局 `class_name` 重名 | 测试辅助类加 `Probe` 前缀 |
| 测试里组件状态全是默认值 | `_init()` 阶段 `add_child` 不触发 `_ready` | 测试入口改 `_process()`（第 7.2 节） |
| 订阅静默失效 | lambda 捕获了已销毁的节点 | 用具名方法；表现层走 `GxController`，它会自动解绑 |
| 信号报参数数量不符 | handler 参数数和信号不一致 | `GxBindableProperty` 只发新值，handler 固定一个参数 |
| 读存档崩在下标 | 槽位不存在时返回 `{}` | 一律 `data.get("key", 默认值)` |
| 音频没声音也不报错 | `load()` 返回了 `null` | 项目层做音频注册表，用 `ResourceLoader.exists()` 校验 |
| 弹窗 pop 后访问崩溃 | `pop_panel()` 已 `queue_free` | 在 `panel_will_pop` 里取数据 |
| 状态机不推进 | 它是 `RefCounted`，没有引擎回调 | 自己在 `_process` 调 `update(delta)` |
| 冷却不走 | 同上 | 自己调 `tick(delta)` |
| Gauge 方向反了 | `auto_rate > 0` 是**消耗**，`< 0` 是回复 | 按注释来，别凭直觉 |
| 对象池对象还在耗 CPU | `release()` 只回池，不离场景树 | 在 `on_release` 里隐藏并 `PROCESS_MODE_DISABLED` |
| 导出版本资源丢失 | 文件名大小写不统一，或 `.import`/`.uid` 没提交 | 全项目 `snake_case`；按第 7.4 节改 `.gitignore` |
| `get_model` 报没注册 | 架构没 `initialize()`，或没进 `_on_register()` | 检查项目的 `GameArchitecture` |

---

## 9. 改本文的规则

- 新增硬性约束 → 写进对应章节，**不要**新建文档。
- 废弃旧约束 → 直接删掉，不要留"历史原因"段落。
- 规则有争议 → 先改本文达成一致，再改代码。
- 本文与代码不一致 → **以代码为事实，立刻修本文**，不要让两边长期漂移。
