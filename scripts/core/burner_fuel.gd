class_name BurnerFuel
extends RefCounted
## Fuel slot plus energy buffer, shared by burner drills, furnaces and boilers.

const STACK := 50
## Inserters and drills stop topping up fuel past this many items.
const AUTO_LIMIT := 10

var item: StringName = &""
var count := 0
var energy := 0.0  # joules left over from the item currently burning


func can_accept(fuel: StringName, limit: int = STACK) -> bool:
	return GameData.is_fuel(fuel) and (item == &"" or item == fuel) and count < limit


func add(fuel: StringName, n: int, limit: int = STACK) -> int:
	if not can_accept(fuel, limit):
		return 0
	var added := mini(n, limit - count)
	item = fuel
	count += added
	return added


func take_all() -> Dictionary:
	var out := {}
	if count > 0:
		out[item] = count
	item = &""
	count = 0
	return out


## Burns fuel to supply `joules`. Returns the fraction that could be supplied (0..1).
func consume(joules: float) -> float:
	if joules <= 0.0:
		return 1.0
	while energy < joules and count > 0:
		energy += GameData.fuel_value(item)
		count -= 1
		if count == 0:
			item = &""
	var used := minf(joules, energy)
	energy -= used
	return used / joules


func has_fuel() -> bool:
	return count > 0 or energy > 0.0
