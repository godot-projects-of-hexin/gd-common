extends SceneTree
## AudioManager tests.
## Run: godot --headless --path . --script res://addons/gd-common/tests/test_audio_manager.gd
##
## The headless audio driver is a dummy device, so these tests assert player
## wiring and state transitions, not audible output.


func _init() -> void:
	var failures := 0
	failures += _t_roots_have_correct_process_modes()
	failures += _t_sfx_pool_is_allocated()
	failures += _t_play_sfx_rejects_null_stream()
	failures += _t_play_sfx_assigns_stream()
	failures += _t_invalid_bus_falls_back_to_master()
	failures += _t_music_starts_and_reports_state()
	failures += _t_play_same_music_is_idempotent()
	failures += _t_pause_and_resume_music()
	failures += _t_pause_music_without_music_is_no_op()
	failures += _t_play_music_clears_pause_flag()
	failures += _t_stop_music_clears_stream()
	failures += _t_ambient_keys_are_tracked()
	failures += _t_stop_all_sfx()
	if failures > 0:
		print("AUDIO_MANAGER_TEST: %d failure(s)" % failures)
		quit(1)
	else:
		print("AUDIO_MANAGER_TEST: all passed")
		quit(0)


func _fail(label: String) -> int:
	print("  FAIL: %s" % label)
	return 1


func _make_manager() -> Node:
	var script: Script = load("res://addons/gd-common/audio/audio_manager.gd")
	var manager: Node = script.new()
	root.add_child(manager)
	return manager


## A minimal valid stream, so play() has something real to attach to.
func _make_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	return stream


func _t_roots_have_correct_process_modes() -> int:
	var manager := _make_manager()
	var sfx_root: Node = manager.get_node_or_null("SfxRoot")
	var ambient_root: Node = manager.get_node_or_null("AmbientRoot")
	var music_root: Node = manager.get_node_or_null("MusicRoot")
	if sfx_root == null or ambient_root == null or music_root == null:
		return _fail("expected SfxRoot, AmbientRoot and MusicRoot children")
	if sfx_root.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return _fail("SfxRoot must be PAUSABLE so SFX go quiet when the tree pauses")
	if ambient_root.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return _fail("AmbientRoot must be PAUSABLE")
	if music_root.process_mode != Node.PROCESS_MODE_ALWAYS:
		return _fail("MusicRoot must be ALWAYS so music fades keep ticking while paused")
	return 0


func _t_sfx_pool_is_allocated() -> int:
	var manager := _make_manager()
	var sfx_root: Node = manager.get_node("SfxRoot")
	if sfx_root.get_child_count() != manager.SFX_SLOTS:
		return _fail("expected %d SFX players, got %d" % [manager.SFX_SLOTS, sfx_root.get_child_count()])
	var music_root: Node = manager.get_node("MusicRoot")
	if music_root.get_child_count() != 2:
		return _fail("expected 2 music players for crossfading, got %d" % music_root.get_child_count())
	return 0


func _t_play_sfx_rejects_null_stream() -> int:
	var manager := _make_manager()
	if manager.play_sfx(null) != null:
		return _fail("play_sfx(null) should return null")
	return 0


func _t_play_sfx_assigns_stream() -> int:
	var manager := _make_manager()
	var stream := _make_stream()
	var player: AudioStreamPlayer = manager.play_sfx(stream, -6.0, 1.2)
	if player == null:
		return _fail("play_sfx returned null for a valid stream")
	if player.stream != stream:
		return _fail("player did not receive the stream")
	if not is_equal_approx(player.volume_db, -6.0):
		return _fail("volume_db was not applied")
	if not is_equal_approx(player.pitch_scale, 1.2):
		return _fail("pitch_scale was not applied")
	return 0


func _t_invalid_bus_falls_back_to_master() -> int:
	var manager := _make_manager()
	manager.set_buses(&"NoSuchBus", &"NoSuchBus", &"NoSuchBus")
	var first_sfx: AudioStreamPlayer = manager.get_node("SfxRoot").get_child(0)
	if first_sfx.bus != manager.FALLBACK_BUS:
		return _fail("unknown bus should fall back to '%s', got '%s'"
			% [manager.FALLBACK_BUS, first_sfx.bus])
	return 0


func _t_music_starts_and_reports_state() -> int:
	var manager := _make_manager()
	var stream := _make_stream()
	manager.play_music(stream, 0.0)
	if not manager.is_music_playing():
		return _fail("is_music_playing() should be true after play_music")
	if manager.current_music() != stream:
		return _fail("current_music() did not return the started stream")
	if manager.is_music_paused():
		return _fail("music should not be paused right after play_music")
	return 0


func _t_play_same_music_is_idempotent() -> int:
	var manager := _make_manager()
	var stream := _make_stream()
	manager.play_music(stream, 0.0)
	var player_before: AudioStream = manager.current_music()
	manager.play_music(stream, 0.0)
	if manager.current_music() != player_before:
		return _fail("replaying the same track should not switch players")
	return 0


func _t_pause_and_resume_music() -> int:
	var manager := _make_manager()
	manager.play_music(_make_stream(), 0.0)
	manager.pause_music(0.0)
	if not manager.is_music_paused():
		return _fail("is_music_paused() should be true after pause_music")
	manager.pause_music(0.0)
	if not manager.is_music_paused():
		return _fail("a second pause_music must be a harmless no-op")
	manager.resume_music(0.0)
	if manager.is_music_paused():
		return _fail("is_music_paused() should be false after resume_music")
	return 0


func _t_pause_music_without_music_is_no_op() -> int:
	var manager := _make_manager()
	manager.pause_music(0.0)
	if manager.is_music_paused():
		return _fail("pausing with no music must not set the paused flag")
	return 0


func _t_play_music_clears_pause_flag() -> int:
	var manager := _make_manager()
	manager.play_music(_make_stream(), 0.0)
	manager.pause_music(0.0)
	manager.play_music(_make_stream(), 0.0)
	if manager.is_music_paused():
		return _fail("play_music must clear the paused flag")
	return 0


func _t_stop_music_clears_stream() -> int:
	var manager := _make_manager()
	manager.play_music(_make_stream(), 0.0)
	manager.stop_music(0.0)
	if manager.is_music_playing():
		return _fail("is_music_playing() should be false after stop_music")
	if manager.current_music() != null:
		return _fail("stop_music should release the stream so the next play restarts it")
	return 0


func _t_ambient_keys_are_tracked() -> int:
	var manager := _make_manager()
	manager.play_ambient(_make_stream(), 0.0, &"rain")
	if not manager.active_ambient_keys().has(&"rain"):
		return _fail("ambient key 'rain' was not tracked")
	manager.stop_ambient(&"rain", 0.0)
	if manager.active_ambient_keys().has(&"rain"):
		return _fail("ambient key 'rain' survived stop_ambient")
	return 0


func _t_stop_all_sfx() -> int:
	var manager := _make_manager()
	manager.play_sfx(_make_stream())
	manager.play_sfx(_make_stream())
	manager.stop_all_sfx()
	for child in manager.get_node("SfxRoot").get_children():
		if (child as AudioStreamPlayer).playing:
			return _fail("stop_all_sfx left a player running")
	return 0
