class_name Assembler
extends Building
## Electric crafting machine. The player picks the recipe in its window;
## inserters then feed ingredients and take the results.

var recipe_id: StringName = &""
var inputs: Dictionary = {}  ## item -> count
var output_count := 0
var crafting := false
var progress := 0.0


## Changes the recipe and returns the items that no longer fit (for the player).
func set_recipe(r: StringName) -> Dictionary:
	var refund := contents_without_building()
	recipe_id = r
	inputs.clear()
	output_count = 0
	crafting = false
	progress = 0.0
	queue_redraw()
	return refund


func get_power_demand() -> float:
	return def["power"] if crafting else def["drain"]


func _limit(item: StringName) -> int:
	var need: int = GameData.RECIPES[recipe_id]["in"][item]
	return maxi(need * 2, 2)


func can_accept(item: StringName) -> bool:
	if recipe_id == &"" or not GameData.RECIPES[recipe_id]["in"].has(item):
		return false
	return inputs.get(item, 0) < _limit(item)


func accept(item: StringName) -> bool:
	if not can_accept(item):
		return false
	inputs[item] = inputs.get(item, 0) + 1
	return true


func takeable_items() -> Array[StringName]:
	var out: Array[StringName] = []
	if output_count > 0:
		out.append(recipe_id)
	return out


func take(item: StringName) -> bool:
	if output_count <= 0 or item != recipe_id:
		return false
	output_count -= 1
	return true


func tick(dt: float) -> void:
	if recipe_id == &"":
		status = "No recipe set (click to choose)"
		return
	var rec: Dictionary = GameData.RECIPES[recipe_id]
	if not crafting:
		if output_count + rec["count"] > GameData.stack_size(recipe_id):
			status = "Output full"
			return
		var ins: Dictionary = rec["in"]
		for k in ins:
			if inputs.get(k, 0) < ins[k]:
				status = "Missing ingredients"
				return
		for k in ins:
			inputs[k] -= ins[k]
		crafting = true
		progress = 0.0
	if power_satisfaction <= 0.0:
		status = "No power"
		return
	status = "Crafting"
	anim_time += dt * power_satisfaction
	progress += dt * def["speed"] * power_satisfaction / rec["time"]
	if progress >= 1.0:
		output_count += rec["count"]
		GameData.add_stat(StringName("assembled:%s" % recipe_id), rec["count"])
		crafting = false
		progress = 0.0
	queue_redraw()


func status_icon() -> String:
	if recipe_id != &"" and power_satisfaction <= 0.0:
		return "no_power"
	if recipe_id != &"" and not crafting and status == "Missing ingredients":
		return "no_input"
	return ""


func contents_without_building() -> Dictionary:
	var out := {}
	merge_into(out, inputs)
	if output_count > 0:
		merge_into(out, {recipe_id: output_count})
	if crafting:
		merge_into(out, GameData.RECIPES[recipe_id]["in"])
	return out


func contents() -> Dictionary:
	return contents_without_building()


func ui_slots() -> Array:
	var slots := []
	if recipe_id == &"":
		return slots
	var ins: Dictionary = GameData.RECIPES[recipe_id]["in"]
	for k in ins:
		slots.append({"key": "in:" + String(k), "label": "Input", "item": k, "count": inputs.get(k, 0)})
	slots.append({"key": "output", "label": "Output", "item": recipe_id, "count": output_count})
	return slots


func ui_take(key: String) -> Dictionary:
	var out := {}
	if key == "output" and output_count > 0:
		out[recipe_id] = output_count
		output_count = 0
	elif key.begins_with("in:"):
		var item := StringName(key.substr(3))
		if inputs.get(item, 0) > 0:
			out[item] = inputs[item]
			inputs[item] = 0
	return out


func ui_accepts(item: StringName) -> bool:
	return recipe_id != &"" and GameData.RECIPES[recipe_id]["in"].has(item)


func ui_insert(item: StringName, count: int) -> int:
	if not ui_accepts(item):
		return 0
	var n := maxi(0, mini(count, GameData.stack_size(item) - inputs.get(item, 0)))
	inputs[item] = inputs.get(item, 0) + n
	return n


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray([status])
	if recipe_id != &"":
		lines.append("Recipe: " + GameData.recipe_text(recipe_id))
		lines.append("Progress: %d%%" % roundi(progress * 100.0))
	lines.append(power_line())
	return lines


func _draw_overlay() -> void:
	if recipe_id == &"":
		return
	if crafting and power_satisfaction > 0.0:
		_draw_spinner(Vector2(-1, -1), 17.0, 6, Color(0.55, 0.58, 0.5), 2.0)
	draw_circle(Vector2(-1, -1), 13.0, Color(0.14, 0.15, 0.14))
	draw_texture_rect(GameData.icon(recipe_id), Rect2(Vector2(-13, -13), Vector2(24, 24)), false)
	if crafting:
		draw_rect(Rect2(-24, 30, 46.0 * progress, 3), Color(0.4, 0.9, 0.4))
