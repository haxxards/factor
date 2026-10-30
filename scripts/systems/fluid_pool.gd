class_name FluidPool
extends RefCounted
## A set of connected fluid boxes treated as one tank. Fluids never mix:
## a pool holds one fluid at a time, and a pool joining boxes with
## different filters (e.g. water and steam) is blocked.

var boxes: Array[FluidBox] = []
var capacity := 0.0
var amount := 0.0
var fluid: StringName = &""
var filter: StringName = &""
var conflict := false


func accepts(f: StringName) -> bool:
	if conflict:
		return false
	if filter != &"" and f != filter:
		return false
	return fluid == &"" or fluid == f or amount <= 0.0001


func available(f: StringName) -> float:
	return amount if fluid == f and not conflict else 0.0


func space(f: StringName) -> float:
	return capacity - amount if accepts(f) else 0.0


func add(f: StringName, n: float) -> float:
	var a := minf(n, space(f))
	if a > 0.0:
		amount += a
		fluid = f
	return a


func remove(f: StringName, n: float) -> float:
	var r := minf(n, available(f))
	amount -= r
	if amount <= 0.0001:
		amount = 0.0
		fluid = filter
	return r
