class_name SteamEngine
extends Building
## Generator: consumes steam to produce electricity for the network it is in.
## Steam connects at both ends so engines can be chained.

var steam: FluidBox
var output_power := 0.0  ## W last tick
var _generated := 0.0  ## J generated since the last tick


func _init_building() -> void:
	steam = FluidBox.new(self, 200.0, &"steam")


func is_generator() -> bool:
	return true


func fluid_boxes() -> Array[FluidBox]:
	return [steam]


func fluid_connections() -> Array:
	return [
		_conn(steam, Vector2i(1, 0), Vector2i(1, -1)),
		_conn(steam, Vector2i(1, 2), Vector2i(1, 3)),
	]


func _joules_per_steam() -> float:
	return def["max_power"] / def["steam_rate"]


func available_power(dt: float) -> float:
	return minf(def["max_power"], steam.available(&"steam") * _joules_per_steam() / dt)


func generate(joules: float) -> float:
	var got := steam.remove(&"steam", joules / _joules_per_steam()) * _joules_per_steam()
	_generated += got
	return got


func tick(dt: float) -> void:
	# The power system calls generate() before buildings tick.
	output_power = _generated / dt
	_generated = 0.0
	if power_net == null:
		status = "Not connected to a power pole"
	elif steam.available(&"steam") <= 0.0 and output_power <= 0.0:
		status = "No steam"
	else:
		status = "Running"
	anim_time += dt * clampf(output_power / def["max_power"], 0.0, 1.0) * 2.0
	if output_power > 0.0:
		queue_redraw()


func ui_lines() -> PackedStringArray:
	var lines := PackedStringArray([status, "Output: %s / %s" % [GameData.format_power(output_power),
		GameData.format_power(def["max_power"])]])
	lines.append_array(Pipe.fluid_lines(steam, "Steam"))
	if power_net:
		lines.append("Network demand: %s" % GameData.format_power(power_net.demand))
	return lines


func _draw_overlay() -> void:
	_draw_spinner(Vector2(4, 0), 20.0, 4, Color(0.62, 0.64, 0.68), 3.0)
	draw_circle(Vector2(4, 0), 5.0, Color(0.6, 0.6, 0.64))
