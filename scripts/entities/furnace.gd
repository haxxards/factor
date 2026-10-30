class_name Furnace
extends Building
## Burns coal to smelt ore into plates (and stone into bricks). The recipe is
## picked automatically from whatever is in the input slot.

const AUTO_INPUT_LIMIT := 20
const INPUT_STACK := 50

var burner := BurnerFuel.new()
var input_item: StringName = &""
var input_count := 0
var output_item: StringName = &""
var output_count := 0
var recipe_id: StringName = &""  ## recipe currently smelting
var progress := 0.0
var working := false


func can_accept(item: StringName) -> bool:
	if GameData.is_fuel(item):
		return burner.can_accept(item, BurnerFuel.AUTO_LIMIT)
	return _input_ok(item, AUTO_INPUT_LIMIT)


func accept(item: StringName) -> bool:
	if GameData.is_fuel(item):
		return burner.add(item, 1, BurnerFuel.AUTO_LIMIT) == 1
	if not _input_ok(item, AUTO_INPUT_LIMIT):
		return false
	input_item = item
	input_count += 1
	return true


func _input_ok(item: StringName, limit: int) -> bool:
	if GameData.smelting_recipe_for(item) == &"":
		return false
	return (input_item == &"" or input_item == item) and input_count < limit


func insert_priority(item: StringName) -> int:
	return 1 if GameData.is_fuel(item) and burner.count == 0 else 0


func takeable_items() -> Array[StringName]:
	var out: Array[StringName] = []
	if output_count > 0:
		out.append(output_item)
	return out


func take(item: StringName) -> bool:
	if output_count <= 0 or item != output_item:
		return false
	output_count -= 1
	if output_count == 0:
		output_item = &""
	return true


func tick(dt: float) -> void:
	working = false
	if recipe_id == &"":
		_try_start()
	if recipe_id == &"":
		status = "Waiting for ore"
		return
	var rec: Dictionary = GameData.RECIPES[recipe_id]
	if output_item != &"" and (output_item != recipe_id or output_count + rec["count"] > GameData.stack_size(recipe_id)):
		status = "Output full"
		return
	var eff := burner.consume(def["fuel_power"] * dt)
	if eff <= 0.0:
		status = "No fuel"
		return
	working = true
	status = "Smelting %s" % GameData.item_name(recipe_id)
	anim_time += dt
	progress += dt * eff * def["speed"] / rec["time"]
	if progress >= 1.0:
		output_item = recipe_id
		output_count += rec["count"]
		GameData.add_stat(StringName("made:%s" % recipe_id), rec["count"])
		recipe_id = &""
		progress = 0.0
	queue_redraw()


func _try_start() -> void:
	if input_count <= 0:
		return
	var r := GameData.smelting_recipe_for(input_item)
	var need: int = GameData.RECIPES[r]["in"][input_item]
	if input_count < need:
		return
	if output_item != &"" and output_item != r:
		return
	input_count -= need
	if input_count == 0:
		input_item = &""
	recipe_id = r
	progress = 0.0


func status_icon() -> String:
	if not burner.has_fuel() and (recipe_id != &"" or input_count > 0):
		return "no_fuel"
	return ""


func contents() -> Dictionary:
	var out := {}
	merge_into(out, {burner.item: burner.count} if burner.count > 0 else {})
	merge_into(out, {input_item: input_count} if input_count > 0 else {})
	merge_into(out, {output_item: output_count} if output_count > 0 else {})
	if recipe_id != &"":
		merge_into(out, GameData.RECIPES[recipe_id]["in"])
	return out


func ui_slots() -> Array:
	return [
		{"key": "fuel", "label": "Fuel", "item": burner.item, "count": burner.count},
		{"key": "input", "label": "Input", "item": input_item, "count": input_count},
		{"key": "output", "label": "Output", "item": output_item, "count": output_count},
	]


func ui_take(key: String) -> Dictionary:
	var out := {}
	match key:
		"fuel":
			out = burner.take_all()
		"input":
			if input_count > 0:
				out[input_item] = input_count
			input_item = &""
			input_count = 0
		"output":
			if output_count > 0:
				out[output_item] = output_count
			output_item = &""
			output_count = 0
	return out


func ui_accepts(item: StringName) -> bool:
	return burner.can_accept(item) if GameData.is_fuel(item) else _input_ok(item, INPUT_STACK)


func ui_insert(item: StringName, count: int) -> int:
	if GameData.is_fuel(item):
		return burner.add(item, count)
	if not _input_ok(item, INPUT_STACK):
		return 0
	var n := mini(count, INPUT_STACK - input_count)
	input_item = item
	input_count += n
	return n


func ui_lines() -> PackedStringArray:
	return PackedStringArray([status, "Progress: %d%%" % roundi(progress * 100.0),
		"Burns %s" % GameData.format_power(def["fuel_power"])])


func _draw_overlay() -> void:
	if working:
		_draw_fire(Vector2(0, 15), Vector2(7, 6))
		var glow := 0.4 + 0.15 * sin(anim_time * 5.0)
		draw_circle(Vector2(0, -12), 7.0, Color(1.0, 0.5, 0.15, glow))
