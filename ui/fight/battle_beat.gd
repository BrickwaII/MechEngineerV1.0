class_name BattleBeat
extends RefCounted
## One action as the battle shows it: who acts, with which skill fx, what
## lands on whom (the action's FightEvents), and when each part plays. Needs
## no scene; BattlePresenter plays beats one at a time.
##
## A skill beat is wind-up, strike, recover (data/feel/feel.json attack parts,
## 300-600 ms together); everything lands at the end of the strike. A wait
## beat is a wind-up (the unit gathers charge) and a recover. Times follow the
## animation speed setting; the skill's level never changes them.

enum Kind { SKILL, WAIT }

var kind := Kind.SKILL
var actor_id := ""
## The actor's own skill, or null when it is unknown.
var skill: CombatSkill
var events: Array[FightEvent] = []
## SkillFx.for_skill() of the skill used.
var fx := {}
var windup := 0.0
var strike := 0.0
var recover := 0.0


static func from_events(fight: Fight, p_events: Array[FightEvent], settings: GameSettings = null) -> BattleBeat:
	var beat := BattleBeat.new()
	beat.events = p_events.duplicate()
	if p_events.is_empty():
		return beat
	var first := p_events[0]
	beat.actor_id = first.actor_id
	beat.kind = Kind.WAIT if first.kind == FightEvent.Kind.WAIT else Kind.SKILL
	var actor := fight.combatant(first.actor_id) if fight != null else null
	beat.skill = actor.skill(first.skill_id) if actor != null else null
	if beat.skill == null and fight != null:
		beat.skill = fight.tuning.skill(first.skill_id)
	beat.fx = SkillFx.for_skill(beat.skill) if beat.skill != null else SkillFx.for_fx("", first.skill_level)
	beat.windup = FeelTween.seconds("attack_windup", settings)
	beat.recover = FeelTween.seconds("attack_recover", settings)
	beat.strike = FeelTween.seconds("attack_strike", settings) if beat.kind == Kind.SKILL else 0.0
	return beat


## Seconds from the start to the strike (projectiles leave, the sound starts).
func strike_at() -> float:
	return windup


## Seconds from the start to the moment hits, heals and guards land.
func impact_at() -> float:
	return windup + strike


func duration() -> float:
	return windup + strike + recover


func of_kind(p_kind: FightEvent.Kind) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	for e in events:
		if e.kind == p_kind:
			out.append(e)
	return out


## The first event of the action: SKILL or WAIT.
func lead() -> FightEvent:
	return events[0] if not events.is_empty() else null


## Units something lands on, in order, without repeats.
func target_ids() -> Array[String]:
	var out: Array[String] = []
	for e in events:
		if e.kind in [FightEvent.Kind.HIT, FightEvent.Kind.HEAL, FightEvent.Kind.GUARD] and not e.target_id in out:
			out.append(e.target_id)
	return out


## The unit the action was aimed at (Arc Sweep names one of its targets).
func aimed_at() -> String:
	var e := lead()
	if e != null and not e.target_id.is_empty():
		return e.target_id
	var targets := target_ids()
	return targets[0] if not targets.is_empty() else ""


func motion() -> String:
	return str(fx.get("motion", "lunge"))
