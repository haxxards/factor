class_name PowerPole
extends Building
## Connects machines inside its supply area to the electric network.

var wires: Array[PowerPole] = []


func supply_rect() -> Rect2i:
	var r: int = def["supply"]
	return Rect2i(cell - Vector2i(r, r), Vector2i(r * 2 + 1, r * 2 + 1))


## Where wires attach, in world pixels.
func wire_anchor() -> Vector2:
	return position + Vector2(0, -29)


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray(["Wires: %d" % wires.size()])
	if power_net:
		lines.append("Network: %d poles, %d machines, %d generators" % [power_net.poles.size(),
			power_net.consumers.size(), power_net.generators.size()])
		lines.append("Production: %s / capacity %s" % [GameData.format_power(power_net.production),
			GameData.format_power(power_net.capacity)])
		lines.append("Satisfaction: %d%%" % roundi(power_net.satisfaction * 100.0))
	return lines
