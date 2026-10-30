class_name Chest
extends Building
## Plain storage. Inserters can put anything in and take anything out.

var inventory: Inventory


func _init_building() -> void:
	inventory = Inventory.new(def["slots"])


func can_accept(item: StringName) -> bool:
	return inventory.space_for(item) > 0


func accept(item: StringName) -> bool:
	return inventory.add(item, 1) == 1


func takeable_items() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in inventory.sorted_items():
		out.append(k)
	return out


func take(item: StringName) -> bool:
	return inventory.remove(item, 1) == 1


func contents() -> Dictionary:
	return inventory.items.duplicate()


func ui_slots() -> Array:
	var slots := []
	for k in inventory.sorted_items():
		slots.append({"key": String(k), "label": "", "item": k, "count": inventory.count(k)})
	return slots


func ui_take(key: String) -> Dictionary:
	var item := StringName(key)
	var n := inventory.remove(item, inventory.count(item))
	return {item: n} if n > 0 else {}


func ui_accepts(item: StringName) -> bool:
	return inventory.space_for(item) > 0


func ui_insert(item: StringName, count: int) -> int:
	return inventory.add(item, count)


func ui_lines() -> PackedStringArray:
	return PackedStringArray(["Slots used: %d / %d" % [inventory.slots_used(), inventory.slots]])
