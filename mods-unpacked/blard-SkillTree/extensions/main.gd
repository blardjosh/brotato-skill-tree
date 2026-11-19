extends "res://main.gd"
# blard-SkillTree: level-ups become skill points. The vanilla upgrade choices are skipped;
# at the end of the wave each player with points gets the skill tree before the shop.

const BlardSkillTree = preload("res://mods-unpacked/blard-SkillTree/skill_tree.gd")
const BlardSkillTreeScreen = preload("res://mods-unpacked/blard-SkillTree/ui/skill_tree_screen.gd")


func _on_EndWaveTimer_timeout() -> void:
	# Same conditions as vanilla for showing the upgrade screen: not a failed wave, not the run's end.
	if not (_is_wave_failed and RunData.current_wave > 0) and not _is_run_lost and not _is_run_won:
		_blard_skilltree_convert_level_ups()
	._on_EndWaveTimer_timeout()


# Turns this wave's queued level-up choices into skill points and clears them from the HUD,
# so the vanilla upgrade screen only handles crates.
func _blard_skilltree_convert_level_ups() -> void:
	var per_level: int = BlardSkillTree.Config.points_per_level()
	for player_index in RunData.get_player_count():
		if player_index >= _upgrades_to_process.size():
			break
		var queue: Array = _upgrades_to_process[player_index]
		if queue.empty():
			continue
		var hud_list = null
		if player_index < _things_to_process_player_containers.size():
			hud_list = _things_to_process_player_containers[player_index].upgrades
		var points: = 0
		for upgrade in queue:
			if hud_list != null:
				hud_list.remove_element(upgrade.level)
			if BlardSkillTree.needs_weapon_slot_upgrade(player_index) and ItemService.weapon_slot_upgrade_data != null:
				RunData.add_upgrade(ItemService.weapon_slot_upgrade_data, player_index)
			else:
				points += per_level
		queue.clear()
		if points > 0:
			BlardSkillTree.add_points(player_index, points)


func _change_scene(path: String) -> void:
	if path == RunData.get_shop_scene_path() and BlardSkillTree.Config.flag("open_on_level_up"):
		var players: Array = BlardSkillTree.players_with_points()
		if not players.empty():
			var screen = BlardSkillTreeScreen.new()
			screen.setup(BlardSkillTreeScreen.MODE_LEVEL_UP, players)
			get_tree().root.add_child(screen)
			yield(screen, "finished")
	._change_scene(path)
