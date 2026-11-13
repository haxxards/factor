class_name BuildPreview
extends Node2D
## World-space overlay: the placement grid and ghost while holding an item,
## and hover highlights / mining progress otherwise.

const GRID_RADIUS := 9.0  ## tiles around the cursor where the grid is brightest
const OK_COLOR := Color(0.45, 1.0, 0.5, 0.55)
const BAD_COLOR := Color(1.0, 0.35, 0.3, 0.55)
const POWER_COLOR := Color(0.35, 0.65, 1.0, 0.10)

var game: Game


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not game.started:
		return
	if game.is_placing():
		_draw_grid()
		_draw_ghost()
	elif game.holding_tool():
		_draw_repair()
	else:
		_draw_hover()
	_draw_mining()


## The grid only appears while placing: faint across the screen, brighter near the cursor.
func _draw_grid() -> void:
	var view := game.world.visible_cells()
	var t := float(World.TILE)
	var top := view.position.y * t
	var bottom := view.end.y * t
	var left := view.position.x * t
	var right := view.end.x * t
	var faint := Color(1, 1, 1, 0.05)
	for x in range(view.position.x, view.end.x + 1):
		draw_line(Vector2(x * t, top), Vector2(x * t, bottom), faint, 1.0)
	for y in range(view.position.y, view.end.y + 1):
		draw_line(Vector2(left, y * t), Vector2(right, y * t), faint, 1.0)
	var mouse := game.get_global_mouse_position() / t
	var r := int(GRID_RADIUS)
	var mc := game.mouse_cell
	for y in range(mc.y - r, mc.y + r + 2):
		for x in range(mc.x - r, mc.x + r + 2):
			# One horizontal and one vertical edge per cell, faded by distance.
			var a_h := 0.32 * (1.0 - Vector2(x + 0.5, y).distance_to(mouse) / GRID_RADIUS)
			if a_h > 0.0:
				draw_line(Vector2(x, y) * t, Vector2(x + 1, y) * t, Color(1, 1, 1, a_h), 1.0)
			var a_v := 0.32 * (1.0 - Vector2(x, y + 0.5).distance_to(mouse) / GRID_RADIUS)
			if a_v > 0.0:
				draw_line(Vector2(x, y) * t, Vector2(x, y + 1) * t, Color(1, 1, 1, a_v), 1.0)


func _draw_ghost() -> void:
	var id := game.hand_item
	var dir := game.hand_dir
	var def: Dictionary = GameData.BUILDINGS[id]
	var origin := game.hand_origin()
	var fp := GameData.footprint(id, dir)
	var rect := Rect2(Vector2(origin * World.TILE), Vector2(fp * World.TILE))
	var ok := game.placement_problem(origin) == ""
	var tint := OK_COLOR if ok else BAD_COLOR

	# Electric things: show where power reaches.
	if def.has("power") or id == &"pole" or id == &"steam_engine":
		for pole in game.world.poles():
			_fill_cells(pole.supply_rect(), POWER_COLOR)
	if id == &"pole":
		var r: int = def["supply"]
		_fill_cells(Rect2i(origin - Vector2i(r, r), Vector2i(r * 2 + 1, r * 2 + 1)), Color(0.35, 0.65, 1.0, 0.18))
		var anchor := rect.get_center() + Vector2(0, -29)
		for pole in game.world.poles():
			if Vector2(pole.cell - origin).length() <= def["reach"]:
				draw_line(anchor, pole.wire_anchor(), Color(0.9, 0.6, 0.3, 0.8), 1.5)
	if def.has("mining_speed"):
		var m: int = def["area_margin"]
		_outline_cells(Rect2i(origin - Vector2i(m, m), fp + Vector2i(m, m) * 2), Color(0.95, 0.85, 0.3, 0.8))

	draw_rect(rect, Color(tint, 0.18))
	var tex := GameData.sprite("belt_straight" if id == &"belt" else String(id))
	var offset: Vector2 = def.get("sprite_offset", Vector2.ZERO)
	var angle: float = dir * PI * 0.5 if def.get("rotatable", false) else 0.0
	draw_set_transform(rect.get_center(), angle)
	if id == &"belt" or id == &"pipe":
		# Strip textures: draw only the first frame.
		draw_texture_rect_region(tex, Rect2(-16, -16, 32, 32), Rect2(0, 0, 32, 32), Color(1, 1, 1, 0.65))
	else:
		draw_texture(tex, -tex.get_size() * 0.5 + offset, Color(1, 1, 1, 0.65))
	draw_set_transform(Vector2.ZERO)
	draw_rect(rect, tint, false, 2.0)

	if def.get("rotatable", false):
		_draw_arrow(rect.get_center(), Vector2(GameData.dir_vec(dir)), Color(1, 1, 1, 0.9))
	if id == &"inserter":
		_mark_cell(origin - GameData.dir_vec(dir), Color(0.4, 0.8, 1.0, 0.8))
		_mark_cell(origin + GameData.dir_vec(dir), Color(1.0, 0.75, 0.3, 0.8))
	if def.has("output"):
		_mark_cell(origin + GameData.rotate_local(def["output"], def["size"], dir), Color(1.0, 0.75, 0.3, 0.8))
	if def.get("needs_water_behind", false):
		_mark_cell(origin + GameData.rotate_local(Vector2i(0, 1), def["size"], dir), Color(0.4, 0.8, 1.0, 0.8))


func _draw_hover() -> void:
	var b := game.world.get_building(game.mouse_cell)
	if b == null:
		if game.world.ore_at(game.mouse_cell) != World.Ore.NONE:
			_corners(Rect2(Vector2(game.mouse_cell * World.TILE), Vector2(World.TILE, World.TILE)), Color(1, 1, 1, 0.6))
		return
	_corners(Rect2(Vector2(b.cell * World.TILE), Vector2(b.size * World.TILE)), Color(1, 1, 1, 0.9))
	if b is Inserter:
		_mark_cell((b as Inserter).pickup_cell(), Color(0.4, 0.8, 1.0, 0.8))
		_mark_cell((b as Inserter).drop_cell(), Color(1.0, 0.75, 0.3, 0.8))
	elif b is MiningDrill:
		var m: int = b.def["area_margin"]
		_outline_cells(Rect2i(b.cell - Vector2i(m, m), b.size + Vector2i(m, m) * 2), Color(0.95, 0.85, 0.3, 0.6))
		_mark_cell((b as MiningDrill).output_cell(), Color(1.0, 0.75, 0.3, 0.8))
	elif b is PowerPole:
		_fill_cells((b as PowerPole).supply_rect(), Color(0.35, 0.65, 1.0, 0.15))


## With a Repair Kit in hand: mark every worn machine on screen, and the target.
func _draw_repair() -> void:
	var view := game.world.visible_cells()
	for b in game.world.buildings:
		if b.needs_repair() and view.has_point(b.cell):
			var r := Rect2(Vector2(b.cell * World.TILE), Vector2(b.size * World.TILE))
			_corners(r, Color(1.0, 0.6, 0.2, 0.55))
	var hovered := game.world.get_building(game.mouse_cell)
	if hovered == null:
		return
	var rect := Rect2(Vector2(hovered.cell * World.TILE), Vector2(hovered.size * World.TILE))
	var color := Color(0.45, 1.0, 0.5, 0.9) if hovered.is_damaged() else Color(1, 1, 1, 0.5)
	_corners(rect, color)
	if game.repair_target == hovered:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(rect, Color(0.45, 1.0, 0.5, 0.12 + 0.1 * pulse))
		var c := rect.get_center()
		draw_arc(c, 14.0, -PI * 0.5, -PI * 0.5 + TAU * hovered.health_fraction(), 32, Color(0.45, 1.0, 0.5), 3.0)


func _draw_mining() -> void:
	if game.mine_progress <= 0.0 or game.mine_target == World.NO_CELL:
		return
	var c := World.cell_center(game.mine_target)
	draw_arc(c, 13.0, -PI * 0.5, -PI * 0.5 + TAU * game.mine_progress, 32, Color(1.0, 0.85, 0.3), 3.0)


func _fill_cells(r: Rect2i, color: Color) -> void:
	draw_rect(Rect2(Vector2(r.position * World.TILE), Vector2(r.size * World.TILE)), color)


func _outline_cells(r: Rect2i, color: Color) -> void:
	draw_rect(Rect2(Vector2(r.position * World.TILE), Vector2(r.size * World.TILE)), color, false, 1.5)


func _mark_cell(c: Vector2i, color: Color) -> void:
	draw_rect(Rect2(Vector2(c * World.TILE) + Vector2(4, 4), Vector2(24, 24)), color, false, 2.0)


func _corners(r: Rect2, color: Color) -> void:
	var l := 7.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_line(corner, corner + Vector2(l * sx, 0), color, 2.0)
		draw_line(corner, corner + Vector2(0, l * sy), color, 2.0)


func _draw_arrow(center: Vector2, d: Vector2, color: Color) -> void:
	var tip := center + d * 12.0
	var side := d.orthogonal() * 6.0
	draw_colored_polygon(PackedVector2Array([tip, center + side, center - side]), color)
