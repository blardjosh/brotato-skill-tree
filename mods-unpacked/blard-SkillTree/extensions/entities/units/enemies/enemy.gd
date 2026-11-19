extends "res://entities/units/enemies/enemy.gd"
# blard-SkillTree: red crits. When a hit's crit chance is over 100%, roll a crit tier
# (SkillTree.roll_crit_tier). Tier 2+ multiplies the hitbox's crit damage for this one hit,
# then puts it back. The tier is kept on the enemy while the hit resolves so the floating
# text extension can colour the number.
#
# Signature matches other mods that extend this (args untyped), so the extensions chain.

const BlardSkillTree = preload("res://mods-unpacked/blard-SkillTree/skill_tree.gd")

var _blard_crit_tier: int = 0


func take_damage(value: int, args) -> Array:
	var hitbox = null
	if args != null and "hitbox" in args:
		hitbox = args.hitbox
	var tier: int = 1
	var original_crit_damage: float = 0.0
	if hitbox != null and is_instance_valid(hitbox) and hitbox.crit_chance > 1.0 and args.from_player_index >= 0:
		tier = BlardSkillTree.roll_crit_tier(hitbox.crit_chance)
		if tier >= 2:
			original_crit_damage = hitbox.crit_damage
			var mult: float = BlardSkillTree.red_crit_multiplier(args.from_player_index)
			hitbox.crit_damage = original_crit_damage * pow(mult, tier - 1)
	_blard_crit_tier = tier
	var result = .take_damage(value, args)
	_blard_crit_tier = 0
	if tier >= 2 and hitbox != null and is_instance_valid(hitbox):
		hitbox.crit_damage = original_crit_damage
	return result
