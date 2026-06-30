extends Node2D

@onready var board_node: Node2D = $Board
@onready var roll_button: Button = $UI/RollButton
@onready var dice_label: Label = $UI/DiceLabel
@onready var coin_label: Label = $UI/CoinLabel

var players: Array[BoardPlayer] = []
var current_player_index: int = 0

func _ready() -> void:
	# Koppla ihop rutorna i ordning
	var spaces = board_node.get_children()
	for i in range(spaces.size() - 1):
		var current = spaces[i] as BoardSpace
		var next = spaces[i+1] as BoardSpace
		current.next_spaces.append(next)
		current.update_appearance()
	
	# Sista rutan behöver också uppdatera utseende
	if spaces.size() > 0:
		(spaces[-1] as BoardSpace).update_appearance()
	
	# Hitta alla spelare i scenen
	for child in get_children():
		if child is BoardPlayer:
			players.append(child)
			child.movement_finished.connect(_on_player_movement_finished)
	
	# Koppla knappen
	roll_button.pressed.connect(_on_roll_button_pressed)
	_update_ui()
	if players.size() > 0:
		dice_label.text = "Det är " + players[current_player_index].player_name + "s tur!"

func _on_roll_button_pressed() -> void:
	roll_button.disabled = true
	var roll = randi_range(1, 6)
	var current_player = players[current_player_index]
	dice_label.text = current_player.player_name + " slog en " + str(roll) + "!"
	current_player.move(roll)

func _on_player_movement_finished() -> void:
	var player = players[current_player_index]
	
	# Kolla vilken ruta man hamnade på
	match player.current_space.type:
		BoardSpace.SpaceType.BLUE:
			player.coins += 3
		BoardSpace.SpaceType.RED:
			player.coins = max(0, player.coins - 3)
	
	_update_ui()
	
	# Vänta lite innan nästa tur
	await get_tree().create_timer(1.0).timeout
	current_player_index = (current_player_index + 1) % players.size()
	roll_button.disabled = false
	dice_label.text = "Det är " + players[current_player_index].player_name + "s tur!"

func _update_ui() -> void:
	var text = ""
	for p in players:
		text += p.player_name + ": " + str(p.coins) + " coins\n"
	coin_label.text = text
