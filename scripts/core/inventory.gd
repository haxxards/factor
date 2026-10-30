class_name Inventory
extends RefCounted
## Slot-limited item storage. Each item type uses ceil(count / stack size) slots.

signal changed

var slots: int
var items: Dictionary = {}  # StringName -> int


func _init(slot_count: int = 32) -> void:
	slots = slot_count


func count(item: StringName) -> int:
	return items.get(item, 0)


func has(item: StringName, n: int = 1) -> bool:
	return count(item) >= n


func is_empty() -> bool:
	return items.is_empty()


func slots_used(except: StringName = &"") -> int:
	var used := 0
	for k in items:
		if k != except:
			used += ceili(float(items[k]) / GameData.stack_size(k))
	return used


## How many more of `item` fit.
func space_for(item: StringName) -> int:
	var free_slots := slots - slots_used(item)
	return maxi(0, free_slots * GameData.stack_size(item) - count(item))


## Adds up to n, returns the amount actually added.
func add(item: StringName, n: int = 1) -> int:
	var added := mini(n, space_for(item))
	if added > 0:
		items[item] = count(item) + added
		changed.emit()
	return added


## Adds ignoring the slot limit, so crafted or picked-up items are never lost.
func force_add(item: StringName, n: int) -> void:
	if n <= 0:
		return
	items[item] = count(item) + n
	changed.emit()


func remove(item: StringName, n: int = 1) -> int:
	var removed := mini(n, count(item))
	if removed > 0:
		items[item] = count(item) - removed
		if items[item] <= 0:
			items.erase(item)
		changed.emit()
	return removed


func set_items(new_items: Dictionary) -> void:
	items.clear()
	for k in new_items:
		if new_items[k] > 0:
			items[k] = new_items[k]
	changed.emit()


func sorted_items() -> Array:
	var keys := items.keys()
	keys.sort_custom(func(a, b): return GameData.item_order(a) < GameData.item_order(b))
	return keys
