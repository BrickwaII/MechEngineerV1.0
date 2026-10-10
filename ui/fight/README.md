# ui/fight/ and ui/draft/

The playable fight (M4). All rules live in fight/; these scripts show the
fight and turn the mouse into `FightCommand`s.

- `fight_demo.tscn`: runnable entry. Draft -> fight -> result text.
- `BattleScreen` (`battle_screen.tscn`): timeline bar, a panel per unit with
  live HP and energy, the log, and the command bar. Mouse: left-click a bot to
  select it, a skill button to pick a skill, an enemy to target it; WAIT;
  CANCEL or right-click to step back.
- `FightSceneService`: a contracts `FightService` that plays the fight as a
  `BattleScreen` under a host node and emits `finished` with the
  `FightResult`. Swap it in for the overworld's fight service.
- `ui/draft/DraftScreen`, `DraftPicker`: the seeded draft from `BotFactory`;
  pick `squad_size` bots, get them as `SquadMemberSummary` data.
- Screen pacing and demo settings: data/ui/fight_screen.json.

Placeholder art: bots are teal squares, enemies red diamonds.

Hooks for the M3 wiring (intent and preview): every enemy `UnitPanel` has an
`intent_label` (node `IntentLabel`), and `BattleScreen.preview_area` (node
`PreviewArea`) sits beside the command bar. Both are marked TODO(m4-telegraph).
