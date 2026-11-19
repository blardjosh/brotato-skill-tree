extends Node

const MOD_ID := "blard-SkillTree"
const LOG_NAME := "blard-SkillTree:Main"
const MOD_OPTIONS_PATH := "/root/ModLoader/Oudstand-ModOptions/ModOptions"
# Loaded after startup (not preloaded): it is fine on its own, but keeping mod_main free of
# preloads means nothing here can touch game autoloads while ModLoader is initializing.
const CONFIG_PATH := "res://mods-unpacked/blard-SkillTree/config.gd"

# Current option values (read through config.gd), plus caches shared by the static helpers.
var config: = {}
var graph_cache: = {}
var icon_cache: = {}
var _mod_options = null
var _register_attempts: = 0


func _init() -> void:
	var dir: String = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/"
	# Only leaf scripts are extended, so no other scripts inherit a stale parent.
	ModLoaderMod.install_script_extension(dir + "extensions/main.gd")
	ModLoaderMod.install_script_extension(dir + "extensions/ui/menus/shop/shop.gd")
	ModLoaderMod.install_script_extension(dir + "extensions/ui/menus/shop/coop_shop.gd")
	ModLoaderLog.info("Loaded", LOG_NAME)


func _ready() -> void:
	call_deferred("_register_mod_options")


func _register_mod_options() -> void:
	var Config = load(CONFIG_PATH)
	if config.empty():
		config = Config.DEFAULTS.duplicate()
	_mod_options = get_node_or_null(MOD_OPTIONS_PATH)
	if _mod_options == null:
		_register_attempts += 1
		if _register_attempts < 5:
			get_tree().create_timer(0.5).connect("timeout", self, "_register_mod_options")
		else:
			ModLoaderLog.info("Mod Options not found; using default settings", LOG_NAME)
		return
	if _mod_options.has_method("get_registered_mods") and MOD_ID in _mod_options.get_registered_mods():
		return
	_mod_options.register_mod_options(MOD_ID, {
		"tab_title": "Skill Tree",
		"info_text": "Level-ups give skill points for the passive tree. Open it in the shop with P (keyboard) or Back/Select (controller). Power is locked in when a run first uses the tree.",
		"options": [
			{"type": "toggle", "id": "open_on_level_up", "label": "Open the tree after a wave with new points", "default": Config.DEFAULTS.open_on_level_up},
			{"type": "toggle", "id": "allow_refunds", "label": "Allow refunding nodes", "default": Config.DEFAULTS.allow_refunds},
			{"type": "dropdown", "id": "points_per_level", "label": "Skill points per level", "choices": Config.POINT_CHOICES, "default": Config.DEFAULTS.points_per_level},
			{"type": "dropdown", "id": "power", "label": "Node power (new runs)", "choices": Config.POWER_CHOICES, "default": Config.DEFAULTS.power},
		],
	})
	for option_id in Config.DEFAULTS.keys():
		var saved = _mod_options.get_value(MOD_ID, option_id)
		if saved != null:
			config[option_id] = saved
	var _err = _mod_options.connect("config_changed", self, "_on_config_changed")
	ModLoaderLog.info("Registered with Mod Options", LOG_NAME)


func _on_config_changed(mod_id: String, option_id: String, new_value) -> void:
	var Config = load(CONFIG_PATH)
	if mod_id != MOD_ID or not Config.DEFAULTS.has(option_id):
		return
	config[option_id] = new_value
