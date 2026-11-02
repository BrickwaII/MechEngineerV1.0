# Mech Engineer — Combat & Leveling Deep Dive

Nov 2, 2026 · @Henry Greenhut

## Summary

Combat collapses to "spam the biggest attack" because nothing in a fight ever makes a different action better. Every reference game avoids this the same way: each turn the player faces more threats and opportunities than their resources can answer, so they must choose which to answer, when, and with what. The fix is not more abilities. It is giving enemies questions that the biggest attack answers badly, and giving actions costs beyond energy.

The six changes most likely to fix it, all compatible with ATB Wait Mode, no positional depth and no random dodge:

1. **Make setup-then-payoff the main way to deal big damage.** One bot applies Exposed (Slay the Spire's Vulnerable), Overheat or Jammed; another cashes it in. The best turn becomes "set up, then hit," spread across bots, not "hit as hard as possible."
2. **Give actions a time cost, not just an energy cost.** Heavy attacks push the bot further back on the timeline (FFX / Triangle Strategy). Now "big hit" competes with "two small hits and act before the enemy's big swing."
3. **Add a defensive verb that matters only when timed.** A Brace that absorbs damage until the bot's next action, paired with spiky, telegraphed enemy attacks (Slay the Spire's Block).
4. **Give enemies breakable states.** Plating that each hit strips one layer of, and a Stagger when it hits zero (Octopath's Break). Multi-hit and typed attacks now beat the single big hit on armored targets.
5. **Add disruption verbs.** Delay, interrupt, taunt and drain actions that change an enemy's previewed intent. Into the Breach's core lesson without its grid: changing what the enemy does is more interesting than damage.
6. **Build enemies as questions.** A roster where each enemy type punishes one lazy strategy, combined so no single answer covers a fight.

There is a bonus: the three personality axes map almost one-to-one onto the three core tensions these changes create. A combat system with real choices is also what gives the personality system a meaningful signal. One-button combat would make every bot drift to the same personality.

Growth must also be bounded. Each bot caps out within its generation, upgrades get more expensive with each step, and the enemy curve outpaces a maxed bot by Act 3. The pressure to gather resources for upgrades or a stronger next generation keeps fights demanding to the end, and everything a capped bot learned still pays off through inheritance.

## Why the current combat collapses to one button

A player spams one action when that action is the best answer in every state the game produces. The fix is to make the game produce states where something else is better. Six causes usually combine:

| Cause | What it looks like | What breaks it |
| --- | --- | --- |
| Energy is the only cost | Heavy attack has the best damage per energy, so it is always correct once affordable | Time cost on the timeline; overdraw debt; diminishing damage per energy at the top end |
| No setup/payoff | Every action is self-contained, so the strongest standalone action wins | Debuffs that multiply the next hit; combos that need two bots or two actions |
| Nothing threatens you in a way damage doesn't solve | Killing fast is the best defense, so it's a pure damage race | Spiky telegraphed attacks worth bracing for; enemies that punish greed |
| Enemies are interchangeable HP bags | Target choice doesn't matter beyond "lowest HP" | Plating, healers, buffers, chargers: enemies with different priorities |
| Turn order is fixed in practice | Nothing you do changes who acts next | Delay, stagger, haste, interrupts, wait bonus |
| Leveling only adds numbers | Higher stats make the same button hit harder | Skill offers that change verbs or add conditions |

One more cause is structural: perfect information without enough pressure. If you can answer every threat each turn, the right answer becomes mechanical. A playtester of a small Slay the Spire–like on itch.io put it plainly: [attacking whenever enemies defend and defending whenever they attack carried them through the whole game](https://itch.io/post/6246627). Slay the Spire avoids this because three energy is never enough to both block everything and kill on schedule. The player must decide what to give up.

The test for every change below: **in a typical fight, no single action should be the best choice more than about half the time.** That is measurable once the simulation tooling exists (see the test plan).

## What makes a turn interesting

A turn is interesting when two or more good options pull against each other and the player can't take all of them. Across every reference game, the pulls come from the same six tensions. A strong combat system runs three or four of them at once.

- **Offense vs. defense.** Hit now, or protect against what's coming. Slay the Spire's Block vs. Strike; Bravely Default's Default; Pokémon's Protect. Only works when incoming damage is spiky and readable.
- **Spend now vs. bank for later.** Use the resource on a small effect now, or save it for a bigger one. Octopath's Boost Points, Bravely's Brave Points, Triangle Strategy's TP, Slay the Spire's retained energy. Mech Engineer already has this in battery and the wait bonus.
- **Setup vs. payoff.** Spend a turn making the next hit better instead of hitting. Slay the Spire's Vulnerable into a heavy attack; Octopath's Break into a fully boosted skill; Pokémon's Swords Dance; Hades' Duo Boons rewarding two gods together. This is the tension that turns a squad into a team: one bot sets up, another cashes in.
- **Tempo.** Act sooner and weaker, or later and stronger. ATB, FFX's turn order, Triangle Strategy's AT bar. Also the ability to push enemies back or pull allies forward.
- **Target priority.** Which threat first? Into the Breach's "which building do I let get hit," Slay the Spire's kill-the-summoner-or-the-summons, Monster Train's which floor to reinforce.
- **Fast vs. safe fight length.** Some enemies scale every turn, punishing slow play (Gremlin Nob, Monster Train bosses). Others front-load damage, punishing greed. Mech Engineer adds a third pressure: longer fights drain grid capacity.

Two cross-cutting rules make these tensions bite:

1. **Pressure must exceed resources.** The player should have roughly two good answers' worth of resources against three threats each round. If they can answer everything, play becomes rote.
2. **Information must be honest.** Slay the Spire's widely praised design rests on [showing each enemy's plan for the coming turn](https://www.lesswrong.com/posts/MEimkSwwuRgiPaZaY/review-slay-the-spire), and Into the Breach [shows the outcome of actions before you commit](https://blog.prototypr.io/into-the-breachs-ux-makes-you-feel-smart-a9cb03210757). Perfect information moves difficulty from luck to judgment. Mech Engineer's intent preview and no-dodge rule already commit to this.

## Game-by-game teardown

Each reference game owns one or two mechanisms worth stealing. The last column is what transfers to Mech Engineer given ATB Wait Mode, no grid positioning and no random dodge.

| Game | Core mechanism | Why it creates choices | Lesson for Mech Engineer |
| --- | --- | --- | --- |
| Final Fantasy ATB (IV–IX, VII) | Speed fills a gauge; Haste, Slow and Stop alter it; Limit Breaks fill from damage taken | Time itself is a resource you can buy and deny | Make speed manipulation an action category, not just a stat |
| Final Fantasy X (CTB) | Visible turn order; heavier actions delay your next turn | Every action is priced in time; you can see the price | Heavy attacks should cost timeline position, shown in the preview |
| [Octopath Traveler](https://en.wikipedia.org/wiki/Octopath_Traveler) | Shields broken by weaknesses; Break stuns and delays; Boost Points bank 1/turn, spend up to 3 | Chip shields with small hits, then dump banked BP into the stunned enemy | Plating + Stagger; banked energy cashed into a broken target |
| [Bravely Default](https://game-wisdom.com/analysis/bravely-default-reconstruction-efforts) | Default guards and banks a point; Brave borrows up to 4 actions, going into debt | Burst now at the cost of future turns; enemies do it too | An Overdraw option: act on future energy, stall afterward |
| Pokémon | Type chart; 4-move limit; setup moves; status; switching | Matchups and a tight loadout force specialization | Typed augments (ice, shock) vs. enemy resistances; small skill slots |
| Triangle Strategy | AT bar; free basic attack; TP +1/turn for skills; Inaction Bonus; follow-up attacks | Every turn: build TP with a free action, or spend it | Free basic action that charges; wait bonus; ally follow-ups |
| Slay the Spire | Intents; Block expires each turn; 3 energy; Vulnerable/Weak; HP persists | Can't block everything and kill on time; debuffs set up payoffs | Brace that expires; Exposed debuff; attrition across fights |
| [Monster Train](https://www.pressreader.com/australia/edge/20200716/283794266093188) | Three floors, capacity limits; enemies climb; relentless bosses | Each turn starts with "can I survive this?" before "can I win?" | Multiple simultaneous threats; boss phases that won't wait |
| Hades | Boons modify a few core verbs; Duo Boons need two gods | Choices change how you play, not just how hard you hit | Skill offers that modify verbs; cross-bot "duo" skills |
| [Into the Breach](https://blog.prototypr.io/into-the-breachs-ux-makes-you-feel-smart-a9cb03210757) | Perfect telegraphs; push/redirect enemies; outcome preview | Best moves cancel or redirect enemy attacks rather than kill | Disruption verbs that change an enemy's intent |

Three patterns show up again and again:

- **Small hits have a job.** Octopath, Slay the Spire and Into the Breach all make cheap, weak actions useful by tying them to enemy states (shields, multi-hit triggers, pushes). Mech Engineer's current problem is that small attacks have no job.
- **Burst is earned, not available.** Octopath's 3-BP boost into a broken enemy and Slay the Spire's Vulnerable-plus-heavy-attack are satisfying because they took setup. Bravely Default lets you burst anytime, but [you pay with lost future turns](https://www.hardcoregaming101.net/bravely-default/).
- **The best defense is sometimes offense on the right target.** Breaking an Octopath enemy delays its attack; killing the Slay the Spire attacker removes its intent; Into the Breach pushes the attacker away. Damage and defense should overlap through timing.

## Leveling and progression

Growth feels good when it changes what you do. Growth that only raises numbers makes the dominant button more dominant. Every reference game that keeps combat fresh to the end ties progression to new verbs, new conditions or new combinations.

**What the references do**

- **Pokémon:** levels add stats, but the memorable moments are new moves that force a 4-slot decision. The replace-a-move prompt is a choice, not a reward.
- **Bravely Default / FF V jobs:** abilities from one job carry into another, so growth is about combinations (a support skill from job A making job B's attack better).
- **Slay the Spire:** most rewards are new cards that change your options, and skipping or removing cards matters as much as adding them. Upgrades usually change a card's function slightly (cost, an extra effect), not just its number.
- **Hades:** boons attach to fixed verbs (attack, special, cast, dash). Each one changes how a verb behaves, and Duo Boons reward investing in two gods together. Build identity emerges from a few strong modifiers.
- **Octopath:** support skills and secondary jobs add rules ("attacks hit twice when boosted") that reshape the break-and-boost loop.

**Rules for Mech Engineer's leveling**

1. **Raw stat growth should keep pace with enemies, not outpace them.** Stats keep the relative power ratio steady. Player advantage should come from skills and synergy, so a skilled player feels stronger than an unskilled one at the same level.
2. **Skill offers should mostly modify verbs.** "Heavy Shot strips 2 plating," "Brace also delays the attacker," "Hitting an Exposed enemy refunds 2 energy." Flat "+15% damage" offers should be rare, because they reinforce the one-button pattern.
3. **Synergy offers should name another bot's action or status.** These are Mech Engineer's Duo Boons: "When an ally Staggers an enemy, this bot's next attack costs 0." They make squad composition a decision.
4. **Named variants (already settled) should mark a change in role,** e.g. Heavy Attack becoming "Breaker Beam" when it gains multi-hit and stops being a single big hit.
5. **Limited slots force trade-offs.** Augment slots already do this. Keep active skills per bot small too (roughly 3–5), so a new skill means giving up an old one, as in Pokémon.

**Why this matters for personality.** Personality drift reads from action tags. If combat collapses to one button, every bot logs the same tags and drifts to the same personality, so skill offers converge too. Diverse combat choices are the input the personality system needs. Fixing combat fixes the signal for leveling as well.

## Bounded growth and generations

Every bot should hit a ceiling within a run, so the only way to keep pace with the enemy curve is to spend resources upgrading it or to replace it with a stronger next-generation bot. Unbounded growth would let one well-built squad steamroll the late game and make the payload and resource economy pointless.

&#91;embedded content: bot lifecycle · grow, cap, upgrade or retire\]

Upgrading buys a bot a little more time at a rising price; retiring turns everything it learned into a stronger child.

**How the references cap growth**

| Game | The cap | What pushes past it |
| --- | --- | --- |
| Pokémon | Level 100; 510 total EVs; IVs fixed at birth | Breeding for better IVs and egg moves |
| Fire Emblem (Awakening, Fates) | Level cap per class; stat caps | Class change items; children inherit parents' classes and skills |
| Into the Breach | Pilots cap at level 2 | Swapping in a new pilot or better weapons |
| Monster Train | Each unit has a fixed number of upgrade slots | Choosing which upgrade to spend a slot on; new units |
| Slay the Spire | Each card upgrades once | Adding new cards rather than growing old ones |
| Darkest Dungeon | Hero level caps; stress and afflictions wear heroes down | Retiring and recruiting fresh heroes |

The shared pattern: a unit's growth is finite and its slots are scarce, so investment in it is a real choice, and replacement is a normal part of play rather than a failure.

**Proposed limits for Mech Engineer**

1. **Generation caps.** Each generation has a ceiling on skill levels and stats, building on the settled band idea (Gen 1 skills reach level 5; a Gen 2 child inherits a raised band such as 3–7). A bot cannot exceed its generation's band by leveling alone.
2. **Chassis upgrades as the costly middle option.** Spending Material and Energy can push one bot's cap up a step or add an augment slot. Each step costs more than the last, so upgrading an old bot gets steadily worse value than waiting for the next payload.
3. **Wear.** Bot durability decay (the settled Fight horizon) should leave a small persistent mark: repairs cost resources, and heavily used bots pick up fatigue that lowers max durability until overhauled. This keeps a single star bot from carrying every fight.
4. **Scarce slots.** Fixed augment slots (settled) plus a small active-skill limit mean a capped bot also runs out of room. New skill offers then become trade-offs, not additions.
5. **The enemy curve outpaces a capped bot.** A maxed Gen 1 bot should comfortably handle Act 1, struggle in Act 2 elites and fall clearly behind in Act 3. That gap is the pressure to invest.

**Upgrade, replace or retire.** Between fights the player chooses among three uses of resources for each bot:

| Choice | Cost | Gains | Best when |
| --- | --- | --- | --- |
| Upgrade | Material + Energy, rising each step | Keeps a proven bot competitive a little longer | The bot is close to a key skill variant or crystallization |
| Replace | Resources toward the next payload | A next-generation bot with higher caps | The bot has hit its cap and the payload is near |
| Retire into lineage | Bot leaves the active squad | Its crystallized traits and raised skill caps pass to offspring | The bot's development is worth more as inheritance than as a fighter |

**Why a capped bot is still worth developing.** Growth that ends in a ceiling only feels bad if it's wasted. Here it isn't: everything a bot learns (crystallized traits, skill levels, personality scales) feeds its offspring, as in Fire Emblem's child units and Pokémon egg moves. Developing a bot is investing in the next generation. Henry has framed this as summoning future bots, so retirement can be presented as the bot's data going into the next timeline rather than as loss.

**How this protects combat.** Caps keep the squad's power and the enemy's power close throughout the run, so the decisions in the previous sections stay necessary to the final boss. They also keep the Brace, combo and disruption verbs relevant: a squad that could simply out-level every enemy would drift back to pressing the biggest attack.

**Open questions**

- Should a bot's cap be visible from the start, so players plan around it?
- Does wear apply per fight or only to bots that took heavy damage?
- Can a retired bot be recalled from lineage later, or is retirement permanent?

## Fun and fair from fight 1 to the final boss

Early fights should be easy to win and hard to win cleanly. That is Slay the Spire's Act 1 trick: you almost never lose to a Jaw Worm, but sloppy blocking costs HP you need later. Mech Engineer already has the equivalent costs: bot durability across a fight and grid capacity drained by longer fights. Grade fights by what they cost, not only by win or loss.

&#91;embedded content: run difficulty curve · 5 stages\]

Each stage adds questions the previous one didn't ask; enemy stats only keep pace with the squad's.

**How difficulty should grow.** Raise the number of simultaneous questions, not enemy HP. Enemy stats should scale with the player's, while difficulty comes from:

- More enemy types at once, so one answer no longer covers the fight.
- Faster enemy timelines, so the player gets fewer actions between threats.
- Enemies that react to the player (intent switches when an ally is hurt, as already designed).
- Enemies that scale during the fight, punishing turtling and stalling.

**Bosses as strategy checks.** Slay the Spire's bosses each punish a degenerate pattern: Time Eater punishes playing many cards, Awakened One punishes Power cards, Guardian punishes attacking into its defensive mode. Mech Engineer's bosses at each payload should do the same. One boss should punish repeated identical actions, another heavy single hits, another a lone carry bot. This keeps "spam one button" from surviving a run even if it works in normal fights.

**Elites test builds; normal fights test execution.** This matches the normal-vs-elite territory risk already in the design. A normal fight introduces or combines one or two questions. An elite asks a question the current build may not answer well, which is why choosing it is a gamble.

**Fairness rules:**

- Every damage number in the preview is exact, or marked unknown (already settled).
- No enemy should be able to kill a full-HP bot from out of nowhere. Lethal attacks need a telegraph at least one ally action in advance.
- New mechanics get introduced alone before they appear in combination.
- Defeat should always be traceable to a choice the player made.

## Proposals for Mech Engineer

These proposals keep every settled decision: ATB Wait Mode, shared energy economy, battery as an MP-style pool, the wait bonus, reactive intent preview, no grid positioning and no random dodge. All names and numbers are starting points for tuning.

### 1. Combos and cross-bot synergy (setup → payoff)

Big damage should come from combinations, not from one big button. The ATB timeline gives Mech Engineer a twist none of the card games have: **every setup has a visible window**. A status lasts until a point on the timeline, so the player can see whether the payoff bot will act before it expires.

**Setup statuses** (applied by cheap or fast actions):

| Status | Applied by | Effect | Lasts until |
| --- | --- | --- | --- |
| Exposed | Scan, Shred, multi-hit attacks | Takes +50% damage from the next hit | Consumed by a hit, or the enemy's next action |
| Overheated | Fire/energy augments, Overclock | Next ice or kinetic hit causes Thermal Shock (bonus damage + strips plating) | Enemy's next action |
| Jammed | EMP, Shock augment | Enemy's next action is delayed on the timeline | Enemy's next action |
| Marked | Target Lock | Allies with Follow-up fire a free shot when it's hit | Two ally actions |
| Charged (ally) | Power Transfer | Ally's next skill costs less or hits harder | Ally's next action |

**Payoff actions** (expensive, slow or conditional):

- **Heavy attacks** deal modest damage by default and big damage against Exposed or Staggered targets. This is the direct fix for "spam the biggest attack": the biggest attack is now a finisher, not an opener.
- **Consumers** spend a status for a larger effect. Detonate removes Overheated to Stagger the target instantly. The player chooses between keeping a status for its passive effect and cashing it in.
- **Follow-ups** trigger off an ally's action, the way Triangle Strategy's follow-up attacks do. They reward squads built around one setup bot and several attackers.

**Design rules for combos:**

1. Setups should be cheap and fast, payoffs expensive and slow, so the order matters and the timeline shows it.
2. Payoffs should consume their setup, so combos must be rebuilt rather than kept up permanently.
3. Elemental augments should combine (Overheated + ice = Thermal Shock). This ties combos to the augment and crystallization loop: an ice-crystallized bot naturally pairs with a fire-augment teammate.
4. A combo should be possible inside one bot (setup, then payoff on its next turn) but faster across two. This keeps solo builds viable at squad size 1 while rewarding teams.
5. Combo windows and their payoff should appear in the action preview: "Heavy Shot: 18 damage (36 if Rook acts first)."

### 2. Actions cost time as well as energy

Give each action a recovery value that sets how far back on the timeline the bot goes after acting, shown in the preview.

| Action type | Energy | Recovery | Role |
| --- | --- | --- | --- |
| Basic shot | 0 | Short | Free; banks a little energy, like Triangle Strategy's free attack |
| Light / multi-hit | Low | Short | Strips plating, applies setups, keeps tempo |
| Heavy attack | High | Long | Payoff; weak without a setup |
| Brace | Low | Short | Defense that lasts until the bot's next action |
| Disrupt (EMP, Delay, Taunt) | Medium | Medium | Changes an enemy's intent or timing |
| Wait | 0 | Choose a later slot | Banks bonus charge (current lean) |
| Overdraw | Spend beyond battery | Very long | Bravely-style burst; bot is stalled afterward |

### 3. Defense that matters only when timed

Brace absorbs damage up to a value set by Defense, until the bot's next action. Enemy attacks should be spiky: a Charger winds up a hit that would take 60% of a bot's HP. Bracing every turn wastes tempo; bracing at the right moment saves a bot. Guard Ally (redirect an attack onto the bracing bot) gives defensive bots a squad role.

### 4. Breakable enemy states

Plated enemies show plating pips. Each hit removes one; a matching augment type removes two. At zero, the enemy is Staggered: knocked back on the timeline, its intent cancelled, and taking bonus damage. This is Octopath's Break adapted to ATB, and it gives multi-hit attacks a job. Open question: Elasticity could set how fast a bot recovers from Stagger, or how much plating it has.

### 5. Enemies as questions

| Enemy archetype | The question it asks | Punishes | Rewards |
| --- | --- | --- | --- |
| Charger | Can you survive or stop its big hit? | Ignoring intents | Brace, Jam, Stagger before it fires |
| Plated | Can you break it? | Single big hits | Multi-hit, matching augments |
| Scaler | Can you kill it before it snowballs? | Turtling, slow setups | Burst combos |
| Medic / Booster | Who do you kill first? | Spreading damage | Focus fire, Taunt |
| Swarm | Can you handle many small threats? | Single-target builds | Area attacks, follow-ups |
| Reflector | Are you hitting blindly? | Spamming multi-hits | Reading state, single payoff hits |
| Drainer | Can you protect your battery? | Hoarding energy | Spending early, Brace |
| Overclocker | Can you keep up with something faster? | Slow heavy builds | Delay, Jam, fast actions |

Note that the roster includes counters to the counters: Reflector punishes multi-hit spam just as Plated punishes heavy spam. No single action should beat every fight.

### 6. Personality axes map onto the tensions

Which actions map to which axes is still open. These tensions offer a natural mapping, for Henry to accept or reject:

| Axis | Toward the first pole | Toward the second pole |
| --- | --- | --- |
| Aggressive ↔ Defensive | Attacks, Overdraw, payoffs | Brace, Guard Ally |
| Solitary ↔ Supportive | Self-setups, solo payoffs, self-buffs | Setups an ally cashes, Power Transfer, follow-ups |
| Reactive ↔ Methodical | Acting immediately, interrupts answering intents | Waiting, banking energy, setting up for later turns |

### A worked turn

Three bots face a Plated Charger winding up a big hit and a Medic. The timeline shows: Rook, Charger, Vale, Medic, Kestrel.

- The lazy play: Rook fires Heavy Shot at the Charger. It hits plating for small damage. The Charger's big hit lands.
- The good play: Rook uses Shred (multi-hit), stripping the Charger's last two plates. It Staggers, its hit is cancelled and it drops behind the Medic on the timeline. Vale Marks it. Kestrel fires Heavy Shot into a Staggered, Marked target, triggering Vale's follow-up. Rook spent less energy, the bot took no damage, and the Charger died.

That difference in outcome is the skill expression the game needs.

## Prototype and test plan

Build the smallest fight that can prove the tensions work, measure it, and only then touch leveling. Leveling built on top of one-button combat will inherit the problem.

**Build order**

1. **Sandbox fight:** 3 bots vs. 3 enemies in the scenario builder, no meta layer, no leveling.
2. **Minimal action kit per bot (5 verbs):** Basic shot, Shred (multi-hit, applies Exposed), Heavy Shot (payoff), Brace, Wait. Add time costs to the timeline preview.
3. **Three enemies:** Charger, Plated, Scaler. Each asks a different question, and together they can't all be answered with one action.
4. **One cross-bot synergy:** Exposed into Heavy Shot, with the bonus shown in the preview. This is the Vulnerable-into-big-attack loop, and it is the first combo to prove out.
5. **Then add, one at a time:** Disrupt verbs, Marked + Follow-up, Overheated + Thermal Shock, Overdraw. Re-run the tests after each.

**Tests that tell you if it's fun**

- [ ] **Greedy-bot test.** Write an AI that always uses the highest-damage affordable action. Run it against a smarter scripted policy across 100 simulated fights. The greedy bot should lose noticeably more bot HP and grid capacity. If it doesn't, a dominant strategy still exists.
- [ ] **Action-share test.** Log action usage from real play. No single action should exceed about 50% of uses in a typical fight.
- [ ] **Hard-choice test.** After each playtest fight, note how many turns had two options you genuinely weighed. Target: most turns.
- [ ] **Clean-win gap.** The same fight played well vs. carelessly should differ clearly in HP and capacity lost, even when both win.
- [ ] **Readability test.** A new player should predict the outcome of their action from the preview alone, without surprise.

**Watch for these failure modes**

- Combos so strong that setup-then-payoff becomes the new single button. Counter with Reflector-style enemies and statuses that expire on the enemy's action.
- Brace becoming rote if every enemy telegraphs every turn. Not every enemy should attack every turn.
- Too many statuses at once. Start with Exposed alone and add others only when the fight feels solved.

## Sources

Mechanics descriptions draw mainly on general knowledge of these games; the pages below support specific points.

- [Slay the Spire: Metrics Driven Design and Balance — GDC 2019 (Anthony Giovannetti)](https://www.gdcvault.com/browse/gdc-19/play/1025731)
- [Review: Slay the Spire — LessWrong](https://www.lesswrong.com/posts/MEimkSwwuRgiPaZaY/review-slay-the-spire)
- [Into the Breach Design Postmortem — GDC 2019 (Matthew Davis)](https://gdcvault.com/play/1025772/-Into-the-Breach-Design)
- [Into the Breach's UX makes you feel smart — Prototypr](https://blog.prototypr.io/into-the-breachs-ux-makes-you-feel-smart-a9cb03210757)
- [Octopath Traveler — Wikipedia](https://en.wikipedia.org/wiki/Octopath_Traveler)
- [Bravely Default: Reconstruction Efforts — Game Wisdom](https://game-wisdom.com/analysis/bravely-default-reconstruction-efforts)
- [Bravely Default — Hardcore Gaming 101](https://www.hardcoregaming101.net/bravely-default/)
- [Monster Train review — Edge, July 2020](https://www.pressreader.com/australia/edge/20200716/283794266093188)
- [Playtester note on mechanical intent responses — itch.io](https://itch.io/post/6246627)
