extends Node
## Generic audio playback (gd-common). Autoload: AudioManager.
## SFX via a small player pool; music on a dedicated player with optional fade.
## Audio *assets* stay in the consuming project; pass AudioStreams in.

const SFX_POOL_SIZE := 8
const SILENCE_DB := -60.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)


func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player := _get_free_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]  # all busy: reuse the first


func play_music(stream: AudioStream, fade_sec: float = 0.0, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if fade_sec <= 0.0:
		_music_player.stream = stream
		_music_player.volume_db = volume_db
		_music_player.play()
		return
	_music_player.stream = stream
	_music_player.volume_db = SILENCE_DB
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", volume_db, fade_sec)


func stop_music(fade_sec: float = 0.0) -> void:
	if fade_sec <= 0.0:
		_music_player.stop()
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", SILENCE_DB, fade_sec)
	_music_tween.tween_callback(_music_player.stop)


func set_bus_volume_db(bus_name: String, volume_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db)
