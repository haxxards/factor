class_name MiningDrill
extends Building
## Mines ore under its area and pushes it to the output tile (a belt, or any
## building that accepts it). Burner or electric depending on its definition.

const OUTPUT_CAP := 10

var burner: BurnerFuel = null
var progress := 0.0
var output: Array[StringName] = []  ## mined ore waiting to be delivered
var area: Array[Vector2i] = []
var area_index := 0
var working := false


func _init_building() -> void:
	if def.has("fuel_power"):
		burner = BurnerFuel.new()
	var m: int = def["area_margin"]
	for y in range(-m, size.y + m):
		for x in range(-m, size.x + m):
			area.append(cell + Vector2i(x, y))


func output_cell() -> Vector2i:
	return to_world_cell(def["output"])


func get_power_demand() -> float:
	return def["power"] if working else def["drain"]


func ore_remaining() -> int:
	var total := 0
	for c in area:
		total += world.ore_amount_at(c)
	return total


func tick(dt: float) -> void:
	_flush_output()
	working = false
	if output.size() >= OUTPUT_CAP:
		status = "Output blocked"
		return
	var ore_cell := _next_ore_cell()
	if ore_cell == World.NO_CELL:
		status = "No resources left"
		return
	var eff := power_satisfaction
	if burner:
		eff = burner.consume(def["fuel_power"] * dt)
	if eff <= 0.0:
		status = "No fuel" if burner else "No power"
		return
	working = true
	status = "Mining"
	anim_time += dt * eff
	wear(dt * eff)
	progress += def["mining_speed"] * dt * eff
	if progress >= 1.0:
		progress -= 1.0
		var item := world.mine_ore(ore_cell)
		if item != &"":
			output.append(item)
			area_index += 1
		_flush_output()
	queue_redraw()


func _next_ore_cell() -> Vector2i:
	for i in area.size():
		var c := area[(area_index + i) % area.size()]
		if world.ore_amount_at(c) > 0:
			area_index = (area_index + i) % area.size()
			return c
	return World.NO_CELL


func _flush_output() -> void:
	while not output.is_empty():
		var target := world.get_building(output_cell())
		if target == null:
			return
		var item := output[0]
		var ok := false
		if target is Belt:
			ok = (target as Belt).insert_at(item, 0.5)
		elif target.can_accept(item):
			ok = target.accept(item)
		if not ok:
			return
		output.remove_at(0)


func can_accept(item: StringName) -> bool:
	return burner != null and burner.can_accept(item, BurnerFuel.AUTO_LIMIT)


func accept(item: StringName) -> bool:
	return burner != null and burner.add(item, 1, BurnerFuel.AUTO_LIMIT) == 1


func insert_priority(item: StringName) -> int:
	return 1 if burner and GameData.is_fuel(item) and burner.count == 0 else 0


func takeable_items() -> Array[StringName]:
	var out: Array[StringName] = []
	if not output.is_empty():
		out.append(output[0])
	return out


func take(item: StringName) -> bool:
	var i := output.find(item)
	if i < 0:
		return false
	output.remove_at(i)
	return true


func _on_broken() -> void:
	working = false


func status_icon() -> String:
	if burner and not burner.has_fuel():
		return "no_fuel"
	if not burner and power_satisfaction <= 0.0:
		return "no_power"
	return ""


func contents() -> Dictionary:
	var out := {}
	for item in output:
		out[item] = out.get(item, 0) + 1
	if burner and burner.count > 0:
		out[burner.item] = out.get(burner.item, 0) + burner.count
	return out


func ui_slots() -> Array:
	var slots := []
	if burner:
		slots.append({"key": "fuel", "label": "Fuel", "item": burner.item, "count": burner.count})
	var first: StringName = output[0] if not output.is_empty() else &""
	slots.append({"key": "output", "label": "Output", "item": first, "count": output.size()})
	return slots


func ui_take(key: String) -> Dictionary:
	if key == "fuel" and burner:
		return burner.take_all()
	var out := {}
	if key == "output":
		for item in output:
			out[item] = out.get(item, 0) + 1
		output.clear()
	return out


func ui_accepts(item: StringName) -> bool:
	return burner != null and burner.can_accept(item)


func ui_insert(item: StringName, count: int) -> int:
	return burner.add(item, count) if burner else 0


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray([status, "Ore left in area: %d" % ore_remaining(),
		"Output: %s tile" % GameData.DIR_NAMES[dir].to_lower(), "Progress: %d%%" % roundi(progress * 100.0)])
	if burner:
		lines.append("Burns %s" % GameData.format_power(def["fuel_power"]))
	else:
		lines.append(power_line())
	return lines


func _draw_overlay() -> void:
	var head: Vector2 = def["head"]
	var r := 10.0 if size.x <= 2 else 14.0
	_draw_spinner(head, r, 3, Color(0.75, 0.75, 0.78), 3.0)
	draw_circle(head, 3.0, Color(0.3, 0.3, 0.33))
	if working and burner:
		_draw_fire(Vector2(16, 18), Vector2(6, 5))
