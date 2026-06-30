extends Node3D

signal dice_rolled(value: int)

@onready var dice_model: Node3D = find_child("DiceModel", true) if has_node("DiceModel") else self

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
	
	# Scale punch effect
	var tween = create_tween()
	tween.tween_property(dice_model, "scale", Vector3(0.7, 0.7, 0.7), 0.1)
	tween.tween_property(dice_model, "scale", Vector3(0.5, 0.5, 0.5), 0.2).set_trans(Tween.TRANS_BOUNCE)
	
	# Add label
	var label = Label3D.new()
	label.text = str(result)
	label.font_size = 350
	label.outline_size = 50
	label.position = Vector3(0, 2.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	
	# Animate label
	var label_tween = create_tween()
	label_tween.tween_property(label, "scale", Vector3(1.2, 1.2, 1.2), 0.3)
	label_tween.tween_property(label, "scale", Vector3(1.0, 1.0, 1.0), 0.2)
	
	await get_tree().create_timer(1.2).timeout
	label.queue_free()
	
	dice_rolled.emit(result)
	return result
