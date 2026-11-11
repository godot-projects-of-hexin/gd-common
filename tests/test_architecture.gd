extends SceneTree
## Architecture layer tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_architecture.gd


class DummyUtility extends GxUtility:
	var init_order: Array

	func _init(order: Array) -> void:
		init_order = order

	func _on_init() -> void:
		init_order.append("utility")

	func answer() -> int:
		return 42


class DummyModel extends GxModel:
	var init_order: Array
	var score := GxBindableProperty.new(0)
	var utility_answer := -1

	func _init(order: Array) -> void:
		init_order = order

	func _on_init() -> void:
		init_order.append("model")
		var utility := get_utility(DummyUtility) as DummyUtility
		if utility != null:
			utility_answer = utility.answer()

	func add_score(amount: int) -> void:
		score.set_value(int(score.get_value()) + amount)


class DerivedModel extends DummyModel:

	func _init(order: Array) -> void:
		super(order)

	func _on_init() -> void:
		pass


class ScoreChangedEvent extends GxEvent:
	var score := 0

	static func create(value: int) -> ScoreChangedEvent:
		var event := ScoreChangedEvent.new()
		event.score = value
		return event


class DummySystem extends GxSystem:
	var init_order: Array
	var model_visible_at_init := false
	var last_event_score := -1

	func _init(order: Array) -> void:
		init_order = order

	func _on_init() -> void:
		init_order.append("system")
		model_visible_at_init = get_model(DummyModel) != null
		register_event(ScoreChangedEvent, _on_score_changed)

	func _on_score_changed(event: ScoreChangedEvent) -> void:
		last_event_score = event.score


class AddScoreCommand extends GxCommand:
	var _amount: int

	func _init(amount: int) -> void:
		_amount = amount

	func _on_execute() -> void:
		var model := get_model(DummyModel) as DummyModel
		model.add_score(_amount)
		send_event(ScoreChangedEvent.create(int(model.score.get_value())))


class ScoreQuery extends GxQuery:

	func _on_run() -> Variant:
		var model := get_model(DummyModel) as DummyModel
		return int(model.score.get_value())


class TestArchitecture extends GxArchitecture:
	var order: Array = []

	func _on_register() -> void:
		# Registered out of dependency order on purpose: initialize() must
		# still run utilities before models before systems.
		register_system(DummySystem.new(order))
		register_model(DummyModel.new(order))
		register_utility(DummyUtility.new(order))


func _init() -> void:
	var failures := 0
	failures += _t_init_order_is_bottom_up()
	failures += _t_resolve_by_script()
	failures += _t_system_sees_model_during_init()
	failures += _t_model_reaches_utility_during_init()
	failures += _t_command_mutates_model_and_emits_event()
	failures += _t_query_returns_value()
	failures += _t_layer_capabilities_are_restricted()
	failures += _t_lookup_falls_back_to_base_script()
	failures += _t_register_after_init_still_inits()
	failures += _t_double_initialize_is_ignored()
	failures += _t_deinitialize_clears_everything()
	failures += _t_default_architecture_accessors()
	failures += _t_unregister_event_stops_delivery()
	if failures > 0:
		print("ARCHITECTURE_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("ARCHITECTURE_TEST: all passed")
		quit(0)


func _make() -> TestArchitecture:
	var architecture := TestArchitecture.new()
	architecture.initialize()
	return architecture


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _t_init_order_is_bottom_up() -> int:
	var architecture := _make()
	if architecture.order != ["utility", "model", "system"]:
		return _fail("init order expected [utility, model, system], got %s" % str(architecture.order))
	if not architecture.is_initialized():
		return _fail("is_initialized() should be true after initialize()")
	return 0


func _t_resolve_by_script() -> int:
	var architecture := _make()
	if architecture.get_utility(DummyUtility) == null:
		return _fail("get_utility returned null")
	if architecture.get_model(DummyModel) == null:
		return _fail("get_model returned null")
	if architecture.get_system(DummySystem) == null:
		return _fail("get_system returned null")
	return 0


func _t_system_sees_model_during_init() -> int:
	var architecture := _make()
	var system := architecture.get_system(DummySystem) as DummySystem
	if not system.model_visible_at_init:
		return _fail("system could not resolve the model inside _on_init")
	return 0


func _t_model_reaches_utility_during_init() -> int:
	var architecture := _make()
	var model := architecture.get_model(DummyModel) as DummyModel
	if model.utility_answer != 42:
		return _fail("model.get_utility failed during _on_init (got %d)" % model.utility_answer)
	return 0


func _t_command_mutates_model_and_emits_event() -> int:
	var architecture := _make()
	architecture.send_command(AddScoreCommand.new(30))
	var model := architecture.get_model(DummyModel) as DummyModel
	if int(model.score.get_value()) != 30:
		return _fail("command did not change model state")
	var system := architecture.get_system(DummySystem) as DummySystem
	if system.last_event_score != 30:
		return _fail("system did not receive the typed event")
	return 0


func _t_query_returns_value() -> int:
	var architecture := _make()
	architecture.send_command(AddScoreCommand.new(7))
	var result: Variant = architecture.send_query(ScoreQuery.new())
	if int(result) != 7:
		return _fail("query returned %s, expected 7" % str(result))
	return 0


func _t_layer_capabilities_are_restricted() -> int:
	# The layering rules are enforced by API surface: a Model cannot reach a
	# System, and the presentation layer cannot reach a Utility. If these
	# assertions ever fail, the rules have quietly been widened.
	var architecture := _make()
	var model := architecture.get_model(DummyModel) as DummyModel
	if model.has_method("get_system"):
		return _fail("GxModel must not expose get_system")
	if model.has_method("get_model"):
		return _fail("GxModel must not expose get_model")
	if model.has_method("send_command"):
		return _fail("GxModel must not expose send_command")
	var utility := architecture.get_utility(DummyUtility) as DummyUtility
	if utility.has_method("get_model") or utility.has_method("send_event"):
		return _fail("GxUtility must not expose architecture accessors")
	var query := ScoreQuery.new()
	if query.has_method("send_command") or query.has_method("send_event"):
		return _fail("GxQuery must stay read-only")
	var controller := GxController.new(null, architecture, false)
	if controller.has_method("get_utility"):
		return _fail("GxController must not expose get_utility")
	return 0


func _t_lookup_falls_back_to_base_script() -> int:
	var architecture := GxArchitecture.new()
	architecture.initialize()
	architecture.register_model(DerivedModel.new([]))
	if architecture.get_model(DerivedModel) == null:
		return _fail("derived model not resolvable by its own script")
	if architecture.get_model(DummyModel) == null:
		return _fail("derived model not resolvable by its base script")
	return 0


func _t_register_after_init_still_inits() -> int:
	var architecture := _make()
	var order: Array = []
	architecture.register_system(DummySystem.new(order))
	if not order.has("system"):
		return _fail("system registered after initialize() was never inited")
	return 0


func _t_double_initialize_is_ignored() -> int:
	var architecture := _make()
	var count_before: int = architecture.order.size()
	architecture.initialize()
	if architecture.order.size() != count_before:
		return _fail("initialize() ran twice")
	return 0


func _t_deinitialize_clears_everything() -> int:
	var architecture := _make()
	architecture.deinitialize()
	if architecture.is_initialized():
		return _fail("is_initialized() should be false after deinitialize()")
	if architecture.has_event_handlers(ScoreChangedEvent):
		return _fail("event handlers survived deinitialize()")
	return 0


func _t_default_architecture_accessors() -> int:
	GxArchitecture.clear_default()
	if GxArchitecture.get_default() != null:
		return _fail("clear_default did not clear")
	var architecture := _make()
	GxArchitecture.set_default(architecture)
	if GxArchitecture.get_default() != architecture:
		return _fail("set_default/get_default mismatch")
	GxArchitecture.clear_default()
	return 0


func _t_unregister_event_stops_delivery() -> int:
	var architecture := _make()
	var system := architecture.get_system(DummySystem) as DummySystem
	system.unregister_event(ScoreChangedEvent, system._on_score_changed)
	architecture.send_command(AddScoreCommand.new(5))
	if system.last_event_score != -1:
		return _fail("handler still fired after unregister_event")
	return 0
