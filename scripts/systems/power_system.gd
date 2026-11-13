class_name PowerSystem
extends RefCounted
## Builds electric networks from pole wires and balances supply and demand each tick.

const MAX_WIRES := 5

var networks: Array[PowerNetwork] = []
var dirty := true


## Wires a newly placed pole to its nearest neighbours in reach.
func connect_pole(pole: PowerPole, all_poles: Array[PowerPole]) -> void:
	var reach: float = pole.def["reach"]
	var candidates: Array = []
	for other in all_poles:
		if other == pole:
			continue
		var d := Vector2(other.cell - pole.cell).length()
		if d <= reach:
			candidates.append([d, other])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(MAX_WIRES, candidates.size()):
		var other: PowerPole = candidates[i][1]
		if not pole.wires.has(other):
			pole.wires.append(other)
			other.wires.append(pole)


func disconnect_pole(pole: PowerPole) -> void:
	for other in pole.wires:
		other.wires.erase(pole)
	pole.wires.clear()


func rebuild(world: World) -> void:
	dirty = false
	networks.clear()
	var poles := world.poles()
	var net_of := {}  # PowerPole -> PowerNetwork
	for p in poles:
		if net_of.has(p):
			continue
		var net := PowerNetwork.new()
		var stack: Array[PowerPole] = [p]
		net_of[p] = net
		while not stack.is_empty():
			var cur: PowerPole = stack.pop_back()
			net.poles.append(cur)
			for other in cur.wires:
				if not net_of.has(other):
					net_of[other] = net
					stack.append(other)
		networks.append(net)

	for b in world.buildings:
		b.power_net = null
		if b is PowerPole:
			b.power_net = net_of[b]
			continue
		if not (b.is_electric() or b.is_generator()):
			continue
		b.power_satisfaction = 0.0
		var rect := Rect2i(b.cell, b.size)
		for p in poles:
			if p.supply_rect().intersects(rect):
				var net: PowerNetwork = net_of[p]
				b.power_net = net
				if b.is_generator():
					net.generators.append(b)
				else:
					net.consumers.append(b)
				break


func update(dt: float) -> void:
	for net in networks:
		var demand := 0.0
		for c in net.consumers:
			# Broken machines only draw their idle drain.
			demand += c.def.get("drain", 0.0) if c.is_broken() else c.get_power_demand()
		var capacity := 0.0
		for g in net.generators:
			if not g.is_broken():
				capacity += g.available_power(dt)
		var produced := 0.0  # joules this tick
		if demand > 0.0 and capacity > 0.0:
			var share := minf(1.0, demand / capacity)
			for g in net.generators:
				if not g.is_broken():
					produced += g.generate(g.available_power(dt) * share * dt)
		if demand > 0.0:
			net.satisfaction = clampf(produced / (demand * dt), 0.0, 1.0)
		else:
			net.satisfaction = 1.0 if capacity > 0.0 else 0.0
		net.demand = demand
		net.capacity = capacity
		net.production = produced / dt
		for c in net.consumers:
			c.power_satisfaction = net.satisfaction
		if produced > 0.0:
			GameData.add_stat(&"energy_mj", produced / 1.0e6)
