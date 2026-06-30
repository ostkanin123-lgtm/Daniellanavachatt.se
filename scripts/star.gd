extends Node3D

func _process(delta: float) -> void:
	# Rotate the star
	rotate_y(delta * 3.0)
	
	# Hover effect
	position.y = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.2
