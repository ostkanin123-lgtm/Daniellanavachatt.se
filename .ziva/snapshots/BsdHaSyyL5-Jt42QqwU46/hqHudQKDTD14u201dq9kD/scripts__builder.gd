extends Node3D
class_name Builder

@export var board_space_scene: PackedScene = preload("res://scenes/board_space_3d.tscn")
@export var rock_scene: PackedScene = preload("res://desert__rocks__stones__pack.glb")
@export var tree_scene: PackedScene = preload("res://scenes/tree_3d.tscn")
@export var grid_size: float = 4.0
@export var snap_to_grid: bool = true

var is_active: bool = false
var current_item_index: int = 0
var preview_item: Node3D
var placement_items: Array[String] = [
	"Space (Blue)", 
	"Space (Red)", 
	"Space (Green)",
	"Space (Star)",
	"Space (Bowser)",
	"Rock", 
	"Tree", 
	"Delete"
]

@onready var camera: Camera3D = get_viewport().get_camera_3d()

func _ready() -> void:
	set_process(false)

func toggle(active: bool) -> void:
	is_active = active
	set_process(active)
	if not active:
		if preview_item:
			preview_item.queue_free()
			preview_item = null
	else:
		_update_preview()

func _process(_delta: float) -> void:
	if not is_active: return
	
	camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	# Intersect with ground plane (y=0)
	# P = O + t*D -> P.y = O.y + t*D.y = 0 -> t = -O.y / D.y
	if ray_dir.y != 0:
		var t = -ray_origin.y / ray_dir.y
		if t > 0:
			var world_pos = ray_origin + t * ray_dir
			
			if snap_to_grid:
				world_pos.x = round(world_pos.x / grid_size) * grid_size
				world_pos.z = round(world_pos.z / grid_size) * grid_size
			
			if preview_item:
				preview_item.global_position = world_pos
			
			if Input.is_action_just_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				# Prevent clicking through UI
				if not _is_mouse_over_ui():
					_place_item(world_pos)
			
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				if not _is_mouse_over_ui():
					# Cycle space type if on space
					if placement_items[current_item_index].begins_with("Space"):
						current_item_index = (current_item_index + 1) % 5 # First 5 are spaces
						_update_preview()
						# Small delay to prevent rapid cycling
						await get_tree().create_timer(0.2).timeout

func _is_mouse_over_ui() -> bool:
	# Very simple check: if mouse is in the bottom area where buttons are
	var mouse_pos = get_viewport().get_mouse_position()
	var screen_size = get_viewport().get_visible_rect().size
	if mouse_pos.y > screen_size.y - 200:
		return true
	return false

func _update_preview() -> void:
	if preview_item:
		preview_item.queue_free()
	
	var item_name = placement_items[current_item_index]
	
	if item_name.begins_with("Space"):
		preview_item = board_space_scene.instantiate()
		if "Blue" in item_name: preview_item.type = BoardSpace3D.SpaceType.BLUE
		elif "Red" in item_name: preview_item.type = BoardSpace3D.SpaceType.RED
		elif "Green" in item_name: preview_item.type = BoardSpace3D.SpaceType.GREEN
		elif "Star" in item_name: preview_item.type = BoardSpace3D.SpaceType.STAR
		elif "Bowser" in item_name: preview_item.type = BoardSpace3D.SpaceType.BOWSER
		
		# Set preview transparency
		preview_item.set_process(false)
		preview_item.set_physics_process(false)
		
	match item_name:
		"Rock":
			preview_item = rock_scene.instantiate()
			preview_item.scale = Vector3(2, 2, 2)
		"Tree":
			preview_item = tree_scene.instantiate()
		"Delete":
			preview_item = MeshInstance3D.new()
			var m = SphereMesh.new()
			m.radius = 1.0
			m.height = 2.0
			preview_item.mesh = m
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0, 0, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			preview_item.material_override = mat
	
	if preview_item:
		add_child(preview_item)
		preview_item.set_process(false)
		preview_item.set_physics_process(false)

func select_item(index: int) -> void:
	current_item_index = index
	_update_preview()

func _place_item(pos: Vector3) -> void:
	var item_name = placement_items[current_item_index]
	
	if item_name.begins_with("Space"):
		var new_space = board_space_scene.instantiate()
		if "Blue" in item_name: new_space.type = BoardSpace3D.SpaceType.BLUE
		elif "Red" in item_name: new_space.type = BoardSpace3D.SpaceType.RED
		elif "Green" in item_name: new_space.type = BoardSpace3D.SpaceType.GREEN
		elif "Star" in item_name: new_space.type = BoardSpace3D.SpaceType.STAR
		elif "Bowser" in item_name: new_space.type = BoardSpace3D.SpaceType.BOWSER
		
		get_node("../Board").add_child(new_space)
		new_space.global_position = pos
		new_space.update_appearance()
		_relink_board()
		
		# Auto-place players on first space if board was empty
		if get_node("../Board").get_child_count() == 1:
			var main = get_parent()
			if main and main.has_method("_reset_players_to_board"):
				main._reset_players_to_board()
		return
		
	match item_name:
		"Rock":
			var new_rock = rock_scene.instantiate()
			get_parent().add_child(new_rock)
			new_rock.global_position = pos
			new_rock.scale = Vector3(2, 2, 2)
			new_rock.rotate_y(randf() * TAU)
		"Tree":
			var new_tree = tree_scene.instantiate()
			get_parent().add_child(new_tree)
			new_tree.global_position = pos
			new_tree.rotate_y(randf() * TAU)
			new_tree.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.8, 1.2), randf_range(0.8, 1.2))
		"Delete":
			_delete_at(pos)

func _delete_at(pos: Vector3) -> void:
	# Find closest object to pos and remove it if it's not the ground or players
	var closest: Node3D = null
	var min_dist = 2.0
	
	for child in get_node("../Board").get_children():
		var d = child.global_position.distance_to(pos)
		if d < min_dist:
			min_dist = d
			closest = child
	
	if closest:
		closest.queue_free()
		await get_tree().process_frame
		_relink_board()
		return

	# Also check decorations
	for child in get_parent().get_children():
		if child is MeshInstance3D and child.name.begins_with("desert"):
			var d = child.global_position.distance_to(pos)
			if d < min_dist:
				min_dist = d
				closest = child
	
	if closest:
		closest.queue_free()

func _relink_board() -> void:
	# Simple linear relinking based on child order
	var board = get_node("../Board")
	if not board: return
	
	var spaces = board.get_children()
	if spaces.is_empty(): return
	
	for i in range(spaces.size()):
		var current = spaces[i]
		if i < spaces.size() - 1:
			current.next_space = spaces[i+1]
		else:
			current.next_space = spaces[0] # Loop it
		if current.has_method("update_appearance"):
			current.update_appearance()
