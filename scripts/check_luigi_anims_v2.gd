@tool
extends Node

func test_write_luigi_anims() -> void:
	var path = "res://luigi_removed_doubles.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			var f = FileAccess.open("res://luigi_anims.txt", FileAccess.WRITE)
			f.store_string(str(ap.get_animation_list()))
			f.close()
