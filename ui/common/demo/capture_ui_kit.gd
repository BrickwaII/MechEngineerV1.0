extends CaptureScript
## Renders the UI kit demo to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/common/demo/capture_ui_kit.gd -- <out_dir>
## Writes ui_kit.png, ui_kit_tooltip.png (a skill card's tooltip open) and
## keyword_hover.png, keyword_pinned.png, keyword_in_keyword.png (keyword links).


func _init() -> void:
	start("res://ui/common/screenshots")


func _run() -> void:
	var demo: Control = load("res://ui/common/demo/ui_kit_demo.tscn").instantiate()
	root.add_child(demo)
	for i in 10:
		await process_frame
	await save("ui_kit")
	var card: SkillCard = demo.first_card
	UiTooltip.show_at(card, card.global_position + Vector2(card.size.x * 0.5, card.size.y + 4))
	for i in 6:
		await process_frame
	await save("ui_kit_tooltip")
	UiTooltip.hide_tooltip()
	# Keyword links: hover a keyword on a card, pin it, then hover a keyword
	# inside the pinned box.
	var effect: RichTextLabel = card.effect_label
	var at := effect.global_position + Vector2(90, 8)
	root.warp_mouse(at)
	KeywordPopup.hover("kw:Pierce", effect)
	await frames(4)
	await save("keyword_hover")
	KeywordPopup.click("kw:Pierce", effect)
	await frames(4)
	await save("keyword_pinned")
	var pinned: Node = KeywordPopup._popup._pin_box
	var text: RichTextLabel = pinned.find_child("Text", true, false)
	root.warp_mouse(text.global_position + Vector2(120, 6))
	KeywordPopup.hover("kw:Defense", text)
	await frames(4)
	await save("keyword_in_keyword")
	quit()
