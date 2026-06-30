extends Node3D

@onready var dice_button: Button = $CanvasLayer/Control/RollButton
@onready var info_label: Label = $CanvasLayer/Control/DiceLabel
@onready var coin_label: Label = $CanvasLayer/Control/VBoxContainer/Player1Info # Simplified for now
@onready var main_camera: Camera3D = $Camera3D

var players: Array[Player3D] = []
var current_player_index: int = 0
var is_rolling: bool = false

@onready var dice_3d: Node3D = $Dice3D

var current_turn: int = 1
var max_turns: int = 10

# Camera variables
var cam_target_pos: Vector3
var cam_target_look_at: Vector3
var cam_follow_speed: float = 4.0
var cam_rot_speed: float = 3.0
var cam_offset: Vector3 = Vector3(0, 15, 18)

func _ready() -> void:
	# Initial camera target
	cam_target_pos = main_camera.global_position
	cam_target_look_at = Vector3.ZERO
	
	# Create some board spaces if they don't exist
	if $Board.get_child_count() == 0:
		var space_scene = load("res://scenes/board_space_3d.tscn")
		for i in range(32): # Even more spaces
			var space = space_scene.instantiate()
			$Board.add_child(space)
			
	# Link board spaces and position them in a nice layout (Large Circle)
	var spaces = $Board.get_children()
	var total_spaces = spaces.size()
	var radius = 25.0 # Much larger
	
	for i in range(total_spaces):
		var angle = i * TAU / total_spaces
		var x = cos(angle) * radius
		var z = sin(angle) * radius # Perfect circle
		
		spaces[i].position = Vector3(x, 0, z)
		
		var next_idx = (i + 1) % total_spaces
		spaces[i].next_space = spaces[next_idx]
		
		# Variety - Let's make it more strategic
		if i == 0:
			spaces[i].type = BoardSpace3D.SpaceType.GREEN # Start
		elif i == 8 or i == 24: # Symmetric stars
			spaces[i].type = BoardSpace3D.SpaceType.STAR
		elif i == 16:
			spaces[i].type = BoardSpace3D.SpaceType.BOWSER
		elif i % 4 == 0:
			spaces[i].type = BoardSpace3D.SpaceType.RED
		else:
			spaces[i].type = BoardSpace3D.SpaceType.BLUE
		
		spaces[i].update_appearance()
	
	# Create a ground plane if it doesn't exist
	if not has_node("Ground"):
		var ground = MeshInstance3D.new()
		ground.name = "Ground"
		var ground_mesh = PlaneMesh.new()
		ground_mesh.size = Vector2(100, 100)
		ground.mesh = ground_mesh
		ground.position.y = -0.5
		
		var ground_mat = StandardMaterial3D.new()
		ground_mat.albedo_color = Color(0.2, 0.4, 0.2) # Dark grass green
		ground_mat.albedo_texture = load("res://assets/generated/grass_floor_frame_0_1774541586.png")
		ground_mat.uv1_scale = Vector3(10, 10, 10)
		ground.material_override = ground_mat
		add_child(ground)
	
	# Set players
	players = []
	var mario = $Players/Mario
	var luigi = $Players/Luigi
	if mario: players.append(mario)
	if luigi: players.append(luigi)
	
	if players.size() > 0:
		players[0].player_name = "Mario"
		if players.size() > 1:
			players[1].player_name = "Luigi"
	
	# Initial space
	var start_space = spaces[0]
	for p in players:
		p.current_space = start_space
		p.global_position = start_space.global_position + Vector3(0, 0.5, 0)
	
	if has_node("Dice3D"):
		$Dice3D.visible = false
	
	add_decorations()
	update_ui()
	update_camera_focus(true)

func add_decorations():
	var rock_scene = load("res://desert__rocks__stones__pack.glb")
	if rock_scene:
		for i in range(15):
			var rock = rock_scene.instantiate()
			add_child(rock)
			# Random position far from board
			var angle = randf() * TAU
			var dist = randf_range(20, 40)
			rock.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
			rock.scale = Vector3.ONE * randf_range(0.3, 1.2)
			rock.rotation_y(randf() * TAU)

func _process(delta: float) -> void:
	# Smoothly follow the camera targets
	main_camera.global_position = main_camera.global_position.lerp(cam_target_pos, cam_follow_speed * delta)
	
	# Instead of look_at every frame which can be jerky with lerp, 
	# interpolate the look_at target
	var current_look_at = cam_target_look_at # Placeholder for current focus
	
	# This creates a look_at rotation towards target focus
	var target_transform = main_camera.global_transform.looking_at(cam_target_look_at, Vector3.UP)
	main_camera.quaternion = main_camera.quaternion.slerp(target_transform.quaternion, cam_rot_speed * delta)

func _on_roll_button_pressed() -> void:
	if is_rolling: return
	
	var player = players[current_player_index]
	is_rolling = true
	dice_button.disabled = true
	
	# Zoom in on player for dice roll
	cam_offset = Vector3(0, 4.5, 6) # Much closer
	cam_follow_speed = 6.0 # Faster follow
	update_camera_focus()
	
	# Show dice above player
	dice_3d.global_position = player.global_position + Vector3(0, 3.5, 0)
	dice_3d.visible = true
	dice_3d.start_roll()
	
	await get_tree().create_timer(1.2).timeout
	
	# Player jumps!
	await player.jump()
	
	# Dice stops
	var roll = await dice_3d.stop_roll()
	info_label.text = "%s slog en %d!" % [player.player_name, roll]
	
	await get_tree().create_timer(0.8).timeout
	dice_3d.visible = false
	
	# Back out slightly for movement
	cam_offset = Vector3(0, 8, 10) 
	cam_follow_speed = 4.0
	
	# Move player
	for i in range(roll):
		await player.move(1)
		update_camera_focus() # Keep following
		await get_tree().create_timer(0.1).timeout
	
	# Landed!
	if player.current_space:
		player.current_space.on_landed(player)
	
	update_ui()
	
	current_player_index = (current_player_index + 1) % players.size()
	
	# Turn logic
	if current_player_index == 0:
		# Everyone has moved - End of Round
		await trigger_minigame()
		
		current_turn += 1
		if current_turn > max_turns:
			show_winner()
			return
	
	await get_tree().create_timer(1.0).timeout
	
	is_rolling = false
	dice_button.disabled = false
	update_ui()
	
	# Normal follow offset for next player's turn start
	cam_offset = Vector3(0, 15, 18)
	update_camera_focus()

func trigger_minigame():
	info_label.text = "MINISPEL TID!"
	
	# Wide view of the whole board
	cam_target_pos = Vector3(0, 35, 35)
	cam_target_look_at = Vector3.ZERO
	cam_follow_speed = 2.0 # Slow cinematic drift
	
	var original_color = info_label.modulate
	
	# Flash the label
	for i in range(3):
		info_label.modulate = Color(1, 1, 0)
		await get_tree().create_timer(0.3).timeout
		info_label.modulate = Color(1, 0, 0)
		await get_tree().create_timer(0.3).timeout
	
	info_label.modulate = original_color
	info_label.text = "Minispel placeholder: Alla fick 10 mynt!"
	
	for p in players:
		p.coins += 10
	
	update_ui()
	await get_tree().create_timer(2.0).timeout

func show_winner():
	var winner = players[0]
	for p in players:
		if p.stars > winner.stars:
			winner = p
		elif p.stars == winner.stars and p.coins > winner.coins:
			winner = p
	
	info_label.text = "Spelet är slut! Vinnaren är: " + winner.player_name + "!"
	info_label.scale *= 1.5
	dice_button.visible = false
	
	# Focus camera on winner
	current_player_index = players.find(winner)
	cam_offset = Vector3(0, 3, 4) # Very close
	cam_follow_speed = 5.0
	update_camera_focus()
	winner.play_animation("Victory")

func update_ui() -> void:
	var current_player = players[current_player_index]
	info_label.text = "Runda %d/%d - Det är %s tur!" % [current_turn, max_turns, current_player.player_name]
	
	if players.size() > 0:
		var p1 = players[0]
		$CanvasLayer/Control/VBoxContainer/Player1Info.text = "%s: %d Mynt, %d Stjärnor" % [p1.player_name, p1.coins, p1.stars]
	if players.size() > 1:
		var p2 = players[1]
		$CanvasLayer/Control/VBoxContainer/Player2Info.text = "%s: %d Mynt, %d Stjärnor" % [p2.player_name, p2.coins, p2.stars]

func update_camera_focus(instant: bool = false) -> void:
	var player = players[current_player_index]
	cam_target_pos = player.global_position + cam_offset
	cam_target_look_at = player.global_position + Vector3(0, 1.0, 0)
	
	if instant:
		main_camera.global_position = cam_target_pos
		main_camera.look_at(cam_target_look_at)
		cam_target_look_at = player.global_position + Vector3(0, 1.0, 0)
