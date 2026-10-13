extends StaticBody3D
## Test target. Make: StaticBody3D + CollisionShape3D + MeshInstance3D, attach this script.

@export var max_health := 100.0
@export var respawn_time := 3.0

var health := 0.0
var _layer := 1


func _ready() -> void:
	health = max_health
	_layer = collision_layer


func take_damage(amount: float, _point: Vector3 = Vector3.ZERO) -> void:
	if health <= 0.0:
		return
	health -= amount
	_flash()
	if health <= 0.0:
		_die()


func _flash() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0.2, 0.2)
			(c as MeshInstance3D).material_override = mat
			await get_tree().create_timer(0.08).timeout
			if is_instance_valid(c):
				(c as MeshInstance3D).material_override = null


func _die() -> void:
	visible = false
	collision_layer = 0
	await get_tree().create_timer(respawn_time).timeout
	health = max_health
	collision_layer = _layer
	visible = true
