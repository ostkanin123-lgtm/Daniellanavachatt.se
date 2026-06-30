class_name BoardPlayer
extends Node2D

@export var current_space: BoardSpace
@export var move_speed: float = 4.0
@export var player_name: String = "Player"

var coins: int = 0
var steps_to_move: int = 0
var is_moving: bool = false
var target_position: Vector2

signal movement_finished

func _ready() -> void:
	if has_node("Label"):
		$Label.text = player_name
	if current_space:
		global_position = current_space.global_position

func _process(delta: float) -> void:
	if is_moving:
		global_position = global_position.move_toward(target_position, move_speed * 100 * delta)
		if global_position.distance_to(target_position) < 1.0:
			_on_reached_space()

func move(steps: int) -> void:
	if is_moving: return
	steps_to_move = steps
	_move_to_next()

func _move_to_next() -> void:
	if steps_to_move <= 0:
		is_moving = false
		movement_finished.emit()
		return
	
	var next = current_space.get_next_space()
	if next:
		current_space = next
		target_position = current_space.global_position
		is_moving = true
	else:
		is_moving = false
		movement_finished.emit()

func _on_reached_space() -> void:
	steps_to_move -= 1
	_move_to_next()
