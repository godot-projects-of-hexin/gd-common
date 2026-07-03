extends SceneTree

func _init() -> void:
	var failures: int = 0
	failures += _t_sfx_root_inherit()
	failures += _t_music_root_always()
	failures += _t_pause_music_silences()
	failures += _t_resume_music_restores()
	failures += _t_double_pause_no_op()
	failures += _t_play_music_clears_pause_flag()
	failures += _t_stop_all_sfx_stops_playing_ones()
	if failures > 0:
		print("SOUND_MANAGER_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("SOUND_MANAGER_TEST: all passed")
		quit(0)

func _make_manager() -> Node:
	var sm_script: Script = load("res://addons/gd-common/audio/sound_manager.gd")
	var sm: Node = sm_script.new()
	root.add_child(sm)
	return sm

func _t_sfx_root_inherit() -> int:
	var sm := _make_manager()
	var sfx_root: Node = sm.get_node("SfxRoot")
	if sfx_root.process_mode != Node.PROCESS_MODE_INHERIT: return 1
	return 0

func _t_music_root_always() -> int:
	var sm := _make_manager()
	var music_root: Node = sm.get_node("MusicRoot")
	if music_root.process_mode != Node.PROCESS_MODE_ALWAYS: return 1
	return 0

func _t_pause_music_silences() -> int:
	var sm := _make_manager()
	sm._music_player.volume_db = 0.0
	sm.pause_music(0.0)
	if not sm.is_music_paused(): return 1
	if abs(sm._music_player.volume_db - sm.SILENCE_DB) > 0.01: return 1
	return 0

func _t_resume_music_restores() -> int:
	var sm := _make_manager()
	sm._music_player.volume_db = -3.0
	sm.pause_music(0.0)
	sm.resume_music(0.0)
	if sm.is_music_paused(): return 1
	if abs(sm._music_player.volume_db - (-3.0)) > 0.01: return 1
	return 0

func _t_double_pause_no_op() -> int:
	var sm := _make_manager()
	sm._music_player.volume_db = -1.0
	sm.pause_music(0.0)
	sm.pause_music(0.0)
	sm.resume_music(0.0)
	if abs(sm._music_player.volume_db - (-1.0)) > 0.01: return 1
	return 0

func _t_play_music_clears_pause_flag() -> int:
	var sm := _make_manager()
	sm._music_player.volume_db = -3.0
	sm.pause_music(0.0)
	if not sm.is_music_paused(): return 1
	sm._music_paused_via_api = true
	var stream := AudioStreamGenerator.new()
	sm.play_music(stream, 0.0)
	if sm.is_music_paused(): return 1
	sm._music_player.stop()
	return 0

func _t_stop_all_sfx_stops_playing_ones() -> int:
	var sm := _make_manager()
	var p: AudioStreamPlayer = sm._sfx_players[0]
	var s := AudioStreamGenerator.new()
	p.stream = s
	p.play()
	if not p.playing: return 1
	sm.stop_all_sfx()
	if p.playing: return 1
	return 0
