extends Node3D

signal dice_rolled(value: int)

@onready var dice_model: Node3D = (func(): 
	var child = find_child("DiceModel", true)
	if child is Node3D: return child
	return self
).call()

var is_rolling := false
var roll_speed := 15.0

func _process(delta: float) -> void:
	if is_rolling:
		dice_model.rotate_y(roll_speed * delta)
		dice_model.rotate_x(roll_speed * 0.7 * delta)
		dice_model.rotate_z(roll_speed * 0.3 * delta)

func start_roll() -> void:
	is_rolling = true
	# Optional: Play a sound here

func stop_roll() -> int:
	is_rolling = false
	var result = randi_range(1, 10)
	
	# Reset rotation
	dice_model.rotation = Vector3(0, 0, 0)
	
	# Add label
	var label = Label3D.new()
	label.text = str(result)
	label.font_size = 256
	label.position = Vector3(0, 2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	
	await get_tree().create_timer(1.0).timeout
	label.queue_free()
	
	dice_rolled.emit(result)
	return result
