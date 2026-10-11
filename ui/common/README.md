# ui/common/

The presentation foundation every screen shares: theme, sound, settings and
the feel kit. Timings, colors and sounds live in `data/feel/`; nothing here
holds a tunable number.

| File | What |
|---|---|
| `feel_data.gd` | `FeelData`: reads `data/feel/*.json`; `FeelData.color("hp")` |
| `pixel_theme.gd`, `pixel_theme.tres` | `PixelTheme.theme()`: font, boxes, colors. Rebuild the .tres with `build_theme.gd` |
| `game_settings.gd` | `GameSettings.shared()`: volumes, shake, reduced motion, animation speed; saved to `user://settings.cfg` |
| `settings/settings_screen.tscn` | The settings screen. F10 (`open_settings`) opens it anywhere, or `SettingsScreen.open_overlay(get_tree().root)` |
| `presentation.gd` | Autoload `Presentation`: applies settings to buses, owns the sound player and the music director, handles F10 |
| `sound_player.gd`, `sound_throttle.gd` | `SoundPlayer.fire(&"hit_light")`: pitch and sample variation, throttled repeats |
| `music_director.gd` | `MusicDirector.current`: the one music player, owned by `Presentation`. Crossfades between contexts (menu, map per act, battle and boss, readout, victory and defeat stings) from `data/feel/audio.json` "music_director"; RunFlow's stage changes drive it |
| `feel_tween.gd` | `FeelTween.to(node, "position", v, "ui")`: named presets |
| `hit_pause.gd` | `HitPause.trigger(get_tree(), "heavy")` on a landed hit |
| `screen_shake.gd` | `ScreenShake.new(root).shake("big")`, big and small hits only |
| `number_popup.gd` | `NumberPopup.spawn(parent, at, 12, "damage")`; kinds damage, crit, heal, energy |
| `ghost_bar.gd` | `GhostBar`: meter with trailing ghost, flash and low-health stripes |
| `sprite_manifest.gd`, `unit_sprite.gd`, `palette_swap.gdshader` | Units from `data/feel/sprite_manifest.json` (format in `assets/README.md`) |
| `demo/` | `theme_demo`, `feel_demo`, `sprite_demo` scenes; `capture_screenshots.gd` renders them |

## Adopting it on a screen

```gdscript
func _ready() -> void:
	theme = PixelTheme.theme()
	shake = ScreenShake.new(self)
	add_child(shake)

func _on_hit(target_bar: GhostBar, at: Vector2, damage: int, big: bool) -> void:
	HitPause.trigger(get_tree(), "heavy" if big else "light")
	SoundPlayer.fire(&"hit_heavy" if big else &"hit_light")
	target_bar.set_value(target_bar.value - damage)
	NumberPopup.spawn(self, at, damage, "crit" if big else "damage")
	if big:
		shake.shake("big")
```

Everything follows the player's settings: durations shrink at 1.5x and 2x and
drop to zero on skip, shake is zero when off or with reduced motion, and
popups fade in place with reduced motion.
