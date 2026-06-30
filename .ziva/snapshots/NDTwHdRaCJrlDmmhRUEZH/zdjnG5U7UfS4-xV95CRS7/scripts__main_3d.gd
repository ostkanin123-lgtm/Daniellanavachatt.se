extends Node3D

@onready var dice_button: Button = $CanvasLayer/Control/RollButton
@onready var info_label: Label = $CanvasLayer/Control/DiceLabel
@onready var coin_label: Label = $CanvasLayer/Control/VBoxContainer/Player1Info # Simplified for now
@onready var main_camera: Camera3D = $Camera3D

var players: Array[Player3D] = []
var current_player_index: int = 0
var is_rolling: bool = false

@onready var dice_3d: Node3D = $Dice3D

func _ready() -> void:
	# Create some board spaces if they don't exist
	if $Board.get_child_count() == 0:
		var space_scene = load("res://scenes/board_space_3d.tscn")
		for i in range(20):
			var space = space_scene.instantiate()
			$Board.add_child(space)
			
	# Link board spaces and position them in a nice layout
	var spaces = $Board.get_children()
	
	# Create a circle layout for now, it's safer
	var loop_size = spaces.size()
	for i in range(loop_size):
		var angle = (float(i) / float(loop_size)) * TAU
		var x = 12.0 * cos(angle)
		var z = 12.0 * sin(angle)
		
		var pos = Vector3(x, 0, z)
		spaces[i].position = pos
		
		var next_idx = (i + 1) % spaces.size()
		spaces[i].next_space = spaces[next_idx]
		
		# Variety
		if i % 5 == 0: spaces[i].type = BoardSpace3D.SpaceType.STAR
		elif i % 3 == 0: spaces[i].type = BoardSpace3D.SpaceType.RED
		else: spaces[i].type = BoardSpace3D.SpaceType.BLUE
		
		spaces[i].update_appearance()
	
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
	
	update_ui()
	update_camera_focus(true)


func add_model_to_space(space: Node3D, path: String, offset: Vector3, scale_val: float):
	var scene = load(path)
	if scene:
		var model = scene.instantiate()
		space.add_child(model)
		model.position = offset
		model.scale = Vector3(scale_val, scale_val, scale_val)
		if "star" in path.to_lower():
			var tween = create_tween().set_loops()
			tween.tween_property(model, "rotation:y", TAU, 2.0).as_relative()
		elif "bowser" in path.to_lower():
			model.rotation_degrees.y = 180

func add_decorations():
	var rock_scene = load("res://desert__rocks__stones__pack.glb")
	if rock_scene:
		var decor_positions = [
			Vector3(8, 0, 8), Vector3(4, 0, 4), Vector3(12, 0, 12), Vector3(4, 0, 12), Vector3(12, 0, 4)
		]
		for pos in decor_positions:
			var rock = rock_scene.instantiate()
			add_child(rock)
			rock.position = pos
			rock.scale = Vector3(0.5, 0.5, 0.5)
			rock.rotation_y(randf() * TAU)

func _on_roll_button_pressed() -> void:
	if is_rolling: return
	
	var player = players[current_player_index]
	is_rolling = true
	dice_button.disabled = true
	
	# Cinematic focus on current player
	update_camera_focus()
	
	# Show dice above player
	dice_3d.global_position = player.global_position + Vector3(0, 3.5, 0)
	dice_3d.visible = true
	dice_3d.start_roll()
	
	# Move camera a bit closer to dice
	var cam_tween = create_tween()
	var cam_target = player.global_position + Vector3(0, 4.5, 5)
	cam_tween.tween_property(main_camera, "global_position", cam_target, 0.4).set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(1.2).timeout
	
	# Player jumps!
	await player.jump()
	
	# Dice stops
	var roll = await dice_3d.stop_roll()
	info_label.text = "%s slog en %d!" % [player.player_name, roll]
	
	await get_tree().create_timer(0.8).timeout
	dice_3d.visible = false
	
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
	await get_tree().create_timer(1.0).timeout
	
	is_rolling = false
	dice_button.disabled = false
	update_ui()
	
	update_camera_focus()

func update_ui() -> void:
	var current_player = players[current_player_index]
	info_label.text = "Det är %s tur!" % current_player.player_name
	
	var coins_text = ""
	for p in players:
		coins_text += "%s: %d Coins, %d Stars\n" % [p.player_name, p.coins, p.stars]
	coin_label.text = coins_text

func update_camera_focus(instant: bool = false) -> void:
	var player = players[current_player_index]
	var target_pos = player.global_position + Vector3(0, 10, 12)
	
	if instant:
		main_camera.global_position = target_pos
		main_camera.look_at(player.global_position + Vector3(0, 1.5, 0))
		return
		
	var tween = create_tween().set_parallel(true)
	tween.tween_property(main_camera, "global_position", target_pos, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var current_rot = main_camera.quaternion
	main_camera.look_at(player.global_position + Vector3(0, 1.5, 0))
	var target_rot = main_camera.quaternion
	main_camera.quaternion = current_rot
	tween.tween_property(main_camera, "quaternion", target_rot, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
