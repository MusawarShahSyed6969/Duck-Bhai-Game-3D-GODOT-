class_name WeaponManager
extends Node
## Child of the Player. Handles weapons, ammo, reloading, switching and shooting.
## Shots are fired from the CAMERA CENTER (where the crosshair is), like GTA.
##
## Controls (auto-registered):
##   Left Mouse / RT ... fire        R / X ........ reload
##   1-5 ............... pick weapon  Q / RB / LB ... next / previous weapon

signal weapon_changed(weapon: WeaponData)
signal ammo_changed(mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal shot_fired
signal hit_confirmed(point: Vector3)

## Leave empty to get 3 built-in weapons (Pistol, Rifle, Shotgun) for testing.
@export var weapons: Array[WeaponData] = []
## Node where the weapon model is spawned (e.g. a BoneAttachment3D on the right hand).
@export var weapon_holder: Node3D
@export_flags_3d_physics var hit_mask := 0xFFFFFFFF
@export var switch_time := 0.35
@export var bloom_recover := 4.0           ## degrees per second the spread bloom shrinks
@export var block_fire_while_sprinting := true
@export var auto_reload_when_empty := true  ## start reloading right after the last bullet
@export var shot_noise_radius := 30.0       ## zombies within this distance hear your shots
## Name of the right-hand bone. Leave empty to auto-detect (RightHand, mixamorig:RightHand, Hand_R ...)
@export var hand_bone_name := ""
## In-game gun placement tool (press T). Only works in debug builds.
@export var tuning_keys_enabled := true

var current: WeaponData
var current_index := -1
var current_spread := 0.0                  ## degrees, read by the crosshair
var is_reloading := false

var _mag: Array[int] = []
var _reserve: Array[int] = []
var _cooldown := 0.0
var _reload_left := 0.0
var _switch_left := 0.0
var _bloom := 0.0
var _player                                 # untyped on purpose (reads player vars)
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _tuning := false
var _model: Node3D


func _ready() -> void:
	_player = get_parent()
	_register_inputs()
	if weapons.is_empty():
		weapons = _default_weapons()
	for w in weapons:
		_mag.append(w.magazine_size)
		_reserve.append(w.start_reserve)
	for i in 4:                              # small pool so fast fire does not cut sounds off
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_equip(0, true)
	_setup_holder()


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------
func get_mag() -> int:
	return _mag[current_index] if current_index >= 0 else 0


func get_reserve() -> int:
	return _reserve[current_index] if current_index >= 0 else 0


## Use for ammo pickups. index = -1 means the current weapon.
func add_ammo(amount: int, index := -1) -> void:
	if index < 0:
		index = current_index
	_reserve[index] = mini(_reserve[index] + amount, weapons[index].max_reserve)
	_emit_ammo()


# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _player == null or current == null or _player.is_dead:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_switch_left = maxf(_switch_left - delta, 0.0)
	_bloom = move_toward(_bloom, 0.0, bloom_recover * delta)
	_update_spread()
	_handle_switch_input()

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	if Input.is_action_just_pressed("reload"):
		start_reload()

	_handle_fire()


func _update_spread() -> void:
	var base: float = current.spread_aim if _player.is_aiming else current.spread_hip
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var extra := current.spread_move * clampf(speed / 6.0, 0.0, 1.0)
	if not _player.is_on_floor():
		extra = current.spread_move * 1.5
	var total := base + extra + _bloom
	if _player.is_crouching:
		total *= 0.6
	current_spread = total


# ----------------------------------------------------------------------------
# Switching
# ----------------------------------------------------------------------------
func _handle_switch_input() -> void:
	for i in mini(weapons.size(), 5):
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			_equip(i)
	if Input.is_action_just_pressed("weapon_next"):
		_equip(current_index + 1)
	if Input.is_action_just_pressed("weapon_prev"):
		_equip(current_index - 1)


func _equip(index: int, instant := false) -> void:
	index = wrapi(index, 0, weapons.size())
	if index == current_index and not instant:
		return
	is_reloading = false                    # switching cancels a reload
	current_index = index
	current = weapons[index]
	_switch_left = 0.0 if instant else switch_time
	_bloom = 0.0
	_spawn_model()
	if not instant:
		_play(SFX.switch_weapon())
	weapon_changed.emit(current)
	_emit_ammo()


func _spawn_model() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	if current.weapon_scene != null and weapon_holder != null:
		_model = current.weapon_scene.instantiate() as Node3D
		weapon_holder.add_child(_model)
		_apply_hold()


# ----------------------------------------------------------------------------
# Reload
# ----------------------------------------------------------------------------
func start_reload() -> void:
	if is_reloading or _switch_left > 0.0:
		return
	if get_mag() >= current.magazine_size or get_reserve() <= 0:
		return
	is_reloading = true
	_reload_left = current.reload_time
	reload_started.emit(current.reload_time)
	_play(current.reload_sound if current.reload_sound != null else SFX.reload_weapon(current.reload_time))


func _finish_reload() -> void:
	is_reloading = false
	var need := current.magazine_size - _mag[current_index]
	var taken := mini(need, _reserve[current_index])
	_mag[current_index] += taken
	_reserve[current_index] -= taken
	_emit_ammo()
	reload_finished.emit()


# ----------------------------------------------------------------------------
# Shooting
# ----------------------------------------------------------------------------
func _handle_fire() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var wants := Input.is_action_pressed("fire") if current.automatic else Input.is_action_just_pressed("fire")
	if not wants:
		return
	if _switch_left > 0.0 or is_reloading or _cooldown > 0.0:
		return
	if block_fire_while_sprinting and _player.is_sprinting:
		return
	if _mag[current_index] <= 0:
		if get_reserve() > 0:
			start_reload()                  # auto reload when empty
		elif Input.is_action_just_pressed("fire"):
			_cooldown = 0.3
			_play(SFX.click())              # empty click (once per trigger pull, never a shot)
		return
	_shoot()


func _shoot() -> void:
	if _mag[current_index] <= 0:
		return                              # safety: can never fire with an empty magazine
	_mag[current_index] -= 1
	_cooldown = 1.0 / current.fire_rate

	var cam := get_viewport().get_camera_3d()
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := cam.project_ray_origin(center)
	var forward := cam.project_ray_normal(center)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [_player.get_rid()]

	var hit_something := false
	for i in current.pellets:
		var dir := _apply_spread(forward, current_spread)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * current.max_range, hit_mask, exclude)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		if _apply_damage(hit.collider, current.damage, hit.position):
			hit_something = true
		_spawn_impact(hit.position, hit.normal)

	if hit_something:
		hit_confirmed.emit(Vector3.ZERO)

	_bloom = minf(_bloom + current.spread_per_shot, current.spread_max_bloom)
	_player.add_recoil(deg_to_rad(current.recoil_pitch_deg), deg_to_rad(randf_range(-current.recoil_yaw_deg, current.recoil_yaw_deg)))
	_play(_fire_stream(), 0.04)
	_emit_ammo()
	shot_fired.emit()
	get_tree().call_group("enemies", "hear_noise", _player.global_position, shot_noise_radius)
	if auto_reload_when_empty and _mag[current_index] <= 0 and get_reserve() > 0:
		start_reload()


func _apply_spread(dir: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return dir
	var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var angle := randf() * TAU
	var radius := tan(deg_to_rad(degrees)) * sqrt(randf())
	return (dir + b.x * cos(angle) * radius + b.y * sin(angle) * radius).normalized()


## Works on anything with take_damage(amount, point) OR a child node named "Health".
func _apply_damage(target: Object, amount: float, point: Vector3) -> bool:
	if target.has_method("take_damage"):
		target.take_damage(amount, point)
		return true
	if target is Node:
		var h := (target as Node).get_node_or_null("Health")
		if h != null and h.has_method("take_damage"):
			h.take_damage(amount)
			return true
	return false


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.25)
	m.mesh = sphere
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos + normal * 0.02
	var t := m.create_tween()
	t.tween_property(m, "scale", Vector3.ZERO, 0.35)
	t.tween_callback(m.queue_free)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# Weapon in hand: follows the right-hand bone, so it moves with EVERY animation
# ----------------------------------------------------------------------------
func _setup_holder() -> void:
	if weapon_holder != null:
		return                              # you assigned your own holder
	var skel := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		push_warning("[WeaponManager] No Skeleton3D found under the Player. Is your character model a child of the Player?")
		return
	var bone := _find_hand_bone(skel)
	if bone == "":
		var names := []
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
		push_warning("[WeaponManager] Right hand bone not found. Set 'Hand Bone Name' on WeaponManager. Bones: " + str(names))
		return

	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	skel.add_child(attachment)
	attachment.bone_name = bone
	var holder := Node3D.new()
	holder.name = "WeaponHolder"
	attachment.add_child(holder)
	weapon_holder = holder

	# FBX skeletons are often scaled (e.g. 0.01). Cancel that so weapons keep their real size.
	await get_tree().process_frame
	var s := attachment.global_transform.basis.get_scale()
	if s.x > 0.0001 and s.y > 0.0001 and s.z > 0.0001:
		holder.scale = Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z)
	print("[WeaponManager] Weapon attached to bone '", bone, "'. Press T in game to adjust the grip.")
	_spawn_model()


func _find_hand_bone(skel: Skeleton3D) -> String:
	if hand_bone_name != "" and skel.find_bone(hand_bone_name) != -1:
		return hand_bone_name
	var wanted := ["righthand", "mixamorigrighthand", "handr", "rhand", "handright"]
	for i in skel.get_bone_count():
		var bone_name := skel.get_bone_name(i)
		var norm := ""
		for ch in bone_name.to_lower():
			if ch >= "a" and ch <= "z":
				norm += ch
		if norm in wanted:
			return bone_name
	return ""


func _apply_hold() -> void:
	if _model == null or current == null:
		return
	_model.position = current.hold_position
	_model.rotation_degrees = current.hold_rotation_deg
	_model.scale = Vector3.ONE * current.hold_scale


## T = toggle tuning | Arrows = move X/Y | PageUp/PageDown = move Z
## Shift + same keys = rotate | - / = = scale | P = save into the WeaponData file
func _unhandled_key_input(event: InputEvent) -> void:
	if not tuning_keys_enabled or not OS.is_debug_build():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_T and not k.echo:
		_tuning = not _tuning
		print("[Weapon tuning] ", "ON - arrows/PgUp/PgDn move, Shift+keys rotate, -/= scale, P saves" if _tuning else "OFF")
		return
	if not _tuning or _model == null or current == null:
		return

	var d := Vector3.ZERO
	match k.keycode:
		KEY_LEFT: d.x = -1.0
		KEY_RIGHT: d.x = 1.0
		KEY_UP: d.y = 1.0
		KEY_DOWN: d.y = -1.0
		KEY_PAGEUP: d.z = 1.0
		KEY_PAGEDOWN: d.z = -1.0
		KEY_MINUS: current.hold_scale *= 0.95
		KEY_EQUAL: current.hold_scale *= 1.05
		KEY_P:
			_save_hold()
			return
	if d != Vector3.ZERO:
		if k.shift_pressed:
			current.hold_rotation_deg += d * 2.0
		else:
			current.hold_position += d * 0.005
	_apply_hold()
	print("[Weapon tuning] %s | hold_position = Vector3(%.3f, %.3f, %.3f) | hold_rotation_deg = Vector3(%.1f, %.1f, %.1f) | hold_scale = %.2f" % [
		current.weapon_name, current.hold_position.x, current.hold_position.y, current.hold_position.z,
		current.hold_rotation_deg.x, current.hold_rotation_deg.y, current.hold_rotation_deg.z, current.hold_scale])


func _save_hold() -> void:
	if current.resource_path != "" and not current.resource_path.contains("::"):
		var err := ResourceSaver.save(current, current.resource_path)
		print("[Weapon tuning] Saved to ", current.resource_path, " -> ", error_string(err))
	else:
		print("[Weapon tuning] This weapon is not a saved .tres file. Copy the values printed above into its WeaponData.")


func _emit_ammo() -> void:
	ammo_changed.emit(get_mag(), get_reserve())


func _play(stream: AudioStream, pitch_variation := 0.0) -> void:
	if stream == null:
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


func _fire_stream() -> AudioStream:
	if current.fire_sound != null:
		return current.fire_sound
	var kind := "pistol"
	if current.pellets > 1:
		kind = "shotgun"
	elif current.automatic:
		kind = "rifle"
	return SFX.gunshot(kind)


func _default_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []

	var pistol := WeaponData.new()
	pistol.weapon_name = "Pistol"
	pistol.damage = 25.0
	pistol.fire_rate = 4.0
	pistol.automatic = false
	pistol.magazine_size = 12
	pistol.start_reserve = 60
	pistol.max_reserve = 120
	pistol.reload_time = 1.3
	pistol.spread_hip = 1.8
	pistol.spread_aim = 0.2
	pistol.recoil_pitch_deg = 0.7
	list.append(pistol)

	var rifle := WeaponData.new()
	rifle.weapon_name = "Assault Rifle"
	rifle.damage = 18.0
	rifle.fire_rate = 10.0
	rifle.automatic = true
	rifle.magazine_size = 30
	rifle.start_reserve = 120
	rifle.max_reserve = 240
	rifle.reload_time = 2.0
	rifle.spread_hip = 3.0
	rifle.spread_aim = 0.5
	rifle.spread_per_shot = 0.35
	rifle.spread_max_bloom = 3.5
	rifle.recoil_pitch_deg = 0.5
	rifle.recoil_yaw_deg = 0.25
	list.append(rifle)

	var shotgun := WeaponData.new()
	shotgun.weapon_name = "Shotgun"
	shotgun.damage = 9.0
	shotgun.pellets = 8
	shotgun.fire_rate = 1.2
	shotgun.automatic = false
	shotgun.magazine_size = 6
	shotgun.start_reserve = 30
	shotgun.max_reserve = 60
	shotgun.reload_time = 2.6
	shotgun.max_range = 60.0
	shotgun.spread_hip = 6.0
	shotgun.spread_aim = 3.5
	shotgun.spread_per_shot = 0.0
	shotgun.recoil_pitch_deg = 3.0
	shotgun.recoil_yaw_deg = 0.5
	list.append(shotgun)

	return list


# ----------------------------------------------------------------------------
# Input registration
# ----------------------------------------------------------------------------
func _register_inputs() -> void:
	_key("reload", KEY_R)
	_key("weapon_next", KEY_Q)
	for i in range(1, 6):
		_key("weapon_%d" % i, (KEY_1 + i - 1) as Key)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_joy_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_joy_button("reload", JOY_BUTTON_X)
	_joy_button("weapon_next", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_button("weapon_prev", JOY_BUTTON_LEFT_SHOULDER)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _key(action: String, key: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _joy_button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
