extends Node
## Captures a screenshot of the running demo, for docs and visual checks.
##   godot --path . res://tools/screenshot.tscn -- --demo --out=shot.png --wait=6 --zoom=1.0 --at=68,46
## Optional: --hold=belt --dir=1 --mouse=x,y --inventory --help --open=x,y --menu (no --demo)
## Needs a real display (or xvfb-run); it does not work with --headless.

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var game: Game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	if not game.started and not args.has("menu"):
		game.start_game(true)
	if args.has("at"):
		var at: PackedStringArray = args["at"].split(",")
		game.player.position = World.cell_center(Vector2i(int(at[0]), int(at[1])))
	if args.has("zoom"):
		var z := float(args["zoom"])
		game.camera.zoom = Vector2(z, z)
	if args.has("hold"):
		game.set_hand(StringName(args["hold"]))
		game.hand_dir = int(args.get("dir", "1"))
	if args.has("help"):
		game.hud.toggle_help()
	if args.has("inventory"):
		game.hud.toggle_inventory()
	if args.has("open"):
		var at: PackedStringArray = args["open"].split(",")
		game.hud.open_building(game.world.get_building(Vector2i(int(at[0]), int(at[1]))))
	if args.has("mouse"):
		var m: PackedStringArray = args["mouse"].split(",")
		get_viewport().warp_mouse(Vector2(float(m[0]), float(m[1])))
	await get_tree().create_timer(float(args.get("wait", "5"))).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.get("out", "user://screenshot.png"))
	print("saved ", args.get("out", "user://screenshot.png"))
	get_tree().quit()
