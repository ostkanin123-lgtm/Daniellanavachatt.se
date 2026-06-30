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
			sprite.texture = load("res://assets/generated/tile_green_frame_0_1774537221.png")
		SpaceType.BLUE:
			sprite.texture = load("res://assets/generated/tile_blue_frame_0_1774537234.png")
		SpaceType.RED:
			sprite.texture = load("res://assets/generated/tile_red_frame_0_1774537225.png")

func get_next_space() -> BoardSpace:
	if next_spaces.is_empty():
		return null
	return next_spaces[0] # För nuvarande, ta bara första. Senare kan vi lägga till val vid korsningar.
