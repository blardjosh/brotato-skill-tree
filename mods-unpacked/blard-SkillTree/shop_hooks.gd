extends Reference
# blard-SkillTree: shared shop code for the solo and co-op shop extensions.

const SkillTree = preload("res://mods-unpacked/blard-SkillTree/skill_tree.gd")
const ScreenScript = preload("res://mods-unpacked/blard-SkillTree/ui/skill_tree_screen.gd")

const BUTTON_NAME := "BlardSkillTreeButton"
const SOLO_HEADER_PATH := "Content/MarginContainer/HBoxContainer/VBoxContainer/HBoxContainer"
const COOP_HEADER_PATH := "MarginContainer/Carousel/Content/VBoxContainer/HBoxContainer"
const FONT_PATH := "res://resources/fonts/actual/base/font_26_outline.tres"


# Adds a "Skill Tree" button per player next to the reroll button. Mouse-only (no focus), so
# controller navigation in the shop is unchanged; controllers use Back/Select instead.
static func add_buttons(shop) -> void:
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
		var button: = Button.new()
		button.name = BUTTON_NAME
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if ResourceLoader.exists(FONT_PATH):
			button.add_font_override("font", load(FONT_PATH))
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
		var label: = "Tree" if RunData.is_coop_run else "Skill Tree"
		button.text = "%s (%d)" % [label, points] if points > 0 else label
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
