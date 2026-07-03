extends SceneTree


const SAVE_DIR := "user://saves/"


func _init() -> void:
	_cleanup()
	var failures: int = 0
	failures += _t_save_and_load_roundtrip()
	failures += _t_load_missing_returns_empty()
	failures += _t_invalid_version_treated_as_one()
	failures += _t_migrator_runs_on_version_mismatch()
	failures += _t_list_slots_returns_integers_sorted()
	failures += _t_delete_slot_removes_file()
	_cleanup()
	if failures > 0:
		print("SAVE_SYSTEM_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("SAVE_SYSTEM_TEST: all passed")
		quit(0)


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		var d := DirAccess.open(SAVE_DIR)
		if d:
			for f in d.get_files():
				DirAccess.remove_absolute(SAVE_DIR + f)


func _make_sys() -> Node:
	var s: Script = load("res://addons/gd-common/core/save_system.gd")
	var sys: Node = s.new()
	root.add_child(sys)
	return sys


func _t_save_and_load_roundtrip() -> int:
	var sys := _make_sys()
	sys.set_version(2)
	if not sys.save_to_slot(1, {"hp": 80, "name": "ada"}): return 1
	var d: Dictionary = sys.load_from_slot(1)
	if int(d.get("hp", -1)) != 80: return 1
	if String(d.get("name", "")) != "ada": return 1
	return 0


func _t_load_missing_returns_empty() -> int:
	var sys := _make_sys()
	var d: Dictionary = sys.load_from_slot(99)
	if not d.is_empty(): return 1
	return 0


func _t_invalid_version_treated_as_one() -> int:
	# Manually craft a corrupt slot with VERSION_KEY = "garbage"
	var path := SAVE_DIR + "slot_2" + ".cfg"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var cfg := ConfigFile.new()
	cfg.set_value("data", "__version", "garbage")
	cfg.set_value("data", "hp", 7)
	if cfg.save(path) != OK: return 1

	var sys := _make_sys()
	sys.set_version(1)
	# Should NOT crash, should load hp=7 and ignore the garbage version.
	var d: Dictionary = sys.load_from_slot(2)
	if int(d.get("hp", -1)) != 7: return 1
	return 0


func _t_migrator_runs_on_version_mismatch() -> int:
	var sys := _make_sys()
	sys.set_version(3)
	sys.save_to_slot(3, {"hp": 10})
	sys.set_version(5)
	var migrated: Array = [false]
	sys.set_migrator(func(data: Dictionary, from_v: int, to_v: int) -> Dictionary:
		migrated[0] = true
		if from_v == 3 and to_v == 5:
			data["hp"] = 99
		return data)
	var d: Dictionary = sys.load_from_slot(3)
	if not migrated[0]: return 1
	if int(d.get("hp", -1)) != 99: return 1
	return 0


func _t_list_slots_returns_integers_sorted() -> int:
	var sys := _make_sys()
	sys.save_to_slot(7, {})
	sys.save_to_slot(2, {})
	sys.save_to_slot(5, {})
	var slots: Array = sys.list_slots()
	if slots.size() != 3: return 1
	if int(slots[0]) != 2: return 1
	if int(slots[1]) != 5: return 1
	if int(slots[2]) != 7: return 1
	return 0


func _t_delete_slot_removes_file() -> int:
	var sys := _make_sys()
	sys.save_to_slot(4, {"a": 1})
	if not sys.has_slot(4): return 1
	if not sys.delete_slot(4): return 1
	if sys.has_slot(4): return 1
	return 0
