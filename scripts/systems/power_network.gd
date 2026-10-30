class_name PowerNetwork
extends RefCounted
## Poles joined by wires, plus every machine inside their supply areas.

var poles: Array[PowerPole] = []
var consumers: Array[Building] = []
var generators: Array[Building] = []
var satisfaction := 0.0  # 0..1, how much of the demand was met last tick
var demand := 0.0  # W requested last tick
var production := 0.0  # W produced last tick
var capacity := 0.0  # W the generators could have produced
