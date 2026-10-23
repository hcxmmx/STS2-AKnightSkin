extends RefCounted
# Compatibility adapter: preserve the established home-only key meanings.
const Core=preload("res://AKnight_Hcxmmx/Settings.gd")
const PATH=Core.PATH
const DEFAULTS={"auto_greeting":true,"bilingual_subtitles":true,"voice_volume":.8,"home_touch_interval":.8}
static func read() -> Dictionary:
	var all_settings=Core.read();var home: Dictionary={}
	for key in DEFAULTS:home[key]=all_settings["home_voice_volume" if key=="voice_volume" else key]
	return home
static func write(key: String,value) -> Error:
	if not DEFAULTS.has(key):return ERR_INVALID_PARAMETER
	return Core.write("home_voice_volume" if key=="voice_volume" else key,value)
