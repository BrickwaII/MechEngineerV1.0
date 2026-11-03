class_name ActionSharePanel
extends PanelContainer
## Developer panel: the live action-use share of one side of a Fight (combat
## rework S9), this fight and every fight shown since the panel was made. It
## counts nothing itself: every number is FightSummary's (S6), tallied from
## the fight's one combat log, the same count the harness's action-share check
## uses. Shares above the harness's limit (data/scenarios/_harness.json
## max_action_share_percent, the deep dive's "no action best more than about
## half the time") are marked.
##
## Read-only and standalone, like DebugOverlay, so any dev scene can host it
## (the sandbox battle, the battle debug simulator):
##
##   var panel := ActionSharePanel.new()
##   add_child(panel)
##   panel.fight = my_fight     # refreshes as the fight raises events
##   ...
##   panel.fight = next_fight   # a finished fight goes into the session total
##
## Toggle it with F6 (the "toggle_key" property).

const Palette := preload("res://ui/dev/dev_palette.gd")
## Characters in a full share bar (100%).
const BAR_WIDTH := 20

## The fight shown. Setting a new one banks the previous one into the session
## total if it was over.
var fight: Fight:
	set(value):
		if fight == value:
			return
		_bank(fight)
		if fight != null and fight.event_raised.is_connected(_on_event):
			fight.event_raised.disconnect(_on_event)
		fight = value
		if fight != null:
			fight.event_raised.connect(_on_event)
		refresh()
## Whose decisions are counted: a Combatant.Side value.
var side := Combatant.Side.PLAYER
## Shares above this percent are marked.
var limit_percent := 50
var toggle_key := KEY_F6
## Finished fights banked into the session total.
var session_fights := 0
## The side's tally over the banked fights.
var session := FightSummary.Tally.new()

var _text: RichTextLabel
var _banked: Array[Fight] = []
var _dirty := false


func _init() -> void:
	name = "ActionSharePanel"
	var harness := HarnessSettings.load_default()
	if harness != null:
		limit_percent = harness.max_action_share_percent
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.OVERLAY
	style.border_color = Palette.RULE
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size.x = 380
	_text.add_theme_font_size_override("normal_font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "monospace"])
	_text.add_theme_font_override("normal_font", mono)
	add_child(_text)


func _process(_delta: float) -> void:
	if _dirty and visible:
		refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == toggle_key:
		visible = not visible
		refresh()
		get_viewport().set_input_as_handled()


## Redraws from the fight now. Called on its own after the fight raises events.
func refresh() -> void:
	_dirty = false
	_text.text = bbcode()


## Forgets the session total.
func clear_session() -> void:
	session = FightSummary.Tally.new()
	session_fights = 0
	_banked.clear()
	refresh()


## Everything the panel shows, as BBCode. Pure: reads the fight only.
func bbcode() -> String:
	var lines := PackedStringArray()
	var who := "squad" if side == Combatant.Side.PLAYER else "enemies"
	if fight == null:
		lines.append(_colored("Action use · %s · no fight" % who, Palette.ACCENT))
	else:
		var summary := FightSummary.of(fight)
		var tally := summary.squad if side == Combatant.Side.PLAYER else summary.enemies
		lines.append(_colored("Action use · %s · this fight · %d decisions · limit %d%%" % [
			who, tally.decisions, limit_percent], Palette.ACCENT))
		lines.append_array(_share_lines(tally))
		for t in summary.units:
			if t.side == side and t.decisions > 0:
				lines.append(_colored("  %s: %s" % [fight.combatant(t.id).display_name, uses_text(t)], Palette.TEXT_DIM))
	if session_fights > 0:
		lines.append(_colored("Session · %d fight%s · %d decisions" % [
			session_fights, "" if session_fights == 1 else "s", session.decisions], Palette.ACCENT))
		lines.append_array(_share_lines(session))
	return "\n".join(lines)


## One row per action `tally` used, most used first (ties by id): id, uses,
## share in percent (FightSummary.Tally.share_percent) and whether it is above
## `limit`.
static func share_rows(tally: FightSummary.Tally, limit: int) -> Array[Dictionary]:
	var ids: Array = tally.action_uses.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ua: int = tally.action_uses[a]
		var ub: int = tally.action_uses[b]
		return ua > ub or (ua == ub and a < b))
	var rows: Array[Dictionary] = []
	for id: String in ids:
		var percent := tally.share_percent(id)
		rows.append({"action": id, "uses": int(tally.action_uses[id]), "percent": percent, "over": percent > limit})
	return rows


## "heavy_strike 2 · shred 1", most used first.
static func uses_text(tally: FightSummary.Tally) -> String:
	var parts := PackedStringArray()
	for row in share_rows(tally, 100):
		parts.append("%s %d" % [row.action, row.uses])
	return " · ".join(parts) if not parts.is_empty() else "-"


func _share_lines(tally: FightSummary.Tally) -> PackedStringArray:
	var out := PackedStringArray()
	var rows := share_rows(tally, limit_percent)
	if rows.is_empty():
		out.append(_colored("  no decisions yet", Palette.TEXT_DIM))
	for row in rows:
		var bar := "█".repeat(roundi(BAR_WIDTH * row.percent / 100.0))
		out.append(_colored("  %-13s %3d %4d%% %s%s" % [
			row.action, row.uses, row.percent, bar, "  over" if row.over else ""],
			Palette.WARNING if row.over else Palette.TEXT))
	return out


func _bank(old: Fight) -> void:
	if old == null or not old.is_over() or _banked.has(old):
		return
	_banked.append(old)
	var summary := FightSummary.of(old)
	session.add(summary.squad if side == Combatant.Side.PLAYER else summary.enemies)
	session_fights += 1


func _on_event(_event: FightEvent) -> void:
	_dirty = true


static func _colored(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]
