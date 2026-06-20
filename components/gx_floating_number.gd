class_name GxFloatingNumber
extends CanvasLayer
## Generic floating number display for Godot 4 (gd-common).
## Instantiate once (set layer as needed), then call spawn() anywhere.
## Each call creates a self-destructing Label with pop→float→wobble→fade animation.

enum Preset { DEFAULT, DAMAGE, HEAL, CRITICAL, MUTED }

const PRESET_CFG := {
	Preset.DEFAULT:  {color = Color(0.95, 0.95, 0.95), scale_start = 1.6, font_size = 18, float_distance = 40.0, wobble = 10.0},
	Preset.DAMAGE:   {color = Color(1.0,  0.25, 0.25), scale_start = 1.5, font_size = 20, float_distance = 40.0, wobble = 10.0},
	Preset.HEAL:     {color = Color(0.25, 1.0,  0.35), scale_start = 1.4, font_size = 18, float_distance = 38.0, wobble = 10.0},
	Preset.CRITICAL: {color = Color(1.0,  0.6,  0.0),  scale_start = 2.5, font_size = 28, float_distance = 60.0, wobble = 20.0},
	Preset.MUTED:    {color = Color(0.55, 0.55, 0.55), scale_start = 1.2, font_size = 16, float_distance = 30.0, wobble = 6.0},
}

const DEFAULT_DURATION := 0.8


## Spawn a floating number using a preset style. Pass overrides to tweak individual params.
func spawn(pos: Vector2, text: String, preset: Preset = Preset.DEFAULT, overrides: Dictionary = {}) -> void:
	var cfg: Dictionary = PRESET_CFG[preset].duplicate()
	cfg.merge(overrides)
	_emit(pos, text, cfg)


## Spawn a floating number with fully custom config.
## cfg keys: color (Color), font_size (int), scale_start (float),
##            float_distance (float), wobble (float), duration (float).
func spawn_custom(pos: Vector2, text: String, cfg: Dictionary) -> void:
	_emit(pos, text, cfg)


func _emit(pos: Vector2, text: String, cfg: Dictionary) -> void:
	var duration: float = cfg.get("duration", DEFAULT_DURATION)
	var color: Color = cfg.get("color", Color.WHITE)
	var font_size: int = cfg.get("font_size", 18)
	var scale_start: float = cfg.get("scale_start", 1.6)
	var float_dist: float = cfg.get("float_distance", 40.0)
	var wobble: float = cfg.get("wobble", 10.0)

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100

	add_child(label)
	label.reset_size()
	label.position = pos - label.size * 0.5
	label.pivot_offset = label.size * 0.5

	_play_animation(label, label.position, scale_start, float_dist, wobble, duration)


func _play_animation(label: Label, start_pos: Vector2, scale_start: float, float_dist: float, wobble: float, duration: float) -> void:
	label.scale = Vector2(scale_start, scale_start)

	var tw := create_tween().set_parallel()

	# Phase 1: pop-in (scale overshoot then settle, 0.12s)
	tw.tween_property(label, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Phase 2: float upward (full duration)
	tw.tween_property(label, "position:y", start_pos.y - float_dist, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 3: horizontal wobble (full duration)
	tw.tween_property(label, "position:x", start_pos.x + randf_range(-wobble, wobble), duration) \
		.set_trans(Tween.TRANS_SINE)

	# Phase 4: fade out (delayed, last 60% of duration)
	tw.tween_property(label, "modulate:a", 0.0, duration * 0.6) \
		.set_delay(duration * 0.4)

	# Cleanup
	tw.tween_callback(label.queue_free).set_delay(duration)
