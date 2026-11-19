extends "res://visual_effects/floating_text/floating_text_manager.gd"
# blard-SkillTree: red crit numbers. Tier 2 crits show red with "!", tier 3+ purple "!!".

const BLARD_RED_CRIT := Color(1.0, 0.2, 0.2)
const BLARD_OVERCRIT := Color(0.85, 0.35, 1.0)


func _on_unit_took_damage(unit: Unit, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool) -> void:
	var tier: int = 0
	if is_crit and not unit is Player and "_blard_crit_tier" in unit:
		tier = int(unit._blard_crit_tier)
	if tier < 2 or not ProgressData.settings.damage_display or args.hide_feedback:
		._on_unit_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
		return
	var color: Color = BLARD_RED_CRIT if tier == 2 else BLARD_OVERCRIT
	var text: String = str(value)
	for _i in tier - 1:
		text += "!"
	var icon = null if hit_type == HitType.NORMAL else get_special_hit_icon(hit_type)
	var text_pos: Vector2 = unit.get_hit_feedback_position(args) if unit.aim_shape != null else unit.global_position
	display(text, text_pos, color, icon, duration, true, direction, false)
