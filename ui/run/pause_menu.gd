class_name PauseMenu
extends Control
## The Esc menu over a paused run: RESUME, SETTINGS and MAIN MENU, as icon
## buttons (ui/README.md rule 3). The host (RunFlow) pauses the tree while
## it shows; the menu itself runs while paused.
##
## MAIN MENU leaves at once, unless the host set `confirm_title`: then the
## menu first asks, with what leaving does in `confirm_body`, LEAVE or STAY.
## Esc resumes (or, while asking, goes back to the menu). SETTINGS opens the
## settings screen over everything (SettingsScreen); its own Esc closes it
## and leaves this menu up.
##
##   var menu := PauseMenu.new()
##   menu.confirm_title = "Leave the battle?"
##   menu.resumed.connect(...)
##   menu.home_requested.connect(...)

const PANEL_WIDTH := 420.0

## RESUME, or Esc on the menu.
signal resumed
## The player chose to leave for the main menu (confirmed, when asked).
signal home_requested

## The title over the buttons.
var title_text := "PAUSED"
## A short dim line under the title: what MAIN MENU does here.
var note_text := ""
## The label of the leave button.
var home_text := "Main menu"
## When set, MAIN MENU asks first with this title and body.
var confirm_title := ""
var confirm_body := ""
## The label of the confirm step's leave button.
var confirm_leave_text := "Leave"

var menu_box: VBoxContainer
var confirm_box: VBoxContainer
var resume_button: ActionButton
var settings_button: ActionButton
var home_button: ActionButton
var leave_button: ActionButton
var stay_button: ActionButton
var confirm_body_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = ScreenTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		# Resuming frees this menu; mark the key handled while it is in the tree.
		get_viewport().set_input_as_handled()
		if is_confirming():
			cancel_confirm()
		else:
			resume()


## True while the menu asks before leaving.
func is_confirming() -> bool:
	return confirm_box != null and confirm_box.visible


func resume() -> void:
	SoundPlayer.fire(&"ui_back")
	resumed.emit()


## MAIN MENU: asks first when the host set a confirm title, else leaves.
func request_home() -> void:
	if confirm_title.is_empty():
		_leave()
	else:
		ask_confirm()


## Shows the confirm step (LEAVE or STAY).
func ask_confirm() -> void:
	SoundPlayer.fire(&"ui_confirm")
	menu_box.visible = false
	confirm_box.visible = true


## Back from the confirm step to the menu.
func cancel_confirm() -> void:
	SoundPlayer.fire(&"ui_back")
	confirm_box.visible = false
	menu_box.visible = true


func open_settings() -> SettingsScreen:
	SoundPlayer.fire(&"ui_confirm")
	return SettingsScreen.open_overlay(get_tree().root)


func _leave() -> void:
	SoundPlayer.fire(&"ui_confirm")
	home_requested.emit()


# --- Layout ------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(FeelData.color("background"), 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = FeelData.color("panel_border_light")
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	menu_box = _column("Menu")
	stack.add_child(menu_box)
	menu_box.add_child(_label(title_text, "accent", 30))
	if not note_text.is_empty():
		menu_box.add_child(_label(note_text, "text_dim", 10))
	resume_button = _action("action_resume", "Resume", resume)
	resume_button.name = "ResumeButton"
	settings_button = _action("action_settings", "Settings", func() -> void: open_settings())
	settings_button.name = "SettingsButton"
	home_button = _action("action_home", home_text, request_home)
	home_button.name = "HomeButton"
	for b in [resume_button, settings_button, home_button]:
		menu_box.add_child(b)

	confirm_box = _column("Confirm")
	confirm_box.visible = false
	stack.add_child(confirm_box)
	confirm_box.add_child(_label(confirm_title, "warning", 20))
	confirm_body_label = _label(confirm_body, "text", 10)
	confirm_body_label.name = "ConfirmBody"
	confirm_box.add_child(confirm_body_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	confirm_box.add_child(row)
	leave_button = ActionButton.make("action_home", confirm_leave_text)
	leave_button.name = "LeaveButton"
	leave_button.pressed.connect(_leave)
	row.add_child(leave_button)
	stay_button = ActionButton.make("action_resume", "Stay")
	stay_button.name = "StayButton"
	stay_button.pressed.connect(cancel_confirm)
	row.add_child(stay_button)


func _column(node_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", 14)
	return box


func _action(icon_id: String, text: String, on_press: Callable) -> ActionButton:
	var b := ActionButton.make(icon_id, text)
	b.pressed.connect(on_press)
	return b


func _label(text: String, color: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = PANEL_WIDTH - 40.0
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l
