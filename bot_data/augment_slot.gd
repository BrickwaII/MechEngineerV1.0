class_name AugmentSlot
extends Resource
## One augment slot on a bot. Structure only: nothing is equippable yet and an
## augment has no effect. augment_id stays empty until augments exist.

@export var augment_id: String


func _init(p_augment_id := "") -> void:
	augment_id = p_augment_id


func is_empty() -> bool:
	return augment_id.is_empty()
