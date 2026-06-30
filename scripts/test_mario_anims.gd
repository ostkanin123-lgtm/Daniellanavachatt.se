extends Node

func test_print_mario_anims() -> void:
	var path = "res://nintendo_switch_-_super_mario_party_-_mario.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.get_node("AnimationPlayer")
		if ap:
			printerr("MARIO ANIMATIONS LIST: " + str(ap.get_animation_list()))
		else:
			printerr("MARIO: AnimationPlayer not found")
	else:
		printerr("MARIO: Failed to load glb")
