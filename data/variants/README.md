# data/variants/

The variant switchboard: every open design decision as swappable options, so
they can be flipped in a running game and compared by playing.

`variants.json` lists each decision once:

| Key | Meaning |
|---|---|
| `id` | the decision's marker, as in `TODO(decision: <id>)` |
| `layer` | the layer whose reader acts on it (`fight`, `campaign`, `bot_data`) |
| `applies` | `live`, `next_fight` or `next_run` |
| `default` | the option played when the player chose nothing; today's behaviour |
| `options` | `{id, name, description, params, built}`; `params` holds the option's numbers, `built: false` lists an option no code implements yet |
| `default_from`, `default_key` | the default lives in another data file (draft-rule) |
| `per_act`, `options_from` | one decision per act, options read from that file (act-maps) |

The player's choices go to `user://variants.json` as
`{"choices": {"d-wait": "extra_energy", "act-maps/act1": "lake_washington_8"}}`,
non-default choices only. Each layer reads only its own decisions:

- fight: `FightVariants` (`fight/variants/`), loaded when each fight starts.
- bot_data `draft-rule` and campaign `act-maps`: applied by `RunFlow` when a new run starts.
- campaign `energy-grid`, `squad-size`, `act-pacing`, `auto-expansion`:
  `CampaignVariants` (`campaign/variants/`), read when a run starts and kept
  in the run's save; `squad-size` sizes the draft (`RunFlow`).
- campaign `grid-cost-owner`: `CampaignVariants`, read when each fight starts
  by the map (`Campaign`) and the run's fight service (`RunFightService`).
- The switchboard screen (`ui/dev/switchboard_screen.tscn`, F4 in a run) reads and writes all of them.

Changing an option's numbers, the default, or adding an option that code
already knows needs no code edit. Compare the options of a fight decision with
`tools/compare_variants.gd`; for a campaign decision the same command plays
whole auto-played campaigns (`CampaignComparison`, `CampaignAutoplay`) and
reports acts cleared, days used, fights fought and forced defenses:

    godot --headless --path . -s res://tools/compare_variants.gd -- --decision auto-expansion --runs 50
