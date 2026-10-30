class_name WireLayer
extends Node2D
## Draws copper wires between connected power poles.

var world: World


func _draw() -> void:
	for pole in world.poles():
		for other in pole.wires:
			if pole.get_instance_id() < other.get_instance_id():
				_draw_wire(pole.wire_anchor(), other.wire_anchor())


func _draw_wire(a: Vector2, b: Vector2) -> void:
	var pts := PackedVector2Array()
	var sag := a.distance_to(b) * 0.06
	for i in 9:
		var t := i / 8.0
		pts.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * sag))
	draw_polyline(pts, Color(0.1, 0.08, 0.06, 0.35), 2.5, true)
	draw_polyline(pts, Color(0.78, 0.46, 0.22), 1.2, true)
