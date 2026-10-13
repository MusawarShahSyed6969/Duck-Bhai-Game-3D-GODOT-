class_name BossZombie
extends Zombie
## THREE-PHASE FINAL BOSS. You must kill him 3 times.
##   Phase 1  NORMAL    - fast predictive spit, leap slam, ground slam, summons minions
##   Phase 2  BEAST     - bigger, faster, armored. Adds jump-over shockwaves, BLINDING FLARE, charge
##   Phase 3  PREDATOR  - cloaks, teleports behind you, toxic pools, long pounce, very aggressive
## Each phase has its own health bar and HUD color.
## Use this script instead of zombie.gd on the boss scene. Everything is an Inspector setting.

signal phase_changed(index: int, phase_name: String)

const ABILITIES := {
	# name:          min phase, min distance, max distance, weight
	"volley":       {"phase": 0, "min": 3.0, "max": 70.0, "w": 3.0},
	"ground_slam":  {"phase": 0, "min": 0.0, "max": 8.0, "w": 3.5},
	"leap_slam":    {"phase": 0, "min": 5.0, "max": 40.0, "w": 3.0},
	"shockwave":    {"phase": 1, "min": 0.0, "max": 14.0, "w": 3.0},
	"blind_flare":  {"phase": 1, "min": 0.0, "max": 45.0, "w": 2.5},
	"charge":       {"phase": 1, "min": 6.0, "max": 40.0, "w": 3.0},
	"toxic_pools":  {"phase": 2, "min": 0.0, "max": 45.0, "w": 2.5},
	"blink_strike": {"phase": 2, "min": 6.0, "max": 70.0, "w": 3.0},
	"pounce":       {"phase": 2, "min": 8.0, "max": 60.0, "w": 2.5},
	"cloak":        {"phase": 2, "min": 5.0, "max": 70.0, "w": 1.5},
}

@export_group("Phases (3 health bars)")
@export var phase_names: Array[String] = ["NORMAL", "BEAST", "PREDATOR"]
@export var phase_colors: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.7, 0.25, 1.0), Color(0.15, 0.9, 1.0)]
@export var phase_health: Array[float] = [800.0, 1200.0, 1500.0]
@export var phase_speed_mult: Array[float] = [1.0, 1.3, 1.7]
@export var phase_damage_mult: Array[float] = [1.0, 1.3, 1.6]
@export var phase_cooldown_mult: Array[float] = [1.0, 0.75, 0.55]
@export var phase_damage_taken: Array[float] = [1.0, 0.85, 0.7]   ## <1 = armor
@export var phase_model_scale: Array[float] = [1.0, 1.2, 1.1]
@export var phase_ability_delay: Array[float] = [3.5, 2.4, 1.5]   ## pause between special moves
@export var phase_voice_pitch: Array[float] = [0.7, 0.55, 0.85]
@export var transition_time := 3.5                                ## roar time between phases (invulnerable)

@export_group("Power: fast predictive spit")
@export var spit_damage := 12.0
@export var spit_speed := 34.0
@export var spit_lead := 1.0                       ## 1 = aims where you WILL be (running in a line won't save you)
@export var spit_spread_deg := 7.0
@export var spit_fan: Array[int] = [3, 5, 7]       ## projectiles per burst, per phase
@export var spit_bursts: Array[int] = [1, 2, 3]
@export var spit_windup := 0.45
@export var projectile_origin_height := 2.0

@export_group("Power: leap slam / pounce")
@export var leap_windup := 0.7
@export var leap_range := 22.0
@export var leap_flight_time := 0.85
@export var leap_radius := 5.0
@export var leap_damage := 35.0
@export var leap_lead := 0.7
@export var leap_rings: Array[int] = [0, 1, 2]     ## shockwave rings created on landing, per phase

@export_group("Power: ground slam")
@export var slam_windup := 1.0
@export var slam_radius := 6.0
@export var slam_damage := 40.0
@export var slam_knockback := 10.0

@export_group("Power: shockwave (JUMP over it)")
@export var shockwave_damage := 30.0
@export var shockwave_speed := 7.0
@export var shockwave_thickness := 0.9
@export var shockwave_max_radius := 24.0
@export var shockwave_clear_height := 0.4          ## be this high above the ground to dodge
@export var shockwave_ring_count := 3
@export var shockwave_spacing := 0.55

@export_group("Power: blinding flare (look AWAY)")
@export var blind_windup := 1.3
@export var blind_duration := 3.5                  ## full blindness if you look at him, only 20% if you look away

@export_group("Power: charge (he crashes into walls and is stunned)")
@export var charge_speed := 24.0
@export var charge_windup := 0.9
@export var charge_damage := 40.0
@export var charge_stun := 1.5
@export var stun_damage_bonus := 1.5               ## he takes this much more damage while stunned

@export_group("Power: toxic pools (slow + damage over time)")
@export var pool_count := 5
@export var pool_radius := 3.0
@export var pool_time := 9.0
@export var pool_arm_time := 1.0
@export var pool_damage_per_sec := 12.0

@export_group("Power: blink strike / cloak")
@export var blink_telegraph := 0.55                ## time you get to turn around
@export var blink_damage := 45.0
@export var cloak_time := 6.0
@export var cloak_speed_mult := 1.4

@export_group("Summon minions")
@export var minion_scene: PackedScene              ## optional. Empty = built-in minions are used
@export var summon_interval := 14.0
@export var summon_count := 2                      ## +1 more per phase
@export var max_minions := 6
@export var kill_minions_on_death := true

@export_group("Animation names (add yours, all optional)")
@export var anim_roar := "roar"                    ## phase change
@export var anim_leap := "leap"                    ## crouch + take off
@export var anim_land := "land"
@export var anim_shoot := "shoot"
@export var anim_summon := "summon"
@export var anim_flare := "flare"
@export var anim_charge := "charge"
@export var anim_stun := "stun"
@export var anim_cloak := "cloak"
@export var anim_blink := "blink"
@export var anim_pools := "pools"
## (slam uses the base "Anim Special" name, melee uses "Anim Attack")
@export var procedural_squash := true              ## squash/stretch the Model when there is no animation

var phase_index := 0
var phase_count := 3
var phase_name := ""
var phase_color := Color.WHITE

var _transitioning := false
var _busy := false
var _motion_free := false
var _track_player := true
var _ability_cd := 3.0
var _last_ability := ""
var _forced_next := ""
var _summon_left := 6.0
var _minions: Array = []
var _shockwaves: Array = []
var _pools: Array = []
var _dot_timer := 0.0
var _cloak_left := 0.0
var _flicker_t := 0.0
var _reveal_left := 0.0
var _meshes_shown := true
var _vuln_mult := 1.0
var _base_speed_mult := 1.0
var _base_cooldown_mult := 1.0
var _aura_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D
var _scale_base := Vector3.ONE
var _scale_rest := Vector3.ONE
var _squash_tween: Tween


func _init() -> void:
	# Boss-friendly defaults (anything you set in the Inspector wins)
	stagger_chance = 0.0
	lose_range = 0.0
	detect_range = 70.0
	attack_damage = 25.0
	attack_range = 2.8
	attack_cooldown = 1.0
	attack_windup = 0.35
	chase_speed = 3.6
	acceleration = 20.0
	turn_speed = 7.0
	knockback = 8.0


func _ready() -> void:
	show_health_bar = false                      # the boss bar is on the HUD instead
	phase_count = mini(phase_health.size(), 3)
	max_health = _pf(phase_health, 1000.0)
	super()
	add_to_group("boss")
	if enemy_name == "Zombie":
		enemy_name = "Final Boss"

	_aura_mat = StandardMaterial3D.new()
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_white_mat = StandardMaterial3D.new()
	_white_mat.albedo_color = Color(1, 1, 1, 0.75)
	_white_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_scale_base = _visual.scale
	_apply_phase(false)
	_summon_left = summon_interval * 0.5


func _extra_anim_names() -> Dictionary:
	return {
		"roar": anim_roar, "leap": anim_leap, "land": anim_land, "shoot": anim_shoot,
		"summon": anim_summon, "flare": anim_flare, "charge": anim_charge, "stun": anim_stun,
		"cloak": anim_cloak, "blink": anim_blink, "pools": anim_pools,
	}


# ----------------------------------------------------------------------------
# Phases
# ----------------------------------------------------------------------------
func get_phase_color(i: int) -> Color:
	if phase_colors.size() == 0:
		return Color.WHITE
	return phase_colors[mini(i, phase_colors.size() - 1)]


func _apply_phase(animate: bool) -> void:
	phase_name = _ps(phase_names, "PHASE")
	phase_color = get_phase_color(phase_index)
	max_health = _pf(phase_health, 1000.0)
	health = max_health
	_base_speed_mult = _pf(phase_speed_mult, 1.0)
	_base_cooldown_mult = _pf(phase_cooldown_mult, 1.0)
	speed_mult = _base_speed_mult
	damage_mult = _pf(phase_damage_mult, 1.0)
	cooldown_mult = _base_cooldown_mult
	_voice.pitch_scale = _pf(phase_voice_pitch, 0.7)

	# Color aura on the whole model so every phase looks different
	_aura_mat.albedo_color = Color(phase_color.r, phase_color.g, phase_color.b, 0.22)
	_base_overlay = _aura_mat if phase_index > 0 else null
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _base_overlay

	if _visual != self:
		_scale_rest = _scale_base * _pf(phase_model_scale, 1.0)
		if animate:
			create_tween().tween_property(_visual, "scale", _scale_rest, 1.0).set_trans(Tween.TRANS_BACK)
		else:
			_visual.scale = _scale_rest
	health_changed.emit(health, max_health)


func take_damage(amount: float, point: Vector3 = Vector3.ZERO) -> void:
	if is_dead or _transitioning:
		return
	if _cloak_left > 0.0:
		_reveal_left = 0.8                           # hitting him uncloaks him briefly
	super(amount * _pf(phase_damage_taken, 1.0) * _vuln_mult, point)


## The base class calls this when health reaches 0.
func _die() -> void:
	if phase_index < phase_count - 1:
		_phase_transition()
	else:
		super()


func _phase_transition() -> void:
	_transitioning = true
	_attacking = false
	_cloak_left = 0.0
	_vuln_mult = 1.0
	_set_meshes_visible(true)
	_clear_hazards()
	velocity = Vector3.ZERO
	_play_anim("roar", true)
	_play_voice(groan_sound, SFX.zombie_death())
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _white_mat
	_shake(3.0)
	await get_tree().create_timer(transition_time * 0.55).timeout
	if is_dead:
		return
	_hurt_player(0.0, 16.0)                          # roar blast throws you back
	_shake(6.0)
	await get_tree().create_timer(transition_time * 0.45).timeout
	if is_dead:
		return
	phase_index += 1
	_apply_phase(true)
	phase_changed.emit(phase_index, phase_name)
	_ability_cd = 1.5
	_transitioning = false


func _on_death() -> void:
	_cloak_left = 0.0
	_set_meshes_visible(true)
	_clear_hazards()
	if kill_minions_on_death:
		for m in _minions:
			if is_instance_valid(m) and not m.is_dead:
				m.take_damage(999999.0)


# ----------------------------------------------------------------------------
# Ability director (runs every physics frame while the boss is awake)
# ----------------------------------------------------------------------------
func _special(delta: float) -> bool:
	_tick_hazards(delta)
	_tick_cloak(delta)
	if is_dead:
		return false

	if _transitioning:
		_move(Vector3.ZERO, 0.0, delta)
		_face(_flat_to_player(), delta * 0.5)
		return true

	if _busy:
		if not _motion_free:
			_move(Vector3.ZERO, 0.0, delta)
		if _track_player:
			_face(_flat_to_player(), delta * 1.5)
		return true

	if not aggro:
		return false
	_ability_cd -= delta
	_summon_left -= delta
	if state == State.STAGGER or _attacking:
		return false                                 # let a melee swing finish

	if _summon_left <= 0.0:
		_minions = _minions.filter(func(m): return is_instance_valid(m) and not m.is_dead)
		if _minions.size() < max_minions:
			_run_ability("summon")
			return true
		_summon_left = 3.0

	if _ability_cd <= 0.0:
		var pick := _forced_next if _forced_next != "" else _pick_ability()
		_forced_next = ""
		_run_ability(pick)
		return true
	return false


func _pick_ability() -> String:
	var dist := _flat_to_player().length()
	var names: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for key in ABILITIES:
		var a: Dictionary = ABILITIES[key]
		if phase_index < int(a["phase"]) or dist < float(a["min"]) or dist > float(a["max"]):
			continue
		if String(key) == _last_ability:
			continue
		names.append(String(key))
		weights.append(float(a["w"]))
		total += float(a["w"])
	if names.is_empty():
		return "volley"
	var r := randf() * total
	for i in names.size():
		r -= weights[i]
		if r <= 0.0:
			return names[i]
	return names[names.size() - 1]


func _run_ability(ability: String) -> void:
	_busy = true
	_motion_free = false
	_track_player = true
	_last_ability = ability
	match ability:
		"volley":
			await _ab_volley()
		"ground_slam":
			await _ab_ground_slam()
		"leap_slam":
			await _ab_leap(false)
		"pounce":
			await _ab_leap(true)
		"shockwave":
			await _ab_shockwave()
		"blind_flare":
			await _ab_blind()
		"charge":
			await _ab_charge()
		"toxic_pools":
			await _ab_pools()
		"blink_strike":
			await _ab_blink()
		"cloak":
			await _ab_cloak()
		"summon":
			await _ab_summon()
	_busy = false
	_motion_free = false
	_track_player = true
	_vuln_mult = 1.0
	_squash_reset(0.2)
	_ability_cd = _pf(phase_ability_delay, 3.0)


func _aborted() -> bool:
	return is_dead or _transitioning or not is_instance_valid(_player)


func _wait(seconds: float) -> bool:
	await get_tree().create_timer(seconds).timeout
	return not _aborted()


# ----------------------------------------------------------------------------
# Abilities
# ----------------------------------------------------------------------------
func _ab_volley() -> void:
	_play_anim("shoot", true)
	_squash(1.15, spit_windup)
	if not await _wait(spit_windup):
		return
	for b in _pi(spit_bursts, 1):
		_fire_fan(_pi(spit_fan, 3))
		_play_voice(attack_sound, SFX.zombie_attack())
		if not await _wait(0.28):
			return
	await _wait(0.4)


func _ab_ground_slam() -> void:
	_play_anim("special", true)
	_squash(0.8, slam_windup)
	var ring := _make_disc(slam_radius, phase_color, self)
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.scale = Vector3(0.05, 1.0, 0.05)
	create_tween().tween_property(ring, "scale", Vector3.ONE, slam_windup)
	if not await _wait(slam_windup):
		ring.queue_free()
		return
	_squash(1.1, 0.08)
	if _flat_to_player().length() <= slam_radius:
		_hurt_player(slam_damage * damage_mult, slam_knockback)
	_burst_disc(ring)
	_shake(4.0)
	await _wait(0.7)


func _ab_leap(pounce: bool) -> void:
	var windup := leap_windup * (0.65 if pounce else 1.0)
	_play_anim("leap", true)
	_squash(0.7, windup)
	if not await _wait(windup):
		return

	# Pick the landing spot where you are GOING to be
	var flight := leap_flight_time * (0.7 if pounce else 1.0)
	var max_dist := leap_range * (1.7 if pounce else 1.0)
	var vel := Vector3.ZERO
	if _player is CharacterBody3D:
		vel = (_player as CharacterBody3D).velocity
		vel.y = 0.0
	var target := _player.global_position + vel * flight * leap_lead
	var jump := target - global_position
	jump.y = 0.0
	if jump.length() > max_dist:
		jump = jump.normalized() * max_dist

	velocity = Vector3(jump.x / flight, 0.5 * _gravity * flight, jump.z / flight)
	_motion_free = true
	_track_player = false
	_squash(1.3, 0.15)
	await get_tree().physics_frame                  # leave the ground
	var timeout := flight + 1.5
	while not is_on_floor() and timeout > 0.0 and not _aborted():
		timeout -= get_physics_process_delta_time()
		await get_tree().physics_frame
	if _aborted():
		return

	velocity = Vector3.ZERO
	_motion_free = false
	_play_anim("land", true)
	_squash(0.75, 0.05)
	var radius := leap_radius * (0.7 if pounce else 1.0)
	var disc := _make_disc(radius, phase_color, self)
	disc.position = Vector3(0.0, 0.05, 0.0)
	_burst_disc(disc)
	if _flat_to_player().length() <= radius:
		_hurt_player(leap_damage * damage_mult * (1.15 if pounce else 1.0), 12.0)
	_shake(6.0)
	if not pounce:
		var rings := _pi(leap_rings, 0)
		for i in rings:
			_spawn_shockwave(global_position)
			if not await _wait(0.45):
				return
	await _wait(0.7)


func _ab_shockwave() -> void:
	_play_anim("special", true)
	_squash(0.7, 0.7)
	if not await _wait(0.7):
		return
	# little hop, then stomp rings (jump over them!)
	velocity.y = 6.5
	_motion_free = true
	_squash(1.25, 0.1)
	await get_tree().physics_frame
	var timeout := 2.0
	while not is_on_floor() and timeout > 0.0 and not _aborted():
		timeout -= get_physics_process_delta_time()
		await get_tree().physics_frame
	if _aborted():
		return
	velocity = Vector3.ZERO
	_motion_free = false
	_squash_reset(0.1)
	for i in shockwave_ring_count:
		_spawn_shockwave(global_position)
		_shake(3.0)
		if not await _wait(shockwave_spacing):
			return
	await _wait(0.6)


func _ab_blind() -> void:
	_play_anim("flare", true)
	_squash(1.2, blind_windup)
	var light := OmniLight3D.new()
	light.omni_range = 30.0
	light.light_energy = 0.0
	light.position = Vector3(0.0, 2.0, 0.0)
	add_child(light)
	create_tween().tween_property(light, "light_energy", 14.0, blind_windup)
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _white_mat
	var ok := await _wait(blind_windup)
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _base_overlay
	if not ok:
		light.queue_free()
		return
	_blind_player()
	var t := create_tween()
	t.tween_property(light, "light_energy", 0.0, 0.4)
	t.tween_callback(light.queue_free)
	_forced_next = "charge"                         # he rushes you while you are blind
	await _wait(0.4)


func _ab_charge() -> void:
	_play_anim("charge", true)
	_squash(0.8, charge_windup)
	if not await _wait(charge_windup * 0.7):
		return
	_track_player = false                           # direction locks - sidestep!
	var dir := _flat_to_player().normalized()
	if not await _wait(charge_windup * 0.3):
		return
	_squash_reset(0.1)
	_motion_free = true
	var max_dist := clampf(_flat_to_player().length() + 8.0, 12.0, 40.0)
	var travelled := 0.0
	var hit := false
	var crashed := false
	while travelled < max_dist and not _aborted() and not crashed:
		velocity.x = dir.x * charge_speed
		velocity.z = dir.z * charge_speed
		_face(dir, 1.0)
		await get_tree().physics_frame
		travelled += charge_speed * get_physics_process_delta_time()
		if not hit and _flat_to_player().length() < 1.9:
			hit = true
			_hurt_player(charge_damage * damage_mult, 12.0)
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col.get_collider() != _player and absf(col.get_normal().y) < 0.5:
				crashed = true
	if _aborted():
		return
	velocity = Vector3.ZERO
	_motion_free = false
	if crashed:
		_play_anim("stun", true)
		_shake(5.0)
		_vuln_mult = stun_damage_bonus               # punish window
		await _wait(charge_stun)
	else:
		await _wait(0.6)


func _ab_pools() -> void:
	_play_anim("pools", true)
	_squash(1.2, 0.6)
	if not await _wait(0.7):
		return
	for i in pool_count:
		var offset := Vector3.ZERO
		if i > 0:
			var a := randf() * TAU
			offset = Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 8.0)
		_spawn_pool(_player.global_position + offset)
	_play_voice(attack_sound, SFX.zombie_attack())
	await _wait(0.7)


func _ab_blink() -> void:
	_play_anim("blink", true)
	_set_meshes_visible(false)
	if not await _wait(0.35):
		_set_meshes_visible(true)
		return
	var dest := _player.global_position + _player_back_dir() * 2.6
	dest = _clip_to_walls(_player.global_position + Vector3.UP, dest)
	global_position = Vector3(dest.x, _player.global_position.y, dest.z)
	velocity = Vector3.ZERO
	_face(_flat_to_player(), 1.0)
	_play_voice(attack_sound, SFX.zombie_attack())
	_set_meshes_visible(true)                       # you hear him, then see him: turn around!
	if not await _wait(blink_telegraph):
		return
	_track_player = false
	_play_anim("attack", true)
	if _flat_to_player().length() < 3.4:
		_hurt_player(blink_damage * damage_mult, 9.0)
	_shake(3.0)
	await _wait(0.7)


func _ab_cloak() -> void:
	_play_anim("cloak", true)
	if not await _wait(0.5):
		return
	_cloak_left = cloak_time


func _ab_summon() -> void:
	_summon_left = summon_interval
	_play_anim("summon", true)
	_squash(1.2, 0.6)
	_play_voice(groan_sound, SFX.zombie_groan())
	if not await _wait(0.7):
		return
	_spawn_minions(summon_count + phase_index)
	_shake(2.0)
	await _wait(0.6)


# ----------------------------------------------------------------------------
# Projectiles, hazards, minions
# ----------------------------------------------------------------------------
func _fire_fan(count: int) -> void:
	var origin := global_position + Vector3.UP * projectile_origin_height + _forward() * 1.0
	var target := _player.global_position + Vector3.UP * 1.1
	if _player is CharacterBody3D:
		var v := (_player as CharacterBody3D).velocity
		var t := origin.distance_to(target) / spit_speed
		target += Vector3(v.x, 0.0, v.z) * t * spit_lead
	var base_dir := (target - origin).normalized()
	var half := (count - 1) * 0.5
	for i in count:
		var dir := base_dir.rotated(Vector3.UP, deg_to_rad((i - half) * spit_spread_deg))
		var p := ZombieProjectile.new()
		p.damage = spit_damage * damage_mult
		p.velocity = dir * spit_speed
		p.color = phase_color
		p.shooter = self
		p.size_mult = 1.5
		if phase_index >= 2:
			p.slow_mult = 0.55
			p.slow_time = 1.5
		get_tree().current_scene.add_child(p)
		p.global_position = origin


func _spawn_shockwave(center: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = phase_color
	tm.material = mat
	mi.mesh = tm
	get_tree().current_scene.add_child(mi)
	mi.global_position = center + Vector3(0.0, 0.1, 0.0)
	mi.scale = Vector3(0.5, 1.0, 0.5)
	_shockwaves.append({"node": mi, "center": center, "r": 0.5, "hit": false})


func _spawn_pool(pos: Vector3) -> void:
	var node := _make_disc(pool_radius, Color(1.0, 0.2, 0.1), get_tree().current_scene)
	node.global_position = Vector3(pos.x, pos.y + 0.05, pos.z)
	_pools.append({"node": node, "pos": pos, "left": pool_time, "arm": pool_arm_time, "active": false})


func _tick_hazards(delta: float) -> void:
	var player_ok := is_instance_valid(_player) and not _player_is_dead()

	for w in _shockwaves.duplicate():
		var node: MeshInstance3D = w["node"]
		w["r"] = float(w["r"]) + shockwave_speed * delta
		var r: float = w["r"]
		if is_instance_valid(node):
			node.scale = Vector3(r, 1.0, r)
		if player_ok and not w["hit"]:
			var rel: Vector3 = _player.global_position - Vector3(w["center"])
			var height := rel.y
			rel.y = 0.0
			if absf(rel.length() - r) < shockwave_thickness and height < shockwave_clear_height:
				w["hit"] = true
				_hurt_player(shockwave_damage * damage_mult, 7.0)
		if r >= shockwave_max_radius:
			if is_instance_valid(node):
				node.queue_free()
			_shockwaves.erase(w)

	var in_pool := false
	for p in _pools.duplicate():
		var node: MeshInstance3D = p["node"]
		p["left"] = float(p["left"]) - delta
		p["arm"] = float(p["arm"]) - delta
		if float(p["arm"]) <= 0.0 and not p["active"]:
			p["active"] = true
			if is_instance_valid(node):
				(node.material_override as StandardMaterial3D).albedo_color = Color(0.35, 1.0, 0.2, 0.5)
		if float(p["left"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_pools.erase(p)
			continue
		if player_ok and p["active"]:
			var rel: Vector3 = _player.global_position - Vector3(p["pos"])
			var height := rel.y
			rel.y = 0.0
			if rel.length() < pool_radius and height < 1.2:
				in_pool = true
	if in_pool:
		_dot_timer -= delta
		if _dot_timer <= 0.0:
			_dot_timer = 0.4
			_hurt_player(pool_damage_per_sec * 0.4 * damage_mult, 0.0)
			if _player.has_method("apply_slow"):
				_player.call("apply_slow", 0.55, 0.6)
	else:
		_dot_timer = 0.0


func _clear_hazards() -> void:
	for w in _shockwaves:
		if is_instance_valid(w["node"]):
			w["node"].queue_free()
	for p in _pools:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	_shockwaves.clear()
	_pools.clear()


func _spawn_minions(count: int) -> void:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m.is_dead)
	var room := max_minions - _minions.size()
	for i in mini(count, room):
		var z: Zombie = null
		if minion_scene != null:
			z = minion_scene.instantiate() as Zombie
			if z == null:
				push_warning("[BossZombie] minion_scene must use zombie.gd - using built-in minion instead.")
		if z == null:
			z = _make_builtin_minion()
		z.always_aggro = true
		get_tree().current_scene.add_child(z)
		var a := randf() * TAU
		z.global_position = global_position + Vector3(cos(a), 0.3, sin(a)) * randf_range(2.5, 4.5)
		_minions.append(z)


func _make_builtin_minion() -> Zombie:
	var z := Zombie.new()
	z.name = "Minion"
	z.enemy_name = "Minion"
	z.max_health = 40.0 + 25.0 * phase_index
	z.chase_speed = 4.2 + 0.5 * phase_index
	z.attack_damage = 8.0 + 3.0 * phase_index
	z.attack_cooldown = 0.9
	z.detect_range = 100.0
	z.lose_range = 0.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0.0, 0.8, 0.0)
	z.add_child(cs)
	var model := Node3D.new()
	model.name = "Model"
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.6, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = phase_color.darkened(0.35)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.8, 0.0)
	model.add_child(mi)
	z.add_child(model)
	return z


# ----------------------------------------------------------------------------
# Blind, cloak, visuals
# ----------------------------------------------------------------------------
func _blind_player() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_boss := (global_position + Vector3.UP * 1.5 - cam.global_position).normalized()
	var facing := -cam.global_transform.basis.z
	var duration := blind_duration if facing.dot(to_boss) > 0.35 else blind_duration * 0.2
	get_tree().call_group("hud", "blind", duration)


func _tick_cloak(delta: float) -> void:
	if _reveal_left > 0.0:
		_reveal_left -= delta
	if _cloak_left > 0.0 and not is_dead:
		_cloak_left -= delta
		_flicker_t += delta
		var show_now := fmod(_flicker_t, 0.7) < 0.07 or _reveal_left > 0.0
		_set_meshes_visible(show_now)
		speed_mult = _base_speed_mult * cloak_speed_mult
		cooldown_mult = _base_cooldown_mult * 0.7
		if _cloak_left <= 0.0:
			_set_meshes_visible(true)
	elif not _transitioning:
		speed_mult = _base_speed_mult
		cooldown_mult = _base_cooldown_mult


func _set_meshes_visible(v: bool) -> void:
	if v == _meshes_shown:
		return
	_meshes_shown = v
	for m in _meshes:
		if is_instance_valid(m):
			m.visible = v


func _player_back_dir() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var back := Vector3(0.0, 0.0, 1.0)
	if cam != null:
		back = cam.global_transform.basis.z
	back.y = 0.0
	return back.normalized()


func _clip_to_walls(from: Vector3, to: Vector3) -> Vector3:
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(to.x, from.y, to.z), 0xFFFFFFFF, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var back_off: Vector3 = (from - Vector3(to.x, from.y, to.z)).normalized() * 0.7
	return Vector3(hit.position.x, to.y, hit.position.z) + back_off


func _make_disc(radius: float, color: Color, parent: Node) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.mesh = c
	m.material_override = mat
	parent.add_child(m)
	return m


func _burst_disc(disc: MeshInstance3D) -> void:
	var mat := disc.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 1, 0.6)
	var t := create_tween().set_parallel(true)
	t.tween_property(disc, "scale", disc.scale * Vector3(1.25, 1.0, 1.25), 0.35)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(disc.queue_free)


func _squash(sy: float, t: float) -> void:
	if not procedural_squash or _visual == self:
		return
	if _squash_tween != null:
		_squash_tween.kill()
	var sxz := 1.0 / sqrt(maxf(sy, 0.1))
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", _scale_rest * Vector3(sxz, sy, sxz), t).set_trans(Tween.TRANS_QUAD)


func _squash_reset(t: float) -> void:
	if not procedural_squash or _visual == self:
		return
	if _squash_tween != null:
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", _scale_rest, t)


func _shake(power: float) -> void:
	if is_instance_valid(_player) and _player.has_method("add_shake"):
		_player.call("add_shake", power * 0.04, 0.45)


# ---- per-phase array helpers -------------------------------------------------
func _pf(arr: Array[float], fallback: float) -> float:
	return arr[mini(phase_index, arr.size() - 1)] if arr.size() > 0 else fallback


func _pi(arr: Array[int], fallback: int) -> int:
	return arr[mini(phase_index, arr.size() - 1)] if arr.size() > 0 else fallback


func _ps(arr: Array[String], fallback: String) -> String:
	return arr[mini(phase_index, arr.size() - 1)] if arr.size() > 0 else fallback
