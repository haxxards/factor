class_name Player
extends Node2D
## The engineer: walks around, carries the inventory and hand-crafts.

signal craft_queue_changed

const SPEED := 7.5 * World.TILE  ## pixels per second
const REACH := 12.0  ## tiles, for building and mining
const RADIUS := 9.0  ## collision half-size in pixels

var world: World
var inventory := Inventory.new(60)
## Queue entries: {"recipe": StringName, "left": float, "give": bool}. Intermediate
## crafts (give = false) were already accounted for when the order was queued.
var craft_queue: Array[Dictionary] = []
var facing := Vector2.UP


func _physics_process(delta: float) -> void:
	if not world.auto_tick:
		return  # paused (start menu)
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if v != Vector2.ZERO:
		facing = v
		_move(v * SPEED * delta)
		queue_redraw()
	process_crafting(delta)


func _move(delta: Vector2) -> void:
	var p := Vector2(position.x + delta.x, position.y)
	if not _blocked(p):
		position.x = p.x
	p = Vector2(position.x, position.y + delta.y)
	if not _blocked(p):
		position.y = p.y


func _blocked(p: Vector2) -> bool:
	for corner in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		if world.is_blocking(World.world_to_cell(p + corner)):
			return true
	return false


func collision_rect() -> Rect2:
	return Rect2(position - Vector2(RADIUS, RADIUS), Vector2(RADIUS, RADIUS) * 2.0)


func in_reach(world_pos: Vector2) -> bool:
	return position.distance_to(world_pos) <= REACH * World.TILE


# --- Crafting ----------------------------------------------------------------

## How many of `recipe` could be crafted right now, counting intermediates.
func craftable_count(recipe: StringName, limit: int = 99) -> int:
	var inv := inventory.items.duplicate()
	var n := 0
	while n < limit and _plan(recipe, inv, [], 0):
		n += 1
	return n


## Queues `count` crafts of `recipe`, crafting missing intermediates
## (e.g. gears for belts) first. Ingredients are taken immediately.
func queue_craft(recipe: StringName, count: int = 1) -> int:
	var inv := inventory.items.duplicate()
	var plan: Array = []
	var done := 0
	for i in count:
		var inv_try := inv.duplicate()
		var plan_try := plan.duplicate()
		if not _plan(recipe, inv_try, plan_try, 0):
			break
		inv = inv_try
		plan = plan_try
		done += 1
	if done == 0:
		return 0
	# Final products appear when their craft finishes, so leave them out for now.
	var per: int = GameData.RECIPES[recipe]["count"]
	inv[recipe] = inv.get(recipe, 0) - per * done
	inventory.set_items(inv)
	for entry in plan:
		craft_queue.append(entry)
	craft_queue_changed.emit()
	return done


func _plan(recipe: StringName, inv: Dictionary, plan: Array, depth: int) -> bool:
	if depth > 5 or not GameData.is_handcraftable(recipe):
		return false
	var rec: Dictionary = GameData.RECIPES[recipe]
	var ins: Dictionary = rec["in"]
	for item in ins:
		var need: int = ins[item]
		while inv.get(item, 0) < need:
			if not _plan(item, inv, plan, depth + 1):
				return false
			plan[plan.size() - 1]["give"] = false
		inv[item] = inv.get(item, 0) - need
	plan.append({"recipe": recipe, "left": rec["time"], "give": true})
	inv[recipe] = inv.get(recipe, 0) + rec["count"]
	return true


func process_crafting(delta: float) -> void:
	if craft_queue.is_empty():
		return
	var entry: Dictionary = craft_queue[0]
	entry["left"] -= delta
	if entry["left"] > 0.0:
		return
	craft_queue.remove_at(0)
	var r: StringName = entry["recipe"]
	if entry["give"]:
		inventory.force_add(r, GameData.RECIPES[r]["count"])
		GameData.add_stat(StringName("crafted:%s" % r))
	craft_queue_changed.emit()


func craft_progress() -> float:
	if craft_queue.is_empty():
		return 0.0
	var r: StringName = craft_queue[0]["recipe"]
	return 1.0 - craft_queue[0]["left"] / GameData.RECIPES[r]["time"]


func _draw() -> void:
	var tex := GameData.sprite("player")
	draw_set_transform(Vector2.ZERO, facing.angle() + PI * 0.5)
	draw_texture(tex, -tex.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO)
