extends Reference
# blard-SkillTree: tree rules and per-player state.
#
# State lives in the player's effects dictionary under one custom key, so it is saved with
# the run, duplicated into the start-of-wave snapshot (wave retries) and wiped on a new run:
#   {"points": int, "alloc": [node ids], "mult": float, "seed": int,
#    "gen": {id: node}, "gen_edges": [[a, b]], "expanded": {id: true}, "gen_n": int,
#    "applied": {id: {stat: amount}}}   <- current amounts of level-scaling nodes
# Node bonuses are applied with RunData.add_stat / remove_stat, the same as vanilla stats.
# Past the keystones the tree is procedural: allocating a frontier node (a keystone or the
# end of a generated path) grows 2-3 new branches outward. Generated nodes are stored in the
# state, so they stay put for the rest of the run.

const TreeData = preload("res://mods-unpacked/blard-SkillTree/tree_data.gd")
const Config = preload("res://mods-unpacked/blard-SkillTree/config.gd")
const Patterns = preload("res://mods-unpacked/blard-SkillTree/patterns.gd")

const STATE_KEY_NAME := "blard_skill_tree"
const START_ID := "start"

enum Kind {START, SMALL, NOTABLE, KEYSTONE}

# stat key -> [translation key ("" = none), English label, shown as percent, lower is better]
const STAT_INFO := {
	"stat_max_hp": ["STAT_MAX_HP", "Max HP", false, false],
	"stat_hp_regeneration": ["STAT_HP_REGENERATION", "HP Regeneration", false, false],
	"stat_lifesteal": ["STAT_LIFESTEAL", "Life Steal", true, false],
	"stat_percent_damage": ["STAT_PERCENT_DAMAGE", "Damage", true, false],
	"stat_melee_damage": ["STAT_MELEE_DAMAGE", "Melee Damage", false, false],
	"stat_ranged_damage": ["STAT_RANGED_DAMAGE", "Ranged Damage", false, false],
	"stat_elemental_damage": ["STAT_ELEMENTAL_DAMAGE", "Elemental Damage", false, false],
	"stat_attack_speed": ["STAT_ATTACK_SPEED", "Attack Speed", true, false],
	"stat_crit_chance": ["STAT_CRIT_CHANCE", "Crit Chance", true, false],
	"stat_engineering": ["STAT_ENGINEERING", "Engineering", false, false],
	"stat_range": ["STAT_RANGE", "Range", false, false],
	"stat_armor": ["STAT_ARMOR", "Armor", false, false],
	"stat_dodge": ["STAT_DODGE", "Dodge", true, false],
	"stat_speed": ["STAT_SPEED", "Speed", true, false],
	"stat_luck": ["STAT_LUCK", "Luck", false, false],
	"stat_harvesting": ["STAT_HARVESTING", "Harvesting", false, false],
	"xp_gain": ["", "XP Gain", true, false],
	"explosion_damage": ["", "Explosion Damage", true, false],
	"explosion_size": ["", "Explosion Size", true, false],
	"structure_attack_speed": ["", "Structure Attack Speed", true, false],
	"structure_percent_damage": ["", "Structure Damage", true, false],
	"structure_range": ["", "Structure Range", false, false],
	"knockback": ["", "Knockback", false, false],
	"piercing": ["", "Piercing", false, false],
	"burning_spread": ["", "Burning Spread", false, false],
	"chance_double_gold": ["", "Chance to Double Materials", true, false],
	"items_price": ["", "Shop Prices", true, true],
	"stat_curse": ["STAT_CURSE", "Curse", false, true],
	"pickup_range": ["", "Pickup Range", false, false],
	"consumable_heal": ["", "Consumable Healing", false, false],
	"hit_protection": ["", "Hits Blocked per Wave", false, false],
	"heal_when_pickup_gold": ["", "Chance to Heal on Material Pickup", true, false],
	"item_box_gold": ["", "Materials per Crate", false, false],
	"bounce": ["", "Bounces", false, false],
	"bounce_damage": ["", "Bounce Damage", true, false],
	"piercing_damage": ["", "Piercing Damage", true, false],
	"damage_against_bosses": ["", "Damage vs Bosses & Elites", true, false],
	"reroll_price": ["", "Reroll Price", true, true],
	"weapons_price": ["", "Weapon Prices", true, true],
	"weapon_slot": ["", "Weapon Slot", false, false],
	"stat_evolution": ["", "Evolution", false, false],
}


# ---------------- Graph ----------------

static func _base_graph() -> Dictionary:
	var node = Config.mod_node()
	if node != null and not node.graph_cache.empty():
		return node.graph_cache
	var g = {"nodes": {}, "adj": {}, "order": [], "edges": TreeData.EDGES}
	for n in TreeData.NODES:
		g.nodes[n["id"]] = n
		g.adj[n["id"]] = []
		g.order.push_back(n["id"])
	for e in TreeData.EDGES:
		g.adj[e[0]].push_back(e[1])
		g.adj[e[1]].push_back(e[0])
	if node != null:
		node.graph_cache = g
	return g


# The fixed tree plus this player's generated nodes. Cached until the player's tree grows.
static func graph(player_index: int) -> Dictionary:
	var base = _base_graph()
	var state = get_state(player_index)
	if state.gen.empty():
		return base
	var key = "%s:%d:%d" % [str(state.seed), state.gen.size(), state.gen_edges.size()]
	var mod = Config.mod_node()
	if mod != null:
		var cached = mod.player_graph_cache.get(player_index)
		if cached is Dictionary and cached.get("key") == key:
			return cached.g
	var g = {
		"nodes": base.nodes.duplicate(),
		"adj": base.adj.duplicate(true),
		"order": base.order.duplicate(),
		"edges": base.edges.duplicate(),
	}
	for id in state.gen.keys():
		g.nodes[id] = state.gen[id]
		g.adj[id] = []
		g.order.push_back(id)
	for e in state.gen_edges:
		if g.adj.has(e[0]) and g.adj.has(e[1]):
			g.adj[e[0]].push_back(e[1])
			g.adj[e[1]].push_back(e[0])
			g.edges.push_back(e)
	if mod != null:
		mod.player_graph_cache[player_index] = {"key": key, "g": g}
	return g


static func get_node_data(player_index: int, id: String) -> Dictionary:
	return graph(player_index).nodes.get(id, {})


static func is_generated(data: Dictionary) -> bool:
	return bool(data.get("gen", false))


# Allocating a frontier node grows new branches (once per node).
static func is_frontier(data: Dictionary) -> bool:
	if is_generated(data):
		return bool(data.get("frontier", false))
	return int(data.get("kind", 1)) == Kind.KEYSTONE


static func is_expanded(player_index: int, id: String) -> bool:
	return get_state(player_index).expanded.has(id)


# ---------------- State ----------------

static func state_key() -> int:
	return Keys.generate_hash(STATE_KEY_NAME)


static func get_state(player_index: int) -> Dictionary:
	var effects: Dictionary = RunData.get_player_effects(player_index)
	var key = state_key()
	var state = effects.get(key)
	if state is Dictionary and _looks_hashed(state):
		# Loading a saved run turns every string inside nested effect data into a hash
		# (Utils.convert_dictionary_to_hash). Turn them back so the tree survives reloads.
		state = _unhash(state)
		effects[key] = state
	if not state is Dictionary:
		state = {}
		effects[key] = state
	# Saved runs come back from JSON with floats; normalize every time.
	state["points"] = int(state.get("points", 0))
	if not state.get("alloc") is Array:
		state["alloc"] = []
	var mult: float = float(state.get("mult", 0.0))
	if mult <= 0.0:
		mult = Config.power()
	state["mult"] = mult
	if not state.has("seed"):
		var seed_rng = RandomNumberGenerator.new()
		seed_rng.randomize()
		state["seed"] = seed_rng.randi()
	if not state.get("gen") is Dictionary:
		state["gen"] = {}
	if not state.get("gen_edges") is Array:
		state["gen_edges"] = []
	if not state.get("expanded") is Dictionary:
		state["expanded"] = {}
	state["gen_n"] = int(state.get("gen_n", 0))
	if not state.get("applied") is Dictionary:
		state["applied"] = {}
	return state


static func _looks_hashed(state: Dictionary) -> bool:
	return state.has(Keys.generate_hash("alloc")) or state.has(Keys.generate_hash("points"))


static func _unhash_value(value):
	if value is int and value != Keys.empty_hash and Keys.hash_to_string.has(value):
		return Keys.hash_to_string[value]
	return _unhash(value)


# Reverses the game's load-time hashing: dictionary keys and array strings came back as
# hashes, which Keys.hash_to_string maps back to the original text.
static func _unhash(value):
	if value is Dictionary:
		var result = {}
		for k in value.keys():
			var new_key = k
			if k is int and k != Keys.empty_hash and Keys.hash_to_string.has(k):
				new_key = Keys.hash_to_string[k]
			result[new_key] = _unhash(value[k])
		return result
	if value is Array:
		var result = []
		for element in value:
			result.push_back(_unhash_value(element))
		return result
	return value


static func get_points(player_index: int) -> int:
	return get_state(player_index).points


static func add_points(player_index: int, amount: int) -> void:
	var state = get_state(player_index)
	state["points"] = state.points + amount


static func players_with_points() -> Array:
	var result = []
	for player_index in RunData.get_player_count():
		if get_points(player_index) > 0:
			result.push_back(player_index)
	return result


static func allocated_set(player_index: int) -> Dictionary:
	var result = {START_ID: true}
	for id in get_state(player_index).alloc:
		result[str(id)] = true
	return result


static func allocated_count(player_index: int) -> int:
	return get_state(player_index).alloc.size()


# ---------------- Rules ----------------

# Unallocated nodes to take, in order, to reach target from the allocated part of the tree.
# Empty if target is already allocated or unknown.
static func path_to(player_index: int, target: String) -> Array:
	var g = graph(player_index)
	var alloc = allocated_set(player_index)
	if alloc.has(target) or not g.nodes.has(target):
		return []
	var came_from = {}
	var queue = []
	for id in alloc.keys():
		came_from[id] = ""
		queue.push_back(id)
	var head = 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		if current == target:
			break
		for next in g.adj[current]:
			if came_from.has(next):
				continue
			came_from[next] = current
			queue.push_back(next)
	if not came_from.has(target):
		return []
	var path = []
	var step: String = target
	while not alloc.has(step):
		path.push_front(step)
		step = came_from[step]
	return path


static func is_reachable(g: Dictionary, id: String, alloc: Dictionary) -> bool:
	if alloc.has(id):
		return false
	for next in g.adj.get(id, []):
		if alloc.has(next):
			return true
	return false


# Allocates the whole path to target if there are enough points. Returns nodes allocated.
static func allocate_path(player_index: int, target: String) -> int:
	var path = path_to(player_index, target)
	var state = get_state(player_index)
	if path.empty() or path.size() > state.points:
		return 0
	for id in path:
		state.alloc.push_back(id)
		state["points"] = state.points - 1
		_apply_node(player_index, id, 1, state.mult)
	for id in path:
		var data = get_node_data(player_index, id)
		if is_frontier(data) and not state.expanded.has(id):
			_expand(player_index, id)
	refresh_scaling(player_index)
	_after_stats_changed(player_index)
	return path.size()


static func can_refund(player_index: int, id: String) -> bool:
	if not Config.flag("allow_refunds") or id == START_ID:
		return false
	if bool(get_node_data(player_index, id).get("no_refund", false)):
		return false
	var alloc = allocated_set(player_index)
	if not alloc.has(id):
		return false
	# Every other allocated node must still connect to the start without this one.
	alloc.erase(id)
	var g = graph(player_index)
	var seen = {START_ID: true}
	var queue = [START_ID]
	var head = 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		for next in g.adj[current]:
			if alloc.has(next) and not seen.has(next):
				seen[next] = true
				queue.push_back(next)
	return seen.size() == alloc.size()


static func refund(player_index: int, id: String) -> bool:
	if not can_refund(player_index, id):
		return false
	var state = get_state(player_index)
	state.alloc.erase(id)
	state["points"] = state.points + 1
	_apply_node(player_index, id, -1, state.mult)
	var applied = state.applied.get(id, {})
	for stat_key in applied.keys():
		_add_stat_amount(player_index, stat_key, - int(applied[stat_key]))
	state.applied.erase(id)
	_after_stats_changed(player_index)
	return true


# Oddity and relic capstones carry exact amounts (weapon slots, blocked hits...), so the
# power option doesn't scale them.
static func node_mult(data: Dictionary, mult: float) -> float:
	if str(data.get("special", "")) != "":
		return 1.0
	return mult


static func scaled_value(base_value: int, mult: float) -> int:
	var scaled = int(round(abs(base_value) * mult))
	if scaled == 0:
		scaled = 1
	return scaled if base_value >= 0 else -scaled


static func _apply_node(player_index: int, id: String, direction: int, mult: float) -> void:
	var data = get_node_data(player_index, id)
	mult = node_mult(data, mult)
	var effects: Dictionary = RunData.get_player_effects(player_index)
	for stat in data.get("stats", []):
		var stat_hash: int = Keys.generate_hash(stat[0])
		if not effects.has(stat_hash):
			continue
		var amount = scaled_value(int(stat[1]), mult) * direction
		if amount >= 0:
			RunData.add_stat(stat_hash, amount, player_index)
		else:
			RunData.remove_stat(stat_hash, - amount, player_index)
	# Capstone bonus effects: plain numeric effects, not scaled by the power option.
	for bonus in data.get("bonus", []):
		var bonus_hash: int = Keys.generate_hash(bonus[0])
		if effects.has(bonus_hash) and typeof(effects[bonus_hash]) in [TYPE_INT, TYPE_REAL]:
			effects[bonus_hash] = effects[bonus_hash] + int(bonus[1]) * direction


static func _after_stats_changed(player_index: int) -> void:
	var mod = Config.mod_node()
	if mod != null:
		mod.red_cache.erase(player_index)
	LinkedStats.reset_player(player_index)
	Utils.reset_stat_cache(player_index)


static func _add_stat_amount(player_index: int, stat_key: String, amount: int) -> void:
	if amount == 0:
		return
	var stat_hash: int = Keys.generate_hash(stat_key)
	if not RunData.get_player_effects(player_index).has(stat_hash):
		return
	if amount > 0:
		RunData.add_stat(stat_hash, amount, player_index)
	else:
		RunData.remove_stat(stat_hash, - amount, player_index)


# ---------------- Mechanized / Mutated / Cursed levels ----------------

const MAX_FLAVOR_LEVEL := 40

# How far this player has gone down each path, using the game's own numbers:
#   Mechanized = Evolution when positive, Mutated = Evolution when negative (both use the
#   full amount with dual evolution), Cursed = Curse.
static func flavor_levels(player_index: int) -> Dictionary:
	var effects: Dictionary = RunData.get_player_effects(player_index)
	var evolution: float = float(effects.get(Keys.stat_evolution_hash, 0))
	var curse: float = float(effects.get(Keys.stat_curse_hash, 0))
	var dual = RunData.has_method("is_dual_evolution") and RunData.is_dual_evolution(player_index)
	var meca: float = abs(evolution) if dual else max(0.0, evolution)
	var mutant: float = abs(evolution) if dual else max(0.0, - evolution)
	return {
		"meca": int(meca),
		"mutant": int(mutant),
		"curse": int(max(0.0, curse)),
	}


static func flavor_level(player_index: int, flavor: String) -> int:
	return int(min(flavor_levels(player_index).get(flavor, 0), MAX_FLAVOR_LEVEL))


static func scaling_amount(per_level: float, level: int, mult: float) -> int:
	return int(round(per_level * level * mult))


# Brings every allocated level-scaling node up to date with the player's current levels.
# Returns true if any stat changed.
static func refresh_scaling(player_index: int) -> bool:
	var state = get_state(player_index)
	var levels: Dictionary = flavor_levels(player_index)
	var changed = false
	for id in state.alloc:
		var data = get_node_data(player_index, id)
		var scaling: Array = data.get("scaling", [])
		if scaling.empty():
			continue
		var level: int = int(min(levels.get(data.get("flavor", ""), 0), MAX_FLAVOR_LEVEL))
		var applied = state.applied.get(id, {})
		if not applied is Dictionary:
			applied = {}
		for entry in scaling:
			var want: int = scaling_amount(float(entry[1]), level, state.mult)
			var have: int = int(applied.get(entry[0], 0))
			if want != have:
				_add_stat_amount(player_index, entry[0], want - have)
				applied[entry[0]] = want
				changed = true
		state.applied[id] = applied
	if changed:
		_after_stats_changed(player_index)
	return changed


static func flavor_available(flavor: String) -> bool:
	var dlc: String = "abyssal_terrors" if flavor == "curse" else "primal_dread"
	return dlc in ProgressData.active_update_data


# ---------------- Procedural frontier ----------------

# Stat pools per sector: [stat key, value of one tier-1 vanilla upgrade]
const SECTOR_POOLS := [
	[["stat_max_hp", 3], ["stat_hp_regeneration", 2], ["stat_armor", 1], ["stat_lifesteal", 1]],
	[["stat_melee_damage", 2], ["stat_percent_damage", 5], ["stat_lifesteal", 1], ["stat_armor", 1]],
	[["stat_crit_chance", 3], ["stat_attack_speed", 5], ["stat_percent_damage", 5]],
	[["stat_ranged_damage", 1], ["stat_range", 15], ["stat_attack_speed", 5]],
	[["stat_elemental_damage", 1], ["explosion_damage", 10], ["explosion_size", 5], ["stat_percent_damage", 5]],
	[["stat_engineering", 2], ["structure_attack_speed", 5], ["structure_percent_damage", 5], ["structure_range", 15]],
	[["stat_harvesting", 5], ["stat_luck", 5], ["xp_gain", 5], ["chance_double_gold", 5]],
	[["stat_speed", 3], ["stat_dodge", 3], ["stat_attack_speed", 5]],
]
const NAME_PREFIXES := [
	["Iron", "Stalwart", "Living", "Titan's", "Granite"],
	["Savage", "Brutal", "Blood", "Warlord's", "Rending"],
	["Keen", "Lethal", "Hawk", "Duelist's", "Needle"],
	["Far", "Hunter's", "Steady", "Volley", "Eagle"],
	["Searing", "Storm", "Ember", "Volatile", "Ashen"],
	["Clockwork", "Gearwright's", "Turret", "Tinker's", "Brass"],
	["Gilded", "Lucky", "Golden", "Hoarder's", "Fortune's"],
	["Swift", "Shadow", "Wind", "Ghost", "Fleet"],
]
const NAME_SUFFIXES := [
	["Heart", "Bastion", "Vigor", "Bulwark", "Hide"],
	["Fury", "Cleave", "Rampage", "Edge", "Onslaught"],
	["Focus", "Strike", "Eye", "Tempo", "Precision"],
	["Sight", "Aim", "Barrage", "Reach", "Volley"],
	["Blaze", "Surge", "Pyre", "Core", "Cinder"],
	["Engine", "Assembly", "Forge", "Matrix", "Works"],
	["Fortune", "Harvest", "Bounty", "Coin", "Hoard"],
	["Step", "Dance", "Stride", "Veil", "Drift"],
]
const CAPSTONE_TITLES := ["Apex", "Ascendant", "Mythic", "Primal", "Eternal", "Sovereign"]
# Bonus effects random capstones can carry: [effect key, amount, description with %d, weight]
const BONUS_EFFECTS := [
	["free_rerolls", 1, "+%d free reroll in every shop", 3],
	["gain_pct_gold_start_wave", 5, "Gain %d%% of your materials at the start of each wave", 2],
	["recycling_gains", 15, "+%d%% recycling value", 3],
	["heal_on_crit_kill", 10, "%d%% chance to heal when a crit kills an enemy", 3],
	["bonus_crit_damage", 25, "+%d%% Crit Damage", 3],
	["instant_gold_attracting", 15, "%d%% chance for materials to fly straight to you", 2],
	["next_level_xp_needed", -8, "%d%% XP needed per level", 3],
	["trees", 1, "+%d tree each wave", 2],
	["projectiles", 1, "+%d projectile for weapons that fire several", 1],
	# Weight 0: only on Mechanized / Mutated / Cursed capstones.
	["meca_parts_on_level_up", 1, "+%d meca part every level-up", 0],
	["instant_meca_fruit_attracting", 30, "%d%% chance for meca fruit to fly straight to you", 0],
	["mutate_into_better_tier_chance", 20, "%d%% chance for mutations to raise the item's tier", 0],
	["instant_mutant_fruit_attracting", 30, "%d%% chance for mutant fruit to fly straight to you", 0],
	["gold_on_cursed_enemy_kill", 2, "+%d materials when you kill a cursed enemy", 0],
	# Weight 0: only on oddity / relic capstones.
	["extra_loot_aliens", 1, "+%d loot alien every wave", 0],
	["one_shot_trees", 1, "Trees die in one hit", 0],
]

# Oddity capstones: hand-made bundles of secondary stats. [name, [[stat, value]], [[bonus, value]]]
const ODDITIES := [
	["Magnetic Field", [["pickup_range", 60]], [["instant_gold_attracting", 20]]],
	["Field Medic", [["consumable_heal", 2], ["heal_when_pickup_gold", 8]], []],
	["Second Skin", [["hit_protection", 1], ["stat_armor", 2]], []],
	["Crate Raider", [["item_box_gold", 6], ["chance_double_gold", 10]], []],
	["Ricochet", [["bounce", 1], ["bounce_damage", 15]], []],
	["Skewer", [["piercing", 1], ["piercing_damage", 20]], []],
	["Giant Slayer", [["damage_against_bosses", 40], ["stat_percent_damage", 5]], []],
	["Haggler", [["reroll_price", -15], ["weapons_price", -10]], []],
	["Battering Ram", [["knockback", 3], ["stat_melee_damage", 4]], []],
	["Quick Study", [["xp_gain", 25]], []],
	["Demolition Expert", [["explosion_size", 20], ["explosion_damage", 20]], []],
	["Overgrowth", [["stat_harvesting", 10]], [["trees", 2]]],
	["Crimson Edge", [["stat_crit_chance", 10]], [], [["red_crit", 0.5]]],
	["Sniper's Patience", [["stat_crit_chance", 8], ["stat_range", 40]], [["bonus_crit_damage", 15]], []],
]

# Named notables with unusual effects (12% of notables). [name, stats, bonus, mods, dlc path]
# mods: "red_crit" = extra red crit multiplier (see RED_CRIT_BASE).
const NOVEL_NOTABLES := [
	["Crimson Focus", [["stat_crit_chance", 6]], [], [["red_crit", 0.25]], ""],
	["Bloodletter", [["stat_crit_chance", 4], ["stat_lifesteal", 2]], [], [["red_crit", 0.15]], ""],
	["Lucky Break", [["stat_crit_chance", 5]], [["heal_on_crit_kill", 10]], [], ""],
	["Scrap Magnet", [["pickup_range", 40], ["stat_harvesting", 5]], [["instant_gold_attracting", 10]], [], ""],
	["Second Wind", [["hit_protection", 1], ["stat_hp_regeneration", 2]], [], [], ""],
	["Sharpened Mind", [["xp_gain", 10], ["stat_crit_chance", 3]], [], [], ""],
	["Adaptive Plating", [["stat_armor", 2], ["stat_evolution", 1]], [], [], "meca"],
	["Mutagenic Gland", [["stat_max_hp", 6], ["stat_evolution", -1]], [], [], "mutant"],
	["Hexed Charm", [["stat_luck", 12], ["stat_curse", 1]], [], [], "curse"],
]

# Relics: very rare, one of each per run. Some have custom behaviour (see RELIC_TEXT).
# [relic id, name, [[stat, value]], [[bonus, value]], can be refunded]
const RELICS := [
	["endless_interest", "Bottomless Bank", [], [["gain_pct_gold_start_wave", 10]], true],
	["evergreen", "Evergreen", [["stat_harvesting", 10]], [], true],
	["extra_slot", "Extra Arsenal", [["weapon_slot", 1]], [], false],
	["insight", "Font of Insight", [], [], true],
	["treasure_map", "Treasure Map", [], [["extra_loot_aliens", 1]], true],
	["lumberjack", "Lumberjack", [["stat_harvesting", 5]], [["one_shot_trees", 1], ["trees", 2]], true],
	["shopkeeper", "Shopkeeper's Favor", [["items_price", -5]], [["free_rerolls", 2]], true],
	["aegis", "Aegis", [["hit_protection", 2]], [], true],
	["blood_moon", "Blood Moon", [["stat_crit_chance", 25]], [], true, [["red_crit", 1.0]]],
]
const RELIC_TEXT := {
	"endless_interest": "Interest keeps paying out after wave 20",
	"evergreen": "Harvesting keeps growing after wave 20 instead of decaying",
	"extra_slot": "Can't be refunded",
	"insight": "+1 skill point at the end of every wave",
	"blood_moon": "Red crits hit far harder",
}

# Red crits: crit chance past 100% rolls higher-magnitude crits. Each full 100% over is a
# guaranteed tier, the remainder is the chance of one more (tier 2 = red, 3+ = overcrit,
# max 4). Each tier past 1 multiplies the crit's damage by this (plus "red_crit" mods).
const RED_CRIT_BASE := 1.5
const RED_CRIT_MAX_TIER := 4

# Special frontier nodes whose stats grow with the matching level. Pools: [stat, per level].
const FLAVORS := {
	"meca": {
		"label": "Mechanized",
		"color": "6fd0ff",
		"pool": [["stat_engineering", 0.5], ["stat_armor", 0.25], ["stat_attack_speed", 1.0], ["structure_percent_damage", 1.5], ["stat_range", 3.0],
			["structure_attack_speed", 1.5], ["structure_range", 3.0], ["stat_ranged_damage", 0.3], ["explosion_damage", 2.0], ["stat_crit_chance", 0.4],
			["stat_percent_damage", 0.8], ["pickup_range", 3.0]],
		"prefixes": ["Servo", "Piston", "Chrome", "Dynamo", "Alloy"],
		"suffixes": ["Core", "Frame", "Plating", "Engine", "Coil"],
		"titles": ["Overclocked", "Perfected", "Omega"],
		"bonuses": [["meca_parts_on_level_up", 1], ["instant_meca_fruit_attracting", 30]],
	},
	"mutant": {
		"label": "Mutated",
		"color": "8cff5a",
		"pool": [["stat_max_hp", 1.0], ["stat_hp_regeneration", 0.4], ["stat_lifesteal", 0.25], ["stat_melee_damage", 0.5], ["stat_speed", 0.5],
			["stat_elemental_damage", 0.3], ["stat_dodge", 0.3], ["stat_armor", 0.2], ["stat_percent_damage", 0.8], ["stat_harvesting", 1.0],
			["consumable_heal", 0.1], ["stat_attack_speed", 0.6]],
		"prefixes": ["Writhing", "Feral", "Tumorous", "Chitin", "Spliced"],
		"suffixes": ["Growth", "Gland", "Marrow", "Hide", "Strain"],
		"titles": ["Apex", "Abominable", "Primordial"],
		"bonuses": [["mutate_into_better_tier_chance", 20], ["instant_mutant_fruit_attracting", 30]],
	},
	"curse": {
		"label": "Cursed",
		"color": "c04dff",
		"pool": [["stat_percent_damage", 1.0], ["stat_crit_chance", 0.5], ["stat_luck", 1.5], ["stat_harvesting", 1.5], ["stat_dodge", 0.4]],
		"prefixes": ["Hexed", "Damned", "Wretched", "Blighted", "Forsaken"],
		"suffixes": ["Idol", "Pact", "Sigil", "Omen", "Bargain"],
		"titles": ["Accursed", "Abyssal", "Doomed"],
		"bonuses": [["gold_on_cursed_enemy_kill", 2]],
	},
}

const PATTERN_SCALE := 160.0     # one pattern unit in tree pixels
const PATTERN_MIN_DIST := 130.0  # closest a new node may sit to any existing node
const EDGE_CLEARANCE := 55.0     # closest a new connection may pass by a node
const LINK_RANGE := 300.0        # how far a port/exit looks for an existing node to link to
const MAX_LINKS := 2
const LINK_MIN_HOPS := 5         # only link to parts of the tree this far away along the tree
const ROTATIONS := [0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90]


# Places one geometric pattern beyond a frontier node. Tries patterns for this depth (then
# any), each rotated and mirrored, until one fits without crowding nodes or crossing lines.
# Its port/exit nodes may then link to a nearby, far-along-the-tree node, which is how deep
# paths that curl back around join up with the rest of the tree.
static func _expand(player_index: int, parent_id: String) -> void:
	var state = get_state(player_index)
	state.expanded[parent_id] = true
	var g = graph(player_index)
	var parent: Dictionary = g.nodes.get(parent_id, {})
	if parent.empty():
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(state.seed) + ":" + parent_id)
	var parent_pos: Vector2 = _node_pos(parent)
	var heading: float = _node_heading(parent)
	var pattern_depth: int = int(parent.get("pdepth", 0)) + 1
	var tier: int = 1 if pattern_depth <= 2 else (2 if pattern_depth <= 4 else 3)

	var reach: float = PATTERN_SCALE * 7.0 + 300.0
	var near_points = []
	for id in g.order:
		var pos: Vector2 = _node_pos(g.nodes[id])
		if pos.distance_to(parent_pos) < reach:
			near_points.push_back(pos)
	var near_edges = []
	for e in g.edges:
		var a: Vector2 = _node_pos(g.nodes[e[0]])
		var b: Vector2 = _node_pos(g.nodes[e[1]])
		if min(a.distance_to(parent_pos), b.distance_to(parent_pos)) < reach + 400.0:
			near_edges.push_back([a, b])

	for pattern in _pattern_order(rng, tier):
		var first_mirror: int = 1 if rng.randf() < 0.5 else -1
		for offset in ROTATIONS:
			for mirror in [first_mirror, - first_mirror]:
				var angle: float = heading + deg2rad(offset)
				var placed: Array = _place(pattern, parent_pos, angle, mirror)
				if _pattern_fits(pattern, parent_pos, placed, near_points, near_edges):
					_build_pattern(rng, player_index, state, g, parent_id, parent, pattern, placed, angle, mirror, pattern_depth, near_points, near_edges)
					return


static func _node_pos(data: Dictionary) -> Vector2:
	return Vector2(float(data.x), float(data.y))


# Direction new growth heads from this node: stored on generated exits, outward otherwise.
static func _node_heading(data: Dictionary) -> float:
	var orbit: int = int(data.get("orbit", 0))
	if orbit != 0:
		var here: Vector2 = _node_pos(data)
		if here.length() > 1.0:
			return here.angle() + orbit * PI / 2.0
	if data.has("heading"):
		return float(data.heading)
	var pos: Vector2 = _node_pos(data)
	if pos.length() < 1.0:
		return - PI / 2.0
	return pos.angle()


static func _pattern_order(rng: RandomNumberGenerator, tier: int) -> Array:
	var pool = []
	var rest = []
	for pattern in Patterns.PATTERNS:
		if tier in pattern.tiers:
			pool.push_back(pattern)
		else:
			rest.push_back(pattern)
	var order = []
	while not pool.empty():
		var total = 0
		for pattern in pool:
			total += int(pattern.weight)
		var roll = rng.randi_range(1, total)
		for i in pool.size():
			roll -= int(pool[i].weight)
			if roll <= 0:
				order.push_back(pool[i])
				pool.remove(i)
				break
	for pattern in rest:
		order.push_back(pattern)
	return order


static func _place(pattern: Dictionary, origin: Vector2, angle: float, mirror: int) -> Array:
	var forward = Vector2(cos(angle), sin(angle))
	var right = Vector2(- forward.y, forward.x)
	var result = []
	for n in pattern.nodes:
		result.push_back(origin + (right * float(n[0]) * mirror + forward * float(n[1])) * PATTERN_SCALE)
	return result


static func _pattern_fits(pattern: Dictionary, origin: Vector2, placed: Array, points: Array, edges: Array) -> bool:
	for pos in placed:
		for other in points:
			if pos.distance_to(other) < PATTERN_MIN_DIST:
				return false
	if not _edge_fits(origin, placed[0], points, edges):
		return false
	for e in pattern.edges:
		if not _edge_fits(placed[e[0]], placed[e[1]], points, edges):
			return false
	return true


static func _orient(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)


static func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return _orient(c, d, a) * _orient(c, d, b) < 0.0 and _orient(a, b, c) * _orient(a, b, d) < 0.0


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# A new line a-b may not cross existing lines or pass close by a node it doesn't end at.
static func _edge_fits(a: Vector2, b: Vector2, points: Array, edges: Array) -> bool:
	for e in edges:
		var c: Vector2 = e[0]
		var d: Vector2 = e[1]
		if c.distance_to(a) < 1.0 or c.distance_to(b) < 1.0 or d.distance_to(a) < 1.0 or d.distance_to(b) < 1.0:
			continue
		if _segments_cross(a, b, c, d):
			return false
	for p in points:
		if p.distance_to(a) < 1.0 or p.distance_to(b) < 1.0:
			continue
		if _point_segment_distance(p, a, b) < EDGE_CLEARANCE:
			return false
	return true


static func _build_pattern(rng: RandomNumberGenerator, player_index: int, state: Dictionary, g: Dictionary, parent_id: String, parent: Dictionary, pattern: Dictionary, placed: Array, angle: float, mirror: int, pattern_depth: int, near_points: Array, near_edges: Array) -> void:
	# What the new nodes offer is steered by the frontier node, its neighbours and what the
	# player has invested in (see _desire_weights), with noise. Split patterns lean their
	# right-hand side towards the second favourite.
	var weights: Dictionary = _desire_weights(rng, player_index, g, parent_id)
	var side_weights: Dictionary = weights
	if pattern.split:
		side_weights = _shift_weights(rng, weights)
	var novel_pool: Array = _novel_stats(weights)
	# A whole pattern can be Mechanized / Mutated / Cursed (chance grows with that level).
	var flavor: String = _roll_pattern_flavor(rng, flavor_levels(player_index))

	# One exit always points somewhere new: its stats come from what you haven't been taking.
	var exit_indices = []
	for i in pattern.nodes.size():
		if pattern.nodes[i][3] == "exit" or pattern.nodes[i][3] == "orbit":
			exit_indices.push_back(i)
	var novel_index: int = exit_indices[rng.randi_range(0, exit_indices.size() - 1)] if not exit_indices.empty() else -1

	var ids = []
	for i in pattern.nodes.size():
		var spec: Array = pattern.nodes[i]
		var kind: int = Kind.SMALL
		if spec[2] == "n":
			kind = Kind.NOTABLE
		elif spec[2] == "c":
			kind = Kind.KEYSTONE
		var node_weights: Dictionary = side_weights if pattern.split and float(spec[0]) * mirror > 0.3 else weights
		var depth: int = pattern_depth * 2 + int(float(spec[1]) / 2.0)
		var role: String = spec[3]
		var is_exit: bool = role == "exit" or role == "orbit"
		var node: Dictionary
		if flavor != "":
			node = _make_flavor_node(rng, state, kind, flavor, _stat_sector(_weighted_pick(rng, node_weights)), depth, placed[i], is_exit)
		else:
			node = _make_desire_node(rng, state, kind, node_weights, depth, placed[i], is_exit, novel_pool if i == novel_index else [])
		node["pdepth"] = pattern_depth
		node["role"] = role
		node["heading"] = angle + deg2rad(float(spec[4]) * mirror)
		if role == "orbit":
			node["orbit"] = 1 if float(spec[4]) * mirror > 0.0 else -1
		state.gen[node.id] = node
		ids.push_back(node.id)
	state.gen_edges.push_back([parent_id, ids[0]])
	for e in pattern.edges:
		state.gen_edges.push_back([ids[e[0]], ids[e[1]]])

	var points: Array = near_points.duplicate()
	var edges: Array = near_edges.duplicate()
	points.push_back(_node_pos(parent))
	for pos in placed:
		points.push_back(pos)
	edges.push_back([_node_pos(parent), placed[0]])
	for e in pattern.edges:
		edges.push_back([placed[e[0]], placed[e[1]]])
	_add_minor_spur(rng, state, pattern, ids, placed, points, edges, pattern_depth)
	_link_pattern(player_index, state, g, parent_id, ids)


# ---------------- Stat desire ----------------

# Every stat new nodes can offer: stat -> [tier-1 value, sector] (from SECTOR_POOLS).
static func _stat_table() -> Dictionary:
	var table = {}
	for sector in SECTOR_POOLS.size():
		for entry in SECTOR_POOLS[sector]:
			if not table.has(entry[0]):
				table[entry[0]] = [float(entry[1]), sector]
	return table


static func _stat_sector(stat_key: String) -> int:
	var table: Dictionary = _stat_table()
	if table.has(stat_key):
		return int(table[stat_key][1])
	return 0


# Adds a node's stats to the weights, normalised so every node counts the same.
static func _add_influence(weights: Dictionary, table: Dictionary, data: Dictionary, strength: float) -> void:
	var units = {}
	var total = 0.0
	var entries: Array = data.get("stats", []) + data.get("scaling", [])
	for entry in entries:
		if not table.has(entry[0]):
			continue
		var amount: float = abs(float(entry[1])) / max(0.01, table[entry[0]][0])
		units[entry[0]] = units.get(entry[0], 0.0) + amount
		total += amount
	if total <= 0.0:
		return
	for stat_key in units.keys():
		weights[stat_key] = weights.get(stat_key, 0.0) + strength * units[stat_key] / total


# How likely each stat is in a new cluster:
#   strong:  the frontier node you just took
#   medium:  its neighbours (allocated ones count double)
#   weaker:  your overall investment across the tree
#   plus a baseline and random noise, so other stats still turn up.
static func _desire_weights(rng: RandomNumberGenerator, player_index: int, g: Dictionary, parent_id: String) -> Dictionary:
	var table: Dictionary = _stat_table()
	var weights = {}
	for stat_key in table.keys():
		weights[stat_key] = 0.6
	_add_influence(weights, table, g.nodes.get(parent_id, {}), 9.0)
	var alloc: Dictionary = allocated_set(player_index)
	for neighbour in g.adj.get(parent_id, []):
		_add_influence(weights, table, g.nodes.get(neighbour, {}), 3.0 if alloc.has(neighbour) else 1.5)
	var invested = {}
	var top = 0.0
	for id in get_state(player_index).alloc:
		var data: Dictionary = g.nodes.get(id, {})
		for entry in data.get("stats", []) + data.get("scaling", []):
			if table.has(entry[0]) and float(entry[1]) > 0.0:
				invested[entry[0]] = invested.get(entry[0], 0.0) + float(entry[1]) / max(0.01, table[entry[0]][0])
				top = max(top, invested[entry[0]])
	if top > 0.0:
		for stat_key in invested.keys():
			weights[stat_key] += 3.5 * invested[stat_key] / top
	for stat_key in weights.keys():
		weights[stat_key] *= rng.randf_range(0.7, 1.3)
	return weights


# The same weights with the runner-up stat boosted (for the second side of split patterns).
static func _shift_weights(rng: RandomNumberGenerator, weights: Dictionary) -> Dictionary:
	var ranked: Array = _ranked_stats(weights)
	var result: Dictionary = weights.duplicate()
	if ranked.size() > 2:
		var pick: String = ranked[rng.randi_range(1, 2)]
		result[pick] = result[pick] + weights[ranked[0]]
		result[ranked[0]] = result[ranked[0]] * 0.4
	return result


static func _ranked_stats(weights: Dictionary) -> Array:
	var ranked: Array = weights.keys()
	for i in range(1, ranked.size()):
		var j: int = i
		while j > 0 and weights[ranked[j - 1]] < weights[ranked[j]]:
			var tmp = ranked[j]
			ranked[j] = ranked[j - 1]
			ranked[j - 1] = tmp
			j -= 1
	return ranked


# The least-wanted half of the stats: where a "new direction" exit draws from.
static func _novel_stats(weights: Dictionary) -> Array:
	var ranked: Array = _ranked_stats(weights)
	return ranked.slice(int(ranked.size() / 2), ranked.size() - 1)


static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary, exclude: Array = []) -> String:
	var total = 0.0
	for stat_key in weights.keys():
		if not stat_key in exclude:
			total += weights[stat_key]
	var roll: float = rng.randf() * total
	var last = ""
	for stat_key in weights.keys():
		if stat_key in exclude:
			continue
		last = stat_key
		roll -= weights[stat_key]
		if roll <= 0.0:
			return stat_key
	return last


static func _desire_amount(stat_key: String, mult: float) -> int:
	var table: Dictionary = _stat_table()
	var base: float = float(table[stat_key][0]) if table.has(stat_key) else 1.0
	return int(max(1, round(base * mult)))


static func _make_desire_node(rng: RandomNumberGenerator, state: Dictionary, kind: int, weights: Dictionary, depth: int, pos: Vector2, frontier: bool, novel_pool: Array) -> Dictionary:
	var novel: bool = not novel_pool.empty()
	var primary: String = _pick(rng, novel_pool) if novel else _weighted_pick(rng, weights)
	var sector: int = _stat_sector(primary)
	if kind == Kind.KEYSTONE:
		var special_roll = rng.randf()
		if special_roll < 0.1 and depth >= 2:
			var relic = _roll_relic(rng, state)
			if not relic.empty():
				return _make_special_node(state, sector, depth, pos, frontier, relic[1], relic[2], relic[3], relic[0], not relic[4], relic[5] if relic.size() > 5 else [])
		elif special_roll < 0.4:
			var oddity: Array = _pick(rng, ODDITIES)
			return _make_special_node(state, sector, depth, pos, frontier, oddity[0], oddity[1], oddity[2], "", false, oddity[3] if oddity.size() > 3 else [])
	elif kind == Kind.NOTABLE and not novel and rng.randf() < 0.12:
		var named_options = []
		for entry in NOVEL_NOTABLES:
			if entry[4] == "" or flavor_available(entry[4]):
				named_options.push_back(entry)
		var named: Array = _pick(rng, named_options)
		var node = _make_special_node(state, sector, depth, pos, frontier, named[0], named[1], named[2], "", false, named[3])
		node["kind"] = Kind.NOTABLE
		node["special"] = "named"
		return node

	state["gen_n"] = state.gen_n + 1
	var grow: float = min(depth * 0.15, 2.5)
	var stats = []
	var bonus = []
	var node_name = ""
	var secondary: String = _weighted_pick(rng, weights, [primary])
	if kind == Kind.SMALL:
		if rng.randf() < 0.25:
			stats.push_back([primary, _desire_amount(primary, 1.4 + grow * 0.6)])
			stats.push_back([secondary, _desire_amount(secondary, 1.0 + grow * 0.4)])
		else:
			stats.push_back([primary, _desire_amount(primary, 2.0 + grow)])
	elif kind == Kind.NOTABLE:
		stats.push_back([primary, _desire_amount(primary, 3.5 + grow * 1.5)])
		stats.push_back([secondary, _desire_amount(secondary, 1.5 + grow * 0.5)])
		node_name = "%s %s" % [_pick(rng, NAME_PREFIXES[sector]), _pick(rng, NAME_SUFFIXES[_stat_sector(secondary)])]
	else:
		stats.push_back([primary, _desire_amount(primary, 5.0 + grow * 2.0)])
		stats.push_back([secondary, _desire_amount(secondary, 2.5 + grow)])
		if rng.randf() < 0.5:
			var ranked: Array = _ranked_stats(weights)
			var cost: String = ranked[ranked.size() - 1 - rng.randi_range(0, 2)]
			if cost != primary and cost != secondary:
				stats.push_back([cost, - _desire_amount(cost, 2.0)])
		bonus.push_back(_roll_bonus(rng))
		node_name = "%s %s" % [_pick(rng, CAPSTONE_TITLES), _pick(rng, NAME_SUFFIXES[sector])]
	var node = {
		"id": "g%d" % state.gen_n, "x": int(round(pos.x)), "y": int(round(pos.y)), "kind": kind, "name": node_name,
		"stats": stats, "bonus": bonus, "sector": sector, "depth": depth, "frontier": frontier, "gen": true,
	}
	if novel:
		node["novel"] = true
	return node


# Sometimes tucks a minor Evolution / Curse node off to the side of a cluster, away from
# its main paths (a dead end hanging off a small node).
static func _add_minor_spur(rng: RandomNumberGenerator, state: Dictionary, pattern: Dictionary, ids: Array, placed: Array, points: Array, edges: Array, pattern_depth: int) -> void:
	if rng.randf() >= 0.35:
		return
	var options = []
	if flavor_available("meca"):
		options.push_back(["Evolution Shard", [["stat_evolution", 1]]])
		options.push_back(["Mutagen Shard", [["stat_evolution", -1]]])
	if flavor_available("curse"):
		options.push_back(["Curse Shard", [["stat_curse", 1]]])
	if options.empty():
		return
	var centre = Vector2.ZERO
	for pos in placed:
		centre += pos
	centre /= float(placed.size())
	var hosts = []
	for i in pattern.nodes.size():
		if pattern.nodes[i][2] == "s" and pattern.nodes[i][3] == "":
			hosts.push_back(i)
	if hosts.empty():
		return
	for _attempt in 6:
		var host: int = hosts[rng.randi_range(0, hosts.size() - 1)]
		var from: Vector2 = placed[host]
		var away: Vector2 = (from - centre).normalized() if from.distance_to(centre) > 1.0 else Vector2.UP
		var pos: Vector2 = from + away.rotated(rng.randf_range(-0.6, 0.6)) * PATTERN_SCALE
		var clear = true
		for other in points:
			if pos.distance_to(other) < PATTERN_MIN_DIST:
				clear = false
				break
		if not clear or not _edge_fits(from, pos, points, edges):
			continue
		var choice: Array = _pick(rng, options)
		var node = _make_special_node(state, -1, pattern_depth, pos, false, choice[0], choice[1], [], "", false, [])
		node["kind"] = Kind.SMALL
		node["special"] = "minor"
		state.gen[node.id] = node
		state.gen_edges.push_back([ids[host], node.id])
		points.push_back(pos)
		edges.push_back([from, pos])
		return


# Lets the pattern's ports (then exits) join a nearby node that is far away along the tree.
static func _link_pattern(player_index: int, state: Dictionary, old_graph: Dictionary, parent_id: String, ids: Array) -> void:
	var near_hops: Dictionary = _hops_within(old_graph, parent_id, LINK_MIN_HOPS - 1)
	var g = graph(player_index)
	var points = []
	for id in g.order:
		points.push_back(_node_pos(g.nodes[id]))
	var edges = []
	for e in g.edges:
		edges.push_back([_node_pos(g.nodes[e[0]]), _node_pos(g.nodes[e[1]])])
	var own = {}
	for id in ids:
		own[id] = true
	var ordered = []
	for role in ["port", "exit", "orbit"]:
		for id in ids:
			if str(state.gen[id].get("role", "")) == role:
				ordered.push_back(id)
	var links = 0
	for id in ordered:
		if links >= MAX_LINKS:
			break
		var here: Vector2 = _node_pos(state.gen[id])
		var best_id = ""
		var best_dist: float = LINK_RANGE
		for other_id in old_graph.order:
			if own.has(other_id) or near_hops.has(other_id):
				continue
			var there: Vector2 = _node_pos(old_graph.nodes[other_id])
			var dist: float = here.distance_to(there)
			if dist < best_dist and _edge_fits(here, there, points, edges):
				best_dist = dist
				best_id = other_id
		if best_id != "":
			state.gen_edges.push_back([id, best_id])
			edges.push_back([here, _node_pos(old_graph.nodes[best_id])])
			links += 1


# Graph distance (in hops) from start, for nodes within max_hops.
static func _hops_within(g: Dictionary, start: String, max_hops: int) -> Dictionary:
	var hops = {start: 0}
	var queue = [start]
	var head = 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		if hops[current] >= max_hops:
			continue
		for next in g.adj.get(current, []):
			if not hops.has(next):
				hops[next] = hops[current] + 1
				queue.push_back(next)
	return hops


# Chance that a whole pattern is Mechanized / Mutated / Cursed. Grows with the level.
static func _roll_pattern_flavor(rng: RandomNumberGenerator, levels: Dictionary) -> String:
	var roll = rng.randf()
	for flavor in ["meca", "mutant", "curse"]:
		if not flavor_available(flavor):
			continue
		var chance: float = min(0.025 * float(levels.get(flavor, 0)), 0.35)
		if roll < chance:
			return flavor
		roll -= chance
	return ""


# A relic this player hasn't seen yet this run, or [] if all are out.
static func _roll_relic(rng: RandomNumberGenerator, state: Dictionary) -> Array:
	var seen = {}
	for id in state.gen.keys():
		var relic_id = state.gen[id].get("relic", "")
		if relic_id != "":
			seen[relic_id] = true
	var options = []
	for relic in RELICS:
		if not seen.has(relic[0]):
			options.push_back(relic)
	if options.empty():
		return []
	return _pick(rng, options)


static func _make_special_node(state: Dictionary, sector: int, depth: int, pos: Vector2, frontier: bool, node_name: String, stats: Array, bonus: Array, relic_id: String, no_refund: bool, mods: Array = []) -> Dictionary:
	state["gen_n"] = state.gen_n + 1
	return {
		"mods": mods.duplicate(true),
		"id": "g%d" % state.gen_n, "x": int(round(pos.x)), "y": int(round(pos.y)), "kind": Kind.KEYSTONE,
		"name": node_name, "stats": stats.duplicate(true), "bonus": bonus.duplicate(true),
		"sector": sector, "depth": depth, "frontier": frontier, "gen": true,
		"special": "relic" if relic_id != "" else "oddity", "relic": relic_id, "no_refund": no_refund,
	}


static func relic_count(player_index: int, relic_id: String) -> int:
	var count = 0
	for id in get_state(player_index).alloc:
		if str(get_node_data(player_index, id).get("relic", "")) == relic_id:
			count += 1
	return count


static func has_relic(player_index: int, relic_id: String) -> bool:
	return relic_count(player_index, relic_id) > 0


# Chance that a new frontier node is Mechanized / Mutated / Cursed. Grows with the level.
static func _roll_flavor(rng: RandomNumberGenerator, levels: Dictionary) -> String:
	var roll = rng.randf()
	for flavor in ["meca", "mutant", "curse"]:
		if not flavor_available(flavor):
			continue
		var chance: float = min(0.04 + 0.015 * float(levels.get(flavor, 0)), 0.3)
		if roll < chance:
			return flavor
		roll -= chance
	return ""


static func _make_flavor_node(rng: RandomNumberGenerator, state: Dictionary, kind: int, flavor: String, sector: int, depth: int, pos: Vector2, frontier: bool) -> Dictionary:
	state["gen_n"] = state.gen_n + 1
	var info: Dictionary = FLAVORS[flavor]
	var kind_mult: float = [1.0, 1.0, 1.6, 2.5][kind]
	var grow: float = 1.0 + min(depth * 0.05, 1.0)
	var picks = _pick_distinct(rng, info.pool, 1 if kind == Kind.SMALL else 2)
	var scaling = []
	var stats = []
	for pick in picks:
		var per_level: float = stepify(float(pick[1]) * kind_mult * grow, 0.01)
		scaling.push_back([pick[0], per_level])
		# A small fixed part so the node is worth something before the level builds up.
		stats.push_back([pick[0], int(max(1, round(per_level * 3.0)))])
	var bonus = []
	var node_name = ""
	if kind == Kind.NOTABLE:
		node_name = "%s %s" % [_pick(rng, info.prefixes), _pick(rng, info.suffixes)]
	elif kind == Kind.KEYSTONE:
		node_name = "%s %s" % [_pick(rng, info.titles), _pick(rng, info.suffixes)]
		bonus.push_back(_pick(rng, info.bonuses))
	if flavor == "curse" and kind != Kind.SMALL:
		stats.push_back(["stat_curse", 1])
	return {
		"id": "g%d" % state.gen_n, "x": int(round(pos.x)), "y": int(round(pos.y)), "kind": kind,
		"name": node_name, "stats": stats, "scaling": scaling, "bonus": bonus, "flavor": flavor,
		"sector": sector, "depth": depth, "frontier": frontier, "gen": true,
	}


static func _make_node(rng: RandomNumberGenerator, state: Dictionary, kind: int, sector: int, mixed_sector: int, depth: int, pos: Vector2, frontier: bool, flavor: String = "") -> Dictionary:
	if flavor != "":
		return _make_flavor_node(rng, state, kind, flavor, sector, depth, pos, frontier)
	if kind == Kind.KEYSTONE and flavor == "":
		var special_roll = rng.randf()
		if special_roll < 0.1 and depth >= 2:
			var relic = _roll_relic(rng, state)
			if not relic.empty():
				return _make_special_node(state, sector, depth, pos, frontier, relic[1], relic[2], relic[3], relic[0], not relic[4])
		elif special_roll < 0.4:
			var oddity: Array = _pick(rng, ODDITIES)
			return _make_special_node(state, sector, depth, pos, frontier, oddity[0], oddity[1], oddity[2], "", false)
	state["gen_n"] = state.gen_n + 1
	var id = "g%d" % state.gen_n
	var pool: Array = SECTOR_POOLS[sector]
	var grow: float = min(depth * 0.15, 2.5)
	var stats = []
	var node_name = ""
	var bonus = []
	if kind == Kind.SMALL:
		if mixed_sector >= 0:
			stats.push_back(_roll_stat(rng, SECTOR_POOLS[mixed_sector], 1.2 + grow * 0.5))
			stats.push_back(_roll_stat(rng, pool, 1.2 + grow * 0.5))
		else:
			stats.push_back(_roll_stat(rng, pool, 2.0 + grow))
	elif kind == Kind.NOTABLE:
		var picks = _pick_distinct(rng, pool, 2)
		stats.push_back([picks[0][0], _base_amount(picks[0], 3.5 + grow * 1.5)])
		stats.push_back([picks[1][0], _base_amount(picks[1], 1.5 + grow * 0.5)])
		node_name = "%s %s" % [_pick(rng, NAME_PREFIXES[sector]), _pick(rng, NAME_SUFFIXES[sector])]
	else:
		var picks = _pick_distinct(rng, pool, 2)
		stats.push_back([picks[0][0], _base_amount(picks[0], 5.0 + grow * 2.0)])
		stats.push_back([picks[1][0], _base_amount(picks[1], 2.5 + grow)])
		if rng.randf() < 0.5:
			var other_pool: Array = SECTOR_POOLS[posmod(sector + 4, SECTOR_POOLS.size())]
			var cost: Array = _pick(rng, other_pool)
			var already = false
			for stat in stats:
				if stat[0] == cost[0]:
					already = true
			if not already:
				stats.push_back([cost[0], - _base_amount(cost, 2.0)])
		bonus.push_back(_roll_bonus(rng))
		node_name = "%s %s" % [_pick(rng, CAPSTONE_TITLES), _pick(rng, NAME_SUFFIXES[sector])]
	return {
		"id": id, "x": int(round(pos.x)), "y": int(round(pos.y)), "kind": kind, "name": node_name,
		"stats": stats, "bonus": bonus, "sector": sector, "depth": depth,
		"frontier": frontier, "gen": true,
	}


static func _roll_stat(rng: RandomNumberGenerator, pool: Array, mult: float) -> Array:
	var stat: Array = _pick(rng, pool)
	return [stat[0], _base_amount(stat, mult)]


static func _base_amount(stat: Array, mult: float) -> int:
	return int(max(1, round(float(stat[1]) * mult)))


static func _roll_bonus(rng: RandomNumberGenerator) -> Array:
	var total = 0
	for bonus in BONUS_EFFECTS:
		total += bonus[3]
	var roll = rng.randi_range(1, total)
	for bonus in BONUS_EFFECTS:
		roll -= bonus[3]
		if roll <= 0:
			return [bonus[0], bonus[1]]
	return [BONUS_EFFECTS[0][0], BONUS_EFFECTS[0][1]]


static func _pick(rng: RandomNumberGenerator, list: Array):
	return list[rng.randi_range(0, list.size() - 1)]


static func _pick_distinct(rng: RandomNumberGenerator, list: Array, count: int) -> Array:
	var shuffled = list.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var result = []
	for i in count:
		result.push_back(shuffled[i % shuffled.size()])
	return result


static func _is_spaced(pos: Vector2, positions: Array, spacing: float) -> bool:
	for other in positions:
		if pos.distance_to(other) < spacing:
			return false
	return true


static func _has_edge(state: Dictionary, a: String, b: String) -> bool:
	for e in state.gen_edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false


static func _nearest_sector(pos: Vector2) -> int:
	var angle = rad2deg(atan2(pos.y, pos.x)) + 90.0
	return posmod(int(round(angle / 45.0)), SECTOR_POOLS.size())


static func flavor_label(flavor: String) -> String:
	if FLAVORS.has(flavor):
		return FLAVORS[flavor].label
	return ""


static func flavor_color(flavor: String) -> Color:
	if FLAVORS.has(flavor):
		return Color(FLAVORS[flavor].color)
	return Color(1, 1, 1)


static func describe_scaling(stat_key: String, per_level: float, level: int, mult: float) -> String:
	var info: Array = STAT_INFO.get(stat_key, ["", "", false, false])
	var pct = "%" if info[2] else ""
	var per_text = str(stepify(per_level * mult, 0.01))
	return "+%s%s %s per level (now %+d%s)" % [per_text, pct, stat_label(stat_key), scaling_amount(per_level, level, mult), pct]


static func describe_bonus(bonus: Array) -> String:
	for info in BONUS_EFFECTS:
		if info[0] == bonus[0]:
			var text: String = info[2]
			if text.find("%") < 0:
				return text
			return text % int(bonus[1])
	return "%s %d" % [str(bonus[0]), int(bonus[1])]


static func mod_total(player_index: int, mod_key: String) -> float:
	var total = 0.0
	for id in get_state(player_index).alloc:
		for entry in get_node_data(player_index, id).get("mods", []):
			if entry[0] == mod_key:
				total += float(entry[1])
	return total


# Cached per player; the key changes with the run, a reload/retry, or any allocation change.
static func red_crit_multiplier(player_index: int) -> float:
	var mod = Config.mod_node()
	var state = get_state(player_index)
	var key = "%s:%d:%d" % [str(state.seed), state.alloc.size(), state.points]
	if mod != null:
		var cached = mod.red_cache.get(player_index)
		if cached is Dictionary and cached.get("key") == key:
			return float(cached.value)
	var value: float = RED_CRIT_BASE + mod_total(player_index, "red_crit")
	if mod != null:
		mod.red_cache[player_index] = {"key": key, "value": value}
	return value


# Crit tier for one hit: 1 = normal crit, 2 = red, 3-4 = overcrit.
static func roll_crit_tier(crit_chance: float) -> int:
	var over: float = crit_chance - 1.0
	if over <= 0.0:
		return 1
	var tier: int = 1 + int(floor(over))
	if randf() < over - floor(over):
		tier += 1
	return int(min(tier, RED_CRIT_MAX_TIER))


static func describe_mod(entry: Array) -> String:
	if entry[0] == "red_crit":
		return "+%d%% red crit damage" % int(round(float(entry[1]) * 100.0))
	return "%s %s" % [str(entry[0]), str(entry[1])]


# ---------------- Level-ups ----------------

# Some characters turn level-ups into weapon slots; those still get the slot, not a point.
static func needs_weapon_slot_upgrade(player_index: int) -> bool:
	var slot_upgrades = RunData.get_player_effect(Keys.weapon_slot_upgrades_hash, player_index)
	var slots = RunData.get_player_effect(Keys.weapon_slot_hash, player_index)
	return slot_upgrades > 0 and slots < slot_upgrades


# ---------------- Text ----------------

static func stat_label(stat_key: String) -> String:
	var info: Array = STAT_INFO.get(stat_key, ["", stat_key.capitalize(), false, false])
	if info[0] != "":
		var translated: String = TranslationServer.translate(info[0])
		if translated != info[0] and translated != "":
			return translated
	return info[1]


static func is_stat_good(stat_key: String, value: int) -> bool:
	var info: Array = STAT_INFO.get(stat_key, ["", "", false, false])
	return (value < 0) if info[3] else (value >= 0)


static func describe_stat(stat_key: String, value: int) -> String:
	var info: Array = STAT_INFO.get(stat_key, ["", "", false, false])
	var sign_text = "+" if value >= 0 else "-"
	var pct = "%" if info[2] else ""
	return "%s%d%s %s" % [sign_text, abs(value), pct, stat_label(stat_key)]


static func node_title(data: Dictionary) -> String:
	if data.get("name", "") != "":
		return data.name
	var stats: Array = data.get("stats", [])
	if stats.empty():
		return "?"
	var parts = []
	for stat in stats:
		parts.push_back(stat_label(stat[0]))
	return PoolStringArray(parts).join(" & ")


# ---------------- Input ownership ----------------

# Which player an input event belongs to (-1: nobody). Solo: always player 0.
static func event_player(event: InputEvent) -> int:
	if not RunData.is_coop_run:
		return 0
	var is_joy: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	var remapped = -1
	if event is InputEventKey or event is InputEventMouse:
		remapped = CoopService.KEYBOARD_REMAPPED_DEVICE_ID
	elif is_joy:
		remapped = event.device
	else:
		return -1
	for player_index in RunData.get_player_count():
		var device: int = CoopService.get_remapped_player_device(player_index)
		if device == remapped:
			return player_index
		if is_joy and event.device == 0 and device == CoopService.GAMEPAD_REMAPPED_DEVICE_ID:
			return player_index
	return -1


static func player_uses_gamepad(player_index: int) -> bool:
	if RunData.is_coop_run:
		return CoopService.is_player_using_gamepad(player_index)
	return bool(InputService.using_gamepad)


static func player_uses_mouse(player_index: int) -> bool:
	if not RunData.is_coop_run:
		return true
	return CoopService.get_remapped_player_device(player_index) == CoopService.KEYBOARD_REMAPPED_DEVICE_ID


# P on the keyboard or Back/Select on a controller opens the tree.
static func is_open_request(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	if event is InputEventKey:
		return event.physical_scancode == KEY_P or event.scancode == KEY_P
	if event is InputEventJoypadButton:
		return event.button_index == JOY_SELECT
	return false


static func player_name(player_index: int) -> String:
	if not RunData.is_coop_run:
		return ""
	return "Player %d" % (player_index + 1)
