# ui/

Screens and input. May import any layer. Nothing outside ui/ imports ui/.

## Style guide

Every screen follows these rules. The look is a card game like Slay the
Spire: **icons and numbers instead of labels, text on actions, and hover for
the rest.** The kit that does it lives in `ui/common/` (see its README);
`ui/common/demo/ui_kit_demo.tscn` shows every piece, and
`ui/common/screenshots/ui_kit.png` is the reference picture.

Sections 7 to 16 are the **design system**: one card anatomy, one flag
style, one control strip, three panel styles, an 8 px grid and color roles,
so every screen reads as one game. The page that shows all of it is
`ui/common/demo/style_check.tscn` (reference pictures
`ui/common/screenshots/style_check*.png`); compare a screen against it. The
rule behind all of it: **streamlined at rest, everything one click away. We
relocate information, we never remove it.**

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
| Cards and flags | `more` (the ⋮ of a card), `odds`, `elite`, `new`, `multiplier` |
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

### 7. Nothing over the art

Portraits, unit sprites and the land of the map are never covered. Names,
flags, buttons and stats sit in a strip **around** the art, never on top of
it. The one exception is brief feedback that fades on its own: damage and
heal popups, hit sparks. A map region shows at most one small pin, placed
where it covers the least land, with the full card on hover.

The map follows it with **lenses**: the map strip picks Defense, Pressure,
Resources or Odds, and each region shows only that as one small pin; the
full card is on hover, everything on a right-click (`MapView.lens`).

### 8. Card anatomy

Every card for a unit or a region is an `InfoCard` with the same parts:

| Part | What | Kit |
|---|---|---|
| Title strip | The name, and **⋮** on the right | `InfoCard`, `DetailModal.more_button` |
| Flags | On the edge of the card, beside or above the art | `Flag`, `Flag.row` |
| Portrait | The art, alone in its slot | any Control |
| Stat strip | **Exactly three headline stats**, each with its own graphic | `StatStrip` |

The three headlines are the numbers the player needs to decide; everything
else goes in the detail modal. Each headline uses a different graphic so the
three read apart without labels:

| Graphic | For | Example |
|---|---|---|
| `bar` | a value out of a maximum | HP 38/50 |
| `number` | one count, big | ATK 12 |
| `ring` | a share or chance | odds 62% |
| `arrow` | a multiplier | ×1.5 |
| `pips` | a small level | defense 2 of 5 |
| `chip` | a short word | next turn "2nd" |

**⋮ or a right-click** on a card opens its `DetailModal`: the name, flags,
every stat, skills with ranks, statuses, notes, links, in tabs when there is
more than one kind of thing. Esc, the close button or a click outside close
it. A unit with one of its kind has no index ("Precinct Overseer", not
"Precinct Overseer 1").

### 9. Flags

A flag is a badge for one characteristic: Boss, Elite, Low HP, New,
Fortified, Under attack, Uprising. One style everywhere: an icon and a short
word on a fill tinted with its color role, no border, body-size text. A
crowded edge may use compact flags (icon only, name on hover). Common flags
live in `data/ui/flags.json` (`Flag.of("boss")`); a one-off uses
`Flag.make(label, icon, role, line)`.

### 10. One control strip per screen

Each screen (or gallery) has one `ControlStrip`, always on the top edge of
what it controls. Everything that changes **how** the screen shows things
goes there, in this order: choices (Size, View, Lens, Group by, Sort) as
segmented buttons, toggles (Log, Preview), then actions on the right (Home,
speed). No view control lives anywhere else.

### 11. Panels: three styles

| Style | For | Look |
|---|---|---|
| `plain` | information | a flat fill, **no border** |
| `card` | something you click, select or open | a fill and a border, brighter on hover |
| `overlay` | above the screen: modal, drawer, tooltip | a raised fill, a border and a shadow |

`UiStyle.panel("plain")` and so on. **Borders mean "you can click this".**
Information sits on plain backgrounds; a box drawn round text that does
nothing is a bug. No fourth style.

### 12. Spacing on an 8 px grid

Gaps and paddings come from `UiStyle.space()`: `xs` 4 (inside one control,
such as an icon and its number), `s` 8, `m` 16, `l` 24, `xl` 32. Sizes of
panels and cards are multiples of 8. A test checks the style check page.

### 13. Text sizes

The pixel font draws crisply at 10, 20 and 30. **Anything the player reads
to play is at least body size (20)**: names, numbers, flags, buttons,
tooltips, log lines, previews. Title size (30) is for names on a detail
modal and screen headings. Small text (10) is only for a **caption**, a
short all-caps heading over a group whose contents carry their own text
(`UiStyle.caption(label)`). No tiny grey text for anything that matters.
Quiet (grey) text is body size and only labels a value shown beside it.

### 14. Color roles

Name colors by role, not by hue: `UiStyle.role("bad")`. The roles and their
palette colors are in `data/ui/ui_kit.json` `color_roles`:

| Role | Means |
|---|---|
| `text`, `title`, `text_quiet` | reading text, names, labels for a value |
| `interactive` | something you can press; the selected option |
| `good`, `bad`, `caution` | gains and health; losses, danger, enemies' threat; warnings |
| `info` | Energy and neutral numbers |
| `ally`, `enemy` | sides |
| `rare` | Boss, Elite, rare things |
| `hint` | keywords, previews, the result of a formula |
| `neutral` | down, inactive |

### 15. Tooltips explain the math

A number that comes from other numbers shows how in its tooltip, with the
real values: `ATK 12 − DEF 8 × (1 − Pierce 20%) = 6`. Build the line with
`UiFormula` (`UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)`)
and pass it as `math` to `StatStrip`, `IconStat.set_math`,
`DetailModal.rows` or `UiTooltip.set_math`. A number from simulations says
so: "Won 20 of 32 simulated fights".

### 16. Tabs, changes and feedback

Related content on one page goes in `UiTabs` (Region / Squad / Log; Summary /
Growth / Details) rather than one long column. A visible UI change gets a
line in the "What's new" card, which links to F8 feedback.

### Exceptions

Dev tools (the F4 switchboard, `ui/dev/`) may stay text-heavy.

### Stand-ins

TODO(decision: ui-style-icon-art): every icon is generated placeholder art.
TODO(decision: ui-system-ring): the ring gauge is drawn arcs, not pixel art.
TODO(decision: ui-style-bold): the pixel font has no bold face; names are
"bold" by a one-pixel outline in their own color (`UiTooltip._bold`).
