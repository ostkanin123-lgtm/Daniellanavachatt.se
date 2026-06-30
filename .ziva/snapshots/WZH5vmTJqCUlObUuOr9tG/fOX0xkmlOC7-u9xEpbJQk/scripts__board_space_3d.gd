@tool
extends Node3D
class_name BoardSpace3D

# --- EDITOR HINT ---
@export_group("World Editor")
@export var NOTE: String = "Open Main3D.tscn to see the whole board!"
# ------------------

enum SpaceType { GREEN, BLUE, RED, STAR, BOWSER }
@export var type: SpaceType = SpaceType.GREEN: 
	set(val):
		type = val
		update_appearance()

@export var next_space: BoardSpace3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Small delay to ensure children are ready in editor
	if Engine.is_editor_hint():
		await get_tree().process_frame
	update_appearance()

func update_appearance() -> void:
	if not is_inside_tree(): return
	
	# Fallback check for mesh_instance if @onready hasn't fired yet
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
	
	if not mesh_instance: return

	# Clear old visuals first (but keep mesh_instance and Label3D)
	for child in get_children():
		if child != mesh_instance and not child is Label3D:
			child.queue_free()
	
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.5
	
	match type:
		SpaceType.GREEN:
			mat.albedo_color = Color(0.2, 0.8, 0.2) # Default green
			var green_tex = load("res://assets/generated/mario_green_space_frame_0_1774557415.png")
			if green_tex:
				mat.albedo_texture = green_tex
				mat.albedo_color = Color.WHITE
			
		SpaceType.BLUE:
			mat.albedo_color = Color(0.1, 0.4, 1.0) # Default blue
			var blue_tex = load("res://MPS_Blue_Space.webp")
			if blue_tex:
				mat.albedo_texture = blue_tex
				mat.albedo_color = Color.WHITE
				mat.emission_enabled = true
				mat.emission_texture = blue_tex
				mat.emission = Color(0, 0.4, 1.0)
				mat.emission_energy_multiplier = 1.0
			mat.roughness = 0.1
			mat.metallic = 0.3
			
		SpaceType.RED:
			mat.albedo_color = Color(1.0, 0.2, 0.2) # Default red
			var red_tex = load("res://SMPJ_Red_Space.webp")
			if red_tex:
				mat.albedo_texture = red_tex
				mat.albedo_color = Color.WHITE
				mat.emission_enabled = true
				mat.emission_texture = red_tex
				mat.emission = Color(1.0, 0.1, 0.1)
				mat.emission_energy_multiplier = 1.0
			mat.roughness = 0.1
			mat.metallic = 0.3
			
		SpaceType.STAR:
			mat.albedo_color = Color(1.0, 0.9, 0.2) # Gold
			
			if Engine.is_editor_hint() or not is_node_ready():
				# Simplified visual for editor to avoid creating too many nodes during typing
				pass
			else:
				var star_visual = MeshInstance3D.new()
				star_visual.mesh = SphereMesh.new()
				star_visual.scale = Vector3(0.6, 0.6, 0.6)
				star_visual.position.y = 1.2
				add_child(star_visual)
				
				var mat_star = StandardMaterial3D.new()
				mat_star.albedo_color = Color(1, 1, 0)
				mat_star.emission_enabled = true
				mat_star.emission = Color(1, 1, 0)
				star_visual.material_override = mat_star
			
		SpaceType.BOWSER:
			mat.albedo_color = Color(0.2, 0, 0.2) # Dark Purple
			
			if not Engine.is_editor_hint() and is_node_ready():
				var bowser_scene = load("res://nintendo_64_-_mario_party_-_bowser.glb")
				if bowser_scene:
					var bowser = bowser_scene.instantiate()
					bowser.scale = Vector3(0.015, 0.015, 0.015)
					bowser.position.y = 0.3
					add_child(bowser)
					bowser.look_at(Vector3.ZERO, Vector3.UP)
					bowser.rotate_y(PI)
	
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
