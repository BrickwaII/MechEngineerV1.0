# ui/

Screens and input. May import any layer. Nothing outside ui/ imports ui/.

## Style guide

Every screen follows these rules. The look is a card game like Slay the
Spire: **icons and numbers instead of labels, text on actions, and hover for
the rest.** The kit that does it lives in `ui/common/` (see its README);
`ui/common/demo/ui_kit_demo.tscn` shows every piece, and
`ui/common/screenshots/ui_kit.png` is the reference picture.

### 1. Icons and numbers, not labels

Every stat, resource, status, intent, map action, region property and
personality trait is an icon, with its number beside it when it has a value.
Never write "ATK 12" or "Energy: 24"; write `IconStat.make("atk", 12)`.

| What | Icon ids |
|---|---|
| Unit stats | `hp`, `atk`, `def`, `spd`, `battery`, `ela`, `energy` (battle Energy, the lightning; also skill costs) |
| Run resources | `map_energy` (the campaign Energy resource, a power cell), `material`, `grid_power`, `time` |
| Region and campaign | `defense_level`, `pressure`, `alert`, `losses` |
| Personality | `trait_aggressive`, `trait_defensive`, `trait_solitary`, `trait_supportive`, `trait_reactive`, `trait_methodical` |
| Map actions | `action_attack`, `action_reinforce`, `action_wait`, `action_retreat`, `action_fast_forward` |
| Enemy intents | `intent_attack`, `intent_guard`, `intent_heal`, `intent_charge`, `intent_buff` |
| Statuses | `status_guard`, `status_charging`, `status_waiting`, `status_low_energy`, `status_down`, `status_intent_changed` |

Icons are named by id from `data/ui/icons.json` (texture, name, color, tooltip
lines), never by path. A new thing that needs an icon gets a row there and,
for new art, a drawing in `tools/asset_gen/gen_ui_icons.py`.

### 2. Every icon has a tooltip

Hovering any icon shows the standard tooltip (`UiTooltip`): a **bold name**,
one or two plain lines, then the numbers. `IconStat` and the other kit
widgets do this on their own; for any other control call
`UiTooltip.attach(control, name, lines, numbers, icon_id)`.

Keywords in any description (Guard, Pierce, Charge, Energy, Fortify, alert
tiers, traits, ...) are highlighted in one color (`tooltip.keyword_color` in
`data/ui/ui_kit.json`) with a dotted underline that follows wrapped lines, so
they read as links, like Slay the Spire keywords. A hovered or pinned keyword
turns bright on a highlight (`tooltip.keyword_active_back`), so you can see
which word a box belongs to:

- **Hover** a keyword to see its box (icon, name, short definition with its
  numbers) by the cursor.
- **Click** it to pin the box until a click elsewhere or Esc. Keywords inside
  a pinned box are links too: hover shows theirs beside it, click pins theirs.
- Hovering a whole card or tooltip also lists the boxes of every keyword it
  uses.
- A keyword box never covers other cards' text: it opens beside its card,
  tooltip or box where there is room, above a card row otherwise (as Slay the
  Spire does), and stays on screen. A chained box stacks beside its parent box.

Keywords, their aliases (Piercing, Pierces -> Pierce) and definitions live in
`data/ui/glossary.json`. To show a description, use
`UiGlossary.rich(text, font_size)` (a wired RichTextLabel), or
`UiGlossary.wire(label)` plus `UiGlossary.set_text(label, text)` on your own
RichTextLabel (set_text keeps the plain text so hover and pin can restyle it);
UiTooltip and SkillCard already do this.

**Name the keyword and its number; leave the explanation to the glossary.**
Write "Pierce 20%", not "ignores 20% of the target's defense"; "Guard 40%",
not "blocks 40% of its next hit". A new mechanic that shows up in text gets a
glossary entry. Tooltip lines are short: plain words, no more than two
sentences, numbers as digits.

### 3. Actions always show their text

- **Skills** are `SkillCard`s: a card-like tile with the Energy cost in a
  corner badge, the name, the rank (`+2`; tier names such as Mega are part of
  the name), and the effect in short words with numbers ("Deal 12. Pierce
  20%."). A card that cannot be played is disabled and says why in its
  tooltip (`set_problem`).
- **Map and menu actions** are `ActionButton`s: an icon, the label, and the
  cost as an icon and number, always visible
  (`ActionButton.make("action_reinforce", "Reinforce", "material", 2)`).
- Text on cards and buttons is never smaller than the body font: a long
  name wraps onto two lines instead of shrinking.

### 4. Enemy intents

An intent is an icon plus a number above the enemy: `intent_attack` with the
damage, `intent_guard`, `intent_heal` with the amount, `intent_buff`,
`intent_charge`. The intent arrows stay as they are.

### 5. Long prose hides

Paragraphs go behind hover or into an optional panel. The battle log is
collapsed by default; the region panel is rows of icons. A screen at rest
shows names, icons and numbers, not sentences.

### 6. Pixel art, one size, one palette

Icons are 12 x 12 pixel art drawn at a whole-number scale (`icon_scale` in
`data/ui/ui_kit.json`, 2 today). Colors come from `data/feel/palette.json`
only. Art is generated or CC0, and every file is credited in `CREDITS.md`
(a test checks this). Each icon differs by shape as well as color.

### Exceptions

Dev tools (the F4 switchboard, `ui/dev/`) may stay text-heavy.

### Stand-ins

TODO(decision: ui-style-icon-art): every icon is generated placeholder art.
TODO(decision: ui-style-bold): the pixel font has no bold face; names are
"bold" by a one-pixel outline in their own color (`UiTooltip._bold`).
