class_name FluidBox
extends RefCounted
## One fluid container inside a building. Connected boxes share a FluidPool.

var building: Building
var capacity: float
var filter: StringName  # required fluid, or &"" for any (pipes)
var fluid: StringName = &""
var amount := 0.0  # only used while the pools are being rebuilt
var pool: FluidPool = null


func _init(p_building: Building, p_capacity: float, p_filter: StringName = &"") -> void:
	building = p_building
	capacity = p_capacity
	filter = p_filter
	fluid = p_filter


func available(f: StringName) -> float:
	return pool.available(f) if pool else 0.0


func space(f: StringName) -> float:
	return pool.space(f) if pool else 0.0


func add(f: StringName, n: float) -> float:
	return pool.add(f, n) if pool else 0.0


func remove(f: StringName, n: float) -> float:
	return pool.remove(f, n) if pool else 0.0


func current_fluid() -> StringName:
	return pool.fluid if pool else fluid


## This box's share of its pool, for display.
func current_amount() -> float:
	if pool == null or pool.capacity <= 0.0:
		return 0.0
	return pool.amount * capacity / pool.capacity
