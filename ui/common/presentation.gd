extends Node
## Autoload "Presentation": applies the saved settings to the audio buses at
## start and whenever they change, owns the one SoundPlayer (registered as
## SoundPlayer.current), and opens the settings screen on the open_settings
## action (F10) from any screen.

var sound: SoundPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings := GameSettings.shared()
	settings.apply_to_buses()
	settings.changed.connect(settings.apply_to_buses)
	sound = SoundPlayer.new()
	sound.name = "Sound"
	add_child(sound)
	SoundPlayer.current = sound


func _unhandled_input(event: InputEvent) -> void:
	var action: String = FeelData.settings().get("open_action", "open_settings")
	if InputMap.has_action(action) and event.is_action_pressed(action):
		toggle_settings()
		get_viewport().set_input_as_handled()


func open_settings() -> SettingsScreen:
	return SettingsScreen.open_overlay(get_tree().root)


func toggle_settings() -> void:
	if SettingsScreen.is_open(get_tree().root):
		var screen: SettingsScreen = get_tree().root.get_node("SettingsOverlay").get_child(0)
		screen.close()
	else:
		open_settings()
