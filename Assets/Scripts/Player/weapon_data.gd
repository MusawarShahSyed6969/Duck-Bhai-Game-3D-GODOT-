class_name WeaponData
extends Resource
## One weapon's stats. Create new ones in the FileSystem:
## right-click -> Create New -> Resource -> WeaponData, then fill it in the Inspector.

@export var weapon_name := "Pistol"

@export_group("Damage & Fire")
@export var damage := 25.0                 ## damage per bullet (per pellet for shotguns)
@export var fire_rate := 4.0               ## shots per second
@export var automatic := false             ## hold to keep firing
@export var pellets := 1                   ## >1 = shotgun
@export var max_range := 150.0

@export_group("Ammo")
@export var magazine_size := 12
@export var start_reserve := 60
@export var max_reserve := 120
@export var reload_time := 1.4

@export_group("Accuracy (degrees)")
@export var spread_hip := 2.0              ## cone while hip firing
@export var spread_aim := 0.3              ## cone while aiming (right mouse)
@export var spread_move := 1.5             ## extra cone when running / jumping
@export var spread_per_shot := 0.4         ## bloom added by every shot
@export var spread_max_bloom := 3.0        ## bloom cap

@export_group("Recoil (degrees)")
@export var recoil_pitch_deg := 0.6        ## camera kick upward per shot
@export var recoil_yaw_deg := 0.15         ## random sideways kick

@export_group("Hand placement (tune in game with the T key)")
@export var hold_position := Vector3.ZERO      ## offset from the hand bone
@export var hold_rotation_deg := Vector3.ZERO
@export var hold_scale := 1.0

@export_group("Optional visuals / sound (empty = built-in placeholder sounds)")
@export var weapon_scene: PackedScene      ## 3D model spawned in the hand holder
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
