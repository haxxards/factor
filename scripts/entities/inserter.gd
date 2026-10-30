class_name Inserter
extends Building
## Picks one item from the tile behind and swings it to the tile in front.
## Only picks items the destination can currently use.

const SWING_TIME := 0.6  ## seconds for a half swing

var held: StringName = &""
var swing := 0.0  ## 0 = hand over the pickup tile, 1 = over the drop tile
var active := false


func pickup_cell() -> Vector2i:
	return cell - GameData.dir_vec(dir)


func drop_cell() -> Vector2i:
	return cell + GameData.dir_vec(dir)


func get_power_demand() -> float:
	return def["power"] if active else def["drain"]


func tick(dt: float) -> void:
	var was := swing
	var had := held
	if power_satisfaction <= 0.0:
		active = false
		status = "No power"
		return
	var speed := dt / SWING_TIME * power_satisfaction
	if held == &"":
		if swing > 0.0:
			swing = maxf(0.0, swing - speed)
			active = true
			status = "Returning"
		else:
			active = _try_pick()
			status = "Working" if active else "Waiting for items"
	elif swing < 1.0:
		swing = minf(1.0, swing + speed)
		active = true
		status = "Working"
	elif _try_drop():
		held = &""
		active = true
	else:
		active = false
		status = "Waiting to drop"
	if swing != was or held != had:
		queue_redraw()


func _try_pick() -> bool:
	var src := world.get_building(pickup_cell())
	var dst := world.get_building(drop_cell())
	if src == null or dst == null:
		return false
	var candidates: Array[StringName] = []
	if src is Belt:
		candidates = (src as Belt).item_ids.duplicate()
	else:
		candidates = src.takeable_items()
	var best := -1
	var best_priority := -1
	for i in candidates.size():
		var item := candidates[i]
		if _wants(dst, item):
			var priority := 0 if dst is Belt else dst.insert_priority(item)
			if priority > best_priority:
				best = i
				best_priority = priority
	if best < 0:
		return false
	if src is Belt:
		held = (src as Belt).remove_index(best)
		return true
	if src.take(candidates[best]):
		held = candidates[best]
		return true
	return false


func _wants(dst: Building, item: StringName) -> bool:
	return dst is Belt or dst.can_accept(item)


func _try_drop() -> bool:
	var dst := world.get_building(drop_cell())
	if dst == null:
		return false
	if dst is Belt:
		return (dst as Belt).insert_at(held, 0.5)
	return dst.can_accept(held) and dst.accept(held)


func status_icon() -> String:
	return "no_power" if power_satisfaction <= 0.0 else ""


func contents() -> Dictionary:
	return {held: 1} if held != &"" else {}


func ui_slots() -> Array:
	return [{"key": "hand", "label": "Hand", "item": held, "count": 1 if held != &"" else 0}]


func ui_take(_key: String) -> Dictionary:
	var out := contents()
	held = &""
	return out


func ui_lines() -> PackedStringArray:
	return PackedStringArray(["Moves items %s" % GameData.DIR_NAMES[dir].to_lower(), status, power_line()])


## The arm is drawn in world orientation so the held item stays upright.
func _draw() -> void:
	var tex := GameData.sprite("inserter")
	draw_texture(tex, -tex.get_size() * 0.5)
	var back := -Vector2(GameData.dir_vec(dir))
	var hand := back.rotated(swing * PI) * TILE * 0.85
	var elbow := hand * 0.5 + hand.orthogonal().normalized() * 7.0
	var arm := Color(0.84, 0.67, 0.19)
	draw_line(Vector2.ZERO, elbow, arm.darkened(0.2), 4.0)
	draw_line(elbow, hand, arm, 3.0)
	draw_circle(elbow, 2.5, arm.darkened(0.4))
	draw_circle(hand, 3.5, Color(0.25, 0.25, 0.28))
	if held != &"":
		draw_texture_rect(GameData.icon(held), Rect2(hand - Vector2(8, 8), Vector2(16, 16)), false)
	_draw_status_icon()
