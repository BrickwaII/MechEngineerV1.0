class_name MusicDirector
extends Node
## The one music player of the game: crossfades between contexts as the
## screen changes. Contexts, their tracks and the fade times are in
## data/feel/audio.json "music_director"; the map's per-act loops are
## data/feel/screens.json "music.acts".
##
##   menu      the draft and other menus
##   map       the overworld, one loop per act; an act change crossfades over
##             screens.json music.crossfade_ms
##   battle    the battle screen; boss_battle picks the boss variant
##   readout   the post-fight readout and level-ups, a short bright loop
##   victory, defeat   stings when the run is won or lost; played once
##
## The autoload Presentation owns the one director (MusicDirector.current).
## RunFlow's stage_changed drives it through follow_stage() (stage names map
## to contexts in "stages"); the overworld calls play_map() with its act, sets
## boss_battle before the boss fight and plays the run-end stings.
##
## Two players on the Music bus take turns, so the music follows the music
## volume setting. Headless (tests, CI) it keeps track of what would play and
## the fade, but touches no audio.

const SCREENS_PATH := "res://data/feel/screens.json"

const MENU := "menu"
const MAP := "map"
const BATTLE := "battle"
const READOUT := "readout"
const VICTORY := "victory"
const DEFEAT := "defeat"

## The game's director, registered by Presentation.
static var current: MusicDirector

var settings: GameSettings
## False when headless; then nothing plays.
var audio_enabled := DisplayServer.get_name() != "headless"

## The context playing, or "".
var context := ""
## The track id playing (or fading in), or "".
var track := ""
## 0 when a crossfade starts, 1 when it is done.
var fade := 1.0
## The act whose loop the map context plays (0-based).
var act := 0
## True while the next or current battle is the boss fight.
var boss_battle := false

var _fade_seconds := 0.0
var _players: Array[AudioStreamPlayer] = []
## Index into _players of the incoming track.
var _current := 0
var _volumes := [0.0, 0.0]


## Plays the context RunFlow's stage `stage_name` ("MAP", "FIGHT", ...) maps
## to, on the game's director. Unknown stages change nothing.
static func follow_stage(stage_name: String) -> void:
	if current != null:
		current.show_stage(stage_name)


static func config() -> Dictionary:
	return FeelData.audio().get("music_director", {})


## The map loop for an act (0-based); the last one repeats for later acts.
static func track_for_act(p_act: int) -> String:
	var acts: Array = FeelData.table(SCREENS_PATH).get("music", {}).get("acts", [])
	if acts.is_empty():
		return ""
	return acts[clampi(p_act, 0, acts.size() - 1)]


func show_stage(stage_name: String) -> void:
	var name := str(config().get("stages", {}).get(stage_name, ""))
	if not name.is_empty():
		play_context(name)


## Plays the map with `p_act`'s loop.
func play_map(p_act: int) -> void:
	act = p_act
	play_context(MAP)


## The track a context plays now, or "" for none.
func track_for(name: String) -> String:
	if name == MAP:
		return track_for_act(act)
	var c: Dictionary = config().get("contexts", {}).get(name, {})
	if name == BATTLE and boss_battle and c.has("boss_track"):
		return str(c["boss_track"])
	return str(c.get("track", ""))


func is_sting(name: String) -> bool:
	return bool(config().get("contexts", {}).get(name, {}).get("sting", false))


## Crossfades to `name`'s track. The boss flag clears once a battle is over.
## A sting already playing is not started again.
func play_context(name: String) -> void:
	if name == context and is_sting(name):
		return
	if context == BATTLE and name != BATTLE:
		boss_battle = false
	var from := track
	var was_map := context == MAP
	context = name
	var id := track_for(name)
	if id.is_empty():
		return
	var ms := float(config().get("crossfade_ms", 0.0))
	if is_sting(name):
		ms = float(config().get("sting_fade_ms", 0.0))
	elif was_map and name == MAP and not from.is_empty():
		ms = float(FeelData.table(SCREENS_PATH).get("music", {}).get("crossfade_ms", ms))
	var replay := is_sting(name)
	play(id, ms / 1000.0, not replay, replay)


## Crossfades to track `id` over `seconds` (scaled by the animation speed).
## The track already playing carries on unless `restart`.
func play(id: String, seconds: float, loop := true, restart := false) -> void:
	if (id == track and not restart) or id.is_empty():
		return
	var tracks: Dictionary = FeelData.audio().get("music", {})
	if not tracks.has(id):
		push_warning("MusicDirector: no music track '%s'" % id)
		return
	var first := track.is_empty()
	track = id
	_current = 1 - _current
	_fade_seconds = _settings().scale_seconds(seconds)
	fade = 1.0 if first or _fade_seconds <= 0.0 else 0.0
	_volumes[_current] = float(tracks[id].get("volume_db", 0.0))
	if audio_enabled:
		_ensure_players()
		var player := _players[_current]
		var stream: AudioStream = load(tracks[id]["file"])
		if stream is AudioStreamWAV:
			stream = stream.duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player.stream = stream
		player.play()
		if fade >= 1.0:
			_players[1 - _current].stop()
	_apply()
	set_process(fade < 1.0)


func stop() -> void:
	track = ""
	context = ""
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
	fade = 1.0 if _fade_seconds <= 0.0 else minf(fade + delta / _fade_seconds, 1.0)
	_apply()
	if fade >= 1.0:
		if audio_enabled and not _players.is_empty():
			_players[1 - _current].stop()
		set_process(false)


## The incoming and outgoing volumes in dB for the fade so far: an
## equal-power curve, so the mix does not dip in the middle.
func volumes_db() -> Vector2:
	var silent := float(config().get("silent_db", -60.0))
	var incoming := sin(fade * PI / 2.0)
	var outgoing := cos(fade * PI / 2.0)
	return Vector2(
		maxf(_volumes[_current] + linear_to_db(maxf(incoming, 0.0001)), silent),
		maxf(_volumes[1 - _current] + linear_to_db(maxf(outgoing, 0.0001)), silent))


## The bus the music plays on (the music volume setting's bus).
static func bus() -> String:
	return str(config().get("bus", "Music"))


func players() -> Array[AudioStreamPlayer]:
	return _players


func _settings() -> GameSettings:
	return settings if settings != null else GameSettings.shared()


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
		player.name = "Music%d" % i
		player.bus = bus()
		add_child(player)
		_players.append(player)
