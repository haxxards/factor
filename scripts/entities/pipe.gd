class_name Pipe
extends Building
## Connects to fluid connection points on all four sides.

var box: FluidBox
var mask := 0  ## connected sides: 1 = N, 2 = E, 4 = S, 8 = W


func _init_building() -> void:
	box = FluidBox.new(self, 100.0)


func fluid_boxes() -> Array[FluidBox]:
	return [box]


func fluid_connections() -> Array:
	var out := []
	for d in 4:
		out.append({"box": box, "from": cell, "to": cell + GameData.dir_vec(d)})
	return out


func on_fluids_rebuilt() -> void:
	mask = 0
	for d in 4:
		var other := world.get_building(cell + GameData.dir_vec(d))
		if other == null:
			continue
		for oc in other.fluid_connections():
			if oc["to"] == cell and oc["from"] == cell + GameData.dir_vec(d):
				mask |= 1 << d
				break
	queue_redraw()


func ui_lines() -> PackedStringArray:
	return fluid_lines(box)


static func fluid_lines(b: FluidBox, label: String = "Contents") -> PackedStringArray:
	if b.pool and b.pool.conflict:
		return PackedStringArray(["%s: blocked - water and steam pipes are connected" % label])
	var f := b.current_fluid()
	if f == &"" or b.current_amount() < 0.05:
		return PackedStringArray(["%s: empty" % label])
	return PackedStringArray(["%s: %.0f / %.0f %s" % [label, b.current_amount(), b.capacity, GameData.item_name(f)]])


func _draw() -> void:
	var tex := GameData.sprite("pipe")
	draw_texture_rect_region(tex, Rect2(-16, -16, 32, 32), Rect2(mask * 32, 0, 32, 32))
	var f := box.current_fluid()
	if f != &"" and box.current_amount() > 0.5:
		var fill := clampf(box.current_amount() / box.capacity, 0.15, 1.0)
		var c: Color = GameData.FLUIDS[f]["color"]
		c.a = 0.85
		draw_rect(Rect2(-3, -3, 5, 5), c.darkened(0.6 * (1.0 - fill)))
