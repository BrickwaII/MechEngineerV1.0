class_name SoundPlayer
extends Node
## The one sound player. Plays sounds by id from data/feel/audio.json with a
## little pitch and sample variation, and throttles repeats so they never
## stack into noise. The Presentation autoload owns one and registers it as
## SoundPlayer.current, so any screen can call SoundPlayer.fire(&"ui_click").
##
## Headless (tests, CI) it does all the bookkeeping but plays no audio.

## Emitted for every sound that passes the throttle.
signal sound_started(id: StringName, file: String, pitch: float)

static var current: SoundPlayer

var throttle := SoundThrottle.new()
var rng := RandomNumberGenerator.new()
## False when headless; then play() decides but never touches audio.
var audio_enabled := DisplayServer.get_name() != "headless"
## Returns the time in ms; tests swap it for a fake clock.
var clock: Callable = Time.get_ticks_msec

var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_id := &""
var _last_file := {}
var _streams := {}


## Plays `id` on the current sound player, if there is one.
static func fire(id: StringName) -> bool:
	return current.play(id) if is_instance_valid(current) else false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_pool()


## A sound's settings with the defaults filled in, or {} when unknown.
static func sound_def(id: StringName) -> Dictionary:
	var audio := FeelData.audio()
	var sounds: Dictionary = audio.get("sounds", {})
	if not sounds.has(String(id)):
		return {}
	var defaults: Dictionary = audio.get("defaults", {})
	var def: Dictionary = defaults.duplicate(true)
	def.merge(sounds[String(id)], true)
	var throttle_def: Dictionary = defaults.get("throttle", {}).duplicate()
	throttle_def.merge(def.get("throttle", {}), true)
	def["throttle"] = throttle_def
	return def


## Starts `id` unless the throttle drops it. True when it started.
func play(id: StringName) -> bool:
	var def := sound_def(id)
	if def.is_empty():
		push_warning("SoundPlayer: unknown sound '%s'" % id)
		return false
	var limits: Dictionary = def["throttle"]
	if not throttle.try_start(id, clock.call(), int(limits.get("max", 2)), int(limits.get("window_ms", 90))):
		return false
	var file := _pick_file(id, def.get("files", []))
	var variation := float(def.get("pitch_variation", 0.0))
	var pitch := 1.0 + rng.randf_range(-variation, variation)
	sound_started.emit(id, file, pitch)
	if audio_enabled and not file.is_empty():
		var player := _free_player()
		player.stream = _stream(file)
		player.bus = def.get("bus", "Master")
		player.volume_db = float(def.get("volume_db", 0.0))
		player.pitch_scale = pitch
		player.play()
	return true


## Loops a music track from audio.json "music" on the Music bus.
func play_music(id: StringName) -> void:
	var tracks: Dictionary = FeelData.audio().get("music", {})
	if not tracks.has(String(id)) or _music_id == id:
		return
	_music_id = id
	if not audio_enabled:
		return
	var track: Dictionary = tracks[String(id)]
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.bus = "Music"
		add_child(_music)
	var stream: AudioStream = _stream(track["file"])
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music.stream = stream
	_music.volume_db = float(track.get("volume_db", 0.0))
	_music.play()


func stop_music() -> void:
	_music_id = &""
	if _music != null:
		_music.stop()


func music_id() -> StringName:
	return _music_id


## Several files: a random one, never the one played last time.
func _pick_file(id: StringName, files: Array) -> String:
	if files.is_empty():
		return ""
	var choices := files.duplicate()
	if choices.size() > 1:
		choices.erase(_last_file.get(id, ""))
	var file: String = choices[rng.randi_range(0, choices.size() - 1)]
	_last_file[id] = file
	return file


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_streams[file] = load(file)
	return _streams[file]


func _ensure_pool() -> void:
	if not _players.is_empty():
		return
	for i in int(FeelData.audio().get("voices", 12)):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## A free voice, or the one that has played longest when all are busy.
func _free_player() -> AudioStreamPlayer:
	_ensure_pool()
	var oldest := _players[0]
	for player in _players:
		if not player.playing:
			return player
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest
