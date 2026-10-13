class_name Zombie
extends CharacterBody3D
## Customizable zombie enemy. Every behaviour is an Inspector setting, so one
## script gives you walkers, runners, tanks, spitters... (BossZombie extends this).
##
## Scene layout:
##   Zombie (CharacterBody3D)  <- this script
##   |- CollisionShape3D       (capsule, bottom at y = 0)
##   |- Model (Node3D)         <- your mesh / imported model (+ AnimationPlayer) goes in here
##
## The player's bullets work automatically (take_damage), and the zombie hurts the
## player through player.take_damage().

signal health_changed(current: float, maximum: float)
signal died(who: Node3D)

enum State { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD }
enum AttackMode { MELEE, RANGED }

@export var enemy_name := "Zombie"

@export_group("Health")
@export var max_health := 60.0
@export_range(0.0, 1.0) var stagger_chance := 1.0  ## chance that a hit interrupts the zombie (0 = never)
@export var stagger_time := 0.25
@export var corpse_time := 6.0                     ## seconds before the body disappears
@export var show_health_bar := true
@export var health_bar_height := 2.3
@export var health_bar_width := 1.0

@export_group("Movement")
@export var walk_speed := 1.4                      ## patrol speed
@export var chase_speed := 2.4
@export var acceleration := 12.0
@export var turn_speed := 8.0
@export var model_forward_offset_deg := 0.0        ## set 180 if your model faces +Z
@export var use_navigation := false                ## needs a NavigationRegion3D with a baked NavMesh

@export_group("Awareness")
@export var always_aggro := false                  ## chase the player from the start (good for testing)
@export var detect_range := 15.0
@export var view_angle_deg := 360.0                ## 360 = notices you from every direction
@export var require_line_of_sight := false         ## walls block detection
@export var lose_range := 40.0                     ## gives up chasing beyond this (0 = never)
@export var hears_noise := true                    ## gunshots alert the zombie

@export_group("Patrol")
@export var patrol_root: Node3D                    ## a Node3D whose Marker3D children are the path points
@export var patrol_ping_pong := false              ## false = loop, true = walk back and forth
@export var patrol_wait := 1.5
@export var patrol_reach_distance := 0.8

@export_group("Attack")
@export var attack_mode: AttackMode = AttackMode.MELEE
@export var attack_damage := 10.0
@export var attack_range := 1.7                    ## melee reach, or shooting distance for ranged
@export var attack_cooldown := 1.2
@export var attack_windup := 0.35                  ## delay before the hit lands (match your animation)
@export var attack_recover := 0.25                ## only used when there is no attack animation
@export var attack_anim_speed := 1.0               ## 1 = normal, 1.5 = swing 50% faster. Animation always plays to the end
@export var hurt_interrupts_attack := false        ## true = getting shot cancels a swing in progress
@export var knockback := 3.0

@export_group("Ranged attack (attack mode = Ranged)")
@export var projectile_speed := 14.0
@export var projectile_color := Color(0.4, 1.0, 0.2)
@export var projectile_height := 1.4

@export_group("Animations - DRAG & DROP your .anim files here")
@export var clip_idle: Animation
@export var clip_walk: Animation
@export var clip_run: Animation
@export var clip_attack: Animation
@export var clip_hurt: Animation
@export var clip_death: Animation
@export var clip_special: Animation                ## used by the boss (ground slam)

@export_group("Animations - settings")
@export var animation_player: AnimationPlayer      ## optional. Empty = auto-find, or one is created for you
@export var run_anim_speed := 3.5                  ## above this speed the run animation plays
@export var debug_animations := true               ## prints which animations were found / missing

@export_group("Animations - by NAME (only used for empty slots above)")
@export var anim_idle := "idle"
@export var anim_walk := "walk"
@export var anim_run := "run"
@export var anim_attack := "attack"
@export var anim_hurt := "hurt"
@export var anim_death := "death"
@export var anim_special := "slam"                 ## used by the boss

@export_group("Sounds (empty = built-in placeholder)")
@export var voice_pitch := 1.0                     ## <1 deeper, >1 higher
@export var groan_sound: AudioStream
@export var attack_sound: AudioStream
@export var hurt_sound: AudioStream
@export var death_sound: AudioStream

# Public state (HUD / boss use these)
var health := 0.0
var state: State = State.IDLE
var is_dead := false
var aggro := false

# Multipliers (the boss changes these when it enrages)
var speed_mult := 1.0
var damage_mult := 1.0
var cooldown_mult := 1.0

var _player: Node3D
var _yaw := 0.0
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _cooldown := 0.0
var _attacking := false
var _windup_left := 0.0
var _recover_left := 0.0
var _attack_left := 0.0
var _stagger_left := 0.0
var _patrol: Array[Vector3] = []
var _patrol_i := 0
var _patrol_dir := 1
var _patrol_wait_left := 0.0
var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _clips := {}
var _current_anim := ""
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _base_overlay: Material = null     ## aura that stays on the meshes (boss phases use it)
var _visual: Node3D
var _visual_rest := Vector3.ZERO
var _lunge_tween: Tween
var _bar_root: Node3D
var _bar_fg: MeshInstance3D
var _fg_quad: QuadMesh
var _voice: AudioStreamPlayer3D
var _groan_timer := 0.0
static var _debug_printed := false


# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_yaw = rotation.y - deg_to_rad(model_forward_offset_deg)

	_visual = get_node_or_null("Model") as Node3D
	if _visual == null:
		_visual = self
	_visual_rest = _visual.position

	for m in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m as MeshInstance3D)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.55)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_setup_animation()
	_build_patrol()

	if use_navigation:
		_agent = NavigationAgent3D.new()
		_agent.path_desired_distance = 0.7
		_agent.target_desired_distance = 0.7
		add_child(_agent)

	_build_health_bar()

	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 35.0
	_voice.unit_size = 6.0
	_voice.pitch_scale = voice_pitch
	add_child(_voice)
	_groan_timer = randf_range(2.0, 6.0)

	_nearest_patrol()
	state = State.PATROL if _patrol.size() > 0 else State.IDLE
	if always_aggro:
		_become_aggro()


func _build_patrol() -> void:
	_patrol.clear()
	if patrol_root == null:
		return
	for c in patrol_root.get_children():
		if c is Node3D:
			_patrol.append((c as Node3D).global_position)


func _nearest_patrol() -> void:
	var best := INF
	for i in _patrol.size():
		var d := global_position.distance_to(_patrol[i])
		if d < best:
			best = d
			_patrol_i = i


# ----------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var player := _get_player()
	if player == null or _player_is_dead():
		if aggro:
			_lose_player()
		_move(Vector3.ZERO, 0.0, delta)
		move_and_slide()
		_update_animation()
		return

	if _special(delta):
		move_and_slide()
		return

	match state:
		State.IDLE:
			_state_idle(delta)
		State.PATROL:
			_state_patrol(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)

	move_and_slide()
	_update_animation()
	_update_groan(delta)


## Slots the Inspector exposes (drag & drop). The boss adds more.
func _slot_clips() -> Dictionary:
	var d := {
		"idle": clip_idle, "walk": clip_walk, "run": clip_run, "attack": clip_attack,
		"hurt": clip_hurt, "death": clip_death, "special": clip_special,
	}
	d.merge(_extra_clips())
	return d


## Override: extra drag & drop slots (the boss uses this).
func _extra_clips() -> Dictionary:
	return {}


## Override: extra animation keys -> names (the boss uses this).
func _extra_anim_names() -> Dictionary:
	return {}


## Override in the boss. Return true to take over this frame.
func _special(_delta: float) -> bool:
	return false


## Override: runs after every hit.
func _after_damage(_amount: float) -> void:
	pass


## Override: runs when the zombie dies.
func _on_death() -> void:
	pass


# ----------------------------------------------------------------------------
# States
# ----------------------------------------------------------------------------
func _state_idle(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	_try_notice()


func _state_patrol(delta: float) -> void:
	if _try_notice():
		return
	if _patrol.size() == 0:
		state = State.IDLE
		return
	if _patrol_wait_left > 0.0:
		_patrol_wait_left -= delta
		_move(Vector3.ZERO, 0.0, delta)
		return
	var target := _patrol[_patrol_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() <= patrol_reach_distance:
		_advance_patrol()
		_patrol_wait_left = patrol_wait
		return
	var dir := _path_dir(target)
	_face(dir, delta)
	_move(dir, walk_speed, delta)


func _advance_patrol() -> void:
	var count := _patrol.size()
	if count <= 1:
		return
	if patrol_ping_pong:
		_patrol_i += _patrol_dir
		if _patrol_i >= count:
			_patrol_dir = -1
			_patrol_i = count - 2
		elif _patrol_i < 0:
			_patrol_dir = 1
			_patrol_i = 1
	else:
		_patrol_i = (_patrol_i + 1) % count


func _state_chase(delta: float) -> void:
	var dist := _flat_to_player().length()
	if not always_aggro and lose_range > 0.0 and dist > lose_range:
		_lose_player()
		return
	if dist <= attack_range and (attack_mode == AttackMode.MELEE or _has_clear_shot()):
		state = State.ATTACK
		return
	var dir := _path_dir(_player.global_position)
	_face(dir, delta)
	_move(dir, chase_speed * speed_mult, delta)


func _state_attack(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	_face(_flat_to_player(), delta)

	if _attacking:
		# The hit lands after "windup"; the attack only ends when the WHOLE animation has played.
		_attack_left -= delta
		if _windup_left > 0.0:
			_windup_left -= delta
			if _windup_left <= 0.0:
				_deliver_attack()
		if _attack_left <= 0.0 and _windup_left <= 0.0:
			_attacking = false
		return

	var dist := _flat_to_player().length()
	if dist > attack_range * 1.25:
		state = State.CHASE
		return
	if _cooldown <= 0.0:
		_start_attack()


func _state_stagger(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	_stagger_left -= delta
	if _stagger_left <= 0.0:
		state = State.CHASE if aggro else State.IDLE


# ----------------------------------------------------------------------------
# Attacking
# ----------------------------------------------------------------------------
func _start_attack() -> void:
	_attacking = true
	_windup_left = maxf(attack_windup, 0.01)
	_cooldown = attack_cooldown * cooldown_mult
	_play_anim("attack", true)
	_attack_left = attack_windup + attack_recover
	var clip_key := _pick_clip("attack")
	if clip_key != "" and _anim != null:
		var spd := maxf(attack_anim_speed, 0.1)
		var clip_len := _anim.get_animation(_clips[clip_key]).length / spd
		_attack_left = maxf(clip_len, attack_windup)          # stay in the attack until the clip ends
		_cooldown = maxf(_cooldown, clip_len + 0.15)           # next swing can't start before this one is done
		_anim.speed_scale = spd
	_play_voice(attack_sound, SFX.zombie_attack())
	if not _clips.has("attack"):
		_lunge()


func _deliver_attack() -> void:
	if attack_mode == AttackMode.RANGED:
		_fire_projectile()
		return
	var to := _flat_to_player()
	if to.length() <= attack_range * 1.35 and _forward().dot(to.normalized()) > 0.25:
		_hurt_player(attack_damage * damage_mult, knockback)


func _hurt_player(amount: float, kb: float) -> void:
	if _player == null:
		return
	if _player.has_method("take_damage"):
		_player.call("take_damage", amount, global_position)
	if kb > 0.0:
		var away := _player.global_position - global_position
		away.y = 0.0
		away = away.normalized()
		if _player.has_method("apply_push"):
			_player.call("apply_push", away * kb + Vector3.UP * kb * 0.25)
		elif _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity += away * kb


func _fire_projectile() -> void:
	var origin := global_position + Vector3.UP * projectile_height + _forward() * 0.6
	var target := _player.global_position + Vector3.UP * 1.1
	var p := ZombieProjectile.new()
	p.damage = attack_damage * damage_mult
	p.velocity = (target - origin).normalized() * projectile_speed
	p.color = projectile_color
	p.shooter = self
	get_tree().current_scene.add_child(p)
	p.global_position = origin


func _lunge() -> void:
	if _visual == self:
		return
	if _lunge_tween != null:
		_lunge_tween.kill()
	_visual.position = _visual_rest
	var dir := Basis(Vector3.UP, -deg_to_rad(model_forward_offset_deg)) * Vector3(0, 0, -1)
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(_visual, "position", _visual_rest + dir * 0.45, maxf(attack_windup, 0.05)).set_ease(Tween.EASE_IN)
	_lunge_tween.tween_property(_visual, "position", _visual_rest, 0.2)


# ----------------------------------------------------------------------------
# Taking damage / dying  (the player's weapons call this automatically)
# ----------------------------------------------------------------------------
func take_damage(amount: float, _point: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_update_bar(true)
	_flash()
	if not aggro:
		_become_aggro()
	_after_damage(amount)
	if health <= 0.0:
		_die()
		return
	_play_voice(hurt_sound, SFX.zombie_hurt())
	if state != State.STAGGER and stagger_time > 0.0 and randf() < stagger_chance and (hurt_interrupts_attack or not _attacking):
		_attacking = false
		state = State.STAGGER
		_stagger_left = stagger_time
		_play_anim("hurt", true)


## Called by the player's weapon when a shot is fired nearby.
func hear_noise(pos: Vector3, radius: float) -> void:
	if is_dead or aggro or not hears_noise:
		return
	if global_position.distance_to(pos) <= radius:
		_become_aggro()


func _die() -> void:
	is_dead = true
	state = State.DEAD
	aggro = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	if _bar_root != null:
		_bar_root.visible = false
	_play_voice(death_sound, SFX.zombie_death())
	_on_death()
	died.emit(self)

	if _clips.has("death"):
		_play_anim("death", true)
	else:
		var t := create_tween()
		t.tween_property(_visual, "rotation:x", -PI / 2.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	set_physics_process(false)
	await get_tree().create_timer(corpse_time).timeout
	queue_free()


func _flash() -> void:
	for m in _meshes:
		m.material_overlay = _flash_mat
	await get_tree().create_timer(0.08).timeout
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _base_overlay


# ----------------------------------------------------------------------------
# Awareness
# ----------------------------------------------------------------------------
func _try_notice() -> bool:
	if _player != null and _can_notice():
		_become_aggro()
		return true
	return false


func _can_notice() -> bool:
	if always_aggro:
		return true
	var to := _flat_to_player()
	var dist := to.length()
	if dist > detect_range:
		return false
	if view_angle_deg < 359.0 and dist > 2.5:
		if rad_to_deg(_forward().angle_to(to)) > view_angle_deg * 0.5:
			return false
	if require_line_of_sight:
		return _ray_clear(global_position + Vector3.UP * 1.5, _player.global_position + Vector3.UP * 1.2)
	return true


func _become_aggro() -> void:
	if is_dead:
		return
	aggro = true
	if state == State.IDLE or state == State.PATROL:
		state = State.CHASE
		_play_voice(groan_sound, SFX.zombie_groan())


func _lose_player() -> void:
	aggro = false
	_attacking = false
	_nearest_patrol()
	state = State.PATROL if _patrol.size() > 0 else State.IDLE


func _has_clear_shot() -> bool:
	return _ray_clear(global_position + Vector3.UP * projectile_height, _player.global_position + Vector3.UP * 1.1)


func _ray_clear(from: Vector3, to: Vector3) -> bool:
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == _player


# ----------------------------------------------------------------------------
# Movement helpers
# ----------------------------------------------------------------------------
func _get_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _player_is_dead() -> bool:
	return _player != null and bool(_player.get("is_dead"))


func _flat_to_player() -> Vector3:
	var d := _player.global_position - global_position
	d.y = 0.0
	return d


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _move(dir: Vector3, speed: float, delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * speed, acceleration * delta)
	velocity.x = h.x
	velocity.z = h.z


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target := atan2(-dir.x, -dir.z)
	_yaw = lerp_angle(_yaw, target, 1.0 - exp(-turn_speed * delta))
	rotation.y = _yaw + deg_to_rad(model_forward_offset_deg)


func _path_dir(target: Vector3) -> Vector3:
	if _agent != null and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0:
		_agent.target_position = target
		var next := _agent.get_next_path_position() - global_position
		next.y = 0.0
		if next.length() > 0.05:
			return next.normalized()
	var d := target - global_position
	d.y = 0.0
	return d.normalized()


# ----------------------------------------------------------------------------
# Animation (optional) - works on any AnimationPlayer, names matched loosely
# ----------------------------------------------------------------------------
func _setup_animation() -> void:
	_anim = animation_player
	if _anim == null:
		for n in find_children("*", "AnimationPlayer", true, false):
			_anim = n as AnimationPlayer
			break

	# Animations dragged into the Inspector slots
	var slots := _slot_clips()
	var assigned := {}
	for key in slots:
		if slots[key] != null:
			assigned[key] = slots[key]

	if _anim == null:
		if assigned.is_empty():
			return
		# No AnimationPlayer anywhere: create one that points at the node holding the skeleton
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		add_child(_anim)
		var skel_node := find_child("Skeleton3D", true, false)
		var root_node: Node = skel_node.get_parent() if skel_node != null else _visual
		_anim.root_node = _anim.get_path_to(root_node)

	if not assigned.is_empty():
		var lib := AnimationLibrary.new()
		for key in assigned:
			var copy := (assigned[key] as Animation).duplicate() as Animation
			lib.add_animation(String(key), copy)
			_clips[key] = "zc/" + String(key)
		if _anim.has_animation_library("zc"):
			_anim.remove_animation_library("zc")
		_anim.add_animation_library("zc", lib)
		for key in _clips:
			var ca := _anim.get_animation(_clips[key])
			if ca != null:
				ca.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "walk", "run"] else Animation.LOOP_NONE
	_anim.active = true

	var wanted := {
		"idle": anim_idle, "walk": anim_walk, "run": anim_run, "attack": anim_attack,
		"hurt": anim_hurt, "death": anim_death, "special": anim_special,
	}
	wanted.merge(_extra_anim_names())
	for key in wanted:
		if _clips.has(key):
			continue
		var full := _find_anim(String(wanted[key]))
		if full == "":
			continue
		_clips[key] = full
		var a := _anim.get_animation(full)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "walk", "run"] else Animation.LOOP_NONE
	# Fallback: for anything still missing, look for a name containing a keyword
	var keywords := {
		"idle": ["idle", "stand"], "walk": ["walk", "shamble"], "run": ["run", "sprint"],
		"attack": ["attack", "punch", "bite", "claw", "swipe", "hit"],
		"hurt": ["hurt", "damage", "react"], "death": ["death", "die", "dead"],
		"special": ["slam", "smash", "special"],
	}
	for key in keywords:
		if _clips.has(key):
			continue
		for n in _anim.get_animation_list():
			var low := String(n).to_lower()
			var hit := false
			for kw in keywords[key]:
				if low.contains(kw):
					hit = true
			if hit:
				_clips[key] = String(n)
				var fa := _anim.get_animation(String(n))
				if fa != null:
					fa.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "walk", "run"] else Animation.LOOP_NONE
				break

	# Fix track paths so animations made for another skeleton layout (e.g. Mixamo's
	# "AvatarRoot/Skeleton3D:...") work on THIS model.
	var rig_root := _anim.get_node_or_null(_anim.root_node)
	if rig_root != null:
		for key in _clips:
			var clip := _anim.get_animation(_clips[key])
			if clip != null:
				_remap_tracks(String(key), clip, rig_root)
	if debug_animations and not _debug_printed:
		_debug_printed = true
		var missing := []
		for key in wanted:
			if not _clips.has(key):
				missing.append("%s (looked for '%s')" % [key, wanted[key]])
		print("[Zombie] AnimationPlayer: ", _anim.get_path(), " | root_node: ", _anim.root_node)
		print("[Zombie] FOUND: ", _clips)
		print("[Zombie] NOT FOUND: ", missing)
		print("[Zombie] All names in that AnimationPlayer: ", _anim.get_animation_list())
	if _clips.is_empty():
		push_warning("[Zombie] No matching animations. Names in the AnimationPlayer: " + str(_anim.get_animation_list()) + " - set the 'Anim ...' names in the Inspector.")


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
	if skeleton == null:
		return
	var skel_path := str(root.get_path_to(skeleton))
	var remapped := 0
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var node_part := path.get_concatenated_names()
		var sub := path.get_concatenated_subnames()
		var is_skeleton_track := sub != "" and (node_part.ends_with("Skeleton3D") or node_part.contains("Skeleton"))
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
		elif node_part != "" and root.get_node_or_null(NodePath(node_part)) == null:
			anim.remove_track(i)
			removed += 1
	if debug_animations and (remapped > 0 or removed > 0):
		print("[Zombie] '%s': fixed %d track path(s), removed %d unmatched track(s)." % [key, remapped, removed])


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


func _find_anim(wanted: String) -> String:
	var w := wanted.to_lower().strip_edges()
	if w == "":
		return ""
	var names := _anim.get_animation_list()
	for n in names:
		if String(n) == wanted:
			return String(n)
	for n in names:
		if _short_name(String(n)) == w:
			return String(n)
	for n in names:
		if _short_name(String(n)).contains(w):
			return String(n)
	return ""


func _short_name(full: String) -> String:
	var s := full.to_lower()
	s = s.get_slice("|", s.get_slice_count("|") - 1)
	s = s.get_slice("/", s.get_slice_count("/") - 1)
	return s.replace(" ", "_").replace("-", "_")


func _pick_clip(key: String) -> String:
	var chains := {
		"idle": ["idle"], "walk": ["walk", "run", "idle"], "run": ["run", "walk", "idle"],
		"attack": ["attack"], "hurt": ["hurt"], "death": ["death"], "special": ["special", "attack"],
	}
	for k in chains.get(key, [key]):
		if _clips.has(k):
			return k
	return ""


func _play_anim(key: String, force := false, blend := 0.15) -> void:
	if _anim == null:
		return
	var k := _pick_clip(key)
	if k == "":
		return
	var full: String = _clips[k]
	if not force and full == _current_anim and _anim.is_playing():
		return
	_anim.speed_scale = 1.0
	_current_anim = full
	_anim.play(full, blend)


func _update_animation() -> void:
	if _anim == null or _attacking or state == State.STAGGER:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var key := "idle"
	if speed > 0.3:
		key = "run" if speed > run_anim_speed else "walk"
	_play_anim(key)


# ----------------------------------------------------------------------------
# Sound
# ----------------------------------------------------------------------------
func _play_voice(custom: AudioStream, fallback: AudioStream) -> void:
	if _voice == null:
		return
	_voice.stream = custom if custom != null else fallback
	_voice.play()


func _update_groan(delta: float) -> void:
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(3.0, 7.0)
		if aggro and not _voice.playing:
			_play_voice(groan_sound, SFX.zombie_groan())


# ----------------------------------------------------------------------------
# Floating health bar (always faces the camera)
# ----------------------------------------------------------------------------
func _build_health_bar() -> void:
	if not show_health_bar:
		return
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0.0, health_bar_height, 0.0)
	_bar_root.visible = false
	add_child(_bar_root)
	var bg := _make_quad(Color(0, 0, 0, 0.7), 0.0)
	_bar_root.add_child(bg)
	_bar_fg = _make_quad(Color(0.9, 0.15, 0.15), 0.01)
	_fg_quad = _bar_fg.mesh as QuadMesh
	_bar_root.add_child(_bar_fg)


func _make_quad(color: Color, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(health_bar_width, 0.12)
	q.center_offset = Vector3(0.0, 0.0, z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = mat
	mi.mesh = q
	return mi


func _update_bar(show_it := false) -> void:
	if _bar_root == null:
		return
	if show_it:
		_bar_root.visible = true
	var ratio := clampf(health / max_health, 0.0, 1.0)
	var w := maxf(health_bar_width * ratio, 0.001)
	_fg_quad.size = Vector2(w, 0.12)
	_fg_quad.center_offset = Vector3(-(health_bar_width - w) * 0.5, 0.0, 0.01)
