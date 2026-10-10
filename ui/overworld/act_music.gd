class_name ActMusic
extends Node
## The map's music: one generated loop per act (data/feel/screens.json
## "music.acts", tracks in data/feel/audio.json "music"), crossfaded over
## music.crossfade_ms when the act changes. Two players on the Music bus take
## turns; the outgoing one fades to silence and stops.
##
## Headless (tests, CI) it keeps track of what would play and the fade, but
## touches no audio.

var settings: GameSettings
## False when headless; then nothing plays.
var audio_enabled := DisplayServer.get_name() != "headless"

## The track id playing (or fading in), or "".
var track := ""
## 0 when a crossfade starts, 1 when it is done.
var fade := 1.0

var _players: Array[AudioStreamPlayer] = []
## Index into _players of the incoming track.
var _current := 0
var _volumes := [0.0, 0.0]


## The track for an act (0-based); the last one repeats for later acts.
static func track_for_act(act: int) -> String:
	var acts: Array = ScreenFeel.value("music.acts", [])
	if acts.is_empty():
		return ""
	return acts[clampi(act, 0, acts.size() - 1)]


func play_act(act: int) -> void:
	play(track_for_act(act))


## Crossfades to `id`. Playing the track already playing does nothing.
func play(id: String) -> void:
	if id == track or id.is_empty():
		return
	var tracks: Dictionary = FeelData.audio().get("music", {})
	if not tracks.has(id):
		push_warning("ActMusic: no music track '%s'" % id)
		return
	var first := track.is_empty()
	track = id
	_current = 1 - _current
	fade = 1.0 if first else 0.0
	if audio_enabled:
		_ensure_players()
		var player := _players[_current]
		var stream: AudioStream = load(tracks[id]["file"])
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player.stream = stream
		_volumes[_current] = float(tracks[id].get("volume_db", 0.0))
		player.play()
	_apply()
	set_process(fade < 1.0)


func stop() -> void:
	track = ""
	fade = 1.0
	for player in _players:
		player.stop()


func _process(delta: float) -> void:
	advance(delta)


## Moves the crossfade forward by `delta` seconds.
func advance(delta: float) -> void:
	if fade >= 1.0:
		set_process(false)
		return
	var duration := (settings if settings else GameSettings.shared()).scale_seconds(
		ScreenFeel.number("music.crossfade_ms") / 1000.0)
	fade = 1.0 if duration <= 0.0 else minf(fade + delta / duration, 1.0)
	_apply()
	if fade >= 1.0:
		if audio_enabled and not _players.is_empty():
			_players[1 - _current].stop()
		set_process(false)


## The incoming and outgoing volumes in dB for the fade so far: an
## equal-power curve, so the mix does not dip in the middle.
func volumes_db() -> Vector2:
	var silent := ScreenFeel.number("music.silent_db", -60.0)
	var incoming := sin(fade * PI / 2.0)
	var outgoing := cos(fade * PI / 2.0)
	return Vector2(
		maxf(_volumes[_current] + linear_to_db(maxf(incoming, 0.0001)), silent),
		maxf(_volumes[1 - _current] + linear_to_db(maxf(outgoing, 0.0001)), silent))


func _apply() -> void:
	if not audio_enabled or _players.is_empty():
		return
	var v := volumes_db()
	_players[_current].volume_db = v.x
	_players[1 - _current].volume_db = v.y


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		_players.append(player)
