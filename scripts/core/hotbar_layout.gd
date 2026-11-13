class_name HotbarLayout
extends RefCounted
## Which item sits in each hotbar slot (one slot per key in HOTBAR_KEYS).
## Empty slots hold &"". The same item may sit in several slots. The layout
## is saved to the user's settings file on every change.

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "hotbar"
const KEY := "slots"

var slots: Array[StringName] = []
var save_path: String


func _init(path: String = SETTINGS_PATH) -> void:
	save_path = path
	slots.resize(GameData.HOTBAR_KEYS.size())
	slots.fill(&"")
	for i in mini(slots.size(), GameData.DEFAULT_HOTBAR.size()):
		slots[i] = GameData.DEFAULT_HOTBAR[i]


## Only things the hand can hold: buildings and tools.
static func can_hold(item: StringName) -> bool:
	return GameData.is_building_item(item) or GameData.is_tool(item)


func size() -> int:
	return slots.size()


func get_item(i: int) -> StringName:
	return slots[i] if i >= 0 and i < slots.size() else &""


func assign(i: int, item: StringName) -> bool:
	if i < 0 or i >= slots.size() or not can_hold(item):
		return false
	slots[i] = item
	_changed()
	return true


func clear(i: int) -> void:
	if i >= 0 and i < slots.size() and slots[i] != &"":
		slots[i] = &""
		_changed()


func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= slots.size() or b >= slots.size():
		return
	var tmp := slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	_changed()


## Loads a saved layout if there is one. Unknown items become empty slots.
func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK or not cfg.has_section_key(SECTION, KEY):
		return
	var saved: PackedStringArray = cfg.get_value(SECTION, KEY, PackedStringArray())
	for i in mini(slots.size(), saved.size()):
		var item := StringName(saved[i])
		slots[i] = item if can_hold(item) else &""
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(save_path)  # keep any other settings in the file
	var names := PackedStringArray()
	for s in slots:
		names.append(String(s))
	cfg.set_value(SECTION, KEY, names)
	cfg.save(save_path)


func _changed() -> void:
	save()
	changed.emit()
