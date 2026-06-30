@tool
extends Node3D
class_name Player3D

@export var player_name: String = "Player": set = _set_name
@export var player_color: Color = Color.WHITE: set = _set_color

func _set_name(val: String) -> void:
	player_name = val
	var label = get_node_or_null("NameLabel")
	if label:
		label.text = player_name

func _set_color(val: Color) -> void:
	player_color = val
	var label = get_node_or_null("NameLabel")
	if label:
		label.modulate = player_color
@export var model_path: String = ""

var coins: int = 10
var stars: int = 0
var current_space: BoardSpace3D
var is_moving: bool = false
var is_jumping: bool = false
var velocity_y: float = 0.0
const GRAVITY_STRENGTH = -25.0

var anim_timer: float = 0.0
var current_anim_state: String = "Idle"

signal move_finished

@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true)
@onready var skeleton: Skeleton3D = find_child("Skeleton3D", true)

func _ready() -> void:
	# Add a name label if it doesn't exist (using a Sprite3D or similar)
	if not has_node("NameLabel"):
		var label = Label3D.new()
		label.name = "NameLabel"
		label.text = player_name
		label.modulate = player_color
		label.position = Vector3(0, 4.5, 0) # Higher up due to scale
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	else:
		$NameLabel.text = player_name
		$NameLabel.modulate = player_color
		
	if model_path != "":
		# Remove the default model if it exists
		for child in get_children():
			if "model" in child.name.to_lower() and child.name != "PlayerModel":
				child.queue_free()
		
		# Instantiate the new model if it's not already there
		if not has_node("PlayerModel"):
			var scene = load(model_path)
			if scene:
				var model = scene.instantiate()
				model.name = "PlayerModel"
				add_child(model)
				# Find the animation player and skeleton in the new model
				animation_player = model.find_child("AnimationPlayer", true)
				skeleton = model.find_child("Skeleton3D", true)
				# Scale correctly for our board
				if "mario" in model_path.to_lower():
					model.scale = Vector3(6.0, 6.0, 6.0) 
					model.position = Vector3(0, 0, 0)
				elif "luigi" in model_path.to_lower():
					model.scale = Vector3(4.0, 4.0, 4.0)
				else:
					model.scale = Vector3(4.0, 4.0, 4.0)
				
	if animation_player:
		print("Animations for %s: %s" % [player_name, animation_player.get_animation_list()])

	play_animation("Idle")

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	# Procedural gravity / Fall logic if not jumping or moving via tween
	if not is_moving and not is_jumping:
		if global_position.y > 0.0:
			velocity_y += GRAVITY_STRENGTH * delta
			global_position.y += velocity_y * delta
			if global_position.y < 0.0:
				global_position.y = 0.0
				velocity_y = 0.0
		else:
			global_position.y = 0.0
			velocity_y = 0.0

	# Procedural animations as fallback or additional juice
	anim_timer += delta
	
	var model = get_node_or_null("PlayerModel")
	if not model: return
	
	match current_anim_state:
		"Idle":
			var is_luigi = "luigi" in player_name.to_lower()
			if not is_luigi:
				# Gentle bobbing for others
				model.position.y = lerp(model.position.y, sin(anim_timer * 2.0) * 0.1, delta * 5.0)
			else:
				# Luigi stands still on the floor
				model.position.y = lerp(model.position.y, 0.0, delta * 5.0)
				model.rotation.z = lerp_angle(model.rotation.z, 0.0, delta * 5.0)
			
			_apply_character_procedural_anim("Idle")
		"Walk":
			var is_luigi = "luigi" in player_name.to_lower()
			# More intense bobbing/waddle
			model.position.y = abs(sin(anim_timer * (12.0 if is_luigi else 10.0))) * (0.15 if is_luigi else 0.3)
			model.rotation.z = sin(anim_timer * 10.0) * 0.1
			if is_luigi:
				# Luigi's walk is now less "bouncy/shaky"
				model.rotation.x = 0.0
			_apply_character_procedural_anim("Walk")
		"Victory":
			# Spin and jump
			model.rotate_y(delta * 10.0)
			model.position.y = 1.0 + abs(sin(anim_timer * 5.0)) * 2.0
			_apply_character_procedural_anim("Victory")

func _apply_character_procedural_anim(state: String) -> void:
	if not skeleton: return
	
	var is_luigi = "luigi" in player_name.to_lower()
	var is_mario = "mario" in player_name.to_lower()
	
	# Get bone indices
	var l_arm: int = -1
	var r_arm: int = -1
	var l_leg: int = -1
	var r_leg: int = -1
	var head: int = -1
	
	if is_luigi:
		l_arm = skeleton.find_bone("L_upperarm_024")
		r_arm = skeleton.find_bone("R_upperarm_041")
		l_leg = skeleton.find_bone("L_thigh_057")
		r_leg = skeleton.find_bone("R_thigh_062")
		head = skeleton.find_bone("head_05")
	elif is_mario:
		l_arm = skeleton.find_bone("L_upperarm_020")
		r_arm = skeleton.find_bone("R_upperarm_037")
		l_leg = skeleton.find_bone("L_thigh_05")
		r_leg = skeleton.find_bone("R_thigh_011")
		head = skeleton.find_bone("head_053")
	
	if l_arm == -1: return

	match state:
		"Idle":
			# Classic Mario Party poses
			if is_luigi:
				# Luigi: Hands straight down, very nervous
				skeleton.set_bone_pose_rotation(l_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(105)) * Quaternion(Vector3(0, 1, 0), deg_to_rad(15)))
				skeleton.set_bone_pose_rotation(r_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(-105)) * Quaternion(Vector3(0, 1, 0), deg_to_rad(-15)))
				
				# Slow head movement
				if head != -1:
					var head_look = sin(anim_timer * 0.7) * 0.35 # Slow look left and right
					skeleton.set_bone_pose_rotation(head, Quaternion(Vector3(0, 1, 0), head_look))
			else:
				# Mario: Confident, hands slightly out
				skeleton.set_bone_pose_rotation(l_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(45)))
				skeleton.set_bone_pose_rotation(r_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(-45)))
				
		"Walk":
			var cycle_speed = 12.0
			var swing = sin(anim_timer * cycle_speed)
			var bounce = abs(sin(anim_timer * cycle_speed))
			
			if is_luigi:
				# Luigi: Bouncy walk with hands STRAIGHT DOWN
				# Arm swing is minimal, mostly just follows the body
				skeleton.set_bone_pose_rotation(l_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(100 + swing * 3)))
				skeleton.set_bone_pose_rotation(r_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(-100 + swing * 3)))
				# Legs swing wide
				skeleton.set_bone_pose_rotation(l_leg, Quaternion(Vector3(1, 0, 0), swing * 0.6))
				skeleton.set_bone_pose_rotation(r_leg, Quaternion(Vector3(1, 0, 0), -swing * 0.6))
			else:
				# Mario: Big confident arm swings
				skeleton.set_bone_pose_rotation(l_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(45 + swing * 30)))
				skeleton.set_bone_pose_rotation(r_arm, Quaternion(Vector3(1, 0, 0), deg_to_rad(-45 + swing * 30)))
				# Classic run
				skeleton.set_bone_pose_rotation(l_leg, Quaternion(Vector3(1, 0, 0), swing * 0.8))
				skeleton.set_bone_pose_rotation(r_leg, Quaternion(Vector3(1, 0, 0), -swing * 0.8))
				
		"Victory":
			# Both celebrate with arms up
			var spin = sin(anim_timer * 15.0) * 0.2
			skeleton.set_bone_pose_rotation(l_arm, Quaternion(Vector3(0, 0, 1), deg_to_rad(130 + spin)))
			skeleton.set_bone_pose_rotation(r_arm, Quaternion(Vector3(0, 0, 1), deg_to_rad(-130 + spin)))


func jump() -> void:
	is_jumping = true
	# Physically move the player up and down with more "oomph"
	var tween = create_tween().set_parallel(true)
	# Jump up
	tween.tween_property(self, "position:y", 2.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Land on floor (y=0)
	tween.chain().tween_property(self, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Squash and stretch
	var model = find_child("PlayerModel", true)
	if model:
		var scale_tween = create_tween()
		scale_tween.tween_property(model, "scale:y", 0.7, 0.1) # Squish before jump
		scale_tween.tween_property(model, "scale:y", 1.3, 0.15) # Stretch mid-air
		scale_tween.tween_property(model, "scale:y", 1.0, 0.2).set_trans(Tween.TRANS_BOUNCE) # Land
	
	await tween.finished
	is_jumping = false
	velocity_y = 0.0
	play_animation("Idle")

func play_animation(anim_name: String) -> void:
	current_anim_state = anim_name
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
		# Special case for "Take 001" which is often the only anim in Sketchfab models
		if "take 001" in str(anim_list).to_lower():
			animation_player.play("Take 001")
		elif anim_list.size() > 0:
			animation_player.play(anim_list[0])

func move_to_space(target_space: BoardSpace3D) -> void:
	is_moving = true
	var target_pos = target_space.global_position + Vector3(0, 0.0, 0)
	
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
