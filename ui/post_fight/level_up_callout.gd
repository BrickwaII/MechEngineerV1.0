class_name LevelUpCallout
extends PanelContainer
## The big moment when a skill ranks up: a panel over the readout with the
## skill's name, its rank before and after, and what it does before and after
## for this bot ("6 > 8 dmg"), all from the SkillChange (numbers computed by
## SkillNumbers from the bot's stats and the combat tuning).
##
## A rank step: "OVERCHARGE SHOT", "+2 -> +3", "6 -> 7 dmg", with a chime.
## A tier shift is a much bigger moment: "MEGA OVERCHARGE SHOT!", a gold
## panel that pops larger, a heavy hit pause, its own sound, and the new
## bonus effect ("now pierces 50% of armor").
## The readout shows it for its step (data/feel/screens.json "readout") and
## frees it when the step ends or the count-up is skipped.

const PANEL := Color("#16212e")
const RANK_BORDER := Color("#f2b84b")
const TIER_PANEL := Color("#2a1f0b")
const TIER_BORDER := Color("#ffd977")
const TEXT := Color("#dbe6f0")
const TEXT_DIM := Color("#8aa0b4")
const GOLD := Color("#f2b84b")
const BONUS := Color("#7be7a8")

var change: SkillChange
var settings: GameSettings


## The headline: "OVERCHARGE SHOT", or "MEGA OVERCHARGE SHOT!" on a tier shift.
static func title_for(c: SkillChange) -> String:
	var name := c.name_after if not c.name_after.is_empty() else c.skill_name
	if c.is_tier_shift():
		return _without_step(name).to_upper() + "!"
	return c.skill_name.to_upper()


## "+2 -> +3", "BASE -> +1", "+5 -> MEGA"; flat levels "Lv2 -> Lv3".
static func rank_line(c: SkillChange) -> String:
	return "%s -> %s" % [_rank_text(c.rank_before), _rank_text(c.rank_after)]


## "6 -> 8 dmg", "8 -> 9 hp", "50 -> 55% guard", plus "  ·  cost 4 -> 3" when
## the energy cost changed. "" when the numbers are unknown.
static func numbers_line(c: SkillChange) -> String:
	if c.stat_kind.is_empty():
		return ""
	var unit := c.stat_kind if c.stat_kind.begins_with("%") else " " + c.stat_kind
	var out := "%s -> %s%s" % [SkillNumbers.format(c.value_before), SkillNumbers.format(c.value_after), unit]
	if c.cost_after != c.cost_before:
		out += "  ·  cost %d -> %d" % [c.cost_before, c.cost_after]
	return out


## "now pierces 50% of armor", or "" with no new bonus.
static func bonus_line(c: SkillChange) -> String:
	if c.new_bonuses.is_empty():
		return ""
	return "now " + ", ".join(c.new_bonuses)


## The whole callout on one line, for logs and tests:
## "OVERCHARGE SHOT +2 -> +3, 6 -> 7 dmg".
static func one_line(c: SkillChange) -> String:
	var parts := ["%s %s" % [title_for(c), rank_line(c)]]
	if not numbers_line(c).is_empty():
		parts.append(numbers_line(c))
	if not bonus_line(c).is_empty():
		parts.append(bonus_line(c))
	return ", ".join(parts)


static func _rank_text(label: String) -> String:
	return "BASE" if label.is_empty() else label.to_upper()


## "Mega Strike +2" -> "Mega Strike".
static func _without_step(name: String) -> String:
	var plus := name.rfind(" +")
	return name.substr(0, plus) if plus > 0 else name


func setup(p_change: SkillChange, p_settings: GameSettings = null) -> void:
	change = p_change
	settings = p_settings
	name = "LevelUpCallout"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tier := change.is_tier_shift()
	var style := StyleBoxFlat.new()
	style.bg_color = TIER_PANEL if tier else PANEL
	style.border_color = TIER_BORDER if tier else RANK_BORDER
	style.set_border_width_all(4 if tier else 3)
	style.set_content_margin_all(26 if tier else 18)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8 if tier else 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(_line("TIER UP" if tier else "RANK UP", 10, GOLD, "Kicker"))
	box.add_child(_line(title_for(change), 34 if tier else 24, TIER_BORDER if tier else TEXT, "Title"))
	box.add_child(_line(rank_line(change), 20 if tier else 16, GOLD, "Rank"))
	if not numbers_line(change).is_empty():
		box.add_child(_line(numbers_line(change), 26 if tier else 20, TEXT, "Numbers"))
	if not bonus_line(change).is_empty():
		box.add_child(_line(bonus_line(change), 16, BONUS, "Bonus"))


## Centres the panel in `area` and plays the entrance: the pop, the sound, a
## hit pause, and the new number rising out of the panel.
func play(area: Vector2, popups: Control) -> void:
	reset_size()
	position = (area - size) * 0.5
	pivot_offset = size * 0.5
	var tier := change.is_tier_shift()
	SoundPlayer.fire(&"skill_tier_up" if tier else &"skill_rank_up")
	if is_inside_tree():
		HitPause.trigger(get_tree(), "heavy" if tier else "light", settings)
	if not change.stat_kind.is_empty() and popups != null:
		var popup := NumberPopup.new()
		popup.setup(roundi(change.value_after), "crit", settings)
		popup.text = "%s!" % SkillNumbers.format(change.value_after)
		popup.icon = null
		popup.position = position + Vector2(size.x - 30.0, 10.0)
		popups.add_child(popup)
	var s := settings if settings else GameSettings.shared()
	if s.reduced_motion or FeelTween.seconds("ui_pop", settings) <= 0.0:
		return
	scale = Vector2.ONE * ScreenFeel.number("readout.tier_pop_scale" if tier else "readout.callout_pop_scale", 1.2)
	modulate.a = 0.0
	FeelTween.to(self, "scale", Vector2.ONE, "ui_pop", settings)
	FeelTween.to(self, "modulate:a", 1.0, "ui", settings)


## Fades out and frees itself.
func dismiss() -> void:
	var seconds := ScreenFeel.seconds("readout.callout_out_ms", settings)
	if seconds <= 0.0 or not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, seconds)
	tween.tween_callback(queue_free)


func _line(text: String, font_size: int, color: Color, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
