extends Reference
# blard-SkillTree: shared shop code for the solo and co-op shop extensions.

const SkillTree = preload("res://mods-unpacked/blard-SkillTree/skill_tree.gd")
const ScreenScript = preload("res://mods-unpacked/blard-SkillTree/ui/skill_tree_screen.gd")

const BUTTON_NAME := "BlardSkillTreeButton"
const SOLO_HEADER_PATH := "Content/MarginContainer/HBoxContainer/VBoxContainer/HBoxContainer"
const COOP_HEADER_PATH := "MarginContainer/Carousel/Content/VBoxContainer/HBoxContainer"
const MENU_BUTTON_SCRIPT := "res://ui/menus/global/my_menu_button.gd"


# Adds a "Skill Tree" button per player next to the reroll button, styled and sized like the
# shop's own buttons.
static func add_buttons(shop) -> void:
	for player_index in RunData.get_player_count():
		SkillTree.refresh_scaling(player_index)
	for player_index in RunData.get_player_count():
		var header: Node = null
		if RunData.is_coop_run:
			if shop.has_method("_get_coop_player_container"):
				var container = shop._get_coop_player_container(player_index)
				if container != null:
					header = container.get_node_or_null(COOP_HEADER_PATH)
		else:
			header = shop.get_node_or_null(SOLO_HEADER_PATH)
		if header == null:
			continue
		var button = Button.new()
		# Same script as the shop's GO button: game hover/press sounds and focus behaviour.
		if ResourceLoader.exists(MENU_BUTTON_SCRIPT):
			button.set_script(load(MENU_BUTTON_SCRIPT))
			# In co-op, hovering must not steal real focus from the per-player focus emulators.
			button.grab_focus_with_mouse = not RunData.is_coop_run
		button.name = BUTTON_NAME
		# Focusable in solo and co-op: co-op focus emulators only visit FOCUS_ALL controls, and
		# their "pressed" reaches the per-player connection below.
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		# No font/size overrides: it takes the shop theme like the Reroll button next to it and
		# fills the header row's height, so it scales with the rest of the UI.
		button.size_flags_vertical = Control.SIZE_FILL
		button.size_flags_horizontal = 0
		var _err = button.connect("pressed", shop, "_blard_skilltree_open", [player_index])
		header.add_child(button)
		var reroll = header.get_node_or_null("RerollButton")
		if reroll != null:
			header.move_child(button, reroll.get_index())
	refresh_buttons(shop)


static func refresh_buttons(shop) -> void:
	for player_index in RunData.get_player_count():
		var button = _find_button(shop, player_index)
		if button == null:
			continue
		var points: int = SkillTree.get_points(player_index)
		var label = "Tree" if RunData.is_coop_run else "Skill Tree"
		button.text = " %s (%d) " % [label, points] if points > 0 else " %s " % label
		button.modulate = Color(1.0, 0.9, 0.5) if points > 0 else Color(1, 1, 1)


static func _find_button(shop, player_index: int):
	var header: Node = null
	if RunData.is_coop_run:
		if shop.has_method("_get_coop_player_container"):
			var container = shop._get_coop_player_container(player_index)
			if container != null:
				header = container.get_node_or_null(COOP_HEADER_PATH)
	else:
		header = shop.get_node_or_null(SOLO_HEADER_PATH)
	if header == null:
		return null
	return header.get_node_or_null(BUTTON_NAME)


static func open_request_player(shop, event: InputEvent) -> int:
	if not SkillTree.is_open_request(event):
		return -1
	if shop.get_tree().paused:
		return -1
	var content = shop.get_node_or_null("Content")
	if content != null and not content.visible:
		return -1
	return SkillTree.event_player(event)


static func open_screen(shop, player_index: int):
	var screen = ScreenScript.new()
	screen.setup(ScreenScript.MODE_VIEW, [player_index])
	var _err = screen.connect("tree_changed", shop, "_blard_skilltree_on_changed")
	_err = screen.connect("finished", shop, "_blard_skilltree_on_closed")
	shop.get_tree().root.add_child(screen)
	return screen


# Refreshes the shop's stat panels after nodes are allocated or refunded.
static func on_tree_changed(shop, player_index: int) -> void:
	LinkedStats.reset_player(player_index)
	if shop.has_method("_update_stats"):
		shop._update_stats(player_index)
	if shop.has_method("_get_shop_items_container"):
		# Prices can change (Midas lowers them), so redraw the offers.
		var items_container = shop._get_shop_items_container(player_index)
		if items_container != null:
			if items_container.has_method("reload_shop_items"):
				items_container.reload_shop_items()
			if items_container.has_method("update_buttons_color"):
				items_container.update_buttons_color()
	refresh_buttons(shop)


# Called about once a second: buying meca/mutant/cursed items changes the levels that
# scaling nodes follow.
static func tick(shop) -> void:
	for player_index in RunData.get_player_count():
		if SkillTree.refresh_scaling(player_index):
			on_tree_changed(shop, player_index)
