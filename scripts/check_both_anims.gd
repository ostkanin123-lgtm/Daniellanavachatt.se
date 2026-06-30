@tool
extends Node

func test_write_both_anims() -> void:
	var f = FileAccess.open("res://all_anims.txt", FileAccess.WRITE)
	
	var mario_path = "res://nintendo_switch_-_super_mario_party_-_mario.glb"
	var mario_scene = load(mario_path)
	if mario_scene:
		var model = mario_scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			f.store_line("MARIO: " + str(ap.get_animation_list()))
	
	var luigi_path = "res://luigi_removed_doubles.glb"
	var luigi_scene = load(luigi_path)
	if luigi_scene:
		var model = luigi_scene.instantiate()
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true)
		if ap:
			f.store_line("LUIGI: " + str(ap.get_animation_list()))
	
	f.close()
