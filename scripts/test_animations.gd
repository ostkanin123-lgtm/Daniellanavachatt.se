extends Node3D

func _ready():
	var model = load("res://nintendo_switch_-_super_mario_party_-_mario.glb").instantiate()
	add_child(model)
	var anim_player = model.find_child("AnimationPlayer", true)
	if anim_player:
		print("Animations for Mario: ", anim_player.get_animation_list())
	model.queue_free()
	
	var luigi = load("res://luigi_removed_doubles.glb").instantiate()
	add_child(luigi)
	var anim_player_luigi = luigi.find_child("AnimationPlayer", true)
	if anim_player_luigi:
		print("Animations for Luigi: ", anim_player_luigi.get_animation_list())
	luigi.queue_free()
	
	queue_free()
