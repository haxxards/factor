class_name BeltRenderer
extends Node2D
## Draws all belts in one pass with a shared animation frame.

const FRAMES := 8

var world: World


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view := world.visible_cells()
	# The belt texture repeats every 16 px over 8 frames (2 px per frame).
	var frame := int(Time.get_ticks_msec() * 0.001 * Belt.SPEED * World.TILE / 2.0) % FRAMES
	var straight := GameData.sprite("belt_straight")
	var curve_left := GameData.sprite("belt_curve_left")
	var curve_right := GameData.sprite("belt_curve_right")
	var src := Rect2(frame * World.TILE, 0, World.TILE, World.TILE)
	var dst := Rect2(-16, -16, 32, 32)
	for belt in world.belts:
		if not view.has_point(belt.cell):
			continue
		var tex: Texture2D = straight
		if belt.curve < 0:
			tex = curve_left
		elif belt.curve > 0:
			tex = curve_right
		draw_set_transform(belt.position, belt.dir * PI * 0.5)
		draw_texture_rect_region(tex, dst, src)
	draw_set_transform(Vector2.ZERO)
