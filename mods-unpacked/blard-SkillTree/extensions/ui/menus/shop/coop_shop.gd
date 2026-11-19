extends "res://ui/menus/shop/coop_shop.gd"
# blard-SkillTree: "Skill Tree" button + P / Back hotkey to open the passive tree in the shop.

const BlardSkillTreeShop = preload("res://mods-unpacked/blard-SkillTree/shop_hooks.gd")

var _blard_skilltree_screen = null


# Godot 3 runs every script level's _ready (base first), so the shop is fully set up here.
func _ready() -> void:
	BlardSkillTreeShop.add_buttons(self)


# Every script level's _input runs too; this one only reacts to the open-tree hotkey.
func _input(event: InputEvent) -> void:
	if _blard_skilltree_screen != null and is_instance_valid(_blard_skilltree_screen):
		return
	var player_index: int = BlardSkillTreeShop.open_request_player(self, event)
	if player_index < 0:
		return
	get_tree().set_input_as_handled()
	_blard_skilltree_open(player_index)


func _blard_skilltree_open(player_index: int) -> void:
	if _blard_skilltree_screen != null and is_instance_valid(_blard_skilltree_screen):
		return
	_blard_skilltree_screen = BlardSkillTreeShop.open_screen(self, player_index)


func _blard_skilltree_on_changed(player_index: int) -> void:
	BlardSkillTreeShop.on_tree_changed(self, player_index)


func _blard_skilltree_on_closed() -> void:
	_blard_skilltree_screen = null
	BlardSkillTreeShop.refresh_buttons(self)
