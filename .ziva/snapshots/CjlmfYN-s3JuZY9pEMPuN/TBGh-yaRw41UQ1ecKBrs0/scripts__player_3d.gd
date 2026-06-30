extends Node3D
class_name Player3D

@export var player_name: String = "Player"
@export var player_color: Color = Color.WHITE
@export var model_path: String = ""

var coins: int = 10
var stars: int = 0
var current_space: BoardSpace3D
var is_moving: bool = false

signal move_finished

@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true)

func _ready() -> void:
	# Add a name label if it doesn't exist (using a Sprite3D or similar)
	if not has_node("NameLabel"):
		var label = Label3D.new()
		label.name = "NameLabel"
		label.text = player_name
		label.modulate = player_color
		label.position = Vector3(0, 2.0, 0) # Above head
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	else:
		$NameLabel.text = player_name
		$NameLabel.modulate = player_color
		
	if model_path != "":
		# Remove the default model if it exists
		if has_node("MarioModel"):
			$MarioModel.queue_free()
		if has_node("PlayerModel"):
			$PlayerModel.queue_free()
		
		# Instantiate the new model
		var scene = load(model_path)
		if scene:
			var model = scene.instantiate()
			model.name = "PlayerModel"
			add_child(model)
			# Find the animation player in the new model
			animation_player = model.find_child("AnimationPlayer", true)
			# Scale correctly for our board
			if "mario" in model_path.to_lower():
				model.scale = Vector3(0.5, 0.5, 0.5)
			elif "luigi" in model_path.to_lower():
				model.scale = Vector3(0.005, 0.005, 0.005) # Some FBX/GLB might be huge
			else:
				model.scale = Vector3(0.5, 0.5, 0.5)

	play_animation("Idle")

func jump() -> void:
	# Store start position
	var start_y = position.y
	
	# Try to play a "Jump" animation
	play_animation("Jump")
	
	# Physically move the player up and down
	var tween = create_tween()
	tween.tween_property(self, "position:y", start_y + 1.5, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", start_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	play_animation("Idle")

func play_animation(anim_name: String) -> void:
	if not animation_player: return
	
	var actual_anim = ""
	var anim_list = animation_player.get_animation_list()
	
	# Try to find a match by case-insensitive name or substring
	for a in anim_list:
		if a.to_lower() == anim_name.to_lower():
			actual_anim = a
			break
		if anim_name.to_lower() in a.to_lower():
			actual_anim = a
			break
			
	if actual_anim != "":
		animation_player.play(actual_anim)
	else:
		# Fallback: if looking for walk/run and not found, try any animation with 'walk'
		if anim_name == "Walk" or anim_name == "Run":
			for a in anim_list:
				if "walk" in a.to_lower() or "run" in a.to_lower():
					animation_player.play(a)
					return
		if anim_list.size() > 0:
			animation_player.play(anim_list[0])

func move_to_space(target_space: BoardSpace3D) -> void:
	is_moving = true
	var target_pos = target_space.global_position + Vector3(0, 0.5, 0)
	
	if target_pos != global_position:
		look_at(target_pos, Vector3.UP)
		rotation.x = 0
	
	play_animation("Walk")
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_SINE)
	await tween.finished
	
	current_space = target_space
	is_moving = false
	play_animation("Idle")
	move_finished.emit()

func move(steps: int) -> void:
	for i in range(steps):
		if current_space and current_space.next_space:
			# Check if we are PASSING a Star space
			if current_space.next_space.type == BoardSpace3D.SpaceType.STAR:
				# Mario Party rule: Land on or pass the star
				if coins >= 20:
					coins -= 20
					stars += 1
					print("%s bought a STAR!" % player_name)
					# Play a sound or trigger effect here
					
			await move_to_space(current_space.next_space)
			# Small pause between steps
			await get_tree().create_timer(0.2).timeout
		else:
			break
