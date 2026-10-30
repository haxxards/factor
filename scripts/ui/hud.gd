class_name Hud
extends CanvasLayer
## All screen-space UI, built in code: hotbar, hover info, objectives,
## inventory / hand-crafting window, building window, help and start menu.

const SLOT := 46
const REFRESH := 0.1

var game: Game
var root: Control

var info_label: RichTextLabel
var objectives_label: RichTextLabel
var toast_label: Label
var mining_bar: ProgressBar
var queue_row: HBoxContainer
var queue_bar: ProgressBar
var hotbar_buttons: Array[Button] = []

var inventory_window: PanelContainer
var inv_grid: GridContainer
var craft_grid: GridContainer
var craft_buttons: Dictionary = {}  ## recipe -> Button

var building_window: PanelContainer
var bw_title: Label
var bw_lines: Label
var bw_slots: HFlowContainer
var bw_insert_title: Label
var bw_insert: HFlowContainer
var bw_recipe_title: Label
var bw_recipes: GridContainer
var building_target: Building = null
var _slot_widgets: Array = []  ## [{"key", "button"}]
var _slot_signature := ""
var _insert_widgets: Array = []  ## [{"item", "button"}]
var _insert_signature := ""

var help_window: PanelContainer
var start_menu: Control

var _toast_time := 0.0
var _refresh_time := 0.0
var _inventory_dirty := true
var _info_text := ""


func setup(p_game: Game) -> void:
	game = p_game
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_info()
	_build_objectives()
	_build_hotbar()
	_build_inventory_window()
	_build_building_window()
	_build_help()
	game.player.inventory.changed.connect(func(): _inventory_dirty = true)
	game.player.craft_queue_changed.connect(_rebuild_queue)


# --- Layout helpers ----------------------------------------------------------

## Anchors `c` to a point of the screen; it grows away from that point as needed.
func _pin(c: Control, anchor: Vector2, grow_h: int, grow_v: int, offset: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y


## Frees all children right away so get_children() is accurate this frame.
func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	root.add_child(p)
	return p


func _label(text: String, size: int = 14, color: Color = Color(0.9, 0.9, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _rich(width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(width, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _title_row(text: String, on_close: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var t := _label(text, 16, Color(1.0, 0.85, 0.5))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var close := Button.new()
	close.text = " x "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(on_close)
	row.add_child(close)
	return row


## Square button showing an item icon with a count in the corner.
func _item_button(item: StringName, count: int, size: int = SLOT) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var count_label := Label.new()
	count_label.name = "Count"
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.offset_right = -3
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(count_label)
	_set_item_button(b, item, count)
	return b


func _set_item_button(b: Button, item: StringName, count: int) -> void:
	b.icon = GameData.icon(item) if item != &"" else null
	b.tooltip_text = GameData.tooltip(item) if item != &"" else "Empty"
	(b.get_node("Count") as Label).text = str(count) if count > 0 else ""


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.11, 0.12, 0.92)
	panel.border_color = Color(0.32, 0.34, 0.36)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	var states := {
		"normal": Color(0.2, 0.21, 0.23), "hover": Color(0.28, 0.3, 0.33),
		"pressed": Color(0.42, 0.34, 0.16), "disabled": Color(0.14, 0.14, 0.15),
		"hover_pressed": Color(0.48, 0.39, 0.18),
	}
	for state in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state]
		sb.border_color = Color(0.95, 0.72, 0.25) if "pressed" in state else Color(0.06, 0.06, 0.07)
		sb.set_border_width_all(2 if "pressed" in state else 1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(4)
		t.set_stylebox(state, "Button", sb)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.06, 0.06, 0.07, 0.96)
	tip.border_color = Color(0.95, 0.72, 0.25)
	tip.set_border_width_all(1)
	tip.set_content_margin_all(6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	return t


# --- Static parts ------------------------------------------------------------

func _build_info() -> void:
	var p := _panel()
	_pin(p, Vector2(0, 0), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END, Vector2(10, 10))
	info_label = _rich(330)
	p.add_child(info_label)


func _build_objectives() -> void:
	var p := _panel()
	_pin(p, Vector2(1, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END, Vector2(-10, 10))
	objectives_label = _rich(360)
	p.add_child(objectives_label)


func _build_hotbar() -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	_pin(col, Vector2(0.5, 1), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN, Vector2(0, -10))

	toast_label = _label("", 16, Color(1, 0.9, 0.6))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 5)
	col.add_child(toast_label)

	mining_bar = ProgressBar.new()
	mining_bar.custom_minimum_size = Vector2(220, 10)
	mining_bar.show_percentage = false
	mining_bar.max_value = 1.0
	mining_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mining_bar.modulate.a = 0.0
	col.add_child(mining_bar)

	queue_row = HBoxContainer.new()
	queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(queue_row)

	var p := PanelContainer.new()
	col.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	p.add_child(row)
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
	for i in GameData.HOTBAR.size():
		var id: StringName = GameData.HOTBAR[i]
		var b := _item_button(id, 0, 52)
		b.toggle_mode = true
		b.pressed.connect(game.select_hotbar.bind(i))
		var key := _label(keys[i], 11, Color(1, 1, 1, 0.6))
		key.position = Vector2(4, 1)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key)
		row.add_child(b)
		hotbar_buttons.append(b)

	var hint := _label("H: help   E: inventory & crafting   F9: sandbox items", 12, Color(1, 1, 1, 0.55))
	root.add_child(hint)
	_pin(hint, Vector2(0, 1), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN, Vector2(12, -8))


func _build_inventory_window() -> void:
	inventory_window = _panel()
	_pin(inventory_window, Vector2(0.5, 0.45), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH, Vector2(-120, 0))
	inventory_window.visible = false
	var v := VBoxContainer.new()
	inventory_window.add_child(v)
	v.add_child(_title_row("Inventory & Crafting", toggle_inventory))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)

	var left := VBoxContainer.new()
	left.add_child(_label("Inventory - click a building to hold it", 12, Color(0.7, 0.7, 0.7)))
	inv_grid = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.custom_minimum_size = Vector2(8 * (SLOT + 4), SLOT * 2)
	left.add_child(inv_grid)
	h.add_child(left)
	h.add_child(VSeparator.new())

	var right := VBoxContainer.new()
	right.add_child(_label("Hand crafting - click: 1, shift+click: 5", 12, Color(0.7, 0.7, 0.7)))
	craft_grid = GridContainer.new()
	craft_grid.columns = 6
	right.add_child(craft_grid)
	h.add_child(right)
	for r in GameData.crafting_recipes():
		var b := _item_button(r, 0)
		b.tooltip_text = GameData.tooltip(r)
		b.pressed.connect(_on_craft_pressed.bind(r))
		craft_grid.add_child(b)
		craft_buttons[r] = b


func _build_building_window() -> void:
	building_window = _panel()
	_pin(building_window, Vector2(1, 0.5), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH, Vector2(-10, 0))
	building_window.visible = false
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(340, 0)
	building_window.add_child(v)
	var title_row := _title_row("", close_building)
	bw_title = title_row.get_child(0) as Label
	v.add_child(title_row)
	bw_lines = _label("", 13, Color(0.82, 0.84, 0.86))
	bw_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bw_lines.custom_minimum_size = Vector2(340, 0)
	v.add_child(bw_lines)
	v.add_child(_label("Contents - click to take", 12, Color(0.7, 0.7, 0.7)))
	bw_slots = HFlowContainer.new()
	v.add_child(bw_slots)
	bw_insert_title = _label("Insert from inventory - click to insert a stack", 12, Color(0.7, 0.7, 0.7))
	v.add_child(bw_insert_title)
	bw_insert = HFlowContainer.new()
	v.add_child(bw_insert)
	bw_recipe_title = _label("Recipe", 12, Color(0.7, 0.7, 0.7))
	v.add_child(bw_recipe_title)
	bw_recipes = GridContainer.new()
	bw_recipes.columns = 6
	v.add_child(bw_recipes)


func _build_help() -> void:
	help_window = _panel()
	_pin(help_window, Vector2(0.5, 0.45), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH, Vector2.ZERO)
	help_window.visible = false
	var v := VBoxContainer.new()
	help_window.add_child(v)
	v.add_child(_title_row("How to play", toggle_help))
	var text := _rich(640)
	text.text = """[b]Controls[/b]
WASD / arrows - walk          Mouse wheel - zoom
1-0, -, = - pick a building from the hotbar (or click it)
Left click - place (hold and drag for belt lines) / open a building
Right click (hold) - mine ore by hand, or pick a building back up
R / Shift+R - rotate the held building (or the hovered one)
Q - copy the hovered building into your hand / empty the hand
E - inventory and hand crafting        Esc - close windows / empty hand

[b]The loop[/b]
1. Mine stone, coal and ore by hand. Craft a [color=#f5c060]Burner Drill[/color] and a [color=#f5c060]Stone Furnace[/color].
2. Drills output to the marked tile: point one into a furnace, or onto a belt.
3. [color=#f5c060]Inserters[/color] move items from the tile behind them to the tile in front.
4. Power: [color=#7fb8ff]Water Pump[/color] (on the shore, water behind) -> pipe -> [color=#7fb8ff]Boiler[/color] (water in at the sides, steam out the front) -> [color=#7fb8ff]Steam Engines[/color] -> [color=#7fb8ff]Power Poles[/color]. Feed the boiler coal.
5. Electric machines must sit inside a pole's blue supply area. Poles wire up automatically.
6. Give an [color=#f5c060]Assembler[/color] a recipe and feed it with inserters to automate gears and circuits.

Tip: hover anything to see what it is doing in the top-left panel."""
	v.add_child(text)


func show_start_menu() -> void:
	start_menu = ColorRect.new()
	(start_menu as ColorRect).color = Color(0.02, 0.03, 0.02, 0.72)
	start_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(start_menu)
	var p := PanelContainer.new()
	start_menu.add_child(p)
	_pin(p, Vector2(0.5, 0.5), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH, Vector2.ZERO)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var title := _label("FACTOR", 40, Color(1.0, 0.8, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("Factory automation proof of concept", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var demo := Button.new()
	demo.text = "Start with a demo factory"
	demo.custom_minimum_size = Vector2(380, 44)
	demo.pressed.connect(_start.bind(true))
	v.add_child(demo)
	var scratch := Button.new()
	scratch.text = "Start from scratch (2 drills, 2 furnaces)"
	scratch.custom_minimum_size = Vector2(380, 44)
	scratch.pressed.connect(_start.bind(false))
	v.add_child(scratch)
	var note := _label("The demo shows power, belts, smelting and assembly running.\nPress H in game for controls.", 12, Color(0.7, 0.7, 0.7))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


func _start(demo: bool) -> void:
	start_menu.queue_free()
	start_menu = null
	game.start_game(demo)


func on_game_started(demo: bool) -> void:
	toast("Demo factory running - press H for controls" if demo else "Mine stone and coal, then place your drills. H for help")


# --- Windows -----------------------------------------------------------------

func toggle_inventory() -> void:
	inventory_window.visible = not inventory_window.visible
	if inventory_window.visible:
		help_window.visible = false
		_inventory_dirty = true


func toggle_help() -> void:
	help_window.visible = not help_window.visible
	if help_window.visible:
		inventory_window.visible = false


## Closes the most recently relevant window. Returns false if none was open.
func close_top_window() -> bool:
	if building_window.visible:
		close_building()
	elif inventory_window.visible:
		inventory_window.visible = false
	elif help_window.visible:
		help_window.visible = false
	else:
		return false
	return true


func open_building(b: Building) -> void:
	building_target = b
	building_window.visible = true
	_slot_signature = "-"
	_insert_signature = "-"
	_clear(bw_recipes)
	var is_assembler := b is Assembler
	bw_recipe_title.visible = is_assembler
	bw_recipes.visible = is_assembler
	if is_assembler:
		for r in GameData.crafting_recipes():
			var btn := _item_button(r, 0, 40)
			btn.toggle_mode = true
			btn.tooltip_text = GameData.tooltip(r)
			btn.pressed.connect(_on_recipe_pressed.bind(r))
			bw_recipes.add_child(btn)
	_refresh_building()


func close_building() -> void:
	building_window.visible = false
	building_target = null


func toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 2.5


# --- Actions -----------------------------------------------------------------

func _on_craft_pressed(r: StringName) -> void:
	var n := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
	if game.player.queue_craft(r, n) == 0:
		toast("Missing ingredients: " + GameData.recipe_text(r))


func _on_recipe_pressed(r: StringName) -> void:
	var asm := building_target as Assembler
	if asm == null:
		return
	if asm.recipe_id != r:
		_give(asm.set_recipe(r))
	_refresh_building()


func _on_slot_pressed(key: String) -> void:
	if _target_valid():
		_give(building_target.ui_take(key))
		_refresh_building()


func _on_insert_pressed(item: StringName) -> void:
	if not _target_valid():
		return
	var inv := game.player.inventory
	var n := building_target.ui_insert(item, mini(inv.count(item), GameData.stack_size(item)))
	inv.remove(item, n)
	_refresh_building()


func _on_inventory_item_pressed(item: StringName) -> void:
	if GameData.is_building_item(item):
		game.set_hand(item)


func _give(items: Dictionary) -> void:
	for k in items:
		game.player.inventory.force_add(k, items[k])


func _target_valid() -> bool:
	return building_target != null and is_instance_valid(building_target) and not building_target.is_queued_for_deletion()


# --- Per-frame updates -------------------------------------------------------

func _process(delta: float) -> void:
	if game == null:
		return
	_toast_time -= delta
	toast_label.modulate.a = clampf(_toast_time, 0.0, 1.0)
	mining_bar.value = game.mine_progress
	mining_bar.modulate.a = 1.0 if game.mine_progress > 0.0 else 0.0
	if queue_bar:
		queue_bar.value = game.player.craft_progress()
	_update_hotbar()
	_update_info()
	_refresh_time -= delta
	if _refresh_time <= 0.0:
		_refresh_time = REFRESH
		_update_objectives()
		if building_window.visible:
			_refresh_building()
	if _inventory_dirty:
		_inventory_dirty = false
		_rebuild_inventory()
		if building_window.visible:
			_insert_signature = "-"


func _update_hotbar() -> void:
	var inv := game.player.inventory
	for i in hotbar_buttons.size():
		var id: StringName = GameData.HOTBAR[i]
		var b := hotbar_buttons[i]
		(b.get_node("Count") as Label).text = str(inv.count(id))
		b.set_pressed_no_signal(game.hand_item == id)
		b.modulate = Color.WHITE if inv.count(id) > 0 else Color(1, 1, 1, 0.45)


func _update_info() -> void:
	if not game.started:
		return
	var w := game.world
	var c := game.mouse_cell
	var lines := PackedStringArray()
	var b := w.get_building(c)
	if b:
		lines.append("[b][color=#f5c060]%s[/color][/b]" % b.display_name())
		for l in b.ui_lines():
			if l != "":
				lines.append(l)
		lines.append("[color=#888]Click to open, hold right mouse to pick up[/color]")
	elif w.ore_at(c) != World.Ore.NONE:
		lines.append("[b][color=#f5c060]%s[/color][/b]  (%d left)" % [GameData.item_name(w.ore_item_at(c)), w.ore_amount_at(c)])
		lines.append("[color=#888]Hold right mouse to mine by hand[/color]")
	elif w.is_water(c):
		lines.append("[b]Water[/b]")
	else:
		lines.append("[b]Ground[/b]")
	if game.hand_item != &"":
		lines.append("")
		lines.append("Holding [color=#f5c060]%s[/color] x%d, facing %s (R rotates)" % [
			GameData.item_name(game.hand_item), game.player.inventory.count(game.hand_item),
			GameData.DIR_NAMES[game.hand_dir]])
		var problem := game.placement_problem(game.hand_origin())
		if problem != "":
			lines.append("[color=#ff7766]%s[/color]" % problem)
	var text := "\n".join(lines)
	if text != _info_text:
		_info_text = text
		info_label.text = text


func _update_objectives() -> void:
	var lines := PackedStringArray(["[b][color=#f5c060]Objectives[/color][/b]"])
	for o in GameData.OBJECTIVES:
		var v := GameData.stat(o["stat"])
		var goal: float = o["goal"]
		if v >= goal:
			lines.append("[color=#7ddc7d][lb]x[rb] %s[/color]" % o["text"])
		else:
			lines.append("[lb] [rb] %s  [color=#888](%d/%d)[/color]" % [o["text"], int(v), int(goal)])
	var text := "\n".join(lines)
	if objectives_label.text != text:
		objectives_label.text = text


func _rebuild_inventory() -> void:
	var inv := game.player.inventory
	_clear(inv_grid)
	for item in inv.sorted_items():
		var b := _item_button(item, inv.count(item))
		b.pressed.connect(_on_inventory_item_pressed.bind(item))
		inv_grid.add_child(b)
	for r in craft_buttons:
		var n := game.player.craftable_count(r)
		var b: Button = craft_buttons[r]
		(b.get_node("Count") as Label).text = str(n) if n > 0 else ""
		b.modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.4)


func _rebuild_queue() -> void:
	_clear(queue_row)
	queue_bar = null
	var shown := 0
	for entry in game.player.craft_queue:
		if not entry["give"]:
			continue
		if shown == 0:
			var first := VBoxContainer.new()
			var icon := TextureRect.new()
			icon.texture = GameData.icon(entry["recipe"])
			icon.custom_minimum_size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			first.add_child(icon)
			queue_bar = ProgressBar.new()
			queue_bar.custom_minimum_size = Vector2(32, 5)
			queue_bar.show_percentage = false
			queue_bar.max_value = 1.0
			first.add_child(queue_bar)
			queue_row.add_child(first)
		elif shown < 10:
			var icon := TextureRect.new()
			icon.texture = GameData.icon(entry["recipe"])
			icon.custom_minimum_size = Vector2(24, 24)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.modulate.a = 0.7
			queue_row.add_child(icon)
		shown += 1


func _refresh_building() -> void:
	if not _target_valid():
		close_building()
		return
	var b := building_target
	bw_title.text = b.display_name()
	var lines := PackedStringArray()
	for l in b.ui_lines():
		if l != "":
			lines.append(l)
	bw_lines.text = "\n".join(lines)

	# Slots: rebuild only when the layout changes so buttons stay clickable.
	var slots := b.ui_slots()
	var sig := ""
	for s in slots:
		sig += "%s:%s;" % [s["key"], s["item"]]
	if sig != _slot_signature:
		_slot_signature = sig
		_clear(bw_slots)
		_slot_widgets.clear()
		for s in slots:
			var box := VBoxContainer.new()
			box.add_child(_label(s["label"], 11, Color(0.7, 0.7, 0.7)))
			var btn := _item_button(s["item"], s["count"])
			btn.pressed.connect(_on_slot_pressed.bind(s["key"]))
			box.add_child(btn)
			bw_slots.add_child(box)
			_slot_widgets.append({"key": s["key"], "button": btn})
	else:
		for i in slots.size():
			_set_item_button(_slot_widgets[i]["button"], slots[i]["item"], slots[i]["count"])

	var inv := game.player.inventory
	var accepted: Array = []
	for item in inv.sorted_items():
		if b.ui_accepts(item):
			accepted.append(item)
	var isig := ",".join(PackedStringArray(accepted))
	if isig != _insert_signature:
		_insert_signature = isig
		_clear(bw_insert)
		_insert_widgets.clear()
		for item in accepted:
			var btn := _item_button(item, inv.count(item), 40)
			btn.pressed.connect(_on_insert_pressed.bind(item))
			bw_insert.add_child(btn)
			_insert_widgets.append({"item": item, "button": btn})
	else:
		for w in _insert_widgets:
			_set_item_button(w["button"], w["item"], inv.count(w["item"]))
	bw_insert_title.visible = not accepted.is_empty()

	if b is Assembler:
		var recipes := GameData.crafting_recipes()
		var children := bw_recipes.get_children()
		for i in mini(recipes.size(), children.size()):
			(children[i] as Button).set_pressed_no_signal((b as Assembler).recipe_id == recipes[i])
