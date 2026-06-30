extends Node2D

@onready var player: BoardPlayer = $Player
@onready var board_node: Node2D = $Board
@onready var roll_button: Button = $UI/RollButton
@onready var dice_label: Label = $UI/DiceLabel

func _ready() -> void:
	# Koppla ihop rutorna i ordning
	var spaces = board_node.get_children()
	for i in range(spaces.size() - 1):
		var current = spaces[i] as BoardSpace
		var next = spaces[i+1] as BoardSpace
		current.next_spaces.append(next)
		current.update_appearance()
	
	# Sista rutan behöver också uppdatera utseende
	(spaces[-1] as BoardSpace).update_appearance()
	
	# Koppla knappen
	roll_button.pressed.connect(_on_roll_button_pressed)
	player.movement_finished.connect(_on_player_movement_finished)

func _on_roll_button_pressed() -> void:
	roll_button.disabled = true
	var roll = randi_range(1, 6)
	dice_label.text = "You rolled: " + str(roll)
	player.move(roll)

func _on_player_movement_finished() -> void:
	roll_button.disabled = false
	dice_label.text = "Stand on " + str(player.current_space.type)
