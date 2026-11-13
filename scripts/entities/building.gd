class_name Building
extends Node2D
## Base class for everything placed on the grid. The node sits at the centre
## of its footprint; `cell` is the top-left tile.

const TILE := 32

var id: StringName
var def: Dictionary
var world: World
var cell := Vector2i.ZERO
var size := Vector2i.ONE  ## footprint after rotation
var dir := 0  ## 0 = north, 1 = east, 2 = south, 3 = west
var power_net: PowerNetwork = null
var power_satisfaction := 0.0
var status := ""
var anim_time := 0.0
var drawn_icon := ""  ## status icon at the last redraw, so a cleared icon gets erased
var health := 0.0


func setup(p_world: World, p_id: StringName, p_cell: Vector2i, p_dir: int) -> void:
	world = p_world
	id = p_id
	def = GameData.BUILDINGS[id]
	cell = p_cell
	dir = p_dir if def.get("rotatable", false) else 0
	size = GameData.footprint(id, dir)
	position = Vector2(cell * TILE) + Vector2(size * TILE) * 0.5
	z_index = def.get("z", 1)
	health = max_health()
	_init_building()


## Override for per-type initialisation (called once setup() has filled the fields).
func _init_building() -> void:
	pass


func display_name() -> String:
	return GameData.item_name(id)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(cell + Vector2i(x, y))
	return out


func rect() -> Rect2i:
	return Rect2i(cell, size)


## Converts an offset given for the north-facing footprint to a world cell.
func to_world_cell(local: Vector2i) -> Vector2i:
	return cell + GameData.rotate_local(local, def["size"], dir)


func tick(_dt: float) -> void:
	pass


# --- Health ------------------------------------------------------------------

func max_health() -> float:
	return def.get("health", 100.0)


func health_fraction() -> float:
	return health / max_health()


func is_damaged() -> bool:
	return health < max_health()


## Worn enough to flag on screen (light wear is only shown when hovered).
func needs_repair() -> bool:
	return health_fraction() < 0.75


## Machines that wear out while working (and so need Repair Kits).
func wears() -> bool:
	return def.get("wears", false) and GameData.WEAR_SECONDS > 0.0


## A broken machine does nothing until repaired.
func is_broken() -> bool:
	return health <= 0.0


## Applies wear for `work_seconds` of full-speed work.
func wear(work_seconds: float) -> void:
	if wears() and work_seconds > 0.0:
		health = maxf(0.0, health - max_health() * work_seconds / GameData.WEAR_SECONDS)


## Restores up to `amount` health, returns how much was restored.
func repair(amount: float) -> float:
	var restored := minf(amount, max_health() - health)
	health += restored
	queue_redraw()
	return restored


## Called every tick instead of tick() while broken, to stop animations.
func _on_broken() -> void:
	pass


func health_line() -> String:
	if is_broken():
		return "BROKEN - repair it with a Repair Kit"
	if wears() or is_damaged():
		return "Health: %d / %d" % [ceili(health), roundi(max_health())]
	return ""


# --- Power -------------------------------------------------------------------

func is_electric() -> bool:
	return def.has("power")


func is_generator() -> bool:
	return false


## Watts wanted this tick (electric consumers).
func get_power_demand() -> float:
	return 0.0


## Watts a generator could deliver this tick.
func available_power(_dt: float) -> float:
	return 0.0


## Generators: produce up to `joules`, return what was produced.
func generate(_joules: float) -> float:
	return 0.0


func power_line() -> String:
	if not is_electric():
		return ""
	if power_net == null:
		return "Power: not connected (place a pole nearby)"
	return "Power: %d%%  (network %s / %s)" % [roundi(power_satisfaction * 100.0),
		GameData.format_power(power_net.production), GameData.format_power(power_net.capacity)]


# --- Items (used by inserters and drills) -----------------------------------

func can_accept(_item: StringName) -> bool:
	return false


func accept(_item: StringName) -> bool:
	return false


## Inserters pick the highest-priority item the target accepts; used so an
## empty fuel slot gets coal before more ore.
func insert_priority(_item: StringName) -> int:
	return 0


## Items an inserter may take out of this building.
func takeable_items() -> Array[StringName]:
	return []


func take(_item: StringName) -> bool:
	return false


# --- Fluids ------------------------------------------------------------------

func fluid_boxes() -> Array[FluidBox]:
	return []


## Connection points: [{"box": FluidBox, "from": my cell, "to": neighbour cell}]
func fluid_connections() -> Array:
	return []


func _conn(box: FluidBox, local_from: Vector2i, local_to: Vector2i) -> Dictionary:
	return {"box": box, "from": to_world_cell(local_from), "to": to_world_cell(local_to)}


func on_fluids_rebuilt() -> void:
	pass


# --- Player interaction ------------------------------------------------------

## Slots shown in the building window: [{"key", "label", "item", "count"}]
func ui_slots() -> Array:
	return []


## Removes a whole slot, returning {item: count}.
func ui_take(_key: String) -> Dictionary:
	return {}


## Whether the player may insert `item` by hand.
func ui_accepts(_item: StringName) -> bool:
	return false


## Inserts up to `count` from the player, returns how many were taken.
func ui_insert(_item: StringName, _count: int) -> int:
	return 0


func ui_lines() -> PackedStringArray:
	return PackedStringArray()


## Everything inside, returned to the player when the building is picked up.
func contents() -> Dictionary:
	return {}


static func merge_into(target: Dictionary, add: Dictionary) -> void:
	for k in add:
		if add[k] > 0:
			target[k] = target.get(k, 0) + add[k]


# --- Drawing -----------------------------------------------------------------

## Name of a status icon to blink over the building, or "".
func status_icon() -> String:
	return ""


## The icon actually shown: low health takes priority over other problems.
func current_icon() -> String:
	if wears() and health_fraction() <= 0.25:
		return "repair"
	return status_icon()


## Base sprite and overlay are drawn in north-facing local space and rotated
## as a whole, so overlays can use the same coordinates as the sprite.
func _draw() -> void:
	if def.get("rotatable", false):
		draw_set_transform(Vector2.ZERO, dir * PI * 0.5)
	_draw_base()
	_draw_overlay()
	draw_set_transform(Vector2.ZERO)
	_draw_health_bar()
	_draw_status_icon()


## Thin bar along the bottom edge, once noticeably worn.
func _draw_health_bar() -> void:
	if not needs_repair():
		return
	var w := size.x * TILE - 10.0
	var top_left := Vector2(-w * 0.5, size.y * TILE * 0.5 - 7.0)
	var f := health_fraction()
	var color := Color(0.9, 0.25, 0.2).lerp(Color(0.95, 0.85, 0.25), clampf(f * 2.0, 0.0, 1.0))
	if f > 0.5:
		color = Color(0.95, 0.85, 0.25).lerp(Color(0.35, 0.85, 0.35), (f - 0.5) * 2.0)
	draw_rect(Rect2(top_left - Vector2(1, 1), Vector2(w + 2, 5)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(top_left, Vector2(w * f, 3)), color)


func _draw_status_icon() -> void:
	drawn_icon = current_icon()
	if drawn_icon != "" and fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6:
		var tex := GameData.sprite("status_" + drawn_icon)
		draw_texture(tex, -tex.get_size() * 0.5)


func _draw_base() -> void:
	var tex := GameData.sprite(String(id))
	var offset: Vector2 = def.get("sprite_offset", Vector2.ZERO)
	draw_texture(tex, -tex.get_size() * 0.5 + offset)


## Animated parts drawn on top of the sprite.
func _draw_overlay() -> void:
	pass


## Rotating spokes, used for drill heads and flywheels.
func _draw_spinner(center: Vector2, radius: float, spokes: int, color: Color, width: float = 2.0) -> void:
	for i in spokes:
		var a := anim_time * 6.0 + TAU * i / spokes
		draw_line(center, center + Vector2.from_angle(a) * radius, color, width)


## Flickering orange glow for fire boxes.
func _draw_fire(center: Vector2, half: Vector2) -> void:
	var flicker := 0.75 + 0.25 * sin(anim_time * 23.0) * sin(anim_time * 7.0)
	draw_rect(Rect2(center - half, half * 2.0), Color(1.0, 0.55, 0.15, 0.55 * flicker))
	draw_rect(Rect2(center - half * 0.6, half * 1.2), Color(1.0, 0.85, 0.35, 0.6 * flicker))
