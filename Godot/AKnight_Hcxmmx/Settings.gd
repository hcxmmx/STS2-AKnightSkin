extends RefCounted

const PATH="user://a_knight_skin.cfg"
const DEFAULTS={"mode":"rhythm","ultimate_enabled":true,"ultimate_mode":"follow","ultimate_card":"PACTS_END","brightness":1.0,"glow_strength":.35,"combat_voice":true,"original_sfx":true,"voice_volume":.8,"sfx_volume":.8,"combat_voice_interval":4.0,"auto_greeting":true,"bilingual_subtitles":true,"home_voice_volume":.8,"home_touch_interval":.8}
const LOCATIONS={"mode":["visuals","mode"],"ultimate_enabled":["visuals","ultimate_enabled"],"ultimate_mode":["visuals","ultimate_mode"],"ultimate_card":["visuals","ultimate_card"],"brightness":["visuals","brightness"],"glow_strength":["visuals","glow_strength"],"combat_voice":["audio","combat_voice"],"original_sfx":["audio","original_sfx"],"voice_volume":["audio","voice_volume"],"sfx_volume":["audio","sfx_volume"],"combat_voice_interval":["audio","combat_voice_interval"],"auto_greeting":["home","auto_greeting"],"bilingual_subtitles":["home","bilingual_subtitles"],"home_voice_volume":["home","voice_volume"],"home_touch_interval":["home","home_touch_interval"]}
const RANGES={"brightness":[.2,2.0],"glow_strength":[0.0,1.0],"voice_volume":[0.0,1.0],"sfx_volume":[0.0,1.0],"home_voice_volume":[0.0,1.0],"home_touch_interval":[0.0,15.0],"combat_voice_interval":[0.0,15.0]}

static func _validated(key: String,value):
	if RANGES.has(key):
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return DEFAULTS[key]
		return clampf(float(value),RANGES[key][0],RANGES[key][1])
	if DEFAULTS[key] is bool:return value if value is bool else DEFAULTS[key]
	if key=="mode":return value if value in ["rhythm","full"] else DEFAULTS[key]
	if key=="ultimate_mode":return value if value in ["follow","rhythm","full"] else DEFAULTS[key]
	if key=="ultimate_card":
		var id:=str(value).strip_edges().to_upper()
		return id if not id.is_empty() and id.is_valid_identifier() else DEFAULTS[key]
	return str(value)

static func read() -> Dictionary:
	var result=DEFAULTS.duplicate();var cfg=ConfigFile.new()
	if cfg.load(PATH)==OK:
		for key in DEFAULTS:
			var at: Array=LOCATIONS[key]
			result[key]=_validated(key,cfg.get_value(at[0],at[1],DEFAULTS[key]))
	return result

static func write(key: String,value) -> Error:
	if not DEFAULTS.has(key):return ERR_INVALID_PARAMETER
	var cfg=ConfigFile.new();var error:=cfg.load(PATH) if FileAccess.file_exists(PATH) else OK
	if error!=OK:return error
	var at: Array=LOCATIONS[key];cfg.set_value(at[0],at[1],_validated(key,value))
	return cfg.save(PATH)

static func reset() -> Error:
	var cfg=ConfigFile.new();var error:=cfg.load(PATH) if FileAccess.file_exists(PATH) else OK
	if error!=OK:return error
	for key in DEFAULTS:
		var at: Array=LOCATIONS[key];cfg.set_value(at[0],at[1],DEFAULTS[key])
	return cfg.save(PATH)
