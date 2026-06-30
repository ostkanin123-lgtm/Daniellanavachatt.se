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
	
	# Clear old visuals first (but keep mesh_instance)
	for child in get_children():
		if child != mesh_instance and not child is Label3D:
			child.queue_free()
	
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.5
	
	match type:
		SpaceType.GREEN:
			mat.albedo_texture = load("res://assets/generated/mario_green_space_frame_0_1774557415.png")
			# Check if it's the start
			if get_index() == 0:
				var start_label = Label3D.new()
				start_label.text = "START"
				start_label.font_size = 350
				start_label.position.y = 1.0
				start_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				add_child(start_label)
		SpaceType.BLUE:
			mat.albedo_texture = load("res://MPS_Blue_Space.webp")
		SpaceType.RED:
			mat.albedo_texture = load("res://SMPJ_Red_Space.webp")
		SpaceType.STAR:
			mat.albedo_color = Color(1.0, 0.9, 0.2) # Gold
			
			var star_visual = MeshInstance3D.new()
			var star_mesh = BoxMesh.new() # Placeholder for star
			star_visual.mesh = star_mesh
			star_visual.scale = Vector3(0.6, 0.6, 0.6)
			star_visual.position.y = 1.2
			add_child(star_visual)
			
			var mat_star = StandardMaterial3D.new()
			mat_star.albedo_color = Color(1, 1, 0)
			mat_star.emission_enabled = true
			mat_star.emission = Color(1, 1, 0)
			star_visual.material_override = mat_star
			
			var tween = create_tween().set_loops()
			tween.tween_property(star_visual, "rotation:y", TAU, 2.0).as_relative()
			
		SpaceType.BOWSER:
			mat.albedo_color = Color(0.2, 0, 0.2) # Dark Purple
			
			var bowser_scene = load("res://nintendo_64_-_mario_party_-_bowser.glb")
			if bowser_scene:
				var bowser = bowser_scene.instantiate()
				bowser.scale = Vector3(0.015, 0.015, 0.015)
				bowser.position.y = 0.3
				add_child(bowser)
				
				# Face the center (roughly)
				bowser.look_at(Vector3.ZERO, Vector3.UP)
				bowser.rotate_y(PI)
	
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
