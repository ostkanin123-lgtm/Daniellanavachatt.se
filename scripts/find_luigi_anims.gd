@tool
extends Node

func _ready() -> void:
	var path = "res://luigi_removed_doubles.glb"
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		var ap: AnimationPlayer = model.get_node("AnimationPlayer")
		if ap:
			printerr("LUIGI ANIMATIONS LIST: " + str(ap.get_animation_list()))
		else:
			printerr("LUIGI: AnimationPlayer not found at root of glb scene")
	else:
		printerr("LUIGI: Failed to load glb")
