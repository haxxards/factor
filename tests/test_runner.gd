extends Node
## Headless simulation tests. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with the number of failed checks (0 = success).

const DT := 1.0 / 60.0

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_belt_line()
	_test_belt_curve_and_sideload()
	_test_inserter_furnace_chest()
	_test_fluid_conflict()
	_test_handcrafting()
	_test_demo_factory()
	print("")
	if _failures == 0:
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d OF %d CHECKS FAILED" % [_failures, _checks])
	await get_tree().process_frame
	get_tree().quit(_failures)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


## A world with plain grass everywhere (no ore, no water), stepped manually.
func _flat_world() -> World:
	var w := World.new()
	w.auto_tick = false
	add_child(w)
	w.generate(1)
	w.terrain.fill(World.Terrain.GRASS)
	w.ore_type.fill(World.Ore.NONE)
	w.ore_amount.fill(0)
	return w


func _run(w: World, seconds: float) -> void:
	for i in int(seconds / DT):
		w.step(DT)


func _test_belt_line() -> void:
	print("Belt line")
	var w := _flat_world()
	for x in range(10, 15):
		w.place(&"belt", Vector2i(x, 10), 1)
	var first := w.get_building(Vector2i(10, 10)) as Belt
	var last := w.get_building(Vector2i(14, 10)) as Belt
	first.insert_at(&"iron_ore", 0.0)
	_run(w, 3.0)
	_check(last.item_ids.size() == 1 and is_equal_approx(last.item_pos[0], 1.0), "item travels to the end of a 5-tile belt and stops")
	# Keep feeding until the line is backed up; nothing may overlap or vanish.
	var fed := 1
	for i in 400:
		if first.insert_at(&"iron_ore", 0.0):
			fed += 1
		w.step(DT)
	var total := 0
	var spaced := true
	for x in range(10, 15):
		var b := w.get_building(Vector2i(x, 10)) as Belt
		total += b.item_ids.size()
		for j in range(1, b.item_pos.size()):
			if b.item_pos[j - 1] - b.item_pos[j] < Belt.GAP - 0.01:
				spaced = false
	_check(total == fed, "no items lost on a backed-up belt (%d fed, %d on belt)" % [fed, total])
	_check(spaced, "items keep their spacing when compressed")
	_check(total >= 18, "a full belt holds about 4 items per tile (%d on 5 tiles)" % total)
	w.queue_free()


func _test_belt_curve_and_sideload() -> void:
	print("Belt curve and side-loading")
	var w := _flat_world()
	w.place(&"belt", Vector2i(10, 10), 1)  # east, into the curve
	w.place(&"belt", Vector2i(11, 10), 2)  # south: fed from its right side, so it curves
	w.place(&"belt", Vector2i(11, 11), 2)
	w.step(DT)
	var corner := w.get_building(Vector2i(11, 10)) as Belt
	_check(corner.curve == 1, "belt fed only from the side becomes a curve")
	(w.get_building(Vector2i(10, 10)) as Belt).insert_at(&"coal", 0.0)
	_run(w, 2.0)
	_check((w.get_building(Vector2i(11, 11)) as Belt).item_ids.size() == 1, "item follows the curve")

	for x in range(20, 25):
		w.place(&"belt", Vector2i(x, 20), 1)
	w.place(&"belt", Vector2i(22, 19), 2)  # points into the side of the line
	w.step(DT)
	_check((w.get_building(Vector2i(22, 20)) as Belt).curve == 0, "belt with a straight feeder stays straight")
	(w.get_building(Vector2i(22, 19)) as Belt).insert_at(&"stone", 0.5)
	(w.get_building(Vector2i(20, 20)) as Belt).insert_at(&"coal", 0.0)
	_run(w, 4.0)
	var end := w.get_building(Vector2i(24, 20)) as Belt
	_check(end.item_ids.size() == 2, "side-loaded item merges into the line")
	w.queue_free()


func _test_inserter_furnace_chest() -> void:
	print("Inserter -> furnace -> inserter -> chest")
	var w := _flat_world()
	var src := w.place(&"chest", Vector2i(10, 20), 0) as Chest
	src.inventory.add(&"iron_ore", 10)
	src.inventory.add(&"coal", 5)
	var ins_a := w.place(&"inserter", Vector2i(11, 20), 1) as Inserter
	var furnace := w.place(&"furnace", Vector2i(12, 20), 0) as Furnace
	var ins_b := w.place(&"inserter", Vector2i(14, 20), 1) as Inserter
	var dst := w.place(&"chest", Vector2i(15, 20), 0) as Chest
	w.step(DT)
	# No power network in this test: power the arms directly.
	ins_a.power_satisfaction = 1.0
	ins_b.power_satisfaction = 1.0
	_run(w, 3.0)
	_check(furnace.burner.has_fuel() and furnace.input_count + (1 if furnace.recipe_id != &"" else 0) > 0,
		"inserter feeds both fuel and ore into the furnace")
	_run(w, 50.0)
	_check(dst.inventory.count(&"iron_plate") == 10, "all 10 ore smelted and moved to the output chest (%d)" % dst.inventory.count(&"iron_plate"))
	_check(src.inventory.count(&"iron_ore") == 0, "input chest emptied")
	w.queue_free()


func _test_fluid_conflict() -> void:
	print("Fluids")
	var w := _flat_world()
	for y in range(30, 33):
		for x in range(8, 14):
			w.terrain[y * World.W + x] = World.Terrain.WATER
	var pump := w.place(&"pump", Vector2i(10, 29), 0) as OffshorePump
	_check(pump != null, "pump placed with water behind it")
	_check(w.check_place(&"pump", Vector2i(20, 20), 0) != "", "pump refused away from water")
	w.place(&"pipe", Vector2i(10, 28), 0)
	var engine := w.place(&"steam_engine", Vector2i(9, 25), 0) as SteamEngine
	_run(w, 1.0)
	_check(engine.steam.pool.conflict, "connecting a water pipe straight to a steam engine blocks the pool")
	_check(engine.steam.current_amount() == 0.0, "no water leaks into the steam engine")
	w.queue_free()


func _test_handcrafting() -> void:
	print("Hand crafting")
	var w := _flat_world()
	var p := Player.new()
	p.world = w
	add_child(p)
	p.inventory.add(&"iron_plate", 10)
	_check(p.craftable_count(&"belt") == 3, "10 plates are enough for 3 belt crafts (gear first)")
	_check(p.queue_craft(&"belt", 1) == 1, "belt craft queued")
	_check(p.inventory.count(&"iron_plate") == 7, "ingredients for the gear and belt taken up front")
	_check(p.craft_queue.size() == 2, "gear queued as an intermediate before the belt")
	for i in 120:
		p.process_crafting(DT)
	_check(p.inventory.count(&"belt") == 2, "belt craft yields 2 belts")
	_check(p.inventory.count(&"iron_gear") == 0, "intermediate gear was consumed")
	p.inventory.add(&"copper_plate", 2)
	p.inventory.add(&"iron_plate", 0)
	_check(p.queue_craft(&"circuit", 1) == 1, "circuit craft queued from plates")
	_check(p.inventory.count(&"copper_wire") == 1, "leftover wire kept (2 crafts make 4, circuit uses 3)")
	_check(p.queue_craft(&"electric_drill", 1) == 0, "cannot craft without ingredients")
	p.queue_free()
	w.queue_free()


func _test_demo_factory() -> void:
	print("Demo factory (2 simulated minutes)")
	var w := World.new()
	w.auto_tick = false
	add_child(w)
	w.generate(Game.MAP_SEED)
	w.build_demo()
	_check(w.buildings.size() == 71, "every demo building placed (%d)" % w.buildings.size())
	var start := Time.get_ticks_msec()
	_run(w, 120.0)
	print("       (simulated 7200 ticks in %d ms)" % (Time.get_ticks_msec() - start))
	_check(w.power.networks.size() == 1, "all poles form one network")
	var net := w.power.networks[0]
	_check(net.generators.size() == 2, "both steam engines are connected")
	_check(net.satisfaction > 0.99, "power demand fully met (%.0f%%)" % (net.satisfaction * 100.0))
	_check(net.production > 0.0, "engines produce %s" % GameData.format_power(net.production))
	var boiler := w.get_building(Vector2i(61, 58)) as Boiler
	_check(boiler.burner.has_fuel(), "coal drill keeps the boiler fuelled")
	var gears := (w.get_building(Vector2i(58, 46)) as Chest).inventory.count(&"iron_gear")
	_check(gears > 10, "gear chest filled by the iron line (%d gears)" % gears)
	var circuits := (w.get_building(Vector2i(70, 50)) as Chest).inventory.count(&"circuit")
	_check(circuits > 5, "circuit chest filled by the copper line (%d circuits)" % circuits)
	var plates := 0
	for x in [69, 72, 75]:
		plates += 1 if (w.get_building(Vector2i(x, 41)) as Furnace).burner.has_fuel() else 0
	_check(plates == 3, "all iron furnaces still have fuel")
	_check(GameData.stat(&"made:iron_plate") > 40, "iron plates smelted (%d)" % GameData.stat(&"made:iron_plate"))
	w.queue_free()
