class_name OffshorePump
extends Building
## Sits on the shore with water behind it and pushes water out of its front.

var box: FluidBox
var pumped := 0.0  ## water/s last tick


func _init_building() -> void:
	box = FluidBox.new(self, 100.0, &"water")


func fluid_boxes() -> Array[FluidBox]:
	return [box]


func fluid_connections() -> Array:
	return [_conn(box, Vector2i(0, 0), Vector2i(0, -1))]


func tick(dt: float) -> void:
	pumped = box.add(&"water", def["rate"] * dt) / dt
	status = "Pumping" if pumped > 0.0 else "Output full / not connected"


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray([status, "Rate: %.0f water/s" % pumped])
	lines.append_array(Pipe.fluid_lines(box, "Output"))
	return lines


func _draw_overlay() -> void:
	if pumped > 0.0:
		var t := fmod(Time.get_ticks_msec() / 400.0, 1.0)
		draw_arc(Vector2(-1, 2), 3.0 + t * 6.0, 0.0, TAU, 16, Color(0.6, 0.85, 1.0, 1.0 - t), 1.0)
