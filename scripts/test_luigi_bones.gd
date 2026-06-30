extends Node

func test_list_bones() -> void:
	var path = "res://luigi_removed_doubles.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true)
		if skeleton:
			var bone_names = []
			for i in range(skeleton.get_bone_count()):
				bone_names.append(skeleton.get_bone_name(i))
			var f = FileAccess.open("res://luigi_bones.txt", FileAccess.WRITE)
			f.store_string(str(bone_names))
			f.close()
		else:
			printerr("LUIGI: Skeleton3D not found")
	else:
		printerr("LUIGI: Failed to load glb")
