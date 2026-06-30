extends Node

func test_check_animations() -> void:
	var scene = load("res://nintendo_switch_-_super_mario_party_-_mario.glb")
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			var anims = ap.get_animation_list()
			printerr("ANIMATION_LIST:" + str(anims))
		else:
			printerr("ANIMATION_LIST:NONE")
	else:
		printerr("ANIMATION_LIST:LOAD_FAILED")
