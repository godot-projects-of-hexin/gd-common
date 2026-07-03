extends Node
## Generic audio playback (gd-common). Autoload: SoundManager.
## SFX via 8-channel pool; music on a dedicated player with fade;
## ambient sounds on independent players.
## Audio *assets* stay in the consuming project; pass AudioStreams in.
##
## Process-mode split:
##   * SFX / Ambient containers follow the host (PROCESS_MODE_INHERIT) —
##     they pause when get_tree().paused = true.
##   * Music container is PROCESS_MODE_ALWAYS so fade/cross-fade
##     keeps ticking even during pause; use pause_music() to silence it.

const SFX_POOL_SIZE := 8
const SILENCE_DB := -60.0

signal music_paused
signal music_resumed

var _sfx_root: Node
var _music_root: Node
var _ambient_root: Node
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_tween: Tween
var _music_paused_via_api: bool = false
var _music_volume_before_pause: float = 0.0
var _ambient_players: Dictionary = {}  # String (resource_path or instance_id) -> AudioStreamPlayer


func _ready() -> void:
	_ensure_roots()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		_sfx_root.add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_root.add_child(_music_player)


func _ensure_roots() -> void:
	if _sfx_root == null:
		_sfx_root = Node.new()
		_sfx_root.name = "SfxRoot"
		_sfx_root.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(_sfx_root)
	if _ambient_root == null:
		_ambient_root = Node.new()
		_ambient_root.name = "AmbientRoot"
		_ambient_root.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(_ambient_root)
	if _music_root == null:
		_music_root = Node.new()
		_music_root.name = "MusicRoot"
		_music_root.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_root)


# ---- SFX (short one-shot sounds) ----

func play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := _get_free_sfx_player()
	player.stream = stream
	player.volume_db = 0.0
	player.pitch_scale = 1.0
	player.play()


func play_ui_sound(stream: AudioStream) -> void:
	play_sound(stream)


func stop_all_sfx() -> void:
	for p in _sfx_players:
		if p.playing:
			p.stop()


func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]  # all busy: preempt the oldest


# ---- Music ----

func play_music(stream: AudioStream, crossfade: float = 1.5) -> void:
	if stream == null:
		return
	_music_paused_via_api = false
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if crossfade <= 0.0:
		_music_player.stream = stream
		_music_player.volume_db = 0.0
		_music_player.play()
		return
	_music_player.stream = stream
	_music_player.volume_db = SILENCE_DB
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", 0.0, crossfade)


func stop_music(fade: float = 1.5) -> void:
	_music_paused_via_api = false
	if fade <= 0.0:
		_music_player.stop()
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", SILENCE_DB, fade)
	_music_tween.tween_callback(_music_player.stop)


func pause_music(fade: float = 0.0) -> void:
	if _music_paused_via_api:
		return
	_music_paused_via_api = true
	_music_volume_before_pause = _music_player.volume_db
	_fade_music_to(SILENCE_DB, fade)
	music_paused.emit()


func resume_music(fade: float = 0.0) -> void:
	if not _music_paused_via_api:
		return
	_music_paused_via_api = false
	var target_db: float = _music_volume_before_pause
	if target_db <= SILENCE_DB + 0.01:
		target_db = 0.0
	_fade_music_to(target_db, fade)
	music_resumed.emit()


func is_music_paused() -> bool:
	return _music_paused_via_api


func _fade_music_to(target_db: float, fade: float) -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if fade <= 0.0:
		_music_player.volume_db = target_db
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, fade)


func set_bus_volume_db(bus_name: String, volume_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db)


# ---- Ambient (long looping background sounds) ----

func _ambient_key(stream: AudioStream) -> String:
	if stream.resource_path != "":
		return stream.resource_path
	return str(stream.get_instance_id())


func play_ambient_sound(stream: AudioStream, fade: float = 2.0) -> void:
	if stream == null:
		return
	var key := _ambient_key(stream)
	if _ambient_players.has(key):
		var existing: AudioStreamPlayer = _ambient_players[key]
		if existing.playing:
			return
		existing.queue_free()
		_ambient_players.erase(key)
	_fade_in_ambient(stream, fade)


func _fade_in_ambient(stream: AudioStream, fade: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Master"
	_ambient_root.add_child(player)
	_ambient_players[_ambient_key(stream)] = player
	if fade <= 0.0:
		player.volume_db = 0.0
		player.play()
		return
	player.volume_db = SILENCE_DB
	player.play()
	var tw := create_tween()
	tw.tween_property(player, "volume_db", 0.0, fade)


func stop_ambient_sound(stream: AudioStream, fade: float = 1.5) -> void:
	if stream == null:
		return
	var key := _ambient_key(stream)
	if not _ambient_players.has(key):
		return
	var player: AudioStreamPlayer = _ambient_players[key]
	_ambient_players.erase(key)
	_fade_out_and_free(player, fade)


func stop_all_ambient_sounds(fade: float = 1.5) -> void:
	for player: AudioStreamPlayer in _ambient_players.values():
		_fade_out_and_free(player, fade)
	_ambient_players.clear()


func _fade_out_and_free(player: AudioStreamPlayer, fade: float) -> void:
	if not is_instance_valid(player):
		return
	if fade <= 0.0:
		player.stop()
		player.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(player, "volume_db", SILENCE_DB, fade)
	tw.tween_callback(player.stop)
	tw.tween_callback(player.queue_free)
