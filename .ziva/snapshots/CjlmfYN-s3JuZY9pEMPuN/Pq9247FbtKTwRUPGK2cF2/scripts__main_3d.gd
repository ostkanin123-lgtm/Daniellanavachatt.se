extends Node3D

@onready var dice_button: Button = $UI/RollButton
@onready var info_label: Label = $UI/InfoLabel
@onready var coin_label: Label = $UI/CoinLabel
@onready var main_camera: Camera3D = $Camera3D

var players: Array[Player3D] = []
var current_player_index: int = 0
var is_rolling: bool = false

func _ready() -> void:
	# Link board spaces
	var board = $Board
	$Board/Space1.next_space = $Board/Space2
	$Board/Space2.next_space = $Board/Space3
	$Board/Space3.next_space = $Board/Space4
	$Board/Space4.next_space = $Board/Space5
	$Board/Space5.next_space = $Board/Space6
	$Board/Space6.next_space = $Board/Space1
	
	# Set player names
	$Mario.player_name = "Mario"
	$Luigi.player_name = "Luigi"
	$Luigi.get_node("MarioModel").modulate = Color(0.5, 1.0, 0.5) # Make Luigi green
	
	# Find players
	players = [$Mario, $Luigi]
	
	# Set initial space
	var start_space = $Board/Space1
	for p in players:
		p.current_space = start_space
		p.global_position = start_space.global_position + Vector3(0, 0.5, 0)
	
	update_ui()
	update_camera_focus()

func _on_roll_button_pressed() -> void:
	if is_rolling: return
	
	var player = players[current_player_index]
	is_rolling = true
	dice_button.disabled = true
	
	var roll = randi_range(1, 6)
	info_label.text = "%s slog en %d!" % [player.player_name, roll]
	
	for i in range(roll):
		if player.current_space and player.current_space.next_space:
			await player.move_to_space(player.current_space.next_space)
			update_camera_focus()
			await get_tree().create_timer(0.1).timeout
		else:
			break
	
	# Landed!
	if player.current_space:
		player.current_space.on_landed(player)
	
	update_ui()
	
	# Next turn
	current_player_index = (current_player_index + 1) % players.size()
	await get_tree().create_timer(1.0).timeout
	
	is_rolling = false
	dice_button.disabled = false
	update_ui()

func update_ui() -> void:
	var current_player = players[current_player_index]
	info_label.text = "Det är %s tur!" % current_player.player_name
	
	var coins_text = ""
	for p in players:
		coins_text += "%s: %d Coins\n" % [p.player_name, p.coins]
	coin_label.text = coins_text

func update_camera_focus() -> void:
	var player = players[current_player_index]
	var target_pos = player.global_position + Vector3(0, 5, 6) # Cinematic offset
	var tween = create_tween()
	tween.tween_property(main_camera, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_SINE)
	# Camera will always look slightly ahead or at the player
	# We'll set a fixed rotation for that classic board look in the scene file
