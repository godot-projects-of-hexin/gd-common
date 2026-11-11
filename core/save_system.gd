extends Node
## Generic save/load mechanism (gd-common). Autoload: SaveSystem.
## Persists arbitrary Dictionaries to user:// slots. Knows nothing about game data.
## The consuming project's GameData builds the Dictionary and calls save/load.

signal saved(slot: int)
signal loaded(slot: int)

const SAVE_DIR := "user://saves/"
const SAVE_EXT := ".cfg"
const VERSION_KEY := "__version"
const DATA_SECTION := "data"

## Save format version the project expects. Set via set_version().
var _version: int = 1
## Optional migrator: Callable(data: Dictionary, from_version: int, to_version: int) -> Dictionary
var _migrator: Callable = Callable()


func set_version(version: int) -> void:
	_version = version


func set_migrator(callable: Callable) -> void:
	_migrator = callable


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d" % slot + SAVE_EXT


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Persist a flat Dictionary to a slot. Returns true on success.
func save_to_slot(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var cfg := ConfigFile.new()
	cfg.set_value(DATA_SECTION, VERSION_KEY, _version)
	for key in data:
		cfg.set_value(DATA_SECTION, key, data[key])
	var ok := cfg.save(_slot_path(slot)) == OK
	if ok:
		saved.emit(slot)
	return ok


## Load a slot's data. Returns {} if missing/invalid. Runs the migrator if versions differ.
func load_from_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	if not cfg.has_section(DATA_SECTION):
		return {}
	var data: Dictionary = {}
	for key in cfg.get_section_keys(DATA_SECTION):
		data[key] = cfg.get_value(DATA_SECTION, key)
	# Reject corrupted VERSION_KEY (string, float, etc.). A bad version used to
	# silently coerce to 0, then trigger the migrator with garbage from_version.
	# Using typeof() instead of `is int` for Godot 4.3+ compatibility.
	var raw_version = data.get(VERSION_KEY, 1)
	var from_version: int = 1
	if typeof(raw_version) == TYPE_INT:
		from_version = raw_version
	elif typeof(raw_version) == TYPE_FLOAT and float(raw_version) == floor(float(raw_version)):
		from_version = int(raw_version)
	else:
		push_warning(
			"SaveSystem.load_from_slot: invalid VERSION_KEY %s in slot %d; treating as 1"
			% [raw_version, slot]
		)
	data.erase(VERSION_KEY)
	if from_version != _version and _migrator.is_valid():
		data = _migrator.call(data, from_version, _version)
	loaded.emit(slot)
	return data


func delete_slot(slot: int) -> bool:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path) == OK
	return false


func list_slots() -> Array[int]:
	var slots: Array[int] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return slots
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return slots
	for file in dir.get_files():
		if file.begins_with("slot_") and file.ends_with(SAVE_EXT):
			var num_str := file.trim_prefix("slot_").trim_suffix(SAVE_EXT)
			if num_str.is_valid_int():
				slots.append(num_str.to_int())
	slots.sort()
	return slots
