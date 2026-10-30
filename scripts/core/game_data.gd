extends Node
## Static game definitions (items, recipes, buildings), shared helpers,
## texture cache, input map and progress stats. Autoloaded as `GameData`.

signal stats_changed

const TILE := 32
const DIR_VEC := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES := ["North", "East", "South", "West"]

## Every item in the game. Items with "building" place the building of the same id.
const ITEMS := {
	# Raw resources
	&"iron_ore": {"name": "Iron Ore", "stack": 50, "desc": "Smelt in a furnace to get Iron Plates."},
	&"copper_ore": {"name": "Copper Ore", "stack": 50, "desc": "Smelt in a furnace to get Copper Plates."},
	&"coal": {"name": "Coal", "stack": 50, "fuel": 4.0e6, "desc": "Fuel (4 MJ) for burner drills, furnaces and boilers."},
	&"stone": {"name": "Stone", "stack": 50, "desc": "Builds furnaces. Smelts into Stone Bricks."},
	# Intermediates
	&"iron_plate": {"name": "Iron Plate", "stack": 100, "desc": "Basic building material."},
	&"copper_plate": {"name": "Copper Plate", "stack": 100, "desc": "Made into Copper Wire."},
	&"stone_brick": {"name": "Stone Brick", "stack": 100, "desc": "Used to build Boilers."},
	&"iron_gear": {"name": "Iron Gear", "stack": 100, "desc": "Mechanical component."},
	&"copper_wire": {"name": "Copper Wire", "stack": 200, "desc": "Used in circuits and power poles."},
	&"circuit": {"name": "Circuit Board", "stack": 200, "desc": "Electronics for machines and inserters."},
	# Buildings
	&"belt": {"name": "Conveyor Belt", "stack": 100, "building": true,
		"desc": "Moves items in the direction of its arrows. Hold the mouse to drag a line."},
	&"inserter": {"name": "Inserter Arm", "stack": 50, "building": true,
		"desc": "Grabs items from the tile behind it and drops them on the tile in front. Needs power."},
	&"burner_drill": {"name": "Burner Drill", "stack": 50, "building": true,
		"desc": "Mines the 2x2 ore under it and outputs to the front-left tile. Burns coal."},
	&"electric_drill": {"name": "Electric Drill", "stack": 50, "building": true,
		"desc": "Mines a 5x5 area twice as fast as a burner drill and outputs to the front. Needs power."},
	&"furnace": {"name": "Stone Furnace", "stack": 50, "building": true,
		"desc": "Smelts ore into plates and stone into bricks. Burns coal."},
	&"chest": {"name": "Storage Chest", "stack": 50, "building": true, "desc": "Stores 16 stacks of items."},
	&"pipe": {"name": "Pipe", "stack": 100, "building": true, "desc": "Carries water or steam between connected buildings."},
	&"pump": {"name": "Water Pump", "stack": 20, "building": true,
		"desc": "Place on the shore with water directly behind it. Pumps 1200 water/s out the front."},
	&"boiler": {"name": "Boiler", "stack": 20, "building": true,
		"desc": "Burns coal to turn water (side connections) into steam (front connection)."},
	&"steam_engine": {"name": "Steam Engine", "stack": 20, "building": true,
		"desc": "Turns steam into up to 900 kW of electricity. Connections at both ends, so engines chain."},
	&"pole": {"name": "Power Pole", "stack": 50, "building": true,
		"desc": "Powers machines in a 7x7 area and wires itself to poles up to 8 tiles away."},
	&"assembler": {"name": "Assembler", "stack": 50, "building": true,
		"desc": "Crafts the selected recipe automatically. Needs power."},
}

const FLUIDS := {
	&"water": {"name": "Water", "color": Color(0.25, 0.55, 0.95)},
	&"steam": {"name": "Steam", "color": Color(0.92, 0.92, 0.95)},
}

## Recipes are keyed by the item they produce. "smelt" recipes only run in furnaces.
const RECIPES := {
	&"iron_plate": {"in": {&"iron_ore": 1}, "count": 1, "time": 3.2, "smelt": true},
	&"copper_plate": {"in": {&"copper_ore": 1}, "count": 1, "time": 3.2, "smelt": true},
	&"stone_brick": {"in": {&"stone": 2}, "count": 1, "time": 3.2, "smelt": true},
	&"iron_gear": {"in": {&"iron_plate": 2}, "count": 1, "time": 0.5},
	&"copper_wire": {"in": {&"copper_plate": 1}, "count": 2, "time": 0.5},
	&"circuit": {"in": {&"iron_plate": 1, &"copper_wire": 3}, "count": 1, "time": 0.5},
	&"belt": {"in": {&"iron_plate": 1, &"iron_gear": 1}, "count": 2, "time": 0.5},
	&"inserter": {"in": {&"circuit": 1, &"iron_gear": 1, &"iron_plate": 1}, "count": 1, "time": 0.5},
	&"burner_drill": {"in": {&"iron_gear": 3, &"iron_plate": 3, &"stone": 5}, "count": 1, "time": 2.0},
	&"electric_drill": {"in": {&"circuit": 3, &"iron_gear": 5, &"iron_plate": 10}, "count": 1, "time": 2.0},
	&"furnace": {"in": {&"stone": 5}, "count": 1, "time": 0.5},
	&"chest": {"in": {&"iron_plate": 8}, "count": 1, "time": 0.5},
	&"pipe": {"in": {&"iron_plate": 1}, "count": 1, "time": 0.5},
	&"pump": {"in": {&"circuit": 2, &"pipe": 1, &"iron_gear": 1}, "count": 1, "time": 0.5},
	&"boiler": {"in": {&"stone_brick": 5, &"pipe": 4}, "count": 1, "time": 0.5},
	&"steam_engine": {"in": {&"iron_gear": 8, &"pipe": 5, &"iron_plate": 10}, "count": 1, "time": 0.5},
	&"pole": {"in": {&"iron_plate": 1, &"copper_wire": 2}, "count": 2, "time": 0.5},
	&"assembler": {"in": {&"circuit": 3, &"iron_gear": 5, &"iron_plate": 9}, "count": 1, "time": 0.5},
}

const _ENTITY_DIR := "res://scripts/entities/"

## Building definitions. Sizes are for the north-facing orientation.
## power/drain: electric draw in W while working / idle. fuel_power: burner draw in W.
const BUILDINGS := {
	&"belt": {"script": _ENTITY_DIR + "belt.gd", "size": Vector2i(1, 1), "rotatable": true, "z": 0},
	&"inserter": {"script": _ENTITY_DIR + "inserter.gd", "size": Vector2i(1, 1), "rotatable": true, "z": 3,
		"power": 13000.0, "drain": 400.0},
	&"burner_drill": {"script": _ENTITY_DIR + "mining_drill.gd", "size": Vector2i(2, 2), "rotatable": true,
		"solid": true, "fuel_power": 150000.0, "mining_speed": 0.25, "area_margin": 0,
		"output": Vector2i(0, -1), "head": Vector2(0, 2)},
	&"electric_drill": {"script": _ENTITY_DIR + "mining_drill.gd", "size": Vector2i(3, 3), "rotatable": true,
		"solid": true, "power": 90000.0, "drain": 3000.0, "mining_speed": 0.5, "area_margin": 1,
		"output": Vector2i(1, -1), "head": Vector2(0, 2)},
	&"furnace": {"script": _ENTITY_DIR + "furnace.gd", "size": Vector2i(2, 2), "solid": true,
		"fuel_power": 90000.0, "speed": 1.0},
	&"assembler": {"script": _ENTITY_DIR + "assembler.gd", "size": Vector2i(3, 3), "solid": true,
		"power": 75000.0, "drain": 2500.0, "speed": 0.75},
	&"chest": {"script": _ENTITY_DIR + "chest.gd", "size": Vector2i(1, 1), "slots": 16},
	&"pipe": {"script": _ENTITY_DIR + "pipe.gd", "size": Vector2i(1, 1), "z": 0},
	&"pump": {"script": _ENTITY_DIR + "offshore_pump.gd", "size": Vector2i(1, 1), "rotatable": true,
		"rate": 1200.0, "needs_water_behind": true},
	&"boiler": {"script": _ENTITY_DIR + "boiler.gd", "size": Vector2i(3, 2), "rotatable": true, "solid": true,
		"fuel_power": 1.8e6, "steam_rate": 60.0},
	&"steam_engine": {"script": _ENTITY_DIR + "steam_engine.gd", "size": Vector2i(3, 3), "rotatable": true,
		"solid": true, "max_power": 900000.0, "steam_rate": 30.0},
	&"pole": {"script": _ENTITY_DIR + "power_pole.gd", "size": Vector2i(1, 1), "z": 5,
		"supply": 3, "reach": 8.0, "sprite_offset": Vector2(0, -12)},
}

## Order of the hotbar (keys 1-0, -, =).
const HOTBAR := [&"belt", &"inserter", &"burner_drill", &"electric_drill", &"furnace", &"chest",
	&"pole", &"pipe", &"pump", &"boiler", &"steam_engine", &"assembler"]

const OBJECTIVES := [
	{"text": "Mine 10 ore by hand (hold right mouse)", "stat": &"hand_mined", "goal": 10},
	{"text": "Hand-craft a Burner Drill (E)", "stat": &"crafted:burner_drill", "goal": 1},
	{"text": "Smelt 50 Iron Plates", "stat": &"made:iron_plate", "goal": 50},
	{"text": "Generate 5 MJ of electricity", "stat": &"energy_mj", "goal": 5},
	{"text": "Assemble 20 Iron Gears", "stat": &"assembled:iron_gear", "goal": 20},
	{"text": "Assemble 10 Circuit Boards", "stat": &"assembled:circuit", "goal": 10},
]

var stats: Dictionary = {}
var _tex_cache: Dictionary = {}
var _item_order: Dictionary = {}


func _ready() -> void:
	var i := 0
	for id in ITEMS:
		_item_order[id] = i
		i += 1
	_setup_input()


# --- Lookups -----------------------------------------------------------------

func dir_vec(d: int) -> Vector2i:
	return DIR_VEC[posmod(d, 4)]


func item_name(id: StringName) -> String:
	if ITEMS.has(id):
		return ITEMS[id]["name"]
	if FLUIDS.has(id):
		return FLUIDS[id]["name"]
	return String(id)


func stack_size(id: StringName) -> int:
	return ITEMS[id]["stack"] if ITEMS.has(id) else 50


func item_order(id: StringName) -> int:
	return _item_order.get(id, 999)


func is_fuel(id: StringName) -> bool:
	return ITEMS.has(id) and ITEMS[id].has("fuel")


func fuel_value(id: StringName) -> float:
	return ITEMS[id].get("fuel", 0.0) if ITEMS.has(id) else 0.0


func is_building_item(id: StringName) -> bool:
	return BUILDINGS.has(id)


func is_handcraftable(id: StringName) -> bool:
	return RECIPES.has(id) and not RECIPES[id].get("smelt", false)


func crafting_recipes() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in RECIPES:
		if not RECIPES[r].get("smelt", false):
			out.append(r)
	return out


func smelting_recipe_for(input: StringName) -> StringName:
	for r in RECIPES:
		if RECIPES[r].get("smelt", false) and RECIPES[r]["in"].has(input):
			return r
	return &""


## Footprint of a building after rotation.
func footprint(id: StringName, dir: int) -> Vector2i:
	var def: Dictionary = BUILDINGS[id]
	var s: Vector2i = def["size"]
	if def.get("rotatable", false) and dir % 2 == 1:
		return Vector2i(s.y, s.x)
	return s


## Maps a cell offset given for the north-facing footprint `s` onto the rotated footprint.
## Works for offsets outside the footprint too (connection points, output tiles).
func rotate_local(p: Vector2i, s: Vector2i, dir: int) -> Vector2i:
	match dir:
		1:
			return Vector2i(s.y - 1 - p.y, p.x)
		2:
			return Vector2i(s.x - 1 - p.x, s.y - 1 - p.y)
		3:
			return Vector2i(p.y, s.x - 1 - p.x)
	return p


# --- Text --------------------------------------------------------------------

func format_power(watts: float) -> String:
	if watts >= 1.0e6:
		return "%.2f MW" % (watts / 1.0e6)
	if watts >= 1000.0:
		return "%.0f kW" % (watts / 1000.0)
	return "%.0f W" % watts


func recipe_text(r: StringName) -> String:
	var rec: Dictionary = RECIPES[r]
	var parts := PackedStringArray()
	var ins: Dictionary = rec["in"]
	for k in ins:
		parts.append("%d %s" % [ins[k], item_name(k)])
	return "%s  ->  %d %s  (%.1fs)" % [", ".join(parts), rec["count"], item_name(r), rec["time"]]


func tooltip(id: StringName) -> String:
	var lines := PackedStringArray([item_name(id)])
	if ITEMS.has(id) and ITEMS[id].has("desc"):
		lines.append(ITEMS[id]["desc"])
	if RECIPES.has(id):
		var where := "Furnace" if RECIPES[id].get("smelt", false) else "Hand / Assembler"
		lines.append("Recipe (%s): %s" % [where, recipe_text(id)])
	return "\n".join(lines)


# --- Textures ----------------------------------------------------------------

func texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


func icon(id: StringName) -> Texture2D:
	return texture("res://assets/icons/%s.png" % id)


func sprite(sprite_name: String) -> Texture2D:
	return texture("res://assets/sprites/%s.png" % sprite_name)


# --- Stats / objectives ------------------------------------------------------

func add_stat(key: StringName, amount: float = 1.0) -> void:
	stats[key] = stats.get(key, 0.0) + amount
	stats_changed.emit()


func stat(key: StringName) -> float:
	return stats.get(key, 0.0)


# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	_bind(&"move_up", [KEY_W, KEY_UP])
	_bind(&"move_down", [KEY_S, KEY_DOWN])
	_bind(&"move_left", [KEY_A, KEY_LEFT])
	_bind(&"move_right", [KEY_D, KEY_RIGHT])
	_bind(&"rotate", [KEY_R])
	_bind(&"pipette", [KEY_Q])
	_bind(&"inventory", [KEY_E, KEY_TAB])
	_bind(&"help", [KEY_H, KEY_F1])
	_bind(&"close", [KEY_ESCAPE])
	_bind(&"cheat", [KEY_F9])
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
	for i in keys.size():
		_bind(StringName("hotbar_%d" % i), [keys[i]])


func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
