class_name ZombieProjectile
extends Area3D
## Spit / projectile used by ranged zombies. Builds its own collider and mesh.

var velocity := Vector3.ZERO
var damage := 10.0
var color := Color(0.4, 1.0, 0.2)
var shooter: Node
var lifetime := 5.0
var size_mult := 1.0
var slow_mult := 1.0        # < 1 slows the player on hit
var slow_time := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitoring = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25 * size_mult
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2 * size_mult
	sm.height = 0.4 * size_mult
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mesh.mesh = sm
	mesh.material_override = mat
	add_child(mesh)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter or body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.call("take_damage", damage, global_position)
	if slow_time > 0.0 and body.has_method("apply_slow"):
		body.call("apply_slow", slow_mult, slow_time)
	queue_free()
