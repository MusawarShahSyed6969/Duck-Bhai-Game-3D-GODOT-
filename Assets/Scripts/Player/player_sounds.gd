class_name PlayerSounds
extends Node
## Footsteps, jump, landing, hurt and death sounds for the Player.
## Added to the Player automatically. To use your own sounds, add a Node named
## "PlayerSounds" under Player yourself, attach this script and fill the slots.
## Empty slots use built-in placeholder sounds (see sfx.gd).

@export var enabled := true
@export_range(-30.0, 6.0) var volume_db := -4.0
@export var step_sounds: Array[AudioStream] = []   ## random one is played each footstep
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
@export var hurt_sound: AudioStream
@export var death_sound: AudioStream

var _p                                               # the Player (untyped on purpose)
var _feet: AudioStreamPlayer
var _fx: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _step_timer := 0.0
var _was_on_floor := true
var _prev_vy := 0.0
var _hurt_cooldown := 0.0


func _ready() -> void:
	_p = get_parent()
	_feet = _make_player()
	_fx = _make_player()
	_voice = _make_player()
	print("[PlayerSounds] active - footsteps, jump, hurt sounds enabled")
	var h = _p.get_node_or_null("Health")
	if h != null:
		h.damaged.connect(_on_damaged)
		h.died.connect(_on_died)


func _make_player() -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.volume_db = volume_db
	add_child(a)
	return a


func _physics_process(delta: float) -> void:
	if not enabled or _p == null or _p.is_dead:
		return
	_hurt_cooldown -= delta
	var on_floor: bool = _p.is_on_floor()
	var hspeed := Vector2(_p.velocity.x, _p.velocity.z).length()

	# Footsteps: timing follows real speed so it matches the animation
	if on_floor and hspeed > 0.8:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_step()
			var stride: float = 1.2 if _p.is_crouching else 1.9
			_step_timer = clampf(stride / hspeed, 0.18, 0.8)
	else:
		_step_timer = 0.12

	# Jump
	if _was_on_floor and not on_floor and _p.velocity.y > 1.0:
		_play(_fx, jump_sound if jump_sound != null else SFX.jump(), 0.05)

	# Landing (uses last frame's fall speed because velocity.y is 0 on impact)
	if not _was_on_floor and on_floor and _prev_vy < -4.0:
		_play(_fx, land_sound if land_sound != null else SFX.land(), 0.05)

	_was_on_floor = on_floor
	_prev_vy = _p.velocity.y


func _play_step() -> void:
	var s: AudioStream
	if step_sounds.size() > 0:
		s = step_sounds[randi() % step_sounds.size()]
	else:
		s = SFX.step(randi() % 3)
	_feet.volume_db = volume_db + (-7.0 if _p.is_crouching else (2.0 if _p.is_sprinting else 0.0))
	_play(_feet, s, 0.1)


func _on_damaged(_amount: float) -> void:
	if _hurt_cooldown > 0.0 or not enabled:
		return
	_hurt_cooldown = 0.3
	_play(_voice, hurt_sound if hurt_sound != null else SFX.hurt(), 0.06)


func _on_died() -> void:
	if enabled:
		_play(_voice, death_sound if death_sound != null else SFX.death(), 0.0)


func _play(player: AudioStreamPlayer, stream: AudioStream, pitch_variation: float) -> void:
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()
