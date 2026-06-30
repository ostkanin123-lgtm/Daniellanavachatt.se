@tool
extends Node3D

@export var refresh_board: bool = false : set = _set_refresh_board
@export var clear_board: bool = false : set = _set_clear_board

@onready var dice_button: Button = find_child("RollButton", true)
@onready var info_label: Label = find_child("InfoLabel", true)
@onready var coin_label: Label = find_child("CoinLabel", true)
@onready var main_camera: Camera3D = find_child("Camera3D", true)
@onready var dice_3d: Node3D = find_child("Dice3D", true)
@onready var builder: Builder = get_node_or_null("Builder")
@onready var build_ui: Control = find_child("BuildUI", true)

# Game state
var players: Array = []
var current_player_index: int = 0
var is_rolling: bool = false
var game_started: bool = false
var current_turn: int = 1
var max_turns: int = 10
var is_build_mode: bool = false

# Camera targets
var cam_target_pos: Vector3
var cam_target_look_at: Vector3
var cam_follow_speed: float = 4.0
var cam_rot_speed: float = 3.0
var cam_offset: Vector3 = Vector3(0, 15, 18)

func _set_refresh_board(val: bool) -> void:
	if val:
		setup_board()
	refresh_board = false

func _set_clear_board(val: bool) -> void:
	if val:
		if has_node("Board"):
			for child in $Board.get_children():
				child.queue_free()
	clear_board = false

func setup_board() -> void:
	if not has_node("Board"): return
	
	# Clear existing board
	for child in $Board.get_children():
		child.queue_free()
	
	# Clear and rebuild decorations in editor
	if Engine.is_editor_hint():
		clear_decorations()
		add_decorations()

	if has_node("Ground"):
		$Ground.scale = Vector3(10, 1, 10) # 1000x1000 ground
		$Ground.position.y = -0.5 # Ground slightly below tiles
	
	var space_scene = load("res://scenes/board_space_3d.tscn")
	var total_spaces = 32
	var radius = 120.0 # Large radius for 10x10 tiles
	
	for i in range(total_spaces):
		var space = space_scene.instantiate()
		$Board.add_child(space)
		if Engine.is_editor_hint():
			space.owner = get_tree().edited_scene_root
			
		var angle = i * TAU / total_spaces
		var x = cos(angle) * radius
		var z = sin(angle) * radius
		space.position = Vector3(x, 0, z)
		
		# Variety
		if i == 0: space.type = BoardSpace3D.SpaceType.GREEN
		elif i == 8 or i == 24: space.type = BoardSpace3D.SpaceType.STAR
		elif i == 16: space.type = BoardSpace3D.SpaceType.BOWSER
		elif (i % 6 == 0): space.type = BoardSpace3D.SpaceType.RED
		else: space.type = BoardSpace3D.SpaceType.BLUE
		
		if space.has_method("update_appearance"):
			space.update_appearance()
	
	# Link them
	var spaces = $Board.get_children()
	for i in range(spaces.size()):
		spaces[i].next_space = spaces[(i + 1) % spaces.size()]

	# Setup initial player positions
	var start_space = spaces[0] if spaces.size() > 0 else null
	if start_space:
		var m = find_child("Mario", true)
		var l = find_child("Luigi", true)
		for p in [m, l]:
			if p:
				p.current_space = start_space
				p.global_position = start_space.global_position + Vector3(0, 0.5, 0)

func clear_decorations():
	# Remove any existing generated rocks to prevent stacking
	for child in get_children():
		if child.name.begins_with("GeneratedRock"):
			child.queue_free()

func add_decorations():
	if Engine.is_editor_hint():
		clear_decorations()
		
	var rock_scene = load("res://desert__rocks__stones__pack.glb")
	if rock_scene:
		for i in range(50): 
			var rock = rock_scene.instantiate()
			rock.name = "GeneratedRock_" + str(i)
			add_child(rock)
			if Engine.is_editor_hint():
				rock.owner = get_tree().edited_scene_root
			
			var angle = randf() * TAU
			var dist = randf_range(200, 350) # Way outside the board
			
			rock.position = Vector3(cos(angle) * dist, -5.0, sin(angle) * dist)
			var s = randf_range(15.0, 30.0)
			rock.scale = Vector3(s, s * randf_range(0.8, 1.2), s)
			rock.rotate_y(randf() * TAU)
	is_rolling = true
	if dice_button: dice_button.disabled = true
	if info_label: info_label.text = "TRYCK PÅ ENTER FÖR ATT STARTA!"
	update_ui()
	update_camera_focus(true)
	
	# Starta inte i bygg-läge som standard om vi bara kör spelet
	is_build_mode = false
	if builder:
		builder.toggle(is_build_mode)
	
	if build_ui:
		build_ui.visible = is_build_mode
	
	if is_build_mode:
		dice_button.visible = false
		info_label.text = "BYGG-LÄGE AKTIVERAT (Klicka för att placera)"
		# Free camera look
		cam_target_pos = Vector3(0, 40, 40)
		cam_target_look_at = Vector3.ZERO
	else:
		dice_button.visible = true
		info_label.text = "Runda %d/%d" % [current_turn, max_turns]
		update_camera_focus()
		update_ui()


func start_intro():
	game_started = true
	is_rolling = true # Prevent interaction
	dice_button.disabled = true
	
	# Initial wide view - higher and further back
	main_camera.global_position = Vector3(0, 100, 120) 
	cam_target_pos = main_camera.global_position
	cam_target_look_at = Vector3.ZERO
	
	info_label.text = "GÖR ER REDO!"
	
	await get_tree().create_timer(1.0).timeout
	
	# Smoothly rotate the camera for a cinematic feel
	var intro_tween = create_tween().set_parallel(true)
	cam_follow_speed = 1.0 # Very slow
	
	var player = players[0]
	cam_target_pos = player.global_position + Vector3(8, 15, 18) # Dramatic angle
	cam_target_look_at = player.global_position
	
	intro_tween.tween_property(main_camera, "global_position", cam_target_pos, 2.0).set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(2.0).timeout
	
	info_label.text = "START!"
	info_label.modulate = Color(1, 1, 0)
	
	await get_tree().create_timer(1.0).timeout
	
	info_label.modulate = Color.WHITE
	is_rolling = false
	dice_button.disabled = false
	update_ui()
	cam_follow_speed = 4.0 # Back to normal
	update_camera_focus()

func add_decorations():
	var rock_scene = load("res://desert__rocks__stones__pack.glb")
	if rock_scene:
		# Endast utvändiga berg (skapar en ring runt banan)
		for i in range(40): # Fler berg för en tätare ring
			var rock = rock_scene.instantiate()
			add_child(rock)
			
			# Placera dem i en cirkel utanför banan
			# Banan är på radie 80, så vi lägger bergen på 110-160
			var angle = randf() * TAU
			var dist = randf_range(110, 160) 
			
			rock.position = Vector3(cos(angle) * dist, -2.0, sin(angle) * dist)
			
			# Gör dem riktigt stora så de ser ut som bergskedjor
			var s = randf_range(4.0, 8.0)
			rock.scale = Vector3(s, s * randf_range(0.8, 1.5), s)
			
			rock.rotate_y(randf() * TAU)
			# Luta dem lite slumpmässigt för mer naturlig look
			rock.rotate_x(randf_range(-0.1, 0.1))

func _process(delta: float) -> void:
	if not game_started:
		if Input.is_action_just_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			start_intro()
		return

	# Smoothly follow the camera targets
	main_camera.global_position = main_camera.global_position.lerp(cam_target_pos, cam_follow_speed * delta)
	
	# This creates a look_at rotation towards target focus
	var target_transform = main_camera.global_transform.looking_at(cam_target_look_at, Vector3.UP)
	var target_quat = target_transform.basis.get_rotation_quaternion()
	main_camera.quaternion = main_camera.quaternion.slerp(target_quat, cam_rot_speed * delta)

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
	var info = find_child("InfoLabel", true)
	if not info: return
	
	if not game_started:
		info.text = "TRYCK PÅ ENTER FÖR ATT STARTA!"
		return
		
	var current_player = players[current_player_index]
	info.text = "Runda %d/%d - Det är %s tur!" % [current_turn, max_turns, current_player.player_name]
	
	var p1_info = find_child("Player1Info", true)
	if p1_info and players.size() > 0:
		var p1 = players[0]
		p1_info.text = "%s: %d Mynt, %d Stjärnor" % [p1.player_name, p1.coins, p1.stars]
		
	var p2_info = find_child("Player2Info", true)
	if p2_info and players.size() > 1:
		var p2 = players[1]
		p2_info.text = "%s: %d Mynt, %d Stjärnor" % [p2.player_name, p2.coins, p2.stars]
	
	# Fallback for old UI
	if not p1_info and coin_label:
		var text = ""
		for p in players:
			text += "%s: %d Mynt\n" % [p.player_name, p.coins]
		coin_label.text = text

func update_camera_focus(instant: bool = false) -> void:
	var player = players[current_player_index]
	cam_target_pos = player.global_position + cam_offset
	cam_target_look_at = player.global_position + Vector3(0, 1.0, 0)
	
	if instant:
		main_camera.global_position = cam_target_pos
		main_camera.look_at(cam_target_look_at)
		cam_target_look_at = player.global_position + Vector3(0, 1.0, 0)

func toggle_build_mode() -> void:
	is_build_mode = !is_build_mode
	builder.toggle(is_build_mode)
	
	if build_ui:
		build_ui.visible = is_build_mode
	
	if is_build_mode:
		if dice_button: dice_button.visible = false
		if info_label: info_label.text = "BYGG-LÄGE AKTIVERAT (Klicka för att placera)"
		# Flytta upp kameran för bättre överblick när man bygger
		cam_target_pos = Vector3(0, 45, 45)
		cam_target_look_at = Vector3.ZERO
	else:
		if dice_button: dice_button.visible = true
		if info_label: info_label.text = "Runda %d/%d" % [current_turn, max_turns]
		update_camera_focus()
		update_ui()
