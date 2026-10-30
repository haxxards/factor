class_name BeltItemOverlay
extends Node2D
## Draws items riding on belts, above the belts and buildings.

const ITEM_SIZE := 18.0

var world: World


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view := world.visible_cells()
	var half := Vector2(ITEM_SIZE, ITEM_SIZE) * 0.5
	for belt in world.belts:
		if not view.has_point(belt.cell):
			continue
		for i in belt.item_ids.size():
			var p := belt.position + belt.item_offset(belt.item_pos[i]) * World.TILE
			draw_circle(p + Vector2(1, 2), 6.5, Color(0, 0, 0, 0.25))
			draw_texture_rect(GameData.icon(belt.item_ids[i]), Rect2(p - half, half * 2.0), false)
