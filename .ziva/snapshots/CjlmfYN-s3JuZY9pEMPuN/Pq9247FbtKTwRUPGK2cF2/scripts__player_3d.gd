extends Node3D
class_name Player3D

@export var player_name: String = "Player"
var coins: int = 0
var current_space: BoardSpace3D
var is_moving: bool = false

signal move_finished

func move_to_space(target_space: BoardSpace3D) -> void:
	is_moving = true
	var start_pos = global_position
	var target_pos = target_space.global_position + Vector3(0, 0.5, 0) # Offset to stand on top
	
	# Rotate to face target
	if target_pos != global_position:
		look_at(target_pos, Vector3.UP)
		rotation.x = 0 # Keep upright
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_SINE)
	await tween.finished
	
	current_space = target_space
	is_moving = false
	move_finished.emit()
