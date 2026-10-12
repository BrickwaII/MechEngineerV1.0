class_name RunOverScreen
extends Control
## The end of a run, as icons and numbers with hover tooltips (ui/README.md
## style guide): the result and why, the act and day it ended on, regions
## held, fights won and lost, losses, play time, and the run's folder, all
## from the folder's summary.json (RunFolder). MAIN MENU leaves; OPEN FOLDER shows the folder.
## RunFlow shows it when a run ends; the main menu shows it, read-only, for a
## finished run in the load list (BACK instead of MAIN MENU).

signal main_menu_requested
signal folder_requested

const CARD_WIDTH := 560.0
const BUTTON_SIZE := Vector2(220, 48)

var summary: Dictionary = {}
var run_dir := ""
## The label of the button that leaves, "MAIN MENU" or "BACK".
var leave_text := "MAIN MENU"

var title_label: Label
var reason_label: Label
var details: VBoxContainer
var leave_button: Button
var folder_button: Button


## Shows the run in `dir`, with `p_summary` (its summary.json).
func show_run(dir: String, p_summary: Dictionary) -> void:
	run_dir = dir
	summary = p_summary
	if is_inside_tree():
		_fill()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = FeelData.color("panel_border")
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = CARD_WIDTH
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	rows.add_child(_label("RUN OVER", "text_dim", 10))
	title_label = _label("", "accent", 30)
	title_label.name = "TitleLabel"
	rows.add_child(title_label)
	reason_label = _label("", "text_bright", 12)
	reason_label.name = "ReasonLabel"
	rows.add_child(reason_label)
	details = VBoxContainer.new()
	details.name = "Details"
	details.add_theme_constant_override("separation", 6)
	rows.add_child(details)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	rows.add_child(buttons)
	leave_button = _button(leave_text, func() -> void: main_menu_requested.emit())
	leave_button.name = "MainMenuButton"
	buttons.add_child(leave_button)
	folder_button = _button("OPEN FOLDER", func() -> void: folder_requested.emit())
	folder_button.name = "OpenFolderButton"
	buttons.add_child(folder_button)
	_fill()


func _fill() -> void:
	if title_label == null:
		return
	var won := bool(summary.get("won", false))
	title_label.text = "VICTORY" if won else "DEFEAT"
	title_label.add_theme_color_override("font_color", FeelData.color("accent" if won else "danger"))
	reason_label.text = reason_text(str(summary.get("end_reason", "")), won)
	for child in details.get_children():
		child.queue_free()
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	details.add_child(stats)
	var act_tip := "Act %d" % int(summary.get("act", 1))
	if not str(summary.get("act_name", "")).is_empty():
		act_tip += ", %s" % summary.act_name
	for entry: Array in [
		["time", "A%d D%d" % [int(summary.get("act", 1)), int(summary.get("day", 1))], "Where the run ended: %s, day %d." % [act_tip, int(summary.get("day", 1))]],
		["defense_level", "%d/%d" % [int(summary.get("regions_held", 0)), int(summary.get("regions_total", 0))], "Regions held at the end."],
		["action_attack", "%d-%d" % [int(summary.get("fights_won", 0)), int(summary.get("fights_lost", 0))], "Fights won and lost in the whole run."],
		["losses", maxi(0, int(summary.get("loss_limit", 0)) - int(summary.get("losses", 0))) if int(summary.get("loss_limit", 0)) > 0 else "-",
			"Lost battles left in the last act: %d lost there." % int(summary.get("losses", 0))],
		["status_waiting", RunFolder.play_time_text(float(summary.get("play_s", 0.0))), "Real time played."],
	]:
		var stat := IconStat.make(entry[0], entry[1], entry[2])
		stat.name = "Stat_%s" % entry[0]
		stats.add_child(stat)
	var folder := _label(ProjectSettings.globalize_path(run_dir) if not run_dir.is_empty() else "", "text_dim", 8)
	folder.name = "FolderLabel"
	details.add_child(folder)
	leave_button.text = leave_text


## One sentence for why the run ended, from the summary's end_reason
## (RunRecorder's run_end reason).
static func reason_text(reason: String, won: bool) -> String:
	match reason:
		"boss fight won":
			return "The squad beat the boss. The run is won."
		"boss fight lost":
			return "The boss held. Losing a boss fight ends the run."
		"every region lost":
			return "Every territory fell."
		"loss limit reached":
			return "Too many battles lost in one act."
	return "The run is won." if won else "The run is over."


func _label(text: String, color: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(on_press)
	return b
