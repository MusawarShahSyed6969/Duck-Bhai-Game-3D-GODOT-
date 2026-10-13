extends CharacterBody3D
## GTA-style third person controller for Godot 4.x
##
## Attach to a CharacterBody3D that has a CollisionShape3D child.
## Optional children (auto-created / auto-detected if missing):
##   Model            (Node3D)  -> your character mesh/skeleton. It rotates, the body does not.
##   AnimationPlayer  (anywhere under the player)
##   CameraPivot / SpringArm3D / Camera3D  -> created in code if you don't add them.
##
## Controls (registered automatically, no Input Map setup needed):
##   Mouse / Right Stick ... look (camera orbits, character turns toward move direction)
##   W A S D / Left Stick .. move (relative to camera)
##   Shift ................. sprint
##   Ctrl / C .............. crouch (toggle)
##   Space ................. jump
##   Right Mouse / LT ...... aim (zoom, over-the-shoulder, character faces camera, strafing)
##   Mouse Wheel ........... camera distance
##   Esc ................... release mouse   |   Left Click ... capture mouse

# ----------------------------------------------------------------------------
# Exports
# ----------------------------------------------------------------------------
signal stamina_changed(current: float, maximum: float)
signal died

@export_group("Stamina")
@export var max_stamina := 100.0
@export var sprint_stamina_cost := 18.0   ## per second while sprinting
@export var jump_stamina_cost := 12.0
@export var stamina_regen := 20.0         ## per second
@export var stamina_regen_delay := 1.0    ## seconds after use before it regenerates
@export var min_stamina_to_sprint := 15.0 ## once drained you must recover to this before sprinting again

@export_group("Movement")
@export var crouch_speed := 2.0
@export var aim_speed := 2.5
@export var run_speed := 5.0
@export var sprint_speed := 8.5
@export var acceleration := 35.0          ## m/s² when input is held
@export var deceleration := 40.0          ## m/s² when input released
@export var air_control := 0.35           ## 0..1 multiplier for acceleration in the air
@export var turn_speed := 12.0            ## how fast the model turns toward move direction
@export var model_forward_offset_deg := 0.0 ## set to 180 if your model faces +Z
@export var shooter_mode := true          ## true = player ALWAYS faces where the camera looks (strafing)
@export var face_camera_turn_speed := 20.0 ## how fast the player snaps to the camera direction

@export_group("Jump")
@export var jump_velocity := 5.5
@export var coyote_time := 0.12           ## can still jump shortly after leaving a ledge
@export var jump_buffer_time := 0.12      ## jump press is remembered shortly before landing
@export var gravity_scale := 1.6

@export_group("Camera")
@export var mouse_sensitivity := 0.0025   ## radians per pixel
@export var gamepad_look_speed := 3.0     ## radians per second at full stick
@export var invert_y := false
@export var pitch_min_deg := -70.0        ## looking down limit
@export var pitch_max_deg := 40.0         ## looking up limit
@export var camera_height := 1.6          ## pivot height above the player origin
@export var camera_distance := 3.8
@export var camera_distance_min := 1.8
@export var camera_distance_max := 7.0
@export var camera_follow_speed := 18.0   ## position smoothing (higher = tighter)
@export var camera_shoulder_offset := 0.0 ## horizontal offset when not aiming
@export var camera_collision_mask := 1

@export_group("Camera - Aim")
@export var aim_distance := 1.8
@export var aim_shoulder_offset := 0.7    ## over-the-shoulder offset (right shoulder)
@export var aim_fov := 55.0

@export_group("Camera - Feel")
@export var base_fov := 75.0
@export var sprint_fov := 85.0
@export var crouch_camera_drop := 0.5
@export var camera_blend_speed := 8.0

@export_group("Animations - drag your animations into these slots")
## Optional. Leave empty and the script creates its own AnimationPlayer.
@export var animation_player: AnimationPlayer
## Optional. Node the animation tracks are relative to (default: the "Model" node).
@export var animation_root: NodePath
@export var anim_blend_time := 0.2
@export var anim_idle: Animation
@export var anim_walk: Animation          ## used while aiming and moving forward
@export var anim_run: Animation           ## run forward
@export var anim_sprint: Animation
@export var anim_run_backward: Animation
@export var anim_strafe_left: Animation
@export var anim_strafe_right: Animation
@export var anim_turn_left: Animation     ## turn in place (standing still)
@export var anim_turn_right: Animation
@export var anim_jump: Animation
@export var anim_fall: Animation
@export var anim_crouch_idle: Animation
@export var anim_crouch_walk: Animation

@export_group("Animations - turning")
@export var turn_in_place_threshold_deg := 30.0 ## how far the camera must turn before the turn anim plays
@export var idle_turn_speed := 8.0              ## body turn speed while standing still (lower = slower, more visible turn)
@export var animations_debug := true            ## prints warnings if tracks / names can't be found

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------
var is_aiming := false
var is_sprinting := false
var is_crouching := false
var is_dead := false
var stamina := 100.0
var exhausted := false
var _push := Vector3.ZERO       # shove from enemies (decays smoothly)
var _slow_mult := 1.0
var _slow_left := 0.0
var _shake_amount := 0.0
var _shake_left := 0.0
var _shake_total := 0.01
var health: Health

var _stamina_timer := 0.0
var _last_stamina_sent := -1.0

var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(-10.0)
var _target_distance := 0.0
var _coyote_timer := 0.0
var _jump_buffer := 0.0
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var _model: Node3D
var _pivot: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _anim: AnimationPlayer
var _current_anim := ""
var _clips := {}          ## key ("idle", "run", ...) -> full animation name inside the AnimationPlayer
var _turning := false
const LIB := "pc"         ## name of the animation library the script creates


# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("player")
	stamina = max_stamina
	health = get_node_or_null("Health") as Health
	if health != null:
		health.died.connect(_on_died)
	_register_inputs()
	_setup_nodes()
	if get_node_or_null("PlayerSounds") == null:
		var ps := PlayerSounds.new()
		ps.name = "PlayerSounds"
		add_child(ps)
	_cam_yaw = global_rotation.y
	_target_distance = camera_distance
	_spring.spring_length = camera_distance
	_camera.fov = base_fov
	_pivot.global_position = global_position + Vector3(0, camera_height, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_nodes() -> void:
	_model = get_node_or_null("Model") as Node3D
	_setup_animation()

	_pivot = get_node_or_null("CameraPivot") as Node3D
	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "CameraPivot"
		add_child(_pivot)

	_spring = _pivot.get_node_or_null("SpringArm3D") as SpringArm3D
	if _spring == null:
		_spring = SpringArm3D.new()
		_spring.name = "SpringArm3D"
		_pivot.add_child(_spring)

	_camera = _spring.get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_spring.add_child(_camera)

	# The pivot must NOT inherit the player's transform, otherwise the camera
	# would spin with the character.
	_pivot.top_level = true
	_spring.collision_mask = camera_collision_mask
	_spring.margin = 0.2
	_spring.add_excluded_object(get_rid())
	_camera.make_current()


func _register_inputs() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("sprint", KEY_SHIFT)
	_add_key("crouch", KEY_C)
	_add_key("crouch", KEY_CTRL)
	_add_mouse("aim", MOUSE_BUTTON_RIGHT)

	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button("crouch", JOY_BUTTON_B)


func _add_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _add_key(action: String, key: Key) -> void:
	_add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	_add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	_add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: String, button: JoyButton) -> void:
	_add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ----------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_cam_yaw -= motion.relative.x * mouse_sensitivity
		# Mouse down -> look down (negative pitch). invert_y flips it.
		_cam_pitch -= motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		_clamp_pitch()

	# Mouse capture toggle
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Scroll to zoom camera
	if event is InputEventMouseButton and event.pressed and not is_aiming:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(camera_distance - 0.3, camera_distance_min, camera_distance_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(camera_distance + 0.3, camera_distance_min, camera_distance_max)

	# Debug: press K to hurt yourself (test the health bar)
	if event is InputEventKey and event.pressed and event.keycode == KEY_K and OS.is_debug_build():
		take_damage(15.0)

	# Crouch toggle
	if event.is_action_pressed("crouch"):
		is_crouching = not is_crouching


func _clamp_pitch() -> void:
	_cam_pitch = clampf(_cam_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


# ----------------------------------------------------------------------------
# Camera (runs every rendered frame for smoothness)
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Gamepad right stick look
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_cam_yaw -= look.x * gamepad_look_speed * delta
		_cam_pitch -= look.y * gamepad_look_speed * delta * (-1.0 if invert_y else 1.0)
		_clamp_pitch()

	is_aiming = Input.is_action_pressed("aim") and not is_dead

	# Follow the player (smoothed)
	var height := camera_height - (crouch_camera_drop if is_crouching else 0.0)
	var target_pos := global_position + Vector3(0, height, 0)
	var follow_weight := 1.0 - exp(-camera_follow_speed * delta)
	_pivot.global_position = _pivot.global_position.lerp(target_pos, follow_weight)

	# Orbit rotation
	_pivot.global_rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)

	# Blend between normal and aim camera
	var blend := 1.0 - exp(-camera_blend_speed * delta)
	var want_distance := aim_distance if is_aiming else camera_distance
	var want_offset := aim_shoulder_offset if is_aiming else camera_shoulder_offset
	var want_fov := base_fov
	if is_aiming:
		want_fov = aim_fov
	elif is_sprinting:
		want_fov = sprint_fov

	_spring.spring_length = lerpf(_spring.spring_length, want_distance, blend)
	_camera.h_offset = lerpf(_camera.h_offset, want_offset, blend)
	_camera.fov = lerpf(_camera.fov, want_fov, blend)

	# Camera shake (boss slams etc.)
	if _shake_left > 0.0:
		_shake_left -= delta
		var s := _shake_amount * clampf(_shake_left / _shake_total, 0.0, 1.0)
		_camera.v_offset = randf_range(-s, s)
		_camera.rotation.z = randf_range(-s, s) * 0.25
	else:
		_camera.v_offset = 0.0
		_camera.rotation.z = 0.0


# ----------------------------------------------------------------------------
# Movement
# ----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3(0.0, velocity.y - _gravity * gravity_scale * delta, 0.0)
		move_and_slide()
		return

	var on_floor := is_on_floor()

	# Gravity
	if not on_floor:
		velocity.y -= _gravity * gravity_scale * delta

	# Coyote time + jump buffering
	_coyote_timer = coyote_time if on_floor else _coyote_timer - delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer -= delta

	if _jump_buffer > 0.0 and _coyote_timer > 0.0 and stamina >= jump_stamina_cost:
		if is_crouching:
			is_crouching = false # jumping stands you up
		velocity.y = jump_velocity
		_use_stamina(jump_stamina_cost)
		_jump_buffer = 0.0
		_coyote_timer = 0.0

	# Input relative to the camera's yaw (so W always goes "into the screen")
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := Basis(Vector3.UP, _cam_yaw)
	var move_dir := cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	var has_input := input_dir.length() > 0.1

	# Pick speed
	is_sprinting = Input.is_action_pressed("sprint") and has_input and not is_aiming and not is_crouching and not exhausted and stamina > 0.0
	_update_stamina(delta)
	var speed := run_speed
	if is_crouching:
		speed = crouch_speed
	elif is_aiming:
		speed = aim_speed
	elif is_sprinting:
		speed = sprint_speed
	speed *= clampf(input_dir.length(), 0.0, 1.0) # analog sticks walk/run naturally
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_mult = 1.0
	speed *= _slow_mult

	# Accelerate horizontally
	var target_vel := move_dir.normalized() * speed if has_input else Vector3.ZERO
	var accel := acceleration if has_input else deceleration
	if not on_floor:
		accel *= air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_vel, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Enemy shove: added for this move only, then decays
	velocity.x += _push.x
	velocity.z += _push.z
	move_and_slide()
	velocity.x -= _push.x
	velocity.z -= _push.z
	_push = _push.move_toward(Vector3.ZERO, 18.0 * delta)

	_update_model_rotation(move_dir, has_input, delta)
	_update_animation(on_floor, has_input)


func _update_model_rotation(move_dir: Vector3, has_input: bool, delta: float) -> void:
	var rot_node: Node3D = _model if _model != null else self
	var target_angle := rot_node.rotation.y
	var offset := deg_to_rad(model_forward_offset_deg)

	var speed := turn_speed
	if shooter_mode or is_aiming:
		# Shooter style: body always turns to face where the camera looks,
		# even when standing still. Moving the mouse rotates the player.
		target_angle = _cam_yaw + offset
		speed = face_camera_turn_speed if (has_input or not is_on_floor()) else idle_turn_speed
	elif has_input:
		# Classic TPP: face the direction we're running in
		target_angle = atan2(-move_dir.x, -move_dir.z) + offset
	else:
		return

	var weight := 1.0 - exp(-speed * delta)
	rot_node.rotation.y = lerp_angle(rot_node.rotation.y, target_angle, weight)


# ----------------------------------------------------------------------------
# Animation - fully automatic. Just drag animations into the Inspector slots.
# ----------------------------------------------------------------------------
func _setup_animation() -> void:
	var created := false
	_anim = animation_player
	if _anim == null:
		_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		add_child(_anim)
		created = true

	# Tracks inside an animation are paths relative to the player's root_node.
	if not animation_root.is_empty():
		_anim.root_node = _anim.get_path_to(get_node(animation_root))
	elif created:
		var root: Node = _model if _model != null else self
		_anim.root_node = _anim.get_path_to(root)

	# Build a library from the animations dragged into the Inspector.
	var slots := {
		"idle": anim_idle, "walk": anim_walk, "run": anim_run, "sprint": anim_sprint,
		"run_backward": anim_run_backward, "strafe_left": anim_strafe_left,
		"strafe_right": anim_strafe_right, "turn_left": anim_turn_left,
		"turn_right": anim_turn_right, "jump": anim_jump, "fall": anim_fall,
		"crouch_idle": anim_crouch_idle, "crouch_walk": anim_crouch_walk,
	}
	var lib := AnimationLibrary.new()
	for key in slots:
		var a: Animation = slots[key]
		if a == null:
			continue
		lib.add_animation(key, a.duplicate() as Animation)
		_clips[key] = LIB + "/" + key
	if lib.get_animation_list().size() > 0:
		if _anim.has_animation_library(LIB):
			_anim.remove_animation_library(LIB)
		_anim.add_animation_library(LIB, lib)

	# Fallback: for empty slots, look for a matching name in an existing
	# AnimationPlayer (e.g. animations that came with an imported .glb).
	for key in slots:
		if _clips.has(key):
			continue
		var found := _find_existing_animation(key)
		if found != "":
			_clips[key] = found

	# Fix track paths so animations made for a different skeleton hierarchy
	# (e.g. Mixamo "AvatarRoot/Skeleton3D:...") work on YOUR model.
	var rig_root := _anim.get_node_or_null(_anim.root_node)
	if rig_root != null:
		for key in _clips:
			var clip := _anim.get_animation(_clips[key])
			if clip != null:
				_remap_tracks(String(key), clip, rig_root)

	# Locomotion animations must loop, otherwise they freeze on the last frame.
	for key in _clips:
		var anim := _anim.get_animation(_clips[key])
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_NONE if key == "jump" else Animation.LOOP_LINEAR

	_anim.active = true
	_anim.speed_scale = 1.0
	if animations_debug:
		print("[Player] AnimationPlayer: ", _anim.get_path(), " | root_node: ", _anim.root_node, " | active: ", _anim.active)
		print("[Player] Clips I can play: ", _clips)
		print("[Player] All animations inside that player: ", _anim.get_animation_list())
		_debug_check_animations()


## Rewrites animation track paths so they point at the Skeleton3D that really
## exists under `root`. Tracks that can't be matched are removed (no more
## "couldn't resolve track" warnings).
func _remap_tracks(key: String, anim: Animation, root: Node) -> void:
	var skeleton: Skeleton3D = null
	if root is Skeleton3D:
		skeleton = root as Skeleton3D
	else:
		skeleton = root.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton == null:
			for n in root.find_children("*", "Skeleton3D", true, false):
				skeleton = n as Skeleton3D
				break
	var skel_path := ""
	if skeleton != null:
		skel_path = str(root.get_path_to(skeleton))

	var remapped := 0
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var node_part := path.get_concatenated_names()
		var sub := path.get_concatenated_subnames()
		var node_ok := node_part == "" or root.get_node_or_null(NodePath(node_part)) != null
		var is_skeleton_track := skeleton != null and sub != "" and (node_part.ends_with("Skeleton3D") or node_part.contains("Skeleton"))

		if is_skeleton_track:
			var bone := _resolve_bone(skeleton, sub)
			if bone == "":
				anim.remove_track(i)
				removed += 1
				continue
			var new_path := skel_path + ":" + bone
			if new_path != str(path):
				anim.track_set_path(i, NodePath(new_path))
				remapped += 1
		elif not node_ok:
			anim.remove_track(i)
			removed += 1

	if animations_debug and (remapped > 0 or removed > 0):
		print("[Player] Animation '%s': remapped %d track(s), removed %d unmatched track(s)." % [key, remapped, removed])
	if animations_debug and skeleton == null:
		push_warning("[Player] No Skeleton3D found under the animation root. Is your character model a child of the Player?")


func _resolve_bone(skel: Skeleton3D, bone: String) -> String:
	if skel.find_bone(bone) != -1:
		return bone
	var stripped := bone
	for p in ["mixamorig:", "mixamorig_", "mixamorig"]:
		if bone.begins_with(p):
			stripped = bone.substr(p.length())
			break
	for cand in [stripped, "mixamorig:" + stripped, "mixamorig_" + stripped, "mixamorig" + stripped]:
		if skel.find_bone(cand) != -1:
			return cand
	return ""


func _find_existing_animation(key: String) -> String:
	for full_name in _anim.get_animation_list():
		var short := String(full_name).to_lower()
		short = short.get_slice("|", short.get_slice_count("|") - 1)
		short = short.get_slice("/", short.get_slice_count("/") - 1)
		short = short.replace(" ", "_").replace("-", "_")
		if short == key:
			return full_name
	return ""


func _debug_check_animations() -> void:
	if _clips.is_empty():
		push_warning("[Player] No animations assigned. Drag animations into the 'Animations' slots in the Inspector.")
		return
	var root := _anim.get_node_or_null(_anim.root_node)
	if root == null:
		push_warning("[Player] AnimationPlayer root_node is invalid: " + str(_anim.root_node))
		return
	for key in _clips:
		var anim := _anim.get_animation(_clips[key])
		var missing := 0
		for i in anim.get_track_count():
			var path := anim.track_get_path(i)
			if root.get_node_or_null(NodePath(path.get_concatenated_names())) == null:
				missing += 1
		if missing > 0:
			push_warning("[Player] Animation '%s': %d/%d tracks can't find their node under root '%s'. Set 'Animation Root' in the Inspector to the node that contains your skeleton/mesh." % [key, missing, anim.get_track_count(), root.name])


## Returns the first key from the list that has an animation assigned.
func _pick(keys: Array) -> String:
	for k in keys:
		if _clips.has(k):
			return k
	return ""


func _update_animation(on_floor: bool, has_input: bool) -> void:
	if _anim == null or _clips.is_empty():
		return

	var rot_node: Node3D = _model if _model != null else self
	var offset := deg_to_rad(model_forward_offset_deg)
	var next := ""

	if not on_floor:
		next = _pick(["jump", "idle"]) if velocity.y > 0.0 else _pick(["fall", "jump", "idle"])
	else:
		var hvel := Vector3(velocity.x, 0.0, velocity.z)
		if hvel.length() > 0.4:
			_turning = false
			# Movement direction relative to where the body is facing
			var facing := rot_node.global_rotation.y - offset
			var local := Basis(Vector3.UP, facing).inverse() * hvel

			if abs(local.x) > abs(local.z) * 1.3:
				# Sideways -> strafe
				if local.x > 0.0:
					next = _pick(["strafe_right", "run"])
				else:
					next = _pick(["strafe_left", "run"])
			elif local.z > 0.0:
				# Backwards
				next = _pick(["crouch_walk", "run_backward", "run"]) if is_crouching else _pick(["run_backward", "run"])
			else:
				# Forwards
				if is_crouching:
					next = _pick(["crouch_walk", "walk", "run"])
				elif is_sprinting:
					next = _pick(["sprint", "run"])
				elif is_aiming:
					next = _pick(["walk", "run"])
				else:
					next = _pick(["run", "walk"])
		else:
			# Standing still
			if is_crouching:
				next = _pick(["crouch_idle", "idle"])
			else:
				var diff := angle_difference(rot_node.rotation.y, _cam_yaw + offset)
				if abs(diff) > deg_to_rad(turn_in_place_threshold_deg):
					_turning = true
				elif abs(diff) < deg_to_rad(4.0):
					_turning = false
				if _turning and (shooter_mode or is_aiming):
					# Positive angle difference = body must rotate counter-clockwise = turn left
					next = _pick(["turn_left", "idle"]) if diff > 0.0 else _pick(["turn_right", "idle"])
				else:
					next = _pick(["idle"])

	if next == "":
		return
	var full: String = _clips[next]
	var finished := not _anim.is_playing() and next != "jump"
	if full != _current_anim or finished:
		_current_anim = full
		_anim.play(full, anim_blend_time)
		if animations_debug:
			print("[Player] Playing '", full, "' | is_playing: ", _anim.is_playing(), " | length: ", _anim.get_animation(full).length)


# ----------------------------------------------------------------------------
# Stamina, health, recoil
# ----------------------------------------------------------------------------
func _update_stamina(delta: float) -> void:
	if is_sprinting:
		stamina = maxf(stamina - sprint_stamina_cost * delta, 0.0)
		_stamina_timer = stamina_regen_delay
		if stamina <= 0.0:
			exhausted = true
	else:
		_stamina_timer -= delta
		if _stamina_timer <= 0.0:
			stamina = minf(stamina + stamina_regen * delta, max_stamina)
	if exhausted and stamina >= min_stamina_to_sprint:
		exhausted = false
	if not is_equal_approx(stamina, _last_stamina_sent):
		_last_stamina_sent = stamina
		stamina_changed.emit(stamina, max_stamina)


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_timer = stamina_regen_delay
	_last_stamina_sent = stamina
	stamina_changed.emit(stamina, max_stamina)


## Call this from enemies, explosions, fall damage... e.g. player.take_damage(20)
func take_damage(amount: float, _point: Vector3 = Vector3.ZERO) -> void:
	if health != null:
		health.take_damage(amount)


## Called by the WeaponManager on every shot (radians).
func add_recoil(pitch: float, yaw: float) -> void:
	_cam_pitch += pitch
	_cam_yaw += yaw
	_clamp_pitch()


func _on_died() -> void:
	is_dead = true
	is_aiming = false
	is_sprinting = false
	died.emit()


## Shove the player (enemy hits, shockwaves). Horizontal part slides, Y part launches up.
func apply_push(v: Vector3) -> void:
	_push.x = clampf(_push.x + v.x, -18.0, 18.0)
	_push.z = clampf(_push.z + v.z, -18.0, 18.0)
	if v.y > 0.0:
		velocity.y = maxf(velocity.y, v.y)


## Slow the player down (toxic pools, spit). mult 0.5 = half speed.
func apply_slow(mult: float, duration: float) -> void:
	_slow_mult = minf(_slow_mult, mult)
	_slow_left = maxf(_slow_left, duration)


func add_shake(amount: float, duration: float = 0.45) -> void:
	_shake_amount = maxf(_shake_amount * (_shake_left / _shake_total), amount)
	_shake_left = duration
	_shake_total = duration
