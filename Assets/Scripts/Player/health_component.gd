class_name Health
extends Node
## Add as a child node named "Health" to anything that can take damage
## (player, enemies, crates...). The weapon system finds it automatically.

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal died

@export var max_health := 100.0
@export var regen_per_second := 0.0        ## 0 = no regeneration
@export var regen_delay := 5.0             ## seconds after last hit before regen starts

var current := 0.0
var is_dead := false
var _since_damage := 0.0


func _ready() -> void:
	current = max_health


func _process(delta: float) -> void:
	if is_dead or regen_per_second <= 0.0 or current >= max_health:
		return
	_since_damage += delta
	if _since_damage >= regen_delay:
		current = minf(current + regen_per_second * delta, max_health)
		changed.emit(current, max_health)


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	_since_damage = 0.0
	damaged.emit(amount)
	changed.emit(current, max_health)
	if current <= 0.0:
		is_dead = true
		died.emit()


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	healed.emit(amount)
	changed.emit(current, max_health)


func reset() -> void:
	is_dead = false
	current = max_health
	changed.emit(current, max_health)
