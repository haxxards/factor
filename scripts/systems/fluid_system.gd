class_name FluidSystem
extends RefCounted
## Groups connected fluid boxes into pools. Two boxes connect when their
## buildings have connection points facing each other.

var pools: Array[FluidPool] = []
var dirty := true


## Breaks the box <-> pool reference cycles so everything can be freed.
func clear() -> void:
	for p in pools:
		for box in p.boxes:
			box.pool = null
		p.boxes.clear()
	pools.clear()


func rebuild(world: World) -> void:
	dirty = false
	# Push pooled fluid back into the boxes so it survives regrouping.
	for p in pools:
		for box in p.boxes:
			box.fluid = p.fluid
			box.amount = p.amount * box.capacity / p.capacity if p.capacity > 0.0 else 0.0
			box.pool = null
	pools.clear()

	var links := {}  # FluidBox -> Array of linked FluidBox
	var all_boxes: Array[FluidBox] = []
	for b in world.buildings:
		for box in b.fluid_boxes():
			all_boxes.append(box)
			links[box] = []
	for b in world.buildings:
		for conn in b.fluid_connections():
			var other := world.get_building(conn["to"])
			if other == null or other == b:
				continue
			for oc in other.fluid_connections():
				if oc["from"] == conn["to"] and oc["to"] == conn["from"]:
					links[conn["box"]].append(oc["box"])

	for start in all_boxes:
		if start.pool != null:
			continue
		var pool := FluidPool.new()
		var amounts := {}
		var stack: Array[FluidBox] = [start]
		start.pool = pool
		while not stack.is_empty():
			var cur: FluidBox = stack.pop_back()
			pool.boxes.append(cur)
			pool.capacity += cur.capacity
			if cur.filter != &"":
				if pool.filter == &"":
					pool.filter = cur.filter
				elif pool.filter != cur.filter:
					pool.conflict = true
			if cur.amount > 0.0 and cur.fluid != &"":
				amounts[cur.fluid] = amounts.get(cur.fluid, 0.0) + cur.amount
			for nb in links[cur]:
				if nb.pool == null:
					nb.pool = pool
					stack.append(nb)
		# Keep the most plentiful compatible fluid.
		for f in amounts:
			if amounts[f] > pool.amount and (pool.filter == &"" or f == pool.filter):
				pool.amount = amounts[f]
				pool.fluid = f
		pool.amount = minf(pool.amount, pool.capacity)
		if pool.fluid == &"":
			pool.fluid = pool.filter
		pools.append(pool)

	for b in world.buildings:
		b.on_fluids_rebuilt()
