# ui/common/

The style rules every screen follows are in `ui/README.md`.

The presentation foundation every screen shares: theme, sound, settings and
the feel kit. Timings, colors and sounds live in `data/feel/`; nothing here
holds a tunable number.

| File | What |
|---|---|
| `feel_data.gd` | `FeelData`: reads `data/feel/*.json`; `FeelData.color("hp")` |
| `pixel_theme.gd`, `pixel_theme.tres` | `PixelTheme.theme()`: font, boxes, colors. Rebuild the .tres with `build_theme.gd` |
| `game_settings.gd` | `GameSettings.shared()`: volumes, shake, reduced motion, animation speed, interface size, scaling, fullscreen; saved to `user://settings.cfg` with a version (an older file migrates on load). Tests and `-s` tools keep the shared settings in memory only, never the player's file (`MECH_ENGINEER_SETTINGS` points them at a file) |
| `window_fit.gd` | `WindowFit`: the view fills the window at a crisp scale (Auto or the interface size, capped to keep at least 1280 x 820); fullscreen; the minimum window |
| `settings/settings_screen.tscn` | The settings screen. F10 (`open_settings`) opens it anywhere, or `SettingsScreen.open_overlay(get_tree().root)` |
| `presentation.gd` | Autoload `Presentation`: applies settings to buses and the window (fit on every resize, fullscreen), owns the sound player and the music director, handles F10, F11 and Alt+Enter |
| `sound_player.gd`, `sound_throttle.gd` | `SoundPlayer.fire(&"hit_light")`: pitch and sample variation, throttled repeats |
| `music_director.gd` | `MusicDirector.current`: the one music player, owned by `Presentation`. Crossfades between contexts (menu, map per act, battle and boss, readout, victory and defeat stings) from `data/feel/audio.json` "music_director"; RunFlow's stage changes drive it |
| `feel_tween.gd` | `FeelTween.to(node, "position", v, "ui")`: named presets |
| `hit_pause.gd` | `HitPause.trigger(get_tree(), "heavy")` on a landed hit |
| `screen_shake.gd` | `ScreenShake.new(root).shake("big")`, big and small hits only |
| `number_popup.gd` | `NumberPopup.spawn(parent, at, 12, "damage")`; kinds damage, crit, heal, energy |
| `ghost_bar.gd` | `GhostBar`: meter with trailing ghost, flash and low-health stripes |
| `sprite_manifest.gd`, `unit_sprite.gd`, `palette_swap.gdshader` | Units from `data/feel/sprite_manifest.json` (format in `assets/README.md`) |
| `ui_icons.gd` | `UiIcons`: icon ids -> texture, name, color, tooltip lines from `data/ui/icons.json`; kit layout from `data/ui/ui_kit.json` |
| `ui_glossary.gd` | `UiGlossary`: keywords from `data/ui/glossary.json`, found and highlighted in any text |
| `ui_tooltip.gd` | `UiTooltip`: the standard tooltip; `UiTooltip.attach(control, name, lines, numbers, icon_id)` |
| `icon_stat.gd` | `IconStat.make("atk", 12)`: icon + number + tooltip |
| `skill_card.gd` | `SkillCard.make("Beam", 3, "Deal 12. Pierce 20%.", "+2")`: a skill as a card-like button |
| `action_button.gd` | `ActionButton.make("action_reinforce", "Reinforce", "material", 2)`: icon + label + cost |
| `ui_style.gd` | `UiStyle`: the design system's rules as code: `space("s")`, `panel("plain")`, `role("bad")`, `caption(label)` |
| `ui_formula.gd` | `UiFormula`: a formula line from real values for math tooltips: `UiFormula.parse("{ATK} − {DEF}", {...}, 4)` |
| `stat_strip.gd` | `StatStrip`: a card's three headline stats, each its own graphic (bar, number, ring, arrow, pips, chip) |
| `flag.gd` | `Flag.of("boss")`: the one badge style; catalog in `data/ui/flags.json` |
| `info_card.gd` | `InfoCard`: the card anatomy (title + ⋮, flags, portrait, stat strip) |
| `detail_modal.gd` | `DetailModal`: everything about a thing, from ⋮ or right-click; Esc closes |
| `control_strip.gd` | `ControlStrip`: the one bar of view controls on a screen |
| `ui_tabs.gd` | `UiTabs`: related pages under one row of tabs |
| `demo/` | `style_check` (every design-system piece; `capture_style_check.gd`), `theme_demo`, `feel_demo`, `sprite_demo`, `ui_kit_demo` scenes; `capture_screenshots.gd` and `capture_ui_kit.gd` render them |

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
