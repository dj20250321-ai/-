extends Node3D

static var char_idx := 0

const PX := 1.0 / 16.0
const HALF_W := 14
const MAX_X := 7
const AHEAD := 26
const BEHIND := 8
const HOP_TIME := 0.13
const CHASE_SPEED := 0.4
const CAR_RECT := Rect2(64, 144, 32, 32)
const ATLAS := preload("res://Tilemap/tilemap_packed.png")
const PLAYERS := [Rect2(0, 160, 16, 16), Rect2(16, 160, 16, 16), Rect2(0, 144, 16, 16)]
const OBSTACLES := [
	Rect2(128, 80, 16, 32), Rect2(128, 80, 16, 32), Rect2(128, 80, 16, 32),
	Rect2(112, 80, 16, 32), Rect2(160, 144, 16, 16), Rect2(176, 80, 16, 16),
	Rect2(160, 160, 16, 16), Rect2(32, 112, 16, 32),
]
const TREE_RECTS := [Rect2(128, 80, 16, 32), Rect2(112, 80, 16, 32)]

class Lane:
	var row := 0
	var road := false
	var node: Node3D
	var blocked := {}
	var cars: Array[Node3D] = []
	var speed := 0.0
	var dir := 1

var atlas_img: Image
var lanes := {}
var player: Node3D
var player_sprite: Sprite3D
var cam: Camera3D
var cam_focus := Vector3.ZERO
var cell := Vector2i(0, 0)
var max_row := 0
var chase_row := -3.0
var state := "ready"
var hopping := false
var hop_t := 0.0
var hop_from := Vector3.ZERO
var hop_to := Vector3.ZERO
var queued := Vector2i.ZERO
var touch_start := Vector2.ZERO
var died_at := 0.0
var best := 0
var score_label: Label
var best_label: Label
var msg_label: Label


func _ready() -> void:
	randomize()
	atlas_img = ATLAS.get_image()
	atlas_img.convert(Image.FORMAT_RGBA8)
	_load_best()
	_setup_world()
	_setup_hud()
	for r in range(-2, AHEAD):
		_make_lane(r)
	_make_player()


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8fb8d4")
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 15.0
	cam.near = 0.1
	cam.far = 120.0
	cam.rotation_degrees = Vector3(-35.264, 45, 0)
	add_child(cam)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	score_label = _make_label(layer, 56, VERTICAL_ALIGNMENT_TOP, 10.0)
	score_label.text = "0"
	best_label = _make_label(layer, 20, VERTICAL_ALIGNMENT_TOP, 78.0)
	best_label.text = "최고 기록 %d" % best
	msg_label = _make_label(layer, 28, VERTICAL_ALIGNMENT_BOTTOM, -50.0)
	msg_label.text = "방향키/WASD 또는 화면 스와이프로 이동\n탭하거나 위쪽 키를 눌러 시작"


func _make_label(parent: Node, font_size: int, valign: int, margin: float) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = valign
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color("#1d2433"))
	l.add_theme_constant_override("outline_size", maxi(4, int(font_size / 6.0)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if valign == VERTICAL_ALIGNMENT_TOP:
		l.offset_top = margin
	else:
		l.offset_bottom = margin
	return l


func _make_sprite(rect: Rect2, pad := 0.0) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = ATLAS
	s.region_enabled = true
	s.region_rect = rect
	s.pixel_size = PX
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.offset = Vector2(0, rect.size.y * 0.5 - pad)
	return s


@warning_ignore("integer_division")
func _tile_rect(i: int) -> Rect2i:
	return Rect2i((i % 12) * 16, (i / 12) * 16, 16, 16)


func _make_player() -> void:
	player = Node3D.new()
	add_child(player)
	player_sprite = _make_sprite(PLAYERS[char_idx % PLAYERS.size()])
	player.add_child(player_sprite)
	cam_focus = player.position


func _make_lane(r: int) -> void:
	var lane := Lane.new()
	lane.row = r
	var road_streak := 0
	var k := r - 1
	while lanes.has(k) and lanes[k].road:
		road_streak += 1
		k -= 1
	lane.road = r > 2 and road_streak < 4 and randf() < 0.62
	lane.node = Node3D.new()
	lane.node.position = Vector3(0, 0, -r)
	add_child(lane.node)

	var width := HALF_W * 2 + 1
	var img := Image.create(width * 16, 16, false, Image.FORMAT_RGBA8)
	for tx in range(width):
		var t := 19
		if not lane.road:
			t = 100 if randf() < 0.2 else 88
		img.blit_rect(atlas_img, _tile_rect(t), Vector2i(tx * 16, 0))
	var ground := Sprite3D.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.pixel_size = PX
	ground.axis = Vector3.AXIS_Y
	ground.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var shade := 1.0 if r % 2 == 0 else 0.93
	ground.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	ground.modulate = Color(shade, shade, shade)
	lane.node.add_child(ground)

	if lane.road:
		lane.dir = 1 if randf() < 0.5 else -1
		lane.speed = randf_range(2.0, 4.0) + minf(r * 0.03, 2.5)
		var x := -13.0 + randf() * 4.0
		while x < 13.0:
			var car := _make_sprite(CAR_RECT, 3.0)
			car.modulate = Color.from_hsv(randf(), 0.45, 1.0)
			car.flip_h = lane.dir < 0
			car.position.x = x
			lane.node.add_child(car)
			lane.cars.append(car)
			x += randf_range(5.0, 10.0)
	else:
		for x in range(-HALF_W + 1, HALF_W):
			var inside := absi(x) <= MAX_X
			var rect: Rect2
			if not inside:
				if randf() < 0.85:
					rect = TREE_RECTS[randi() % 2]
				else:
					continue
			elif r > 2 and randf() < 0.13:
				rect = OBSTACLES[randi() % OBSTACLES.size()]
				lane.blocked[x] = true
			else:
				continue
			var o := _make_sprite(rect)
			o.position.x = x
			lane.node.add_child(o)
	lanes[r] = lane


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_UP, KEY_W, KEY_SPACE:
				_act(Vector2i(0, 1))
			KEY_DOWN, KEY_S:
				_act(Vector2i(0, -1))
			KEY_LEFT, KEY_A:
				_act(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D:
				_act(Vector2i(1, 0))
	elif e is InputEventScreenTouch:
		if e.pressed:
			touch_start = e.position
		else:
			var d: Vector2 = e.position - touch_start
			if d.length() < 30.0:
				_act(Vector2i(0, 1))
			elif absf(d.x) > absf(d.y):
				_act(Vector2i(1 if d.x > 0 else -1, 0))
			else:
				_act(Vector2i(0, 1 if d.y < 0 else -1))


func _act(d: Vector2i) -> void:
	if state == "dead":
		if Time.get_ticks_msec() / 1000.0 - died_at > 0.5:
			char_idx += 1
			get_tree().reload_current_scene()
		return
	if hopping:
		queued = d
		return
	var nx := cell.x + d.x
	var nr := cell.y + d.y
	if absi(nx) > MAX_X or nr < max_row - 3 or nr < 0:
		return
	var lane: Lane = lanes.get(nr)
	if lane == null or lane.blocked.has(nx):
		return
	if state == "ready" and d.y > 0:
		state = "playing"
		msg_label.text = ""
	cell = Vector2i(nx, nr)
	hop_from = player.position
	hop_to = Vector3(nx, 0, -nr)
	hop_t = 0.0
	hopping = true
	if d.x != 0:
		player_sprite.flip_h = d.x < 0
	if nr > max_row:
		max_row = nr
		score_label.text = str(max_row)


func _process(dt: float) -> void:
	_update_hop(dt)
	_update_cars(dt)
	if state == "playing":
		_update_chase(dt)
		_check_hit()
	_update_camera(dt)
	_update_lanes()


func _update_hop(dt: float) -> void:
	if not hopping:
		return
	hop_t = minf(hop_t + dt / HOP_TIME, 1.0)
	player.position = hop_from.lerp(hop_to, hop_t)
	player_sprite.position.y = sin(PI * hop_t) * 0.45
	if hop_t >= 1.0:
		hopping = false
		player_sprite.position.y = 0.0
		if queued != Vector2i.ZERO:
			var q := queued
			queued = Vector2i.ZERO
			_act(q)


func _update_cars(dt: float) -> void:
	for lane: Lane in lanes.values():
		for car in lane.cars:
			car.position.x += lane.dir * lane.speed * dt
			if car.position.x > 13.5:
				car.position.x -= 27.0
			elif car.position.x < -13.5:
				car.position.x += 27.0


func _update_chase(dt: float) -> void:
	chase_row += CHASE_SPEED * dt * (1.0 + max_row / 150.0)
	chase_row = maxf(chase_row, max_row - 9.0)
	var prow := -player.position.z
	if chase_row >= prow - 0.2:
		_die("뒤처지면 안 돼요!")
	elif prow - chase_row < 2.5:
		msg_label.text = "서두르세요!"
	elif msg_label.text == "서두르세요!":
		msg_label.text = ""


func _check_hit() -> void:
	var lane: Lane = lanes.get(roundi(-player.position.z))
	if lane == null or not lane.road:
		return
	for car in lane.cars:
		if absf(car.position.x - player.position.x) < 1.0:
			player_sprite.scale.y = 0.25
			_die("차에 치였어요!")
			return


func _die(reason: String) -> void:
	if state == "dead":
		return
	state = "dead"
	died_at = Time.get_ticks_msec() / 1000.0
	if max_row > best:
		best = max_row
		_save_best()
	best_label.text = "최고 기록 %d" % best
	msg_label.text = "%s\n점수 %d\n탭하거나 아무 방향키를 눌러 다시 시작" % [reason, max_row]


func _update_camera(dt: float) -> void:
	var target := Vector3(player.position.x * 0.6, 0, player.position.z - 1.5)
	cam_focus = cam_focus.lerp(target, 1.0 - exp(-6.0 * dt))
	cam.position = cam_focus + Vector3(1, 1, 1) * 30.0


func _update_lanes() -> void:
	for r in range(cell.y - BEHIND, cell.y + AHEAD):
		if not lanes.has(r) and r >= -2:
			_make_lane(r)
	for r in lanes.keys():
		if r < cell.y - BEHIND - 2:
			lanes[r].node.queue_free()
			lanes.erase(r)


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") == OK:
		best = int(cfg.get_value("game", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save("user://save.cfg")
