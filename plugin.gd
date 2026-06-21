@tool
extends EditorPlugin
## gd-common addon entry point.
## Registers shared autoload singletons when the plugin is enabled.

const AUTOLOADS := {
	"EventBus": "res://addons/gd-common/core/event_bus.gd",
	"SaveSystem": "res://addons/gd-common/core/save_system.gd",
	"SoundManager": "res://addons/gd-common/audio/sound_manager.gd",
	"UIManager": "res://addons/gd-common/core/ui_manager.gd",
}

func _enter_tree() -> void:
	for singleton_name in AUTOLOADS:
		if not ProjectSettings.has_setting("autoload/" + singleton_name):
			add_autoload_singleton(singleton_name, AUTOLOADS[singleton_name])


func _exit_tree() -> void:
	for singleton_name in AUTOLOADS:
		if ProjectSettings.has_setting("autoload/" + singleton_name):
			remove_autoload_singleton(singleton_name)
