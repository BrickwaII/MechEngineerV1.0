# ui/fight/ and ui/draft/

The playable fight (M4). All rules live in fight/; these scripts show the
fight and turn the mouse into `FightCommand`s.

- `fight_demo.tscn`: runnable entry. Draft -> fight -> result text.
- `BattleScreen` (`battle_screen.tscn`): timeline bar, a panel per unit with
  live HP and energy, the log, and the command bar. Mouse: left-click a bot to
  select it, a skill button to pick a skill, an enemy to target it (a bot,
  for Patch Up and Shield Ally; Brace needs no target); WAIT; CANCEL or
  right-click to step back. The buttons are the bot's own skills, by its
  names and levels.
  A unit's name on its card is never clipped and never shrinks: a long one
  wraps onto two lines at body size (`UnitPanel._fit_name()`); its tooltip
  and the detail card give the full name. A unit alone of its kind has no
  number ("Precinct Overseer", but "Rust Hound 1" and "Rust Hound 2"). A host may add a Home
  button to the header (`show_home_button()`).
  The field grows with the window, its squad and enemy columns no wider than
  `battle.max_field_width` (data/ui/ui_kit.json), centred. Detailed cards show only while they fit
  its height; otherwise the cards are compact and Detailed is greyed out with
  the reason, and the player's choice comes back when the window has room
  (`_fit_view()`). A boss's hp bar sits in the header's free middle.
- `FightSceneService`: a contracts `FightService` that plays the fight as a
  `BattleScreen` under a host node and emits `finished` with the
  `FightResult`. Swap it in for the overworld's fight service.
- `ui/draft/DraftScreen`, `DraftPicker`: the seeded draft from `BotFactory`;
  pick `squad_size` bots, get them as `SquadMemberSummary` data.
- Screen pacing and demo settings: data/ui/fight_screen.json.

Presentation (M7 P2): see the section at the end.

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

Presentation (M7 P2). Timings and easing come from P1's feel kit
(data/feel/feel.json); everything particular to the battle is in
data/ui/battle_presentation.json. The whole screen uses `PixelTheme`.
- `BattleArt`: how each unit looks. Bots are the manifest's ally unit with
  parts and a palette from their id (no two squad mates share a palette);
  enemies use `SpriteManifest.for_enemy()` (the enemy table's sprite and
  tier), else a
  manifest unit of the same id (or listing it in `enemy_ids`), else the
  `enemy_sprites` alias, else the fallback walker recolored per enemy type.
- `BattleTierRule`: the tier-rule switch (generation / skill_levels /
  augments, thresholds in data/variants/variants.json). Bots come from
  `BattleScreen.bot_source` (RunFlow passes the squad); without one, tiers
  come from what the fight knows.
- `UnitPanel` + `UnitView`: a card per unit on the card anatomy
  (ui/README.md rule 8): the animated sprite on its tier plate and glow
  (target reticle while targetable), never covered; a title strip with the
  name, the enemy's intent chip and ⋮; a `StatStrip` of three headlines (the
  HP `PreviewBar` with the Energy bar under it, ATK as a big number, and the
  next turn as a chip, "Now" / "2nd" / ...); and flags on the edge: Boss,
  Elite, Ready / Target, `StatusRow` statuses ("Guard 40%", "Charging >6",
  ...), Low HP and the personality trait. ⋮, or a right-click while nothing
  is being aimed, opens the `DetailModal` (`UnitDetail.spec()`): Stats,
  Skills (skill cards with ranks), Status, Personality (the hexagon for
  bots) and, for enemies, Next move.
- `BattleMath`: the math tooltips (ui/README.md rule 15): an arrow badge's
  damage (`ATK × Power − DEF × 50% × (1 − Pierce) = N`, then guard and caps),
  repair and guard, and a turn chip's "(Turn at − Gauge) / Fill = ticks".
  `IntentArrows` puts an invisible hotspot over each badge to carry its
  tooltip; the NEXT chips and the card's turn chip share the turn math.
- `IntentArrows`: an arrow from each enemy to its intent's target; dim, with
  the next enemy to act (or the one under the pointer) bright.
- `BattlePresenter` + `BattleBeat`: plays each resolved action from the
  fight's `FightEvent`s: wind-up, strike, recover; projectiles; at impact the
  hit/heal/guard/down reaction, meters (held until then), number popups,
  effects, particles, sounds, hit pause, and a small shake on big hits only.
  Units not involved hold still. The fight never waits; only the next enemy
  waits for the beat. Headless or with "skip", beats resolve at once.
- `SkillFx`: one look and sound per skill (by the unit's own skill name, then
  id, then effect), growing per level in the steps of `level_steps`: bigger,
  brighter, more particles and projectiles, heavier hit pause, extra sound
  layers; never longer.
- `TimelineBar`: chips slide to their new places when the order changes.
- `OutcomeBanner`: the victory or defeat moment, then `fight_finished`
  (click to skip the hold).
- Art and sound: assets/fight/, generated by tools/asset_gen/gen_battle.py.
- Screenshots: `demo/capture_battle.gd` (needs a display) writes
  screenshots/battle_preview.png, battle_mid_fight.png,
  attack_strip_lv1_vs_max.png, ally_tiers.png, status_icons.png, victory.png.

Readability (R1-B, Playtest 1 follow-up). Sizes and colors:
data/feel/battle_readout.json (`ReadoutStyle`). The numbers come from
fight/preview (`BattleReadout`, `ArrowBadge`), so they are what the fight
resolves: tests/fight/preview/preview_matches_resolution_test.gd plays many
seeded fights and checks every previewed number against the resolution.
- `IntentArrows` draws a badge on every arrow: damage, `+heal` or `guard%`,
  with a skull when the hit would down its target. With a skill selected and
  a target under the pointer, the bot's own arrow (preview color) carries its
  badge; enemy arrows show their plan after the choice (changed ones bright,
  in the "changed" color, the old number struck out when only the number
  changes) and the arrows it replaces fade to ghosts.
- `PreviewBar`: the hp slice a hit would take blinks on the target's bar
  (green past the fill for a heal); the selected skill's cost blinks on the
  bot's energy bar as soon as the skill is picked.
- `UnitPanel`: ATK on every card, DEF (plus guard), SPD and BAT in the ATK
  tooltip and the detail card (`UnitDetail`): the full stats, skills with
  level, energy cost and effect, statuses, and an enemy's next move and why it
  changed. The intent and preview words no longer sit under the sprite (the
  labels keep their text for the detail card and tests); the log stays.
- `TimelineBar`: hovering a unit lights its slots and dims the rest; a choice
  that would change the order (pointing at WAIT previews a wait) shows the
  order it would leave, titled AFTER.
- Screenshots: `demo/capture_readability.gd` (needs a display) writes
  screenshots/readability_*.png. Icons: tools/asset_gen/gen_readability_icons.py.

## Battle layout (UI cleanup PR 4)

Laid out after Slay the Spire and Into the Breach:

- **Header**: the fight's title and Defense, Home. **Turn row**: the turn
  order as unit portraits (`UnitPortrait`; name and "when and why" on hover)
  and, at its right end, the screen's one `ControlStrip`: speed (1x, 1.5x,
  2x, Skip; saved to GameSettings), Log, Preview, and Detailed / Compact
  cards (a crowded field of more than three enemies starts compact).
- **Action dock** (bottom left): the acting bot's portrait, name and Energy,
  and its skills as `ActionTile`s (icon, short name, cost, hotkey 1-9). A
  disabled tile says why on hover.
- **Focused card** (`FocusCard`, the dock's middle): picking a tile lifts it
  into a card with the effect and its keyword links, the cost, and the damage
  math for the target under the pointer. Every valid target meanwhile shows
  its outcome as the first flag on its card ("-11", "KO -12", "+8"). A click
  confirms; Esc or a right-click puts it back. With no skill picked the step
  header ("Servo is ready. Choose a skill, or Wait.") stands there instead.
- **Wait** and **Cancel** on the dock's right.
- **Drawer**: the log and the choice preview in words open from the strip,
  in the field's empty middle (on the right edge when the middle is narrow);
  it keeps its height and scrolls.
- **Arrows**: badges take the first point along their arrow that covers no
  card and no other badge; hovering a unit fades every arrow that does not
  touch it.

## Combat rework readouts (S7)

The rework's fight state, read from the fight (never changed by the screen):

- **Cards** (`UnitPanel.rework_statuses()`, `StatusRow`): Brace as its own
  flag ("Brace 8"), Exposed with its bonus ("Exposed +50%", from
  data/combat/statuses.json), plating as drawn pips (whole filled, broken
  hollow; the numbers on hover), Staggered with its bonus, and a committed
  wind-up ("Wind-up Ram"). Every flag's keyword has a glossary entry
  (Exposed, Brace, Plating, Stagger, Recovery, Wind-up, Combo).
- **Intent chip**: a wind-up, and the hit it committed to, show the wind-up
  icon with the hit's damage. A chip that changes animates: the old number
  lifts off and fades in the "changed" color, the new chip pops in
  (data/ui/battle_presentation.json `intent_flip_*`).
- **Timeline marks** (`TimelineMarks`): beside a chip's portrait, small
  icons for what ends or lands on that slot: Exposed or Brace wearing off as
  the unit acts, a Staggered unit's lost turn, a wind-up's hit landing. The
  chip's tooltip names each one. A wound-up enemy is on the order where its
  hit lands (`Timeline.preview()` counts each action toward its wait).
- **Skill cards**: "Deal 5 ×2. Apply Exposed.", "+50% vs Exposed.",
  "Recovery 30%."
- Screenshots: `demo/capture_rework.gd` (needs a display) writes
  screenshots/rework_plating.png, rework_exposed.png, rework_brace.png,
  rework_wind_up.png, rework_stagger.png, from Battle Mode's Rework kit
  against a Charger, a Plated and a Scaler.

## Choice outlook (S7)

What a choice would lead to, before it is made, from `ChoiceReadout` (no
scene, tested headless; every number is worked out on `FightCopy`s, never
the fight):

- **Where the bot lands**: the AFTER bar shows the order the choice leaves,
  played forward with the real rules (`FightPreview.project_turns()`:
  recovery, waits, wind-ups and Staggers count), with the bot's landing chip
  lit and marked »; the outlook says "Next turn: 6th, in 19 ticks. Recovery
  30%." TODO(decision: recovery-projection): later turns assume every unit,
  the squad's other bots included, plays its current intent.
- **Conditional combos** in the outlook panel (`OutlookPanel`, the field's
  empty middle, so the dock never grows): a payoff without its setup ("11
  now. 24 if Bolt puts Exposed on first (acts 4th)."), a payoff with it
  ("Combo: 24 against Exposed (11 without)."), a setup and the hit that
  cashes it in ("Then Spark's Overcharge Shot: 12, 27 with Exposed (Spark
  acts 2nd)." or "Exposed wears off as ... acts"), and plating ("Plating 4 →
  2.", "Breaks its Plating: Stagger! ... and drops its Ram.").
- **Peek**: pointing at a dock tile shows its card (cost, damage before
  Defense, landing) before it is picked.
- **Wait** is always there and free: "Free +N" under the button (the Energy
  it banks by the bot's next turn), and on hover its card: Energy now +
  banked = at its next turn, the recharge rate while waiting, where it lands.
  With every skill affordable it banks toward the costliest
  (TODO(decision: wait-target)).
- tests/fight/preview/preview_matches_resolution_test.gd holds the landing
  slot, tick and Energy, the setup's hit and the payoff's damage to what the
  fight resolves.
- Screenshots (`demo/capture_rework.gd`): rework_focus_landing.png,
  rework_combo_setup.png, rework_wait.png.
