extends Node3D

const ROOM_HALF_X := 4.5
const ROOM_HALF_Z := 4.5
const WALL_HEIGHT := 3.2
const PLAYER_SPEED := 4.2
const LOOK_SENS := 0.0025
const TURN_SPEED := 1.8
const NETWORK_TICK := 0.08

@onready var world_root: Node3D = $Generated
@onready var local_player: CharacterBody3D = $LocalPlayer
@onready var head: Node3D = $LocalPlayer/Head
@onready var camera: Camera3D = $LocalPlayer/Head/Camera3D
@onready var remote_players_root: Node3D = $RemotePlayers
@onready var key_root: Node3D = $KeyRoot
@onready var door_pivot: Node3D = $DoorPivot
@onready var door_body: StaticBody3D = $DoorPivot/DoorBody
@onready var door_collision: CollisionShape3D = $DoorPivot/DoorBody/CollisionShape3D
@onready var lamp_light: OmniLight3D = $LampLight

@onready var room_code_edit: LineEdit = $UI/Panel/VBox/RoomCode
@onready var ip_edit: LineEdit = $UI/Panel/VBox/IpAddress
@onready var port_edit: LineEdit = $UI/Panel/VBox/Port
@onready var status_label: Label = $UI/Panel/VBox/Status
@onready var hint_label: Label = $UI/Hint

var key_spots: Array[Vector3] = [
	Vector3(-3.2, 0.65, -3.3),
	Vector3(3.1, 0.95, -2.9),
	Vector3(-1.2, 0.15, 2.7),
	Vector3(3.2, 0.35, 2.5),
]

var key_index := 0
var key_taken := false
var key_owner_id := 0
var door_open := false

var look_pitch := 0.0
var capture_mouse := true

var net_peer: ENetMultiplayerPeer
var remote_nodes := {}
var send_timer := 0.0

func _ready() -> void:
	_build_room_visuals()
	_apply_key_index(_compute_key_index(room_code_edit.text))
	_update_status("Morkt rum redo. Skapa eller ga med i ett rum.")

	$UI/Panel/VBox/Buttons/HostButton.pressed.connect(_on_host_pressed)
	$UI/Panel/VBox/Buttons/JoinButton.pressed.connect(_on_join_pressed)
	$UI/Panel/VBox/Buttons/DisconnectButton.pressed.connect(_on_disconnect_pressed)
	$UI/Panel/VBox/BackButton.pressed.connect(_on_back_pressed)
	$UI/Panel/VBox/CaptureToggle.toggled.connect(_on_capture_toggled)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	capture_mouse = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and capture_mouse:
		local_player.rotate_y(-event.relative.x * LOOK_SENS)
		look_pitch = clamp(look_pitch - event.relative.y * LOOK_SENS, -1.2, 1.2)
		head.rotation.x = look_pitch

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			capture_mouse = not capture_mouse
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_E:
			_try_interact()

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	lamp_light.light_energy = 0.62 + sin(t * 6.0) * 0.06 + sin(t * 21.0) * 0.03

	if not key_taken:
		key_root.rotation.y += delta * 1.9
		key_root.position.y = 0.55 + sin(t * 2.3) * 0.04

	_update_hint()

func _physics_process(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT):
		local_player.rotate_y(TURN_SPEED * delta)
	if Input.is_key_pressed(KEY_RIGHT):
		local_player.rotate_y(-TURN_SPEED * delta)

	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.y += 1.0
	input = input.normalized()

	var basis := local_player.global_transform.basis
	var move_dir := (basis.x * input.x + basis.z * input.y)
	move_dir.y = 0.0
	move_dir = move_dir.normalized()

	local_player.velocity.x = move_dir.x * PLAYER_SPEED
	local_player.velocity.z = move_dir.z * PLAYER_SPEED
	if not local_player.is_on_floor():
		local_player.velocity.y -= 20.0 * delta
	else:
		local_player.velocity.y = 0.0
	local_player.move_and_slide()

	if multiplayer.multiplayer_peer != null:
		send_timer += delta
		if send_timer >= NETWORK_TICK:
			send_timer = 0.0
			rpc("net_state", local_player.global_position, local_player.rotation.y)

func _try_interact() -> void:
	if not key_taken and local_player.global_position.distance_to(key_root.global_position) < 1.25:
		_take_key(multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1)
		if multiplayer.multiplayer_peer != null:
			rpc("net_key_taken", key_owner_id)
		return

	if local_player.global_position.distance_to(door_pivot.global_position) < 2.0:
		if not key_taken:
			_update_status("Dorren ar last. Nyckeln ar gomd i rummet.")
			return
		if key_owner_id != 0 and key_owner_id != multiplayer.get_unique_id() and multiplayer.multiplayer_peer != null:
			_update_status("Din lagkamrat har nyckeln.")
			return
		_open_door(multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1)
		if multiplayer.multiplayer_peer != null:
			rpc("net_door_open", multiplayer.get_unique_id())

func _update_hint() -> void:
	if not key_taken and local_player.global_position.distance_to(key_root.global_position) < 1.3:
		hint_label.text = "Tryck E for att plocka upp nyckeln"
		return
	if local_player.global_position.distance_to(door_pivot.global_position) < 2.2:
		hint_label.text = "Tryck E vid dorren" if key_taken else "Dorren ar last"
		return
	if capture_mouse:
		hint_label.text = "WASD ror dig, mus tittar, E interagerar"
	else:
		hint_label.text = "Muskontroll av: tryck ESC for att lasa musen"

func _compute_key_index(code: String) -> int:
	var hash := 0
	for c in code:
		hash = int((hash * 31 + c.unicode_at(0)) & 0x7fffffff)
	return hash % key_spots.size()

func _apply_key_index(index: int) -> void:
	key_index = clamp(index, 0, key_spots.size() - 1)
	key_taken = false
	key_owner_id = 0
	door_open = false
	key_root.visible = true
	key_root.position = key_spots[key_index]
	door_pivot.rotation.y = 0.0
	door_collision.disabled = false

func _take_key(owner_id: int) -> void:
	if key_taken:
		return
	key_taken = true
	key_owner_id = owner_id
	key_root.visible = false
	if owner_id == multiplayer.get_unique_id() or multiplayer.multiplayer_peer == null:
		_update_status("Du hittade nyckeln. Oppna dorren.")
	else:
		_update_status("Din lagkamrat hittade nyckeln!")

func _open_door(opener_id: int) -> void:
	if door_open:
		return
	door_open = true
	door_collision.disabled = true
	var tween := create_tween()
	tween.tween_property(door_pivot, "rotation:y", -PI * 0.52, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if opener_id == multiplayer.get_unique_id() or multiplayer.multiplayer_peer == null:
		_update_status("Dorren oppnades. Ni overlevde... for nu.")
	else:
		_update_status("Din lagkamrat oppnade dorren!")

func _update_status(text: String) -> void:
	status_label.text = text

func _on_capture_toggled(enabled: bool) -> void:
	capture_mouse = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE

func _on_host_pressed() -> void:
	var port := int(port_edit.text)
	if port <= 0:
		port = 7777
	_apply_key_index(_compute_key_index(room_code_edit.text))

	net_peer = ENetMultiplayerPeer.new()
	var err := net_peer.create_server(port, 2)
	if err != OK:
		_update_status("Kunde inte hosta pa port %d" % port)
		return

	multiplayer.multiplayer_peer = net_peer
	_update_status("Host aktiv. Dela ditt IP + port %d till vannen." % port)

func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	var port := int(port_edit.text)
	if ip.is_empty():
		ip = "127.0.0.1"
	if port <= 0:
		port = 7777
	_apply_key_index(_compute_key_index(room_code_edit.text))

	net_peer = ENetMultiplayerPeer.new()
	var err := net_peer.create_client(ip, port)
	if err != OK:
		_update_status("Kunde inte ansluta till %s:%d" % [ip, port])
		return

	multiplayer.multiplayer_peer = net_peer
	_update_status("Ansluter till host %s:%d ..." % [ip, port])

func _on_disconnect_pressed() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	for id in remote_nodes.keys():
		if is_instance_valid(remote_nodes[id]):
			remote_nodes[id].queue_free()
	remote_nodes.clear()
	_update_status("Fran kopplad.")

func _on_back_pressed() -> void:
	_on_disconnect_pressed()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_connected_to_server() -> void:
	_update_status("Ansluten. Vantar pa synk fran host...")

func _on_connection_failed() -> void:
	_update_status("Anslutning misslyckades.")

func _on_server_disconnected() -> void:
	_update_status("Host kopplade ner.")
	for id in remote_nodes.keys():
		if is_instance_valid(remote_nodes[id]):
			remote_nodes[id].queue_free()
	remote_nodes.clear()

func _on_peer_connected(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	if multiplayer.is_server():
		rpc_id(id, "net_sync_world", key_index, key_taken, key_owner_id, door_open)

func _on_peer_disconnected(id: int) -> void:
	if remote_nodes.has(id) and is_instance_valid(remote_nodes[id]):
		remote_nodes[id].queue_free()
	remote_nodes.erase(id)
	_update_status("Spelare %d kopplade ner." % id)

func _ensure_remote(id: int) -> Node3D:
	if remote_nodes.has(id) and is_instance_valid(remote_nodes[id]):
		return remote_nodes[id]

	var root := Node3D.new()
	root.name = "Remote_%d" % id
	remote_players_root.add_child(root)

	var mesh := MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	(mesh.mesh as CapsuleMesh).radius = 0.28
	(mesh.mesh as CapsuleMesh).height = 1.2
	mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.72, 0.78, 1.0)
	mat.roughness = 0.62
	mesh.material_override = mat
	root.add_child(mesh)

	var lbl := Label3D.new()
	lbl.text = "Spelare %d" % id
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.position = Vector3(0, 2.1, 0)
	lbl.modulate = Color(0.82, 0.92, 1.0, 1.0)
	root.add_child(lbl)

	remote_nodes[id] = root
	return root

@rpc("any_peer", "unreliable")
func net_state(pos: Vector3, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == multiplayer.get_unique_id():
		return
	var remote := _ensure_remote(sender)
	remote.global_position = pos
	remote.rotation.y = yaw

@rpc("any_peer")
func net_key_taken(owner_id: int) -> void:
	_take_key(owner_id)

@rpc("any_peer")
func net_door_open(opener_id: int) -> void:
	_open_door(opener_id)

@rpc("authority")
func net_sync_world(sync_key_index: int, sync_key_taken: bool, sync_owner_id: int, sync_door_open: bool) -> void:
	_apply_key_index(sync_key_index)
	if sync_key_taken:
		_take_key(sync_owner_id)
	if sync_door_open:
		_open_door(sync_owner_id)

func _build_room_visuals() -> void:
	for c in world_root.get_children():
		c.queue_free()

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.16, 0.17, 0.18)
	wall_mat.roughness = 0.88
	wall_mat.metallic = 0.02

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.13, 0.12, 0.11)
	floor_mat.roughness = 0.93

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.22, 0.14, 0.08)
	wood_mat.roughness = 0.84

	_add_static_box("Floor", Vector3(ROOM_HALF_X * 2.0, 0.12, ROOM_HALF_Z * 2.0), Vector3(0, -0.06, 0), floor_mat)
	_add_static_box("Ceiling", Vector3(ROOM_HALF_X * 2.0, 0.12, ROOM_HALF_Z * 2.0), Vector3(0, WALL_HEIGHT + 0.06, 0), wall_mat)
	_add_static_box("NorthWall", Vector3(ROOM_HALF_X * 2.0, WALL_HEIGHT, 0.16), Vector3(0, WALL_HEIGHT * 0.5, -ROOM_HALF_Z), wall_mat)
	_add_static_box("WestWall", Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0), Vector3(-ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), wall_mat)
	_add_static_box("EastWall", Vector3(0.16, WALL_HEIGHT, ROOM_HALF_Z * 2.0), Vector3(ROOM_HALF_X, WALL_HEIGHT * 0.5, 0), wall_mat)
	_add_static_box("SouthWallLeft", Vector3(3.2, WALL_HEIGHT, 0.16), Vector3(-2.65, WALL_HEIGHT * 0.5, ROOM_HALF_Z), wall_mat)
	_add_static_box("SouthWallRight", Vector3(3.2, WALL_HEIGHT, 0.16), Vector3(2.65, WALL_HEIGHT * 0.5, ROOM_HALF_Z), wall_mat)

	# Bed
	_add_static_box("BedBase", Vector3(2.4, 0.5, 1.3), Vector3(-2.8, 0.25, -2.95), wood_mat)
	var mattress_mat := StandardMaterial3D.new()
	mattress_mat.albedo_color = Color(0.42, 0.42, 0.45)
	mattress_mat.roughness = 0.73
	_add_static_box("Mattress", Vector3(2.2, 0.3, 1.1), Vector3(-2.8, 0.65, -2.95), mattress_mat)
	_add_static_box("Pillow", Vector3(0.62, 0.16, 0.38), Vector3(-3.48, 0.88, -2.95), mattress_mat, false)

	# Table
	_add_static_box("TableTop", Vector3(1.4, 0.12, 0.9), Vector3(2.8, 0.95, -2.7), wood_mat)
	for p in [
		Vector3(2.2, 0.45, -3.05),
		Vector3(3.4, 0.45, -3.05),
		Vector3(2.2, 0.45, -2.35),
		Vector3(3.4, 0.45, -2.35)
	]:
		_add_static_box("TableLeg", Vector3(0.1, 0.9, 0.1), p, wood_mat)

	# Window
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.34, 0.45, 0.53, 0.48)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.12
	glass_mat.metallic = 0.08
	_add_static_box("WindowFrameTop", Vector3(2.6, 0.12, 0.06), Vector3(0, 2.65, -ROOM_HALF_Z + 0.03), wood_mat, false)
	_add_static_box("WindowFrameBottom", Vector3(2.6, 0.12, 0.06), Vector3(0, 1.45, -ROOM_HALF_Z + 0.03), wood_mat, false)
	_add_static_box("WindowFrameL", Vector3(0.12, 1.3, 0.06), Vector3(-1.25, 2.05, -ROOM_HALF_Z + 0.03), wood_mat, false)
	_add_static_box("WindowFrameR", Vector3(0.12, 1.3, 0.06), Vector3(1.25, 2.05, -ROOM_HALF_Z + 0.03), wood_mat, false)
	_add_static_box("WindowGlass", Vector3(2.35, 1.05, 0.03), Vector3(0, 2.05, -ROOM_HALF_Z + 0.05), glass_mat, false)

	# Wall lamps from imported GLB (if available).
	var lamp_scene := load("res://assets/props/wall_light.glb")
	if lamp_scene is PackedScene:
		_add_wall_lamp(lamp_scene, Vector3(-ROOM_HALF_X + 0.07, 1.95, -1.9), PI * 0.5)
		_add_wall_lamp(lamp_scene, Vector3(ROOM_HALF_X - 0.07, 1.95, -1.9), -PI * 0.5)
		_add_wall_lamp(lamp_scene, Vector3(-ROOM_HALF_X + 0.07, 1.95, 1.9), PI * 0.5)
		_add_wall_lamp(lamp_scene, Vector3(ROOM_HALF_X - 0.07, 1.95, 1.9), -PI * 0.5)
	else:
		push_warning("Could not load wall_light.glb")

func _add_static_box(node_name: String, size: Vector3, position: Vector3, mat: Material, with_collision: bool = true) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	world_root.add_child(root)

	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mesh)

	if with_collision:
		var body := StaticBody3D.new()
		root.add_child(body)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)

func _add_wall_lamp(scene: PackedScene, pos: Vector3, rot_y: float) -> void:
	var inst := scene.instantiate()
	if not (inst is Node3D):
		return
	var lamp_root := Node3D.new()
	lamp_root.name = "WallLamp"
	lamp_root.position = pos
	lamp_root.rotation.y = rot_y
	world_root.add_child(lamp_root)
	lamp_root.add_child(inst)

	var mesh_holder := inst as Node3D
	mesh_holder.scale = Vector3(0.45, 0.45, 0.45)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.66, 1.0)
	light.light_energy = 0.35
	light.omni_range = 3.2
	light.omni_attenuation = 1.8
	light.position = Vector3(0, 0.22, 0.16)
	lamp_root.add_child(light)
