extends Node
## Autoload: AudioManager — generic playback for SFX, music and ambient loops.
##
## The project owns its audio [b]assets[/b]; this manager owns the [b]players[/b].
## Pass [AudioStream] objects in, never resource paths, so the shared library
## never needs to know your folder layout:
## [codeblock]
## AudioManager.play_sfx(load("res://assets/audio/ui_click.wav"))
## AudioManager.play_music(load("res://assets/audio/title.ogg"), 1.5)
## AudioManager.play_ambient(load("res://assets/audio/rain.ogg"), 2.0)
## [/codeblock]
## In practice a project adds a thin registry of its own that maps keys to
## streams, and calls this manager from there.
##
## [b]Pause behaviour[/b] is the reason the players are split across three
## roots. When [code]get_tree().paused[/code] becomes true — a pause menu
## opening — SFX and ambient must go quiet, while a music fade has to keep
## ticking or it freezes half-way through. So:
## [codeblock]
## SfxRoot      PROCESS_MODE_PAUSABLE   pauses with the tree
## AmbientRoot  PROCESS_MODE_PAUSABLE   pauses with the tree
## MusicRoot    PROCESS_MODE_ALWAYS     keeps running; use pause_music()
## [/codeblock]
##
## Looping is driven manually from the [signal AudioStreamPlayer.finished]
## signal, so the manager never mutates a shared [AudioStream] resource. For
## gapless loops, enable looping in the stream's import settings as well.

## Emitted when a new music track starts fading in.
signal music_started(stream: AudioStream)
## Emitted after music has fully stopped.
signal music_stopped
## Emitted when music is paused by [method pause_music].
signal music_paused
## Emitted when music is resumed by [method resume_music].
signal music_resumed

## Concurrent one-shot SFX. When all are busy the oldest is preempted, which
## is the right trade-off for short UI and impact sounds. Long sounds belong
## in [method play_ambient], which gets a dedicated player.
const SFX_SLOTS := 8
## Volume treated as silence by fades.
const SILENT_DB := -60.0
const FALLBACK_BUS := &"Master"

var _sfx_root: Node
var _music_root: Node
var _ambient_root: Node

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next_slot := 0

var _music_players: Array[AudioStreamPlayer] = []
var _music_index := 0
var _music_volume_db := 0.0
var _music_loop := true
var _is_music_paused := false

var _ambient_players: Dictionary = {}  # StringName -> AudioStreamPlayer
var _ambient_volume_db := 0.0

var _sfx_bus: StringName = FALLBACK_BUS
var _music_bus: StringName = FALLBACK_BUS
var _ambient_bus: StringName = FALLBACK_BUS

var _tweens: Dictionary = {}  # int (player instance id) -> Tween


static func _stream_key(stream: AudioStream) -> StringName:
	if not stream.resource_path.is_empty():
		return StringName(stream.resource_path)
	return StringName(str(stream.get_instance_id()))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx_root = _make_root("SfxRoot", Node.PROCESS_MODE_PAUSABLE)
	_ambient_root = _make_root("AmbientRoot", Node.PROCESS_MODE_PAUSABLE)
	_music_root = _make_root("MusicRoot", Node.PROCESS_MODE_ALWAYS)
	for index in SFX_SLOTS:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		player.bus = _sfx_bus
		_sfx_root.add_child(player)
		_sfx_players.append(player)
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.bus = _music_bus
		player.finished.connect(_on_music_finished.bind(player))
		_music_root.add_child(player)
		_music_players.append(player)


# --- buses -------------------------------------------------------------------

## Route players to project audio buses. Unknown bus names fall back to
## [constant FALLBACK_BUS] with a warning instead of silently losing audio.
func set_buses(sfx_bus: StringName, music_bus: StringName, ambient_bus: StringName) -> void:
	_sfx_bus = _validate_bus(sfx_bus)
	_music_bus = _validate_bus(music_bus)
	_ambient_bus = _validate_bus(ambient_bus)
	for player in _sfx_players:
		player.bus = _sfx_bus
	for player in _music_players:
		player.bus = _music_bus
	for key in _ambient_players:
		(_ambient_players[key] as AudioStreamPlayer).bus = _ambient_bus


# --- sound effects -----------------------------------------------------------

## Play a one-shot sound effect. Returns the player, or null when the stream
## is missing — a null stream is a loading mistake, not a silent no-op.
func play_sfx(
		stream: AudioStream,
		volume_db: float = 0.0,
		pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if stream == null:
		push_error("AudioManager.play_sfx: stream is null")
		return null
	var player := _take_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Play a sound effect with a randomized pitch, so repeated hits of the same
## clip do not sound mechanical.
func play_sfx_varied(
		stream: AudioStream,
		pitch_min: float = 0.95,
		pitch_max: float = 1.05,
		volume_db: float = 0.0) -> AudioStreamPlayer:
	return play_sfx(stream, volume_db, randf_range(pitch_min, pitch_max))


## Stop every sound effect currently playing.
func stop_all_sfx() -> void:
	for player in _sfx_players:
		if player.playing:
			player.stop()


# --- music -------------------------------------------------------------------

## Crossfade to a new music track. Calling this with the track that is already
## playing does nothing, so it is safe to call on every scene load.
## Also clears the paused flag set by [method pause_music].
func play_music(stream: AudioStream, fade_duration: float = 1.0, loop: bool = true) -> void:
	if stream == null:
		push_error("AudioManager.play_music: stream is null")
		return
	var current := _current_music_player()
	if current != null and current.stream == stream and current.playing and not _is_music_paused:
		return
	_music_loop = loop
	_is_music_paused = false
	var incoming := _music_players[1 - _music_index]
	_music_index = 1 - _music_index
	incoming.stream = stream
	incoming.stream_paused = false
	incoming.volume_db = SILENT_DB if fade_duration > 0.0 else _music_volume_db
	incoming.play()
	if fade_duration > 0.0:
		_fade_to(incoming, _music_volume_db, fade_duration)
	if current != null and current.playing:
		_fade_out_and_stop(current, fade_duration)
	music_started.emit(stream)


## Fade music out and stop it. The stream reference is released so the next
## [method play_music] with the same track starts from the beginning.
func stop_music(fade_duration: float = 1.0) -> void:
	var current := _current_music_player()
	if current == null or not current.playing:
		return
	_is_music_paused = false
	_fade_out_and_stop(current, fade_duration, true)


## Fade to silence and pause, keeping the playhead. Idempotent.
func pause_music(fade_duration: float = 0.0) -> void:
	if _is_music_paused:
		return
	var current := _current_music_player()
	if current == null or not current.playing:
		return
	_is_music_paused = true
	if fade_duration > 0.0:
		var tween := _fade_to(current, SILENT_DB, fade_duration)
		if tween != null:
			tween.finished.connect(func() -> void:
				if _is_music_paused and is_instance_valid(current):
					current.stream_paused = true
			)
	else:
		current.volume_db = SILENT_DB
		current.stream_paused = true
	music_paused.emit()


## Resume from where [method pause_music] left off. Idempotent.
func resume_music(fade_duration: float = 0.0) -> void:
	if not _is_music_paused:
		return
	var current := _current_music_player()
	if current == null:
		_is_music_paused = false
		return
	_is_music_paused = false
	current.stream_paused = false
	if fade_duration > 0.0:
		_fade_to(current, _music_volume_db, fade_duration)
	else:
		current.volume_db = _music_volume_db
	music_resumed.emit()


## Target volume music fades back to. Applied immediately when music is active
## and not paused.
func set_music_volume_db(volume_db: float) -> void:
	_music_volume_db = volume_db
	var current := _current_music_player()
	if current != null and current.playing and not _is_music_paused:
		current.volume_db = volume_db


## True while a music track is loaded and playing, including while paused.
func is_music_playing() -> bool:
	var current := _current_music_player()
	return current != null and current.playing


## True between [method pause_music] and [method resume_music].
func is_music_paused() -> bool:
	return _is_music_paused


## The stream currently assigned to the active music player, or null.
func current_music() -> AudioStream:
	var current := _current_music_player()
	return current.stream if current != null else null


# --- ambient loops -----------------------------------------------------------

## Start a looping ambient sound on its own player. Ambients are keyed so they
## can be stopped individually; the key defaults to the stream's resource path.
## Calling this for an already-playing key restarts that ambient.
func play_ambient(
		stream: AudioStream,
		fade_duration: float = 1.0,
		key: StringName = &"") -> AudioStreamPlayer:
	if stream == null:
		push_error("AudioManager.play_ambient: stream is null")
		return null
	var resolved_key := key if key != &"" else _stream_key(stream)
	stop_ambient(resolved_key, 0.0)
	var player := AudioStreamPlayer.new()
	player.name = "Ambient_%s" % resolved_key
	player.bus = _ambient_bus
	player.stream = stream
	player.volume_db = SILENT_DB if fade_duration > 0.0 else _ambient_volume_db
	_ambient_root.add_child(player)
	player.finished.connect(_on_ambient_finished.bind(player))
	player.play()
	_ambient_players[resolved_key] = player
	if fade_duration > 0.0:
		_fade_to(player, _ambient_volume_db, fade_duration)
	return player


## Fade out and free one ambient player.
func stop_ambient(key: StringName, fade_duration: float = 1.0) -> void:
	if not _ambient_players.has(key):
		return
	var player := _ambient_players[key] as AudioStreamPlayer
	_ambient_players.erase(key)
	if player == null or not is_instance_valid(player):
		return
	if fade_duration <= 0.0:
		_kill_tween(player)
		player.queue_free()
		return
	var tween := _fade_to(player, SILENT_DB, fade_duration)
	if tween == null:
		player.queue_free()
		return
	tween.finished.connect(func() -> void:
		if is_instance_valid(player):
			player.queue_free()
	)


## Fade out and free every ambient player. Call this on scene transitions.
func stop_all_ambient(fade_duration: float = 1.0) -> void:
	for key in _ambient_players.keys():
		stop_ambient(key as StringName, fade_duration)


## Keys of the ambients currently playing.
func active_ambient_keys() -> Array:
	return _ambient_players.keys()


# --- everything --------------------------------------------------------------

## Stop music, SFX and ambient in one call.
func stop_all(fade_duration: float = 0.5) -> void:
	stop_music(fade_duration)
	stop_all_ambient(fade_duration)
	stop_all_sfx()


# --- internals ---------------------------------------------------------------

func _make_root(root_name: String, mode: Node.ProcessMode) -> Node:
	var root := Node.new()
	root.name = root_name
	root.process_mode = mode
	add_child(root)
	return root


func _validate_bus(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return bus_name
	push_warning("AudioManager: bus '%s' not found; using '%s'" % [bus_name, FALLBACK_BUS])
	return FALLBACK_BUS


func _take_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	var preempted := _sfx_players[_sfx_next_slot]
	_sfx_next_slot = (_sfx_next_slot + 1) % _sfx_players.size()
	return preempted


func _current_music_player() -> AudioStreamPlayer:
	if _music_players.is_empty():
		return null
	return _music_players[_music_index]


func _fade_to(player: AudioStreamPlayer, target_db: float, duration: float) -> Tween:
	if player == null or not is_instance_valid(player):
		return null
	_kill_tween(player)
	# Bound to the player, so the fade inherits that player's process mode:
	# music fades keep running while the tree is paused, SFX fades do not.
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", target_db, duration)
	_tweens[player.get_instance_id()] = tween
	return tween


func _fade_out_and_stop(player: AudioStreamPlayer, duration: float, release: bool = false) -> void:
	if duration <= 0.0:
		_kill_tween(player)
		player.stop()
		if release:
			player.stream = null
		music_stopped.emit()
		return
	var tween := _fade_to(player, SILENT_DB, duration)
	if tween == null:
		return
	tween.finished.connect(func() -> void:
		if not is_instance_valid(player):
			return
		player.stop()
		if release:
			player.stream = null
		music_stopped.emit()
	)


func _kill_tween(player: AudioStreamPlayer) -> void:
	var id := player.get_instance_id()
	if not _tweens.has(id):
		return
	var tween := _tweens[id] as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens.erase(id)


func _on_music_finished(player: AudioStreamPlayer) -> void:
	if not _music_loop or _is_music_paused:
		return
	if player != _current_music_player() or player.stream == null:
		return
	player.play()


func _on_ambient_finished(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player) or player.stream == null:
		return
	if not _ambient_players.values().has(player):
		return
	player.play()
