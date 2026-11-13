class_name Game
extends Node2D
## Game controller: owns the world, player, camera and HUD, and turns mouse
## and keyboard input into building, mining and UI actions.

const MAP_SEED := 20261030
const MINE_TIME_ORE := 0.6
const MINE_TIME_BUILDING := 0.35
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0

const STARTER_KIT := {&"burner_drill": 2, &"furnace": 2, &"coal": 10, &"iron_plate": 20}
const DEMO_KIT := {&"belt": 100, &"inserter": 20, &"pole": 10, &"burner_drill": 4, &"electric_drill": 4,
	&"furnace": 6, &"assembler": 3, &"chest": 6, &"pipe": 20, &"pump": 1, &"boiler": 1, &"steam_engine": 2,
	&"coal": 50, &"iron_plate": 100, &"copper_plate": 50, &"stone": 50, &"iron_gear": 20, &"circuit": 20,
	&"repair_kit": 10}

var world: World
var player: Player
var camera: Camera2D
var hud: Hud
var preview: BuildPreview
var hotbar := HotbarLayout.new()

var started := false
var hand_item: StringName = &""  ## building or tool in the hand, &"" for an empty hand
var hand_dir := 0
var hand_slot := -1  ## hotbar slot the hand was filled from, or -1
var mouse_cell := Vector2i.ZERO
var mine_target := World.NO_CELL
var mine_progress := 0.0  ## 0..1 for the current hand-mining action
var repair_target: Building = null  ## building being repaired this frame

var _drag_placing := false
var _last_drag_origin := World.NO_CELL
var _mining := false
var _repairing := false


func _ready() -> void:
	hotbar.load_saved()
	hotbar.changed.connect(_on_hotbar_changed)
	world = World.new()
	world.name = "World"
	world.auto_tick = false
	add_child(world)
	world.generate(MAP_SEED)

	player = Player.new()
	player.name = "Player"
	player.world = world
	player.z_index = 4
	player.position = World.cell_center(World.SPAWN)
	add_child(player)

	camera = Camera2D.new()
	camera.zoom = Vector2(1.4, 1.4)
	player.add_child(camera)
	camera.make_current()

	preview = BuildPreview.new()
	preview.game = self
	preview.z_index = 10
	add_child(preview)

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)

	if OS.get_cmdline_user_args().has("--demo"):
		start_game(true)
	else:
		hud.show_start_menu()


func start_game(demo: bool) -> void:
	if started:
		return
	started = true
	if demo:
		world.build_demo()
	var kit: Dictionary = DEMO_KIT if demo else STARTER_KIT
	for k in kit:
		player.inventory.force_add(k, kit[k])
	world.auto_tick = true
	hud.on_game_started(demo)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not started:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.12)
			MOUSE_BUTTON_LEFT:
				_on_left_click()
			MOUSE_BUTTON_RIGHT:
				_mining = true
				mine_progress = 0.0
		return
	if event.is_action_pressed(&"rotate"):
		_rotate(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
	elif event.is_action_pressed(&"pipette"):
		_pipette()
	elif event.is_action_pressed(&"inventory"):
		hud.toggle_inventory()
	elif event.is_action_pressed(&"help"):
		hud.toggle_help()
	elif event.is_action_pressed(&"close"):
		if not hud.close_top_window():
			set_hand(&"")
	elif event.is_action_pressed(&"cheat"):
		_cheat()
	else:
		for i in hotbar.size():
			if event.is_action_pressed(StringName("hotbar_%d" % i)):
				select_hotbar(i)
				break


func _process(delta: float) -> void:
	if not started:
		return
	mouse_cell = World.world_to_cell(get_global_mouse_position())
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_placing = false
		_repairing = false
		repair_target = null
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mining = false
		mine_progress = 0.0
		mine_target = World.NO_CELL
	if _drag_placing and is_placing():
		var origin := hand_origin()
		if origin != _last_drag_origin:
			_try_place(origin, false)
	if _repairing:
		_update_repair(delta)
	if _mining:
		_update_mining(delta)


func _zoom(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


# --- Hand / placing ----------------------------------------------------------

## Forget which slot the hand came from once that slot holds something else.
func _on_hotbar_changed() -> void:
	if hand_slot >= 0 and hotbar.get_item(hand_slot) != hand_item:
		hand_slot = -1


## Selects whatever is in slot i; selecting the same slot again (or an empty
## slot) empties the hand.
func select_hotbar(i: int) -> void:
	var id := hotbar.get_item(i)
	if id == &"" or (hand_item == id and hand_slot == i):
		set_hand(&"")
		return
	set_hand(id)
	hand_slot = i


func set_hand(id: StringName) -> void:
	if id != &"" and not (GameData.is_building_item(id) or GameData.is_tool(id)):
		return
	hand_item = id
	hand_slot = -1
	if id != &"" and player.inventory.count(id) <= 0:
		hud.toast("No %s in inventory - craft some first (E)" % GameData.item_name(id))


## True while holding a building to place (as opposed to a tool or nothing).
func is_placing() -> bool:
	return hand_item != &"" and GameData.is_building_item(hand_item)


func holding_tool() -> bool:
	return hand_item != &"" and GameData.is_tool(hand_item)


## Top-left cell of the held building, centred under the mouse.
func hand_origin() -> Vector2i:
	return World.origin_for(get_global_mouse_position(), GameData.footprint(hand_item, hand_dir))


func _on_left_click() -> void:
	if holding_tool():
		_repairing = true
		return
	if is_placing():
		_try_place(hand_origin(), true)
		_drag_placing = true
		return
	var b := world.get_building(mouse_cell)
	if b:
		hud.open_building(b)


## Why the held item can't go at `origin`, or "" if it can.
func placement_problem(origin: Vector2i) -> String:
	if player.inventory.count(hand_item) <= 0:
		return "None in inventory"
	var fp := GameData.footprint(hand_item, hand_dir)
	var area := Rect2(Vector2(origin * World.TILE), Vector2(fp * World.TILE))
	if not player.in_reach(area.get_center()):
		return "Out of reach"
	var reason := world.check_place(hand_item, origin, hand_dir)
	if reason == "" and GameData.BUILDINGS[hand_item].get("solid", false) and area.intersects(player.collision_rect()):
		return "You are standing there"
	return reason


func _try_place(origin: Vector2i, verbose: bool) -> void:
	_last_drag_origin = origin
	# Same 1x1 building already there: just turn it to face the hand direction.
	var existing := world.get_building(origin)
	if existing and existing.id == hand_item and existing.size == Vector2i.ONE:
		if existing.dir != hand_dir:
			world.rotate_building(existing, hand_dir - existing.dir)
		return
	var problem := placement_problem(origin)
	if problem != "":
		if verbose:
			hud.toast(problem)
		return
	var b := world.place(hand_item, origin, hand_dir)
	if b:
		# A machine that was picked up damaged goes back down damaged.
		b.health = b.max_health() * player.take_worn(hand_item)
		player.inventory.remove(hand_item, 1)


func _rotate(steps: int) -> void:
	if is_placing():
		hand_dir = posmod(hand_dir + steps, 4)
		return
	var b := world.get_building(mouse_cell)
	if b and not world.rotate_building(b, steps) and b.def.get("rotatable", false):
		hud.toast("Pick it up to rotate a non-square building")


## Q: pick the hovered building type into the hand, or empty the hand.
func _pipette() -> void:
	var b := world.get_building(mouse_cell)
	if hand_item != &"" or b == null:
		set_hand(&"")
		return
	set_hand(b.id)
	hand_dir = b.dir


# --- Mining ------------------------------------------------------------------

func _update_mining(delta: float) -> void:
	var b := world.get_building(mouse_cell)
	if b == null and world.ore_at(mouse_cell) == World.Ore.NONE:
		mine_progress = 0.0
		mine_target = World.NO_CELL
		return
	if not player.in_reach(World.cell_center(mouse_cell)):
		mine_progress = 0.0
		return
	if mouse_cell != mine_target:
		mine_target = mouse_cell
		mine_progress = 0.0
	mine_progress += delta / (MINE_TIME_BUILDING if b else MINE_TIME_ORE)
	if mine_progress < 1.0:
		return
	mine_progress = 0.0
	if b:
		pick_up(b)
		return
	var item := world.ore_item_at(mouse_cell)
	if player.inventory.space_for(item) <= 0:
		hud.toast("Inventory full")
		return
	world.mine_ore(mouse_cell)
	player.inventory.add(item, 1)
	GameData.add_stat(&"hand_mined")


# --- Repairing ---------------------------------------------------------------

func _update_repair(delta: float) -> void:
	repair_target = null
	var b := world.get_building(mouse_cell)
	if b == null or not b.is_damaged():
		return
	if not player.in_reach(World.cell_center(mouse_cell)):
		hud.toast("Out of reach")
		return
	if player.repair_health_left() <= 0.0:
		hud.toast("Out of Repair Kits - craft some (E)")
		_repairing = false
		return
	repair_target = b
	player.repair(b, delta)


## Removes a building and returns it (and everything inside it) to the inventory.
func pick_up(b: Building) -> void:
	if b.is_damaged():
		player.add_worn(b.id, b.health_fraction())
	var items := b.contents()
	items[b.id] = items.get(b.id, 0) + 1
	for k in items:
		player.inventory.force_add(k, items[k])
	world.remove_building(b)


func _cheat() -> void:
	for id in GameData.BUILDINGS.keys() + [&"repair_kit"]:
		player.inventory.force_add(id, 20)
	for id in [&"iron_plate", &"copper_plate", &"coal", &"stone", &"iron_gear", &"circuit"]:
		player.inventory.force_add(id, 100)
	hud.toast("Sandbox: added 20 of every building and 100 of each material")
