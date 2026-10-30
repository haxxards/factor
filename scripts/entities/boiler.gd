class_name Boiler
extends Building
## Burns fuel to turn water into steam. Water connects on the two short sides
## (so boilers can be chained), steam leaves through the front.

var burner := BurnerFuel.new()
var water: FluidBox
var steam: FluidBox
var produced := 0.0  ## steam/s last tick


func _init_building() -> void:
	water = FluidBox.new(self, 200.0, &"water")
	steam = FluidBox.new(self, 200.0, &"steam")


func fluid_boxes() -> Array[FluidBox]:
	return [water, steam]


func fluid_connections() -> Array:
	return [
		_conn(water, Vector2i(0, 1), Vector2i(-1, 1)),
		_conn(water, Vector2i(2, 1), Vector2i(3, 1)),
		_conn(steam, Vector2i(1, 0), Vector2i(1, -1)),
	]


func tick(dt: float) -> void:
	var want: float = def["steam_rate"] * dt
	want = minf(want, water.available(&"water"))
	want = minf(want, steam.space(&"steam"))
	produced = 0.0
	if want <= 0.0:
		status = "No water" if water.available(&"water") <= 0.0 else "Steam output full"
		return
	var energy_per_unit: float = def["fuel_power"] / def["steam_rate"]
	var eff := burner.consume(want * energy_per_unit)
	if eff <= 0.0:
		status = "No fuel"
		return
	var made := want * eff
	water.remove(&"water", made)
	steam.add(&"steam", made)
	produced = made / dt
	anim_time += dt
	status = "Producing steam"
	queue_redraw()


func can_accept(item: StringName) -> bool:
	return burner.can_accept(item, BurnerFuel.AUTO_LIMIT)


func accept(item: StringName) -> bool:
	return burner.add(item, 1, BurnerFuel.AUTO_LIMIT) == 1


func insert_priority(item: StringName) -> int:
	return 1 if GameData.is_fuel(item) and burner.count == 0 else 0


func status_icon() -> String:
	return "no_fuel" if not burner.has_fuel() else ""


func contents() -> Dictionary:
	return {burner.item: burner.count} if burner.count > 0 else {}


func ui_slots() -> Array:
	return [{"key": "fuel", "label": "Fuel", "item": burner.item, "count": burner.count}]


func ui_take(_key: String) -> Dictionary:
	return burner.take_all()


func ui_accepts(item: StringName) -> bool:
	return burner.can_accept(item)


func ui_insert(item: StringName, count: int) -> int:
	return burner.add(item, count)


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray([status, "Steam: %.0f / s (max %.0f)" % [produced, def["steam_rate"]]])
	lines.append_array(Pipe.fluid_lines(water, "Water"))
	lines.append_array(Pipe.fluid_lines(steam, "Steam"))
	return lines


func _draw_overlay() -> void:
	if produced > 0.0:
		_draw_fire(Vector2(0, 15), Vector2(9, 7))
		var t := fmod(anim_time * 0.8, 1.0)
		draw_circle(Vector2(0, -36 - t * 10.0), 4.0 + t * 5.0, Color(1, 1, 1, 0.45 * (1.0 - t)))
