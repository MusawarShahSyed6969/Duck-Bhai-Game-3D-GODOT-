extends CanvasLayer
## Whole HUD built in code: health, stamina, ammo, weapon name, reload bar,
## dynamic crosshair, hit marker, damage flash and death screen.
## Add a CanvasLayer to your scene and attach this script. Nothing else to set up.

@export var crosshair_base_gap := 6.0
@export var pixels_per_degree := 9.0       ## how much the crosshair opens per degree of spread
@export var crosshair_only_when_aiming := true  ## hide the crosshair while hip-firing / walking

# Inner class: the crosshair is drawn with code (no textures needed)
class Crosshair extends Control:
	var gap := 8.0
	var arm := 10.0
	var thickness := 2.0
	var color := Color(1, 1, 1, 0.9)
	var hit_time := 0.0
	var lines_alpha := 1.0              # fades the crosshair in / out

	func _draw() -> void:
		var c := size * 0.5
		if lines_alpha > 0.01:
			var col := Color(color.r, color.g, color.b, color.a * lines_alpha)
			var shadow := Color(0, 0, 0, 0.6 * lines_alpha)
			for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var a: Vector2 = c + d * gap
				var b: Vector2 = c + d * (gap + arm)
				draw_line(a + Vector2.ONE, b + Vector2.ONE, shadow, thickness + 1.0)
				draw_line(a, b, col, thickness)
			draw_circle(c, 1.6, col)
		if hit_time > 0.0:
			var hc := Color(1, 0.25, 0.2, clampf(hit_time / 0.15, 0.0, 1.0))
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 7.0, c + d * 15.0, hc, 2.5)


var _player
var _wm
var _health

var _root: Control
var _crosshair: Crosshair
var _hp_bar: ProgressBar
var _sta_bar: ProgressBar
var _sta_row: Control
var _weapon_label: Label
var _ammo_label: Label
var _reload_bar: ProgressBar
var _flash: ColorRect
var _death_screen: Control
var _boss_box: Control
var _boss_label: Label
var _boss_bar: ProgressBar
var _reload_tween: Tween
var _gap := 8.0
var _dead := false


func _ready() -> void:
	layer = 10
	_build_ui()
	await get_tree().process_frame          # wait so the player is fully ready
	_bind()


# ----------------------------------------------------------------------------
# Connect to the player
# ----------------------------------------------------------------------------
func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("[HUD] No node in group 'player' found.")
		return

	_player.stamina_changed.connect(_on_stamina_changed)
	_player.died.connect(_on_died)
	_on_stamina_changed(_player.stamina, _player.max_stamina)

	_health = _player.get_node_or_null("Health")
	if _health != null:
		_health.changed.connect(_on_health_changed)
		_health.damaged.connect(_on_damaged)
		_on_health_changed(_health.current, _health.max_health)
	else:
		push_warning("[HUD] Player has no child node named 'Health'.")

	_wm = _player.get_node_or_null("WeaponManager")
	if _wm != null:
		_wm.weapon_changed.connect(_on_weapon_changed)
		_wm.ammo_changed.connect(_on_ammo_changed)
		_wm.reload_started.connect(_on_reload_started)
		_wm.reload_finished.connect(_hide_reload)
		_wm.hit_confirmed.connect(_on_hit)
		_on_weapon_changed(_wm.current)
		_on_ammo_changed(_wm.get_mag(), _wm.get_reserve())
	else:
		push_warning("[HUD] Player has no child node named 'WeaponManager'.")


# ----------------------------------------------------------------------------
# Per-frame
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _wm != null:
		var target: float = crosshair_base_gap + float(_wm.current_spread) * pixels_per_degree
		_gap = lerpf(_gap, target, 1.0 - exp(-25.0 * delta))
		_crosshair.gap = _gap
		_crosshair.color.a = 0.4 if _wm.is_reloading else 0.9
	var show_lines := true
	if crosshair_only_when_aiming:
		show_lines = _player != null and _player.is_aiming
	_crosshair.lines_alpha = lerpf(_crosshair.lines_alpha, 1.0 if show_lines else 0.0, 1.0 - exp(-18.0 * delta))
	_crosshair.hit_time = maxf(_crosshair.hit_time - delta, 0.0)
	_crosshair.visible = not _dead
	_crosshair.queue_redraw()

	# Boss bar
	var boss = get_tree().get_first_node_in_group("boss")
	if boss != null and not boss.is_dead and boss.aggro:
		_boss_box.visible = true
		_boss_label.text = boss.enemy_name
		_boss_bar.max_value = boss.max_health
		_boss_bar.value = boss.health
	else:
		_boss_box.visible = false

	# Stamina bar fades when full
	var full := _sta_bar.value >= _sta_bar.max_value - 0.1
	_sta_row.modulate.a = lerpf(_sta_row.modulate.a, 0.25 if full else 1.0, 1.0 - exp(-6.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if _dead and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()


# ----------------------------------------------------------------------------
# Signal handlers
# ----------------------------------------------------------------------------
func _on_health_changed(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current
	var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(0.9, 0.2, 0.2) if current / maximum < 0.3 else Color(0.25, 0.8, 0.35)


func _on_damaged(_amount: float) -> void:
	_flash.color.a = 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.4)


func _on_stamina_changed(current: float, maximum: float) -> void:
	_sta_bar.max_value = maximum
	_sta_bar.value = current
	var fill := _sta_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(0.95, 0.45, 0.15) if _player.exhausted else Color(0.95, 0.8, 0.2)


func _on_weapon_changed(weapon: WeaponData) -> void:
	_weapon_label.text = weapon.weapon_name if weapon != null else ""
	_hide_reload()


func _on_ammo_changed(mag: int, reserve: int) -> void:
	_ammo_label.text = "EMPTY" if (mag <= 0 and reserve <= 0) else "%d / %d" % [mag, reserve]
	var low: bool = _wm.current != null and mag <= maxi(1, int(_wm.current.magazine_size * 0.25))
	_ammo_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if low else Color.WHITE)


func _on_reload_started(duration: float) -> void:
	_reload_bar.visible = true
	_reload_bar.value = 0.0
	if _reload_tween != null:
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.tween_property(_reload_bar, "value", 1.0, duration)


func _hide_reload() -> void:
	if _reload_tween != null:
		_reload_tween.kill()
	_reload_bar.visible = false


func _on_hit(_point: Vector3) -> void:
	_crosshair.hit_time = 0.15


func _on_died() -> void:
	_dead = true
	_death_screen.visible = true


# ----------------------------------------------------------------------------
# UI construction
# ----------------------------------------------------------------------------
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Damage flash (full screen red)
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0, 0, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	# Crosshair
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	# Bottom-left: health + stamina
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 30
	left.offset_top = -90
	left.offset_right = 330
	left.offset_bottom = -30
	left.add_theme_constant_override("separation", 8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(left)

	_hp_bar = _make_bar(Color(0.25, 0.8, 0.35), 18.0)
	left.add_child(_make_row("HP", _hp_bar))
	_sta_bar = _make_bar(Color(0.95, 0.8, 0.2), 12.0)
	_sta_row = _make_row("STA", _sta_bar)
	left.add_child(_sta_row)

	# Bottom-right: weapon + ammo + reload
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -330
	right.offset_top = -130
	right.offset_right = -30
	right.offset_bottom = -30
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(right)

	_weapon_label = _make_label(20, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_weapon_label)
	_ammo_label = _make_label(44, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_ammo_label)
	_reload_bar = _make_bar(Color(0.9, 0.9, 0.9), 6.0)
	_reload_bar.max_value = 1.0
	_reload_bar.visible = false
	right.add_child(_reload_bar)

	# Boss health bar (top center, shows while a node in group "boss" is fighting)
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -300
	_boss_box.offset_right = 300
	_boss_box.offset_top = 24
	_boss_box.offset_bottom = 80
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	_boss_label = _make_label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_box.add_child(_boss_label)
	_boss_bar = _make_bar(Color(0.8, 0.1, 0.1), 18.0)
	_boss_box.add_child(_boss_bar)

	# Death screen
	_death_screen = ColorRect.new()
	(_death_screen as ColorRect).color = Color(0, 0, 0, 0.6)
	_death_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_screen.visible = false
	_root.add_child(_death_screen)
	var title := _make_label(72, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "YOU DIED"
	title.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -80
	title.offset_bottom = 10
	_death_screen.add_child(title)
	var hint := _make_label(24, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "Press ENTER to restart"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint.offset_left = -300
	hint.offset_right = 300
	hint.offset_top = 20
	hint.offset_bottom = 60
	_death_screen.add_child(hint)


func _make_bar(fill_color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _make_row(text: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _make_label(16, HORIZONTAL_ALIGNMENT_LEFT)
	l.text = text
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	row.add_child(bar)
	return row


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
