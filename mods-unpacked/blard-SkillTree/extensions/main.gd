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
		# Font of Insight relic: +1 point every wave, level-up or not.
		var insight: int = BlardSkillTree.relic_count(player_index, "insight")
		if insight > 0:
			BlardSkillTree.add_points(player_index, insight)
		if queue.empty():
			continue
		var hud_list = null
		if player_index < _things_to_process_player_containers.size():
			hud_list = _things_to_process_player_containers[player_index].upgrades
		var points = 0
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
	if path == RunData.get_shop_scene_path():
		# Mechanized / Mutated / Cursed nodes follow levels gained during the wave.
		for player_index in RunData.get_player_count():
			BlardSkillTree.refresh_scaling(player_index)
	if path == RunData.get_shop_scene_path() and BlardSkillTree.Config.flag("open_on_level_up"):
		var players: Array = BlardSkillTree.players_with_points()
		if not players.empty():
			var screen = BlardSkillTreeScreen.new()
			screen.setup(BlardSkillTreeScreen.MODE_LEVEL_UP, players)
			get_tree().root.add_child(screen)
			yield(screen, "finished")
	._change_scene(path)


# Evergreen relic: past the last regular wave, harvesting keeps growing instead of decaying.
func _on_HarvestingTimer_timeout() -> void:
	var before = []
	for player_index in RunData.get_player_count():
		before.push_back(RunData.get_player_effect(Keys.stat_harvesting_hash, player_index))
	._on_HarvestingTimer_timeout()
	if RunData.current_wave <= RunData.nb_of_waves:
		return
	for player_index in RunData.get_player_count():
		if not BlardSkillTree.has_relic(player_index, "evergreen"):
			continue
		var now = RunData.get_player_effect(Keys.stat_harvesting_hash, player_index)
		if now < before[player_index]:
			RunData.add_stat(Keys.stat_harvesting_hash, int(before[player_index] - now), player_index)
		var harvesting: float = Utils.get_stat(Keys.stat_harvesting_hash, player_index)
		if harvesting > 0:
			var growth: float = float(RunData.get_player_effect(Keys.harvesting_growth_hash, player_index))
			var gain: int = int(ceil(harvesting * growth / 100.0))
			if gain > 0:
				RunData.add_stat(Keys.stat_harvesting_hash, gain, player_index)


# Bottomless Bank relic: interest (Piggy Bank style) keeps paying after the last regular
# wave. Skipped when the EndlessPiggyBank mod is on, since that already pays it.
func _on_EntitySpawner_players_spawned(players: Array) -> void:
	._on_EntitySpawner_players_spawned(players)
	if RunData.current_wave <= RunData.nb_of_waves:
		return
	var piggy_mod = get_node_or_null("/root/ModLoader/BrotatoQoL-EndlessPiggyBank")
	if piggy_mod != null and "enabled" in piggy_mod and piggy_mod.enabled:
		return
	for player_index in RunData.get_player_count():
		if not BlardSkillTree.has_relic(player_index, "endless_interest"):
			continue
		var pct: float = float(RunData.get_player_effect(Keys.gain_pct_gold_start_wave_hash, player_index))
		if pct <= 0.0:
			continue
		var gain: int = int(RunData.get_player_gold(player_index) * pct / 100.0)
		if gain > 0:
			RunData.add_gold(gain, player_index)
			RunData.add_tracked_value(player_index, Keys.item_piggy_bank_hash, gain)
