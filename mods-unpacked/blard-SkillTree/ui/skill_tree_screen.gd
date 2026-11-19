extends CanvasLayer
# blard-SkillTree: full-screen passive tree.
#   MODE_LEVEL_UP: shown between the wave and the shop for each player with unspent points.
#   MODE_VIEW:     opened from the shop (P / Back) to view, navigate, spend and refund.
#
# The screen sits on top of everything and eats keyboard/controller input while open, so the
# shop or the end-of-wave screen behind it never sees those presses. Mouse input goes through
# the GUI; the full-screen canvas stops it from reaching anything underneath.

signal tree_changed(player_index)
signal finished

const SkillTree = preload("res://mods-unpacked/blard-SkillTree/skill_tree.gd")

const MODE_LEVEL_UP := 0
const MODE_VIEW := 1

const THEME_PATH := "res://resources/themes/base_theme.tres"
const FONT_DIR := "res://resources/fonts/actual/base/"
const TREE_RADIUS := 1080.0
const MIN_ZOOM := 0.08
const MAX_ZOOM := 1.6
const NODE_RADIUS := [30.0, 15.0, 25.0, 36.0]

var SECTOR_COLORS = [
	Color("e0574f"), # Vitality
	Color("f08a3c"), # Melee
	Color("f2d15a"), # Precision
	Color("6fd16f"), # Ranged
	Color("ff6a2b"), # Elemental
	Color("6fa8f5"), # Engineering
	Color("e6c240"), # Fortune
	Color("7fe6d8"), # Agility
]
var RING_COLOR = Color("b9b9c8")
var GOLD = Color("ffd560")
var PREVIEW = Color("8fe3ff")
var GOOD_TEXT = Color("8ef08e")
var BAD_TEXT = Color("ff7b7b")
var BONUS_TEXT = Color("d59bff")
var FRONTIER = Color("c48cff")
var ORBIT = Color("78e6ff")
var MINOR = Color("e8e8e8")
var RED_CRIT = Color("ff5a5a")
var RELIC = Color("fff1b8")
var ODDITY = Color("5ee6c8")

var mode: int = MODE_VIEW
var player_index: int = 0
var _player_queue = []

var _root: Control
var _canvas = null
var _title_label: Label
var _points_label: Label
var _info_panel: PanelContainer
var _info_title: Label
var _info_kind: Label
var _info_stats: RichTextLabel
var _info_status: Label
var _hint_label: Label
var _close_button: Button

var _font_small: Font
var _font_tiny: Font
var _font_mid: Font
var _font_big: Font

var cam = Vector2.ZERO
var zoom = 0.5
var _cam_target = Vector2.ZERO
var _following = false
var selected_id = SkillTree.START_ID
var _message = ""
var _message_time = 0.0

var _dragging = false
var _drag_distance = 0.0
var _stick = Vector2.ZERO
var _rstick = Vector2.ZERO
var _move_cooldown = 0.0

var _closing = false
var _closing_frames = 0
var _pause_menu = null
var _pause_was_enabled = true
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


class TreeCanvas:
	extends Control
	var screen = null

	func _draw() -> void:
		if screen != null:
			screen.draw_tree(self)


func setup(p_mode: int, players: Array) -> void:
	mode = p_mode
	_player_queue = players.duplicate()


func _ready() -> void:
	layer = 100
	pause_mode = Node.PAUSE_MODE_PROCESS
	_load_fonts()
	_build_ui()
	_block_pause_menu()
	_previous_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _player_queue.empty():
		_player_queue.push_back(0)
	_show_player(_player_queue.pop_front())


# ---------------- UI construction ----------------

func _load_fonts() -> void:
	_font_tiny = _try_load_font("font_22.tres")
	_font_small = _try_load_font("font_26_outline.tres")
	_font_mid = _try_load_font("font_32_outline.tres")
	_font_big = _try_load_font("font_40_outline.tres")


func _try_load_font(file_name: String) -> Font:
	var path: String = FONT_DIR + file_name
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Font:
			return res
	return null


func _full_rect(control: Control) -> void:
	control.anchor_left = 0
	control.anchor_top = 0
	control.anchor_right = 1
	control.anchor_bottom = 1
	control.margin_left = 0
	control.margin_top = 0
	control.margin_right = 0
	control.margin_bottom = 0


func _panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1, 0.92)
	style.border_color = Color(0.35, 0.35, 0.45, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _make_label(font: Font, color: Color = Color.white) -> Label:
	var label = Label.new()
	if font != null:
		label.add_font_override("font", font)
	label.add_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "SkillTreeRoot"
	_full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(THEME_PATH):
		var theme_res = load(THEME_PATH)
		if theme_res is Theme:
			_root.theme = theme_res
	add_child(_root)

	var background = ColorRect.new()
	_full_rect(background)
	background.color = Color(0.025, 0.025, 0.04, 0.97)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	_canvas = TreeCanvas.new()
	_canvas.screen = self
	_full_rect(_canvas)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.connect("gui_input", self, "_on_canvas_gui_input")
	_root.add_child(_canvas)

	# Header: title + points (top left)
	var header = PanelContainer.new()
	header.add_stylebox_override("panel", _panel_style())
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.rect_position = Vector2(24, 20)
	var header_box = VBoxContainer.new()
	header_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_box)
	_title_label = _make_label(_font_big, GOLD)
	header_box.add_child(_title_label)
	_points_label = _make_label(_font_mid)
	header_box.add_child(_points_label)
	_root.add_child(header)

	# Close / continue (top right)
	_close_button = Button.new()
	_close_button.focus_mode = Control.FOCUS_NONE
	if _font_mid != null:
		_close_button.add_font_override("font", _font_mid)
	_close_button.anchor_left = 1
	_close_button.anchor_right = 1
	_close_button.margin_left = -330
	_close_button.margin_right = -24
	_close_button.margin_top = 24
	_close_button.margin_bottom = 94
	_close_button.connect("pressed", self, "_close")
	_root.add_child(_close_button)

	# Node info (bottom left)
	_info_panel = PanelContainer.new()
	_info_panel.add_stylebox_override("panel", _panel_style())
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.anchor_top = 1
	_info_panel.anchor_bottom = 1
	_info_panel.margin_left = 24
	_info_panel.margin_right = 584
	_info_panel.margin_top = -330
	_info_panel.margin_bottom = -70
	var info_box = VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(info_box)
	_info_title = _make_label(_font_mid, GOLD)
	info_box.add_child(_info_title)
	_info_kind = _make_label(_font_tiny, Color(0.7, 0.7, 0.8))
	info_box.add_child(_info_kind)
	_info_stats = RichTextLabel.new()
	_info_stats.bbcode_enabled = true
	_info_stats.scroll_active = false
	_info_stats.fit_content_height = true
	_info_stats.rect_min_size = Vector2(520, 40)
	_info_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_small != null:
		_info_stats.add_font_override("normal_font", _font_small)
	info_box.add_child(_info_stats)
	_info_status = _make_label(_font_tiny, Color(0.85, 0.85, 0.9))
	_info_status.autowrap = true
	_info_status.rect_min_size = Vector2(520, 0)
	info_box.add_child(_info_status)
	_root.add_child(_info_panel)

	# Controls hint (bottom)
	_hint_label = _make_label(_font_tiny, Color(0.75, 0.75, 0.82))
	_hint_label.align = Label.ALIGN_CENTER
	_hint_label.anchor_top = 1
	_hint_label.anchor_bottom = 1
	_hint_label.anchor_right = 1
	_hint_label.margin_top = -52
	_hint_label.margin_bottom = -16
	_root.add_child(_hint_label)


# ---------------- Player flow ----------------

func _show_player(p_player_index: int) -> void:
	player_index = p_player_index
	if SkillTree.refresh_scaling(player_index):
		emit_signal("tree_changed", player_index)
	selected_id = SkillTree.START_ID
	cam = Vector2.ZERO
	_cam_target = Vector2.ZERO
	_following = false
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	zoom = clamp(min(view_size.x, view_size.y) * 0.46 / TREE_RADIUS, MIN_ZOOM, MAX_ZOOM)
	_stick = Vector2.ZERO
	_rstick = Vector2.ZERO
	_message = ""
	_refresh_all()


func _refresh_all() -> void:
	var who: String = SkillTree.player_name(player_index)
	var title = "LEVEL UP!" if mode == MODE_LEVEL_UP else "SKILL TREE"
	if who != "":
		title += "  -  " + who
	_title_label.text = title
	if RunData.is_coop_run:
		_title_label.add_color_override("font_color", CoopService.get_player_color(player_index))
	var points = SkillTree.get_points(player_index)
	_points_label.text = "Skill points: %d      Allocated: %d" % [points, SkillTree.allocated_count(player_index)]
	_points_label.add_color_override("font_color", GOLD if points > 0 else Color(0.8, 0.8, 0.85))
	if mode == MODE_LEVEL_UP:
		_close_button.text = "Next player" if not _player_queue.empty() else "Continue"
	else:
		_close_button.text = "Close"
	if SkillTree.player_uses_gamepad(player_index):
		_hint_label.text = "Stick / D-pad: move     A: allocate     Y: refund     Right stick: pan     LB / RB: zoom     B: " + _close_button.text.to_lower()
	else:
		_hint_label.text = "Click: allocate     Right-click: refund     Drag: pan     Wheel: zoom     Arrows / WASD: move     Enter: allocate     Esc: " + _close_button.text.to_lower()
	_refresh_info()
	_canvas.update()


func _refresh_info() -> void:
	var data = SkillTree.get_node_data(player_index, selected_id)
	if data.empty():
		_info_panel.visible = false
		return
	_info_panel.visible = true
	_info_title.text = SkillTree.node_title(data)
	var kind: int = int(data.get("kind", 1))
	var sector: int = int(data.get("sector", -1))
	var kind_text: String = ["Origin", "Passive", "Notable", "Keystone"][kind]
	var flavor: String = str(data.get("flavor", ""))
	if flavor != "":
		kind_text = SkillTree.flavor_label(flavor) + " " + ["Passive", "Passive", "Notable", "Capstone"][kind]
	elif str(data.get("special", "")) == "relic":
		kind_text = "Relic  -  one of a kind"
	elif str(data.get("special", "")) == "oddity":
		kind_text = "Oddity Capstone"
	elif str(data.get("special", "")) == "named":
		kind_text = "Named Notable"
	elif str(data.get("special", "")) == "minor":
		kind_text = "Minor Passive  -  off the beaten path"
	elif SkillTree.is_generated(data):
		kind_text = "Uncharted " + ["Passive", "Passive", "Notable", "Capstone"][kind]
	if sector >= 0 and sector < SkillTree.TreeData.SECTORS.size() and str(data.get("special", "")) != "minor":
		kind_text += "  -  " + str(SkillTree.TreeData.SECTORS[sector])
	if bool(data.get("novel", false)):
		kind_text += "  -  New direction"
	_info_kind.text = kind_text

	var mult: float = SkillTree.node_mult(data, SkillTree.get_state(player_index).mult)
	var lines = []
	for stat in data.get("stats", []):
		var value = SkillTree.scaled_value(int(stat[1]), mult)
		var color: Color = GOOD_TEXT if SkillTree.is_stat_good(stat[0], value) else BAD_TEXT
		lines.push_back("[color=#%s]%s[/color]" % [color.to_html(false), SkillTree.describe_stat(stat[0], value)])
	if flavor != "":
		var level: int = SkillTree.flavor_level(player_index, flavor)
		var flavor_hex: String = SkillTree.flavor_color(flavor).to_html(false)
		for entry in data.get("scaling", []):
			lines.push_back("[color=#%s]%s[/color]" % [flavor_hex, SkillTree.describe_scaling(entry[0], float(entry[1]), level, mult)])
		var source: String = {"meca": "your Evolution", "mutant": "your negative Evolution", "curse": "your Curse"}.get(flavor, "")
		lines.push_back("[color=#999999]%s level: %d (= %s)[/color]" % [SkillTree.flavor_label(flavor), level, source])
	for entry in data.get("mods", []):
		lines.push_back("[color=#%s]%s[/color]" % [RED_CRIT.to_html(false), SkillTree.describe_mod(entry)])
	var relic_id: String = str(data.get("relic", ""))
	if relic_id != "" and SkillTree.RELIC_TEXT.has(relic_id):
		lines.push_back("[color=#%s]%s[/color]" % [RELIC.to_html(false), SkillTree.RELIC_TEXT[relic_id]])
	for bonus in data.get("bonus", []):
		lines.push_back("[color=#%s]%s[/color]" % [BONUS_TEXT.to_html(false), SkillTree.describe_bonus(bonus)])
	if lines.empty():
		lines.push_back("Where every build begins.")
	_info_stats.bbcode_text = PoolStringArray(lines).join("\n")

	var status = ""
	var alloc = SkillTree.allocated_set(player_index)
	var uses_pad = SkillTree.player_uses_gamepad(player_index)
	if selected_id == SkillTree.START_ID:
		status = "Starting point."
	elif alloc.has(selected_id):
		status = "Allocated."
		if SkillTree.can_refund(player_index, selected_id):
			status += "  " + ("Y" if uses_pad else "Right-click") + " to refund."
	else:
		var cost = SkillTree.path_to(player_index, selected_id).size()
		var points = SkillTree.get_points(player_index)
		if cost == 0:
			status = "Unreachable."
		elif cost > points:
			status = "Needs %d point%s (you have %d)." % [cost, "" if cost == 1 else "s", points]
		else:
			status = "Costs %d point%s.  %s to allocate." % [cost, "" if cost == 1 else "s", "A" if uses_pad else "Click"]
	if SkillTree.is_frontier(data) and not SkillTree.is_expanded(player_index, selected_id):
		if int(data.get("orbit", 0)) != 0:
			status += "\nOrbit frontier: the next cluster grows around the tree."
		else:
			status += "\nFrontier: taking it reveals a new cluster beyond."
		if bool(data.get("novel", false)):
			status += " Offers stats you haven't been building."
	if _message != "":
		status = _message
	_info_status.text = status


# ---------------- Drawing ----------------

func _to_screen(data: Dictionary, center: Vector2) -> Vector2:
	return center + (Vector2(data.x, data.y) - cam) * zoom


func _to_world(screen_pos: Vector2) -> Vector2:
	return cam + (screen_pos - _canvas.rect_size / 2.0) / zoom


func _node_color(data: Dictionary) -> Color:
	var flavor: String = str(data.get("flavor", ""))
	if flavor != "":
		return SkillTree.flavor_color(flavor)
	var sector: int = int(data.get("sector", -1))
	if sector >= 0 and sector < SECTOR_COLORS.size():
		return SECTOR_COLORS[sector]
	if int(data.get("kind", 1)) == SkillTree.Kind.START:
		return GOLD
	if str(data.get("special", "")) == "minor":
		return MINOR
	return RING_COLOR


func _node_icon(data: Dictionary) -> Texture:
	var stats: Array = data.get("stats", [])
	if stats.empty():
		return null
	var stat_key: String = stats[0][0]
	var node = SkillTree.Config.mod_node()
	if node != null and node.icon_cache.has(stat_key):
		return node.icon_cache[stat_key]
	var icon = ItemService.get_stat_small_icon(Keys.generate_hash(stat_key))
	if not icon is Texture:
		icon = null
	if node != null:
		node.icon_cache[stat_key] = icon
	return icon


func draw_tree(c: Control) -> void:
	var g = SkillTree.graph(player_index)
	var center: Vector2 = c.rect_size / 2.0
	var alloc = SkillTree.allocated_set(player_index)
	var preview = {}
	if not alloc.has(selected_id):
		for id in SkillTree.path_to(player_index, selected_id):
			preview[id] = true
	var line_scale: float = clamp(zoom * 1.6, 0.6, 2.0)

	# Sector names around the edge.
	if _font_mid != null:
		for k in SkillTree.TreeData.SECTORS.size():
			var angle = deg2rad(-90.0 + 45.0 * k)
			var world = Vector2(cos(angle), sin(angle)) * (TREE_RADIUS + 110.0)
			var pos: Vector2 = center + (world - cam) * zoom
			var text: String = str(SkillTree.TreeData.SECTORS[k]).to_upper()
			var text_size: Vector2 = _font_mid.get_string_size(text)
			var col: Color = SECTOR_COLORS[k]
			col.a = 0.55
			c.draw_string(_font_mid, pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0), text, col)

	# Edges
	for e in g.edges:
		var a: Dictionary = g.nodes[e[0]]
		var b: Dictionary = g.nodes[e[1]]
		var pa = _to_screen(a, center)
		var pb = _to_screen(b, center)
		var a_on: bool = alloc.has(e[0])
		var b_on: bool = alloc.has(e[1])
		var a_path: bool = a_on or preview.has(e[0])
		var b_path: bool = b_on or preview.has(e[1])
		var color = Color(0.3, 0.3, 0.36)
		var width = 3.0
		if a_on and b_on:
			color = GOLD
			width = 6.0
		elif a_path and b_path:
			color = PREVIEW
			width = 5.0
		elif a_on or b_on:
			color = Color(0.62, 0.58, 0.45)
			width = 4.0
		c.draw_line(pa, pb, color, width * line_scale, true)

	# Nodes
	var view_rect = Rect2(Vector2(-80, -80), c.rect_size + Vector2(160, 160))
	for id in g.order:
		var data: Dictionary = g.nodes[id]
		var pos = _to_screen(data, center)
		if not view_rect.has_point(pos):
			continue
		var kind: int = int(data.kind)
		var radius: float = NODE_RADIUS[kind] * zoom
		var base_color = _node_color(data)
		var allocated: bool = alloc.has(id)
		var reachable: bool = SkillTree.is_reachable(g, id, alloc)
		var outline: Color
		var fill: Color
		var icon_tint = Color(1, 1, 1, 1)
		if allocated:
			outline = GOLD
			fill = base_color.darkened(0.25)
		elif preview.has(id):
			outline = PREVIEW
			fill = Color(0.1, 0.13, 0.17)
			icon_tint = Color(1, 1, 1, 0.9)
		elif reachable:
			outline = base_color
			fill = Color(0.1, 0.1, 0.13)
			icon_tint = Color(1, 1, 1, 0.85)
		else:
			outline = base_color.darkened(0.55)
			fill = Color(0.06, 0.06, 0.08)
			icon_tint = Color(1, 1, 1, 0.35)
		var ring: float = (5.0 if kind >= SkillTree.Kind.NOTABLE else 3.5) * line_scale
		var generated: bool = SkillTree.is_generated(data)
		if SkillTree.is_frontier(data) and not SkillTree.is_expanded(player_index, id):
			var pulse: float = 0.5 + 0.5 * sin(OS.get_ticks_msec() / 300.0)
			var glow: Color = ORBIT if int(data.get("orbit", 0)) != 0 else FRONTIER
			glow.a = 0.25 + 0.35 * pulse
			c.draw_arc(pos, radius + ring + (12.0 + 4.0 * pulse) * line_scale, 0.0, TAU, 40, glow, 3.0 * line_scale, true)
		if kind == SkillTree.Kind.KEYSTONE:
			var halo: Color = FRONTIER.darkened(0.2) if generated else outline.darkened(0.3)
			var special: String = str(data.get("special", ""))
			if special == "relic":
				halo = RELIC
				var sparkle: float = 0.5 + 0.5 * sin(OS.get_ticks_msec() / 220.0)
				var star: Color = RELIC
				star.a = 0.35 + 0.4 * sparkle
				c.draw_arc(pos, radius + ring * 3.4, 0.0, TAU, 48, star, 2.0 * line_scale, true)
			elif special == "oddity":
				halo = ODDITY.darkened(0.15)
			c.draw_circle(pos, radius + ring * 2.2, halo)
		c.draw_circle(pos, radius + ring, outline)
		c.draw_circle(pos, radius, fill)
		if str(data.get("flavor", "")) != "":
			var mark: Color = base_color
			mark.a = 0.9 if allocated or reachable else 0.45
			c.draw_arc(pos, radius * 0.82, 0.0, TAU, 32, mark, 2.5 * line_scale, true)
		var icon = _node_icon(data)
		if icon != null:
			var icon_size = radius * 1.25
			c.draw_texture_rect(icon, Rect2(pos - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), false, icon_tint)
		if id == selected_id:
			c.draw_arc(pos, radius + ring + 7.0 * line_scale, 0.0, TAU, 40, Color(1, 1, 1, 0.95), 3.0 * line_scale, true)
		if kind >= SkillTree.Kind.NOTABLE and zoom >= 0.34 and _font_tiny != null:
			var title: String = data.name
			var text_size: Vector2 = _font_tiny.get_string_size(title)
			var text_color: Color = Color(1, 1, 1, 0.95) if allocated or reachable or preview.has(id) else Color(0.7, 0.7, 0.75, 0.6)
			c.draw_string(_font_tiny, pos + Vector2(-text_size.x / 2.0, radius + ring + text_size.y), title, text_color)


# ---------------- Actions ----------------

func _select(id: String, follow: bool) -> void:
	if id == "" or id == selected_id:
		return
	selected_id = id
	_message = ""
	if follow:
		var data = SkillTree.get_node_data(player_index, id)
		_cam_target = Vector2(data.x, data.y)
		_following = true
	_refresh_info()
	_canvas.update()


func _activate() -> void:
	if SkillTree.get_node_data(player_index, selected_id).empty():
		return
	if SkillTree.allocated_set(player_index).has(selected_id):
		return
	var cost = SkillTree.path_to(player_index, selected_id).size()
	var nodes_before: int = SkillTree.graph(player_index).order.size()
	if SkillTree.allocate_path(player_index, selected_id) > 0:
		emit_signal("tree_changed", player_index)
		var grown: int = SkillTree.graph(player_index).order.size() - nodes_before
		_refresh_all()
		if grown > 0:
			_flash("The tree grows: %d new node%s revealed!" % [grown, "" if grown == 1 else "s"])
	else:
		_flash("Not enough skill points." if cost > 0 else "Can't reach that node.")


func _refund_selected() -> void:
	if not SkillTree.allocated_set(player_index).has(selected_id) or selected_id == SkillTree.START_ID:
		return
	if not SkillTree.Config.flag("allow_refunds"):
		_flash("Refunds are turned off in Mod Options.")
		return
	if SkillTree.refund(player_index, selected_id):
		emit_signal("tree_changed", player_index)
		_refresh_all()
	else:
		_flash("Refund the nodes further out first.")


func _flash(text: String) -> void:
	_message = text
	_message_time = 2.0
	_refresh_info()


func _move_selection(direction: Vector2) -> void:
	var g = SkillTree.graph(player_index)
	var current = SkillTree.get_node_data(player_index, selected_id)
	if current.empty():
		_select(SkillTree.START_ID, true)
		return
	var from = Vector2(current.x, current.y)
	var best_id = ""
	var best_score = INF
	for id in g.order:
		if id == selected_id:
			continue
		var data: Dictionary = g.nodes[id]
		var offset: Vector2 = Vector2(data.x, data.y) - from
		var dist = offset.length()
		if dist < 1.0:
			continue
		var dot = offset.normalized().dot(direction)
		if dot < 0.45:
			continue
		# Prefer close nodes straight ahead; connected neighbours get a small bonus.
		var score = dist * (2.2 - dot * 1.2)
		if id in g.adj[selected_id]:
			score *= 0.8
		if score < best_score:
			best_score = score
			best_id = id
	if best_id != "":
		_select(best_id, true)


func _zoom_by(factor: float, screen_pos: Vector2) -> void:
	var world_before = _to_world(screen_pos)
	zoom = clamp(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	cam = world_before - (screen_pos - _canvas.rect_size / 2.0) / zoom
	_following = false
	_canvas.update()


func _node_at(screen_pos: Vector2) -> String:
	var world = _to_world(screen_pos)
	var g = SkillTree.graph(player_index)
	var best = ""
	var best_dist = INF
	for id in g.order:
		var data: Dictionary = g.nodes[id]
		var dist = world.distance_to(Vector2(data.x, data.y))
		var reach: float = NODE_RADIUS[int(data.kind)] + 8.0 / zoom
		if dist <= reach and dist < best_dist:
			best = id
			best_dist = dist
	return best


func _close() -> void:
	if _closing:
		return
	if not _player_queue.empty():
		_show_player(_player_queue.pop_front())
		return
	_closing = true
	_closing_frames = 0
	_root.visible = false


# ---------------- Input ----------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		return # handled through the GUI (_on_canvas_gui_input / the button)
	get_tree().set_input_as_handled()
	if _closing:
		return
	if SkillTree.event_player(event) != player_index:
		return

	if event is InputEventJoypadMotion:
		match event.axis:
			JOY_AXIS_0:
				_stick.x = event.axis_value
			JOY_AXIS_1:
				_stick.y = event.axis_value
			JOY_AXIS_2:
				_rstick.x = event.axis_value
			JOY_AXIS_3:
				_rstick.y = event.axis_value
		return

	if not event.is_pressed():
		return

	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_0:
				_activate()
			JOY_BUTTON_1, JOY_SELECT, JOY_START:
				_close()
			JOY_BUTTON_2, JOY_BUTTON_3:
				_refund_selected()
			JOY_DPAD_UP:
				_move_selection(Vector2.UP)
			JOY_DPAD_DOWN:
				_move_selection(Vector2.DOWN)
			JOY_DPAD_LEFT:
				_move_selection(Vector2.LEFT)
			JOY_DPAD_RIGHT:
				_move_selection(Vector2.RIGHT)
			JOY_L, JOY_L2:
				_zoom_by(1.0 / 1.2, _canvas.rect_size / 2.0)
			JOY_R, JOY_R2:
				_zoom_by(1.2, _canvas.rect_size / 2.0)
		return

	if event is InputEventKey:
		var code: int = event.physical_scancode if event.physical_scancode != 0 else event.scancode
		if event.is_echo() and not code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D, KEY_I, KEY_J, KEY_K, KEY_L]:
			return
		match code:
			KEY_ESCAPE, KEY_P:
				_close()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
				_activate()
			KEY_BACKSPACE, KEY_DELETE, KEY_R:
				_refund_selected()
			KEY_UP, KEY_W, KEY_I:
				_move_selection(Vector2.UP)
			KEY_DOWN, KEY_S, KEY_K:
				_move_selection(Vector2.DOWN)
			KEY_LEFT, KEY_A, KEY_J:
				_move_selection(Vector2.LEFT)
			KEY_RIGHT, KEY_D, KEY_L:
				_move_selection(Vector2.RIGHT)
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				_zoom_by(1.2, _canvas.rect_size / 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				_zoom_by(1.0 / 1.2, _canvas.rect_size / 2.0)
			KEY_HOME:
				_select(SkillTree.START_ID, true)


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _closing or not SkillTree.player_uses_mouse(player_index):
		return
	if event is InputEventMouseMotion:
		if _dragging:
			cam -= event.relative / zoom
			_drag_distance += event.relative.length()
			_following = false
			_canvas.update()
		else:
			var hovered = _node_at(event.position)
			if hovered != "":
				_select(hovered, false)
	elif event is InputEventMouseButton:
		match event.button_index:
			BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_distance = 0.0
				else:
					var was_click: bool = _dragging and _drag_distance < 10.0
					_dragging = false
					if was_click:
						var clicked = _node_at(event.position)
						if clicked != "":
							_select(clicked, false)
							_activate()
			BUTTON_MIDDLE:
				_dragging = event.pressed
				_drag_distance = 0.0
			BUTTON_RIGHT:
				if event.pressed:
					var clicked = _node_at(event.position)
					if clicked != "":
						_select(clicked, false)
						_refund_selected()
			BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(1.12, event.position)
			BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / 1.12, event.position)


func _process(delta: float) -> void:
	if _closing:
		_process_closing()
		return

	_move_cooldown -= delta
	if _stick.length() > 0.6:
		if _move_cooldown <= 0.0:
			_move_selection(_stick.normalized())
			_move_cooldown = 0.22
	else:
		_move_cooldown = 0.0

	var redraw = false
	if _rstick.length() > 0.25:
		cam += _rstick * 900.0 * delta / zoom
		_following = false
		redraw = true
	if _following:
		cam = cam.linear_interpolate(_cam_target, min(1.0, delta * 9.0))
		if cam.distance_to(_cam_target) < 0.5:
			cam = _cam_target
			_following = false
		redraw = true
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message = ""
			_refresh_info()
	# Frontier rings pulse, so keep redrawing.
	_canvas.update()


# Waits until the close/pause buttons are released before handing input back, so the press
# that closed the tree doesn't also open the pause menu behind it.
func _process_closing() -> void:
	if _any_close_input_held():
		_closing_frames = 0
		return
	_closing_frames += 1
	if _closing_frames < 3:
		return
	_restore_pause_menu()
	Input.set_mouse_mode(_previous_mouse_mode)
	emit_signal("finished")
	queue_free()


func _any_close_input_held() -> bool:
	for action in ["ui_pause", "ui_cancel"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
		for device in range(CoopService.REMAP_END):
			var device_action: String = "%s_%s" % [action, device]
			if InputMap.has_action(device_action) and Input.is_action_pressed(device_action):
				return true
	if Input.is_physical_key_pressed(KEY_P) or Input.is_key_pressed(KEY_ESCAPE):
		return true
	for device in Input.get_connected_joypads():
		for button in [JOY_BUTTON_1, JOY_SELECT, JOY_START]:
			if Input.is_joy_button_pressed(device, button):
				return true
	return false


func _block_pause_menu() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	_pause_menu = scene.get_node_or_null("PauseMenu")
	if _pause_menu == null:
		_pause_menu = scene.find_node("PauseMenu", true, false)
	if _pause_menu != null and "enabled" in _pause_menu:
		_pause_was_enabled = _pause_menu.enabled
		_pause_menu.enabled = false
	else:
		_pause_menu = null


func _restore_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.enabled = _pause_was_enabled


func _exit_tree() -> void:
	_restore_pause_menu()
