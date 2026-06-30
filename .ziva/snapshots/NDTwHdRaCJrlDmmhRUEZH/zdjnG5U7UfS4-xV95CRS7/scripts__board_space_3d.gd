extends Node3D
class_name BoardSpace3D

enum SpaceType { GREEN, BLUE, RED, STAR, BOWSER }
@export var type: SpaceType = SpaceType.GREEN
@export var next_space: BoardSpace3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	update_appearance()

func update_appearance() -> void:
	if not is_inside_tree(): return
	
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.3
	mat.rim_enabled = true
	mat.rim = 0.5
	
	match type:
		SpaceType.GREEN:
			mat.albedo_color = Color(0.2, 0.8, 0.2)
		SpaceType.BLUE:
			mat.albedo_color = Color(0.1, 0.4, 1.0)
		SpaceType.RED:
			mat.albedo_color = Color(1.0, 0.2, 0.2)
		SpaceType.STAR:
			mat.albedo_color = Color(1.0, 0.8, 0.0) # Gold
			# Let's add a small floating cube to represent the star
			var star_visual = MeshInstance3D.new()
			star_visual.mesh = BoxMesh.new()
			star_visual.scale = Vector3(0.5, 0.5, 0.5)
			star_visual.position.y = 1.0
			add_child(star_visual)
			# Add animation to it
			var tween = create_tween().set_loops()
			tween.tween_property(star_visual, "position:y", 1.5, 1.0).set_trans(Tween.TRANS_SINE)
			tween.tween_property(star_visual, "position:y", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
			
			var star_script = load("res://scripts/star.gd")
			if star_script:
				star_visual.set_script(star_script)
				
		SpaceType.BOWSER:
			mat.albedo_color = Color(0.5, 0.0, 0.5) # Purple
	
	if mesh_instance:
		mesh_instance.material_override = mat

func on_landed(player: Node3D) -> void:
	match type:
		SpaceType.BLUE:
			player.coins += 3
		SpaceType.RED:
			player.coins = max(0, player.coins - 3)
		SpaceType.STAR:
			# If you land on it, maybe you get a free star or a lot of coins?
			player.stars += 1
		SpaceType.BOWSER:
			# Bowser takes everything!
			player.coins = max(0, player.coins - 10)
