extends Reference
# blard-SkillTree settings. Values come from the Mod Options "Mods" tab when that mod is
# installed; otherwise the defaults below are used.

const MOD_ID := "blard-SkillTree"

const POWER_CHOICES := ["50%", "75%", "100%", "125%", "150%", "200%"]
const POINT_CHOICES := ["1", "2", "3"]

const DEFAULTS := {
	"open_on_level_up": true,
	"allow_refunds": true,
	"points_per_level": "1",
	"power": "100%",
}


static func value(option_id: String):
	var node = mod_node()
	if node != null and node.config.has(option_id) and node.config[option_id] != null:
		return node.config[option_id]
	return DEFAULTS[option_id]


static func flag(option_id: String) -> bool:
	return bool(value(option_id))


static func points_per_level() -> int:
	return int(max(1, str(value("points_per_level")).to_int()))


# Multiplier for every node value. It is locked into a run the first time that run uses the
# tree, so refunds always remove exactly what was added.
static func power() -> float:
	var pct: float = str(value("power")).replace("%", "").to_float()
	if pct <= 0.0:
		pct = 100.0
	return pct / 100.0


static func mod_node() -> Node:
	var tree = Engine.get_main_loop()
	if tree == null or not tree is SceneTree:
		return null
	return tree.root.get_node_or_null("ModLoader/" + MOD_ID)
