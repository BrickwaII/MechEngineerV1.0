# Mech Engineer

Godot 4.6, GDScript, gdUnit4. A turn-based tactical roguelike: a squad of bots
fights enemies across a territory map under a countdown.

Design source of truth: https://claude.ai/artifact/Lkdta9UVJ1wbxcWdbG6LvL
Build plan and task list: https://claude.ai/code/artifact/5b07a253-5012-4e73-a455-bb9356f10175
Overworld layout mockup: https://claude.ai/artifact/4xtZSietnJE6UNHu3kJZ9P
Build Board: https://claude.ai/artifact/T31MSnVskLzhNyQiDxDYNM

## Layers and import rules
contracts/   Shared interfaces and stubs. Imports nothing. Every folder may import it.
bot_data/    Layer 1. Pure state: stats, personality, skills, augment slots. No behavior.
fight/       Layer 2. Combat, energy, intent, preview, post-fight.
             May import bot_data and contracts.
campaign/    Layer 3. Map, time, pressure, run state.
             May import contracts only until the integration step.
ui/          Screens and input. May import any layer. Nothing outside ui/ imports ui/.
tools/       Dev tools. May import any layer except ui/.
data/        Region files, tuning tables. Hand-edited, no code.
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
