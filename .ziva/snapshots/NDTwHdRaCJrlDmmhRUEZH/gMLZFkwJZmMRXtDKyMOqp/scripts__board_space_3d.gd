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
	mat.roughness = 0.5
	
	match type:
		SpaceType.GREEN:
			mat.albedo_texture = load("res://assets/generated/mario_green_space_frame_0_1774557415.png")
		SpaceType.BLUE:
			mat.albedo_texture = load("res://MPS_Blue_Space.webp")
		SpaceType.RED:
			mat.albedo_texture = load("res://SMPJ_Red_Space.webp")
		SpaceType.STAR:
			mat.albedo_color = Color(1.0, 0.8, 0.0) # Gold
			# Clear old visuals first
			for child in get_children():
				if child != mesh_instance:
					child.queue_free()
					
			var star_visual = MeshInstance3D.new()
			star_visual.mesh = BoxMesh.new()
			star_visual.scale = Vector3(0.5, 0.5, 0.5)
			star_visual.position.y = 1.0
			add_child(star_visual)
			
			var tween = create_tween().set_loops()
			tween.tween_property(star_visual, "position:y", 1.5, 1.0).set_trans(Tween.TRANS_SINE)
			tween.tween_property(star_visual, "position:y", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
			
		SpaceType.BOWSER:
			mat.albedo_texture = load("res://SMPJ_Red_Space.webp") # Use red for bowser too or just purple
			mat.albedo_color = Color(0.5, 0.0, 0.5) # Purple tint
			
			# Clear old visuals
			for child in get_children():
				if child != mesh_instance:
					child.queue_free()
					
			var bowser_scene = load("res://nintendo_64_-_mario_party_-_bowser.glb")
			if bowser_scene:
				var bowser = bowser_scene.instantiate()
				bowser.scale = Vector3(0.01, 0.01, 0.01) # Usually these N64 models are huge or tiny
				bowser.position.y = 0.5
				add_child(bowser)
	
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
