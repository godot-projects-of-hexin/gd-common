@tool
extends EditorPlugin
## gd-common addon entry point.
##
## Registers the shared autoload singletons when the plugin is enabled, and
## removes only the ones it actually added when disabled — a project that
## already defines its own [code]EventBus[/code] keeps it either way.
##
## The architecture layer ([GxArchitecture] and friends) is deliberately
## [b]not[/b] an autoload: a global handle every node can reach would defeat
## the layering rules. Projects expose one architecture instance through a
## static accessor instead. See [code]agent.md[/code].

const AUTOLOADS := {
	"EventBus": "res://addons/gd-common/core/event_bus.gd",
	"SaveSystem": "res://addons/gd-common/core/save_system.gd",
	"AudioManager": "res://addons/gd-common/audio/audio_manager.gd",
	"UIManager": "res://addons/gd-common/core/ui_manager.gd",
}

var _added_autoloads: Array[String] = []


func _enter_tree() -> void:
	_added_autoloads.clear()
	for singleton_name: String in AUTOLOADS:
		if ProjectSettings.has_setting("autoload/" + singleton_name):
			push_warning(
				"gd-common: autoload '%s' already exists; keeping the project's own."
				% singleton_name
			)
			continue
		add_autoload_singleton(singleton_name, String(AUTOLOADS[singleton_name]))
		_added_autoloads.append(singleton_name)


func _exit_tree() -> void:
	# Remove only what this plugin added, so disabling the addon can never
	# delete an autoload the project declared itself.
	for singleton_name: String in _added_autoloads:
		if ProjectSettings.has_setting("autoload/" + singleton_name):
			remove_autoload_singleton(singleton_name)
	_added_autoloads.clear()
