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

Intent and preview (M4, from fight/intent/ and fight/preview/):
- `FightTelegraph`: no scene, tested headless. Holds an `IntentTracker`, turns
  each enemy's intent into words ("Heavy Strike -> Spark (9)"), keeps a
  "changed: <why>" mark per revised intent until the next bot action
  resolves, gives each unit's personality tag, and runs the choice preview on
  a copy of the fight.
- Enemy panels show their intent (node `IntentLabel`), re-planned after every
  action; a revised intent turns purple with a `ChangeLabel` and border for
  one turn. Every panel shows its personality tag (`TagLabel`).
- Enemies act with `IntentFightPolicy` on the same planner, so the telegraph
  is what happens.
- With a skill selected, pointing at a target fills the preview box
  (`PreviewArea`) and each touched panel's `PreviewLabel`: damage, hp after,
  who goes down, which enemy intents would change. Unknown values show "?".
  Nothing is submitted until the click.

Screenshots: screenshots/intent_row.png, intent_changed.png, choice_preview.png.
