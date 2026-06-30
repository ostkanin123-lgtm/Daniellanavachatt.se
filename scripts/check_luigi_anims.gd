@tool
extends Node

func test_print_luigi_anims() -> void:
	var path = "res://luigi_removed_doubles.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			printerr("LUIGI ANIMATIONS: " + str(ap.get_animation_list()))
		else:
			printerr("LUIGI ANIMATIONS: NONE FOUND")
	else:
		printerr("LUIGI ANIMATIONS: LOAD FAILED")
