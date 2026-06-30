class_name BoardSpace
extends Node2D

enum SpaceType { GREEN, BLUE, RED }

@export var type: SpaceType = SpaceType.GREEN
@export var next_spaces: Array[BoardSpace] = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	update_appearance()

func update_appearance() -> void:
	if not is_node_ready(): return
	
	match type:
		SpaceType.GREEN:
			sprite.texture = load("res://assets/generated/board_tile_green_frame_0_1774537604.png")
		SpaceType.BLUE:
			sprite.texture = load("res://assets/generated/board_tile_blue_frame_0_1774537608.png")
		SpaceType.RED:
			sprite.texture = load("res://assets/generated/board_tile_red_frame_0_1774537613.png")

func get_next_space() -> BoardSpace:
	if next_spaces.is_empty():
		return null
	return next_spaces[0] # För nuvarande, ta bara första. Senare kan vi lägga till val vid korsningar.
