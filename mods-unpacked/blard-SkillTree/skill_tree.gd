extends Reference
# blard-SkillTree: tree rules and per-player state.
#
# State lives in the player's effects dictionary under one custom key, so it is saved with
# the run, duplicated into the start-of-wave snapshot (wave retries) and wiped on a new run:
#   {"points": int, "alloc": [node ids], "mult": float}
# Node bonuses are applied with RunData.add_stat / remove_stat, the same as vanilla stats.

const TreeData = preload("res://mods-unpacked/blard-SkillTree/tree_data.gd")
const Config = preload("res://mods-unpacked/blard-SkillTree/config.gd")

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
}


# ---------------- Graph ----------------

static func graph() -> Dictionary:
	var node = Config.mod_node()
	if node != null and not node.graph_cache.empty():
		return node.graph_cache
	var g: = {"nodes": {}, "adj": {}, "order": [], "edges": TreeData.EDGES}
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


static func get_node_data(id: String) -> Dictionary:
	var g: = graph()
	return g.nodes.get(id, {})


# ---------------- State ----------------

static func state_key() -> int:
	return Keys.generate_hash(STATE_KEY_NAME)


static func get_state(player_index: int) -> Dictionary:
	var effects: Dictionary = RunData.get_player_effects(player_index)
	var key: = state_key()
	var state = effects.get(key)
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
	return state


static func get_points(player_index: int) -> int:
	return get_state(player_index).points


static func add_points(player_index: int, amount: int) -> void:
	var state: = get_state(player_index)
	state["points"] = state.points + amount


static func players_with_points() -> Array:
	var result: = []
	for player_index in RunData.get_player_count():
		if get_points(player_index) > 0:
			result.push_back(player_index)
	return result


static func allocated_set(player_index: int) -> Dictionary:
	var result: = {START_ID: true}
	for id in get_state(player_index).alloc:
		result[str(id)] = true
	return result


static func allocated_count(player_index: int) -> int:
	return get_state(player_index).alloc.size()


# ---------------- Rules ----------------

# Unallocated nodes to take, in order, to reach target from the allocated part of the tree.
# Empty if target is already allocated or unknown.
static func path_to(player_index: int, target: String) -> Array:
	var g: = graph()
	var alloc: = allocated_set(player_index)
	if alloc.has(target) or not g.nodes.has(target):
		return []
	var came_from: = {}
	var queue: = []
	for id in alloc.keys():
		came_from[id] = ""
		queue.push_back(id)
	var head: = 0
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
	var path: = []
	var step: String = target
	while not alloc.has(step):
		path.push_front(step)
		step = came_from[step]
	return path


static func is_reachable(id: String, alloc: Dictionary) -> bool:
	if alloc.has(id):
		return false
	for next in graph().adj.get(id, []):
		if alloc.has(next):
			return true
	return false


# Allocates the whole path to target if there are enough points. Returns nodes allocated.
static func allocate_path(player_index: int, target: String) -> int:
	var path: = path_to(player_index, target)
	var state: = get_state(player_index)
	if path.empty() or path.size() > state.points:
		return 0
	for id in path:
		state.alloc.push_back(id)
		state["points"] = state.points - 1
		_apply_node(player_index, id, 1, state.mult)
	_after_stats_changed(player_index)
	return path.size()


static func can_refund(player_index: int, id: String) -> bool:
	if not Config.flag("allow_refunds") or id == START_ID:
		return false
	var alloc: = allocated_set(player_index)
	if not alloc.has(id):
		return false
	# Every other allocated node must still connect to the start without this one.
	alloc.erase(id)
	var g: = graph()
	var seen: = {START_ID: true}
	var queue: = [START_ID]
	var head: = 0
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
	var state: = get_state(player_index)
	state.alloc.erase(id)
	state["points"] = state.points + 1
	_apply_node(player_index, id, -1, state.mult)
	_after_stats_changed(player_index)
	return true


static func scaled_value(base_value: int, mult: float) -> int:
	var scaled: = int(round(abs(base_value) * mult))
	if scaled == 0:
		scaled = 1
	return scaled if base_value >= 0 else -scaled


static func _apply_node(player_index: int, id: String, direction: int, mult: float) -> void:
	var data: = get_node_data(id)
	var effects: Dictionary = RunData.get_player_effects(player_index)
	for stat in data.get("stats", []):
		var stat_hash: int = Keys.generate_hash(stat[0])
		if not effects.has(stat_hash):
			continue
		var amount: = scaled_value(int(stat[1]), mult) * direction
		if amount >= 0:
			RunData.add_stat(stat_hash, amount, player_index)
		else:
			RunData.remove_stat(stat_hash, - amount, player_index)


static func _after_stats_changed(player_index: int) -> void:
	LinkedStats.reset_player(player_index)
	Utils.reset_stat_cache(player_index)


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
	var sign_text: = "+" if value >= 0 else "-"
	var pct: = "%" if info[2] else ""
	return "%s%d%s %s" % [sign_text, abs(value), pct, stat_label(stat_key)]


static func node_title(data: Dictionary) -> String:
	if data.get("name", "") != "":
		return data.name
	var stats: Array = data.get("stats", [])
	if stats.empty():
		return "?"
	var parts: = []
	for stat in stats:
		parts.push_back(stat_label(stat[0]))
	return PoolStringArray(parts).join(" & ")


# ---------------- Input ownership ----------------

# Which player an input event belongs to (-1: nobody). Solo: always player 0.
static func event_player(event: InputEvent) -> int:
	if not RunData.is_coop_run:
		return 0
	var is_joy: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	var remapped: = -1
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
