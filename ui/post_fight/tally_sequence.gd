class_name TallySequence
extends RefCounted
## The post-fight count-up as a list of timed steps, with no scene. Each bot's
## steps play in order, one bot after another:
##
##   bot      the bot's panel comes in
##   count    one "what it did" counter counts up from 0
##   skill    a skill's uses count up
##   level_up the payoff: the skill's new level pops
##   shift    the payoff: a personality scale slides to its new value
##   gap      a short pause before the next bot
##
## The readout calls advance() every frame, reveals the steps it returns and
## reads progress() to draw the step in flight. skip() finishes everything at
## once. Durations come from data/feel/screens.json "readout" and follow the
## animation speed setting; with animations skipped the whole tally is done
## from the start.

class Step:
	var kind := ""
	## Index of the bot in the report.
	var bot := 0
	## count: the ActionTag label; shift: the Personality scale.
	var key: Variant
	## What a count or skill step counts up to.
	var to := 0
	var change: SkillChange
	var duration := 0.0

	func _init(p_kind: String, p_bot: int, p_duration: float) -> void:
		kind = p_kind
		bot = p_bot
		duration = p_duration


var steps: Array[Step] = []
var settings: GameSettings
## Index of the step in flight; steps.size() when done.
var current := 0
## Seconds into the step in flight.
var elapsed := 0.0
## The last step advance() or skip() reported as started.
var _last_started := -1


func _init(report: PostFightReport, p_settings: GameSettings = null) -> void:
	settings = p_settings
	if report == null or not report.error.is_empty():
		return
	for i in report.bots.size():
		_add_bot(i, report.bots[i])
	if not steps.is_empty() and steps[-1].kind == "gap":
		steps.pop_back()


func is_done() -> bool:
	return current >= steps.size()


## Total length in seconds.
func total_seconds() -> float:
	var total := 0.0
	for step in steps:
		total += step.duration
	return total


## 0 to 1 through step `index`: 1 for steps done, 0 for steps not started.
func progress(index: int) -> float:
	if index < current:
		return 1.0
	if index > current or is_done():
		return 0.0 if index > current else 1.0
	var step := steps[index]
	return 1.0 if step.duration <= 0.0 else clampf(elapsed / step.duration, 0.0, 1.0)


## What a count or skill step shows right now: 0 up to its total.
func shown_count(index: int) -> int:
	return roundi(steps[index].to * progress(index))


## Moves the tally forward by `delta` seconds. Returns the indices of the
## steps that started, in order (including the first step on the first call).
func advance(delta: float) -> Array[int]:
	if not is_done():
		elapsed += delta
		while not is_done() and elapsed >= steps[current].duration:
			elapsed -= steps[current].duration
			current += 1
		if is_done():
			elapsed = 0.0
	return _start_up_to(mini(current, steps.size() - 1))


## Finishes the tally. Returns the indices of the steps that had not started.
func skip() -> Array[int]:
	current = steps.size()
	elapsed = 0.0
	return _start_up_to(steps.size() - 1)


func _start_up_to(last: int) -> Array[int]:
	var started: Array[int] = []
	for i in range(_last_started + 1, last + 1):
		started.append(i)
	_last_started = maxi(_last_started, last)
	return started


func _add_bot(index: int, r: BotFightReport) -> void:
	steps.append(Step.new("bot", index, _seconds("readout.bot_in_ms")))
	for label: String in ActionTag.ALL_LABELS:
		var count: int = r.label_counts.get(label, 0)
		if count > 0:
			var step := Step.new("count", index, _count_seconds(count))
			step.key = label
			step.to = count
			steps.append(step)
	for change in r.skill_changes:
		var step := Step.new("skill", index, _count_seconds(change.uses))
		step.change = change
		step.to = change.uses
		steps.append(step)
		if change.has_bot_skill() and change.levels_gained() > 0:
			var payoff := Step.new("level_up", index, _seconds("readout.level_up_ms"))
			payoff.change = change
			steps.append(payoff)
	for scale in Personality.SCALE_COUNT:
		if r.is_scale_active(scale) and not is_zero_approx(r.shift(scale)):
			var step := Step.new("shift", index, _seconds("readout.shift_ms"))
			step.key = scale
			steps.append(step)
	steps.append(Step.new("gap", index, _seconds("readout.between_bots_ms")))


## A row that counts to `count`: one count step each, at least a row's
## entrance, at most count_max_ms.
func _count_seconds(count: int) -> float:
	var ms := clampf(count * ScreenFeel.number("readout.count_step_ms"), ScreenFeel.number("readout.row_in_ms"),
		ScreenFeel.number("readout.count_max_ms"))
	return _s().scale_seconds(ms / 1000.0)


func _seconds(path: String) -> float:
	return ScreenFeel.seconds(path, _s())


func _s() -> GameSettings:
	return settings if settings else GameSettings.shared()
