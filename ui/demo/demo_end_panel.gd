class_name DemoEndPanel
extends Control
## The end of a demo scenario, in place of the run's own next step: what
## happened (victory, defeat, the payload, the run over), then REPLAY (the
## same scenario from its start) or BACK TO DEMOS (the picker).

signal replay_requested
signal back_requested

const PANEL_WIDTH := 460.0

var eyebrow_text := "DEMO"
var title_text := ""
var body_text := ""
## Palette color of the title.
var title_color := "accent"

var title_label: Label
var body_label: Label
var replay_button: ActionButton
var back_button: ActionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = ScreenTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(FeelData.color("background"), 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size.x = PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = FeelData.color("panel_border_light")
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	rows.add_child(_label(eyebrow_text, "warning", 10))
	title_label = _label(title_text, title_color, 30)
	title_label.name = "TitleLabel"
	rows.add_child(title_label)
	body_label = _label(body_text, "text", 10)
	body_label.name = "BodyLabel"
	body_label.visible = not body_text.is_empty()
	rows.add_child(body_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	rows.add_child(buttons)
	replay_button = ActionButton.make("action_replay", "Replay")
	replay_button.name = "ReplayButton"
	replay_button.pressed.connect(func() -> void:
		SoundPlayer.fire(&"ui_confirm")
		replay_requested.emit())
	buttons.add_child(replay_button)
	back_button = ActionButton.make("action_home", "Back to demos")
	back_button.name = "BackButton"
	back_button.pressed.connect(func() -> void:
		SoundPlayer.fire(&"ui_back")
		back_requested.emit())
	buttons.add_child(back_button)


func _label(text: String, color: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = PANEL_WIDTH - 44.0
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l
