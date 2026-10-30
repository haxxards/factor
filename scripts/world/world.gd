class_name World
extends Node2D
## The map grid: terrain, ore, buildings, and the fixed-rate simulation tick.

signal structure_changed

const W := 128
const H := 96
const TILE := 32
const SPAWN := Vector2i(68, 49)
const NO_CELL := Vector2i(-9999, -9999)

enum Terrain { GRASS, WATER, SAND }
enum Ore { NONE, IRON, COPPER, COAL, STONE }
const ORE_ITEMS := [&"", &"iron_ore", &"copper_ore", &"coal", &"stone"]

var terrain := PackedByteArray()
var ore_type := PackedByteArray()
var ore_amount := PackedInt32Array()
var occupancy: Dictionary = {}  ## Vector2i -> Building
var buildings: Array[Building] = []
var belts: Array[Belt] = []
var belt_order: Array[Belt] = []
var belts_dirty := true
var power := PowerSystem.new()
var fluids := FluidSystem.new()
var auto_tick := true  ## tests step the world manually
var tick_count := 0

var terrain_layer: TileMapLayer
var ore_layer: TileMapLayer
var building_root: Node2D
var belt_renderer: BeltRenderer
var item_overlay: BeltItemOverlay
var wire_layer: WireLayer
var _poles: Array[PowerPole] = []


func _ready() -> void:
	terrain_layer = _make_layer(GameData.sprite("terrain"), -20)
	ore_layer = _make_layer(GameData.sprite("ores"), -19)
	belt_renderer = BeltRenderer.new()
	belt_renderer.world = self
	belt_renderer.z_index = 0
	add_child(belt_renderer)
	building_root = Node2D.new()
	building_root.name = "Buildings"
	add_child(building_root)
	item_overlay = BeltItemOverlay.new()
	item_overlay.world = self
	item_overlay.z_index = 2
	add_child(item_overlay)
	wire_layer = WireLayer.new()
	wire_layer.world = self
	wire_layer.z_index = 6
	add_child(wire_layer)


func _exit_tree() -> void:
	fluids.clear()


func _make_layer(atlas: Texture2D, z: int) -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = Vector2i(TILE, TILE)
	for y in atlas.get_height() / TILE:
		for x in atlas.get_width() / TILE:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.z_index = z
	add_child(layer)
	return layer


func _physics_process(delta: float) -> void:
	if auto_tick:
		step(delta)


## One simulation tick. Order: rebuild changed networks, settle power,
## run machines, then move belts downstream-first.
func step(dt: float) -> void:
	if belts_dirty:
		_rebuild_belts()
	if fluids.dirty:
		fluids.rebuild(self)
	if power.dirty:
		power.rebuild(self)
		wire_layer.queue_redraw()
	power.update(dt)
	for b in buildings:
		if not b is Belt:
			b.tick(dt)
	for belt in belt_order:
		belt.move_items(dt)
	tick_count += 1
	if tick_count % 15 == 0:
		# Lets idle buildings blink their status icons.
		for b in buildings:
			if not b is Belt and (b.drawn_icon != "" or b.status_icon() != ""):
				b.queue_redraw()


# --- Map queries -------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and terrain[c.y * W + c.x] == Terrain.WATER


func ore_at(c: Vector2i) -> int:
	return ore_type[c.y * W + c.x] if in_bounds(c) else Ore.NONE


func ore_amount_at(c: Vector2i) -> int:
	return ore_amount[c.y * W + c.x] if in_bounds(c) else 0


func ore_item_at(c: Vector2i) -> StringName:
	return ORE_ITEMS[ore_at(c)]


func get_building(c: Vector2i) -> Building:
	return occupancy.get(c)


func poles() -> Array[PowerPole]:
	return _poles


## Whether the player can't walk through this tile.
func is_blocking(c: Vector2i) -> bool:
	if not in_bounds(c) or is_water(c):
		return true
	var b := get_building(c)
	return b != null and b.def.get("solid", false)


static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c * TILE) + Vector2(TILE, TILE) * 0.5


## Cells currently on screen (with a margin), for culling.
func visible_cells() -> Rect2i:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var vr := get_viewport().get_visible_rect()
	var a: Vector2 = inv * vr.position
	var b: Vector2 = inv * vr.end
	var lo := Vector2i(floori(a.x / TILE) - 2, floori(a.y / TILE) - 2)
	var hi := Vector2i(ceili(b.x / TILE) + 2, ceili(b.y / TILE) + 2)
	return Rect2i(lo, hi - lo)


## Removes one unit of ore and returns the item, or &"" if there is none.
func mine_ore(c: Vector2i) -> StringName:
	if not in_bounds(c):
		return &""
	var i := c.y * W + c.x
	var t := ore_type[i]
	if t == Ore.NONE:
		return &""
	ore_amount[i] -= 1
	if ore_amount[i] <= 0:
		ore_type[i] = Ore.NONE
		ore_amount[i] = 0
		ore_layer.erase_cell(c)
	return ORE_ITEMS[t]


# --- Building placement ------------------------------------------------------

## Top-left cell for a building of footprint `fp` centred under a world position.
static func origin_for(world_pos: Vector2, fp: Vector2i) -> Vector2i:
	var p := world_pos / TILE - Vector2(fp) * 0.5 + Vector2(0.5, 0.5)
	return Vector2i(floori(p.x), floori(p.y))


## Returns "" if the building can be placed, otherwise the reason it can't.
func check_place(id: StringName, origin: Vector2i, dir: int) -> String:
	var def: Dictionary = GameData.BUILDINGS[id]
	var fp := GameData.footprint(id, dir)
	for y in fp.y:
		for x in fp.x:
			var c := origin + Vector2i(x, y)
			if not in_bounds(c):
				return "Outside the map"
			if is_water(c):
				return "Can't build on water"
			if occupancy.has(c):
				return "Something is in the way"
	if def.get("needs_water_behind", false):
		var behind := origin + GameData.rotate_local(Vector2i(0, 1), def["size"], dir)
		if not is_water(behind):
			return "Needs water directly behind it (output faces away from the water)"
	return ""


func place(id: StringName, origin: Vector2i, dir: int) -> Building:
	if check_place(id, origin, dir) != "":
		return null
	var script: GDScript = load(GameData.BUILDINGS[id]["script"])
	var b: Building = script.new()
	b.name = "%s_%d_%d" % [id, origin.x, origin.y]
	b.setup(self, id, origin, dir)
	building_root.add_child(b)
	for c in b.cells():
		occupancy[c] = b
	buildings.append(b)
	if b is Belt:
		belts.append(b)
	if b is PowerPole:
		_poles.append(b)
		power.connect_pole(b as PowerPole, _poles)
	_mark_dirty()
	return b


func remove_building(b: Building) -> void:
	for c in b.cells():
		occupancy.erase(c)
	buildings.erase(b)
	if b is Belt:
		belts.erase(b)
	if b is PowerPole:
		power.disconnect_pole(b)
		_poles.erase(b)
	_mark_dirty()
	b.queue_free()


## Rotates a square building in place.
func rotate_building(b: Building, steps: int = 1) -> bool:
	if not b.def.get("rotatable", false) or b.size.x != b.size.y:
		return false
	b.dir = posmod(b.dir + steps, 4)
	b.queue_redraw()
	_mark_dirty()
	return true


func _mark_dirty() -> void:
	belts_dirty = true
	fluids.dirty = true
	power.dirty = true
	wire_layer.queue_redraw()
	structure_changed.emit()


## Relinks belts and orders them so every belt moves before the belt feeding it.
func _rebuild_belts() -> void:
	belts_dirty = false
	for belt in belts:
		belt.refresh_links()
	belt_order.clear()
	var visited := {}
	for start in belts:
		var chain: Array[Belt] = []
		var cur := start
		while cur != null and not visited.has(cur):
			visited[cur] = true
			chain.append(cur)
			cur = cur.next_belt
		for i in range(chain.size() - 1, -1, -1):
			belt_order.append(chain[i])


# --- Map generation ----------------------------------------------------------

func generate(seed_value: int) -> void:
	var n := W * H
	terrain.resize(n)
	terrain.fill(Terrain.GRASS)
	ore_type.resize(n)
	ore_type.fill(Ore.NONE)
	ore_amount.resize(n)
	ore_amount.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.045
	for y in H:
		for x in W:
			if Vector2(x, y).distance_to(Vector2(SPAWN)) > 27.0 and noise.get_noise_2d(x, y) > 0.36:
				terrain[y * W + x] = Terrain.WATER
	# Fixed starting area: a lake to the south and one patch of each resource nearby.
	_stamp_water(Vector2(64, 70), 7.0)
	_stamp_water(Vector2(60, 66.5), 3.6)
	_stamp_ore(Ore.IRON, Vector2(77, 37), 6.8, rng)
	_stamp_ore(Ore.COPPER, Vector2(84, 50), 4.5, rng)
	_stamp_ore(Ore.COAL, Vector2(66, 58), 4.5, rng)
	_stamp_ore(Ore.COAL, Vector2(50, 36), 5.0, rng)
	_stamp_ore(Ore.STONE, Vector2(47, 53), 4.5, rng)
	# Random patches further out.
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 500:
		tries += 1
		var c := Vector2(rng.randf_range(6, W - 6), rng.randf_range(6, H - 6))
		if c.distance_to(Vector2(SPAWN)) < 32.0:
			continue
		_stamp_ore(rng.randi_range(Ore.IRON, Ore.STONE), c, rng.randf_range(3.5, 6.5), rng)
		placed += 1
	_add_shores()
	_render_tiles()


func _stamp_water(center: Vector2, radius: float) -> void:
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			var c := Vector2i(x, y)
			if in_bounds(c) and Vector2(x, y).distance_to(center) <= radius:
				terrain[y * W + x] = Terrain.WATER
				ore_type[y * W + x] = Ore.NONE


func _stamp_ore(type: int, center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	for y in range(floori(center.y - radius) - 1, ceili(center.y + radius) + 2):
		for x in range(floori(center.x - radius) - 1, ceili(center.x + radius) + 2):
			var c := Vector2i(x, y)
			if not in_bounds(c) or is_water(c):
				continue
			var d := Vector2(x, y).distance_to(center) + rng.randf_range(-0.8, 0.8)
			if d > radius:
				continue
			var i := y * W + x
			ore_type[i] = type
			ore_amount[i] = int(lerpf(1800.0, 350.0, clampf(d / radius, 0.0, 1.0)))


func _add_shores() -> void:
	var sand: Array[int] = []
	for y in H:
		for x in W:
			if terrain[y * W + x] == Terrain.WATER:
				continue
			for d in 4:
				if is_water(Vector2i(x, y) + GameData.dir_vec(d)):
					sand.append(y * W + x)
					break
	for i in sand:
		terrain[i] = Terrain.SAND


func _render_tiles() -> void:
	terrain_layer.clear()
	ore_layer.clear()
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var i := y * W + x
			var h := absi(hash(c))
			match terrain[i]:
				Terrain.WATER:
					var deep := true
					for d in 4:
						if not is_water(c + GameData.dir_vec(d)) and in_bounds(c + GameData.dir_vec(d)):
							deep = false
					terrain_layer.set_cell(c, 0, Vector2i(5 if deep else 4, 0))
				Terrain.SAND:
					terrain_layer.set_cell(c, 0, Vector2i(6, 0))
				_:
					terrain_layer.set_cell(c, 0, Vector2i(h % 4, 0))
			if ore_type[i] != Ore.NONE:
				ore_layer.set_cell(c, 0, Vector2i(h % 3, ore_type[i] - 1))


# --- Demo factory ------------------------------------------------------------

## Pre-builds a small working factory that shows every mechanic:
## water -> boiler -> steam engines -> poles, coal drill fuelling the boiler,
## electric iron drills -> belt -> inserters -> furnaces -> belt -> gear assembler,
## and a burner copper drill -> furnace -> wire assembler -> circuit assembler.
func build_demo() -> void:
	# Power plant on the north shore of the lake.
	_demo(&"pump", 60, 62)
	for y in [61, 60, 59]:
		_demo(&"pipe", 60, y)
	var boiler := _demo(&"boiler", 61, 58) as Boiler
	boiler.burner.add(&"coal", 20)
	_demo(&"steam_engine", 61, 55)
	_demo(&"steam_engine", 61, 52)
	_demo(&"electric_drill", 64, 57, 3)  # mines coal straight into the boiler

	# Iron: three electric drills -> ore belt -> three furnaces -> plate belt.
	for x in [73, 76, 79]:
		_demo(&"electric_drill", x, 36, 2)
	for x in range(81, 67, -1):
		_demo(&"belt", x, 39, 3)
	for x in [69, 72, 75]:
		_demo(&"inserter", x, 40, 2)
		var furnace := _demo(&"furnace", x, 41) as Furnace
		furnace.burner.add(&"coal", 40)
		_demo(&"inserter", x, 43, 2)
	for x in range(76, 64, -1):
		_demo(&"belt", x, 44, 3)
	for y in [44, 45, 46]:
		_demo(&"belt", 64, y, 2)  # turns south, shows a curve
	_demo(&"inserter", 63, 46, 3)
	(_demo(&"assembler", 60, 45) as Assembler).set_recipe(&"iron_gear")
	_demo(&"inserter", 59, 46, 3)
	_demo(&"chest", 58, 46)

	# Copper: burner drill -> furnace -> wire assembler -> circuit assembler.
	(_demo(&"burner_drill", 82, 49, 3) as MiningDrill).burner.add(&"coal", 30)
	(_demo(&"furnace", 80, 49) as Furnace).burner.add(&"coal", 40)
	_demo(&"inserter", 79, 50, 3)
	(_demo(&"assembler", 76, 49) as Assembler).set_recipe(&"copper_wire")
	_demo(&"inserter", 75, 50, 3)
	(_demo(&"assembler", 72, 49) as Assembler).set_recipe(&"circuit")
	(_demo(&"chest", 73, 53) as Chest).inventory.add(&"iron_plate", 400)
	_demo(&"inserter", 73, 52, 0)
	_demo(&"inserter", 71, 50, 3)
	_demo(&"chest", 70, 50)

	# Power poles, placed in chain order so each wires to the previous ones.
	for p in [Vector2i(64, 55), Vector2i(65, 49), Vector2i(58, 48), Vector2i(66, 43),
			Vector2i(71, 40), Vector2i(77, 40), Vector2i(77, 47), Vector2i(72, 53)]:
		_demo(&"pole", p.x, p.y)


func _demo(id: StringName, x: int, y: int, dir: int = 0) -> Building:
	var b := place(id, Vector2i(x, y), dir)
	if b == null:
		push_error("Demo: could not place %s at %d,%d (%s)" % [id, x, y, check_place(id, Vector2i(x, y), dir)])
	return b
