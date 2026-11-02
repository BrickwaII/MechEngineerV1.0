# Mech Engineer

Godot 4.6, GDScript, gdUnit4. A turn-based tactical roguelike: a squad of bots
fights enemies across a territory map under a countdown.

Design source of truth: https://claude.ai/artifact/Lkdta9UVJ1wbxcWdbG6LvL
Build plan and task list: https://claude.ai/code/artifact/5b07a253-5012-4e73-a455-bb9356f10175
Overworld layout mockup: https://claude.ai/artifact/4xtZSietnJE6UNHu3kJZ9P
Build Board: https://claude.ai/artifact/T31MSnVskLzhNyQiDxDYNM

## Layers and import rules
contracts/   Shared interfaces and stubs. Imports nothing. Every folder may import it.
lib/         Generic helpers with no game rules: JSON files, checked data
             reading, switchboard variant sets, number text. Imports nothing.
             Every folder but contracts/ may import it. ui-only helpers go in
             ui/common/, tools-only ones in tools/.
bot_data/    Layer 1. Pure state: stats, personality, skills, augment slots. No behavior.
fight/       Layer 2. Combat, energy, intent, preview, post-fight.
             May import bot_data and contracts.
campaign/    Layer 3. Map, time, pressure, run state.
             May import contracts only until the integration step.
ui/          Screens and input. May import any layer. Nothing outside ui/ imports ui/.
tools/       Dev tools. May import any layer except ui/.
data/        Region files, tuning tables. Hand-edited, no code.
             Every layer except contracts/ and lib/ may read it.
tests/       Mirrors the source tree. May import anything.
addons/      Third-party code (gdUnit4). Not ours; do not edit.
scripts/     Shell scripts, such as the test runner.

A test fails if an import breaks these rules: tests/architecture/. A file
imports a layer when it names a res:// or uid:// path in it (preload, load,
extends, a scene's ext_resource) or uses a class_name declared there. When a
rule changes, change ALLOWED in tests/architecture/layer_rules.gd and this
section in the same pull request.

## Contracts
Six types in contracts/, each with a test in tests/contracts/:
UnitStats, SquadMemberSummary, SquadProvider (stub: StubSquadProvider),
FightRequest, FightResult, FightService (stub: StubFightService).
The overworld talks only to SquadProvider and FightService, so real bots and
real fights swap in for the stubs with no map change.

## Testing
- Test command: `scripts/run_tests.sh`
  Runs every suite under tests/ headless, no editor. Needs Godot 4.6 as
  `godot` on PATH or in `$GODOT_BIN`. Exit code 0 means all passed.
- One folder only: `scripts/run_tests.sh -a res://tests/contracts`
- Test files end in `_test.gd` and extend GdUnitTestSuite.
- Reports land in reports/ (git-ignored). CI runs the same script on every
  pull request: .github/workflows/tests.yml.
- In headless mode Godot sends no input events, so UI input tests need a
  display (xvfb-run) and a different command.
- Golden check: `scripts/golden_check.sh [BASE_REF] [--quick]` captures
  fixed-seed outputs (fights, tool reports, autoplay, maps, saves, journaled
  runs) from the working tree and from BASE_REF (default origin/main) and
  diffs them. Run it on refactors: identical output means no behavior changed.

## Working rules
- Stay inside your own folders. A change to contracts/ is its own pull request.
- Every tunable number lives in data/, never inline.
- Logic that needs no scene runs headless and has gdUnit4 tests.
- UI work: attach a screenshot to the pull request.
- No random dodge anywhere. Fights are deterministic for a given seed.
- When an open decision blocks you, use the stated default, mark the code
  TODO(decision: <id>), and list it in the pull request.
- Update your rows on the Build Board when you start and finish a task.
- Commit Godot's .uid files alongside the scripts and scenes they belong to.

## Combat rework ground rules
For combat rework sessions (S0-S17 in docs/design/combat-rework-plan.md).
Read docs/combat-rework-map.md first: it maps the plan's names onto this repo,
and later briefs follow it.
1. Layers. Bot state lives in bot_data/ (plus contracts/), in-fight rules in
   fight/, between-fight growth in fight/post_fight/, the run in campaign/.
   The import rules above still hold. fight/ code never names campaign/ or
   lineage and payload code; it reads generation only through bot_data
   accessors such as Personality.is_active().
2. Tuning lives in data/ as JSON, read through lib/JsonFile by a typed loader
   class with from_dict() and validate(). Read the plan's "Resource (.tres)"
   as "a data file plus its loader". ActionDef, StatusDef and
   EnemyArchetypeDef live in fight/ with their data in data/combat/. Saved
   state (Bot, Skill, Personality, squads) stays Resources.
   TODO(decision: tuning-format).
3. Deterministic. No random dodge. Any randomness takes a seeded
   RandomNumberGenerator passed in (HeadlessFightRunner.policy_rng for
   policies). Fights replay from request, seed and the decision list.
4. Every rule gets a gdUnit4 test that runs headless (scripts/run_tests.sh).
   tests/fight/preview/preview_matches_resolution_test.gd stays green; a new
   piece of fight state is copied in Combatant.clone_for_preview() and
   FightCopy, with a test fight that uses it.
5. Combat emits events. Every action, status applied or consumed, Stagger and
   damage instance raises a FightEvent; add Kind values rather than side
   channels. Change the damage formula in one place and have
   ui/fight/battle_math.gd read it, not copy it.
6. Preview is read-only: it works on FightCopy, never the live fight.
7. One session, one scope, one PR. End with tests green and a PR summary.
   Add open questions to docs/design/combat-rework-questions.md (sessions
   cannot edit the plan doc). If the brief is wrong, stop and report.
8. Golden check. Run scripts/golden_check.sh against origin/main and put a
   "Golden check" section in the PR: "identical", or each changed capture
   with one line on why. Land new rules on new content first (actions,
   statuses and enemies nothing else uses yet) so goldens stay identical. A
   change to existing behaviour is its own commit, explained, and goes behind a
   FightVariants switch when S10 needs to compare old and new.
   `scripts/golden_check.sh combat-rework-base` shows the drift since the
   rework began.
