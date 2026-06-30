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
		label.position = Vector3(0, 2.5, 0) # Above head
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	else:
		$NameLabel.text = player_name
		$NameLabel.modulate = player_color
		
	if model_path != "":
		# Remove the default model if it exists
		for child in get_children():
			if "model" in child.name.to_lower():
				child.queue_free()
		
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
				model.scale = Vector3(1.0, 1.0, 1.0) # Reset to default if it was small
				model.position = Vector3(0, 0, 0)
			elif "luigi" in model_path.to_lower():
				model.scale = Vector3(1.0, 1.0, 1.0)
			else:
				model.scale = Vector3(1.0, 1.0, 1.0)
				
	if animation_player:
		print("Animations for %s: %s" % [player_name, animation_player.get_animation_list()])

	play_animation("Idle")


func jump() -> void:
	# Store start position
	var start_y = position.y
	
	# Try to play a "Jump" animation
	play_animation("Jump")
	
	# Physically move the player up and down with more "oomph"
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", start_y + 2.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "position:y", start_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Squash and stretch
	var model = find_child("PlayerModel", true)
	if model:
		var scale_tween = create_tween()
		scale_tween.tween_property(model, "scale:y", 0.7, 0.1) # Squish before jump
		scale_tween.tween_property(model, "scale:y", 1.3, 0.15) # Stretch mid-air
		scale_tween.tween_property(model, "scale:y", 1.0, 0.2).set_trans(Tween.TRANS_BOUNCE) # Land
	
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
