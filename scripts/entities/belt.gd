class_name Belt
extends Building
## Single-lane conveyor. Items have a position along the belt from 0 (entry)
## to 1 (exit); index 0 is always the front-most item. Drawing is done in bulk
## by BeltRenderer / BeltItemOverlay, so belts do not draw themselves.

const SPEED := 1.875  ## tiles per second
const GAP := 0.25  ## minimum spacing between items, in tiles
const MAX_ITEMS := 4

var item_ids: Array[StringName] = []
var item_pos: Array[float] = []
var next_belt: Belt = null
var input_cell := Vector2i.ZERO  ## tile that items normally arrive from
var curve := 0  ## 0 = straight, -1 = turns in from the left side, 1 = from the right side


## Recomputes the belt this one feeds and whether it is drawn as a curve.
## Mirrors the usual rule: a belt with a straight feeder behind it stays
## straight; otherwise a single side feeder turns it into a curve.
func refresh_links() -> void:
	var fwd := GameData.dir_vec(dir)
	var ahead := world.get_building(cell + fwd)
	next_belt = null
	if ahead is Belt and ahead.dir != (dir + 2) % 4:
		next_belt = ahead as Belt
	curve = 0
	var behind := world.get_building(cell - fwd)
	if not (behind is Belt and behind.dir == dir):
		var left := _fed_from((dir + 3) % 4)
		var right := _fed_from((dir + 1) % 4)
		if left != right:
			curve = -1 if left else 1
	if curve == 0:
		input_cell = cell - fwd
	else:
		input_cell = cell + GameData.dir_vec(dir + 3 if curve < 0 else dir + 1)


func _fed_from(side: int) -> bool:
	var b := world.get_building(cell + GameData.dir_vec(side))
	return b is Belt and b.cell + GameData.dir_vec(b.dir) == cell


func has_space_at(p: float) -> bool:
	if item_ids.size() >= MAX_ITEMS:
		return false
	for q in item_pos:
		if absf(q - p) < GAP - 0.001:
			return false
	return true


## Drops an item onto the belt at position p (used by inserters, drills, side-loading).
func insert_at(item: StringName, p: float = 0.5) -> bool:
	if not has_space_at(p):
		return false
	var i := 0
	while i < item_pos.size() and item_pos[i] > p:
		i += 1
	item_ids.insert(i, item)
	item_pos.insert(i, p)
	return true


## Called by the belt behind us (or beside us) when its front item reaches the end.
func accept_from(src: Belt, item: StringName, overflow: float) -> bool:
	if src.cell != input_cell:
		return insert_at(item, 0.5)  # side-loading joins mid-belt
	var p := overflow
	if not item_pos.is_empty():
		var rear: float = item_pos[item_pos.size() - 1]
		if rear < GAP:
			return false
		p = minf(p, rear - GAP)
	item_ids.append(item)
	item_pos.append(maxf(p, 0.0))
	return true


func remove_index(i: int) -> StringName:
	var item := item_ids[i]
	item_ids.remove_at(i)
	item_pos.remove_at(i)
	return item


## Advances items. Belts are processed downstream-first so a full line moves as one.
func move_items(dt: float) -> void:
	var step := SPEED * dt
	var i := 0
	while i < item_ids.size():
		var p := item_pos[i] + step
		if i == 0:
			if p >= 1.0:
				if next_belt != null and next_belt.accept_from(self, item_ids[0], p - 1.0):
					item_ids.remove_at(0)
					item_pos.remove_at(0)
					continue
				p = 1.0
		else:
			p = minf(p, item_pos[i - 1] - GAP)
		item_pos[i] = maxf(item_pos[i], p)
		i += 1


## Position of an item along the belt, in tiles relative to the tile centre.
func item_offset(p: float) -> Vector2:
	var v := Vector2(GameData.dir_vec(dir))
	if curve == 0:
		return v * (p - 0.5)
	var u := Vector2(GameData.dir_vec(dir + 3 if curve < 0 else dir + 1))
	# Quarter circle around the corner between the entry side and the exit side.
	var corner := (u + v) * 0.5
	var a := p * PI * 0.5
	return corner - v * 0.5 * cos(a) - u * 0.5 * sin(a)


func contents() -> Dictionary:
	var out := {}
	for item in item_ids:
		out[item] = out.get(item, 0) + 1
	return out


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray(["Direction: %s" % GameData.DIR_NAMES[dir], "Items on belt: %d" % item_ids.size()])
	if curve != 0:
		lines.append("Curve (fed from the %s)" % ("left" if curve < 0 else "right"))
	return lines


func _draw() -> void:
	pass
