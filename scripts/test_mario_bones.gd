extends Node

func test_list_mario_bones() -> void:
	var path = "res://nintendo_switch_-_super_mario_party_-_mario.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true)
		if skeleton:
			var bone_names = []
			for i in range(skeleton.get_bone_count()):
				bone_names.append(skeleton.get_bone_name(i))
			var f = FileAccess.open("res://mario_bones.txt", FileAccess.WRITE)
			f.store_string(str(bone_names))
			f.close()
		else:
			printerr("MARIO: Skeleton3D not found")
	else:
		printerr("MARIO: Failed to load glb")
