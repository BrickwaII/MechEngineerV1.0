extends CaptureScript
## Renders escalation for the pull request: the alert meter and a tier news
## card after act 1 reaches Local Concern, the meter's tooltip, then fortified
## regions with their tooltip and news card some days later. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/overworld/capture_escalation.gd -- <out_dir>

const OVERWORLD := "res://ui/overworld/overworld.tscn"


func _init() -> void:
	start("res://ui/overworld/screenshots")


func _run() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await frames(5)
	var c: Campaign = screen.campaign
	await save("r2b_alert_unnoticed")
	# Take ground next to held ground until the alert rises.
	while c.escalation.tier() < 1:
		for region in c.map.regions:
			if c.standing(region.id) == Campaign.Standing.IN_RANGE:
				c._set_owned(region.id, true)
				break
	c.changed.emit()
	await frames(90)
	await save("r2b_alert_meter_and_news")
	screen.escalation_hud.news.clear()
	var meter: Control = screen.escalation_hud.meter
	UiTooltip.show_at(meter, meter.global_position + Vector2(0, meter.size.y + 4))
	await frames(5)
	await save("r2b_alert_tooltip")
	UiTooltip.hide_tooltip()
	var per_level := int(Escalation.load_data().fortify.days_per_level)
	for i in per_level * c.escalation.max_fortify():
		c.escalation.advance_day()
	c.changed.emit()
	for region in c.map.regions:
		if c.escalation.fortify_of(region.id) > 0 and c.standing(region.id) == Campaign.Standing.IN_RANGE:
			screen.map_view.select(region.id)
			screen.map_view._tip_fortify(region.id)
			break
	await frames(90)
	await save("r2b_fortified_region")
	quit()
