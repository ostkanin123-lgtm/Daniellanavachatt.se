@tool
extends Node

func test_write_mario_anims() -> void:
	var path = "res://nintendo_switch_-_super_mario_party_-_mario.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			var f = FileAccess.open("res://mario_anims.txt", FileAccess.WRITE)
			f.store_string(str(ap.get_animation_list()))
			f.close()
