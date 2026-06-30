extends Node3D
class_name BoardSpace3D

enum SpaceType { GREEN, BLUE, RED }
@export var type: SpaceType = SpaceType.GREEN
@export var next_space: BoardSpace3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	update_appearance()

func update_appearance() -> void:
	if not is_inside_tree(): return
	
	var mat = StandardMaterial3D.new()
	match type:
		SpaceType.GREEN:
			mat.albedo_color = Color.GREEN
		SpaceType.BLUE:
			mat.albedo_color = Color.BLUE
		SpaceType.RED:
			mat.albedo_color = Color.RED
	mesh_instance.material_override = mat

func on_landed(player: Node3D) -> void:
	match type:
		SpaceType.BLUE:
			player.coins += 3
		SpaceType.RED:
			player.coins = max(0, player.coins - 3)
