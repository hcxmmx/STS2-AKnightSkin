extends Node

# Long source SFX stems and short impact cues share the preview clock. Seeking
# resumes audible tails; it never fires every impact that was skipped over.
var catalog: Dictionary = {}
static var streams: Dictionary = {}
var cues: Array = []
var players: Array[AudioStreamPlayer] = []
var duration := 0.0
var enabled := true
var gain := .8
var fired: Array = []

func _ready():
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/sfx_catalog.json"))
	for i in 5:
		var player:=AudioStreamPlayer.new();add_child(player);players.append(player)

func configure(page: int, action: String, cycle: int):
	stop();cues.clear();duration=0.0
	if page>=2:
		var name_value: String={2:"skill1",3:"skill2",4:"unique"}[page]
		var skill: Dictionary=catalog.skills[name_value]
		_add(str(skill.clip),float(skill.start))
		for i in skill.hits.size():
			var choices: Array=skill.hit_variants
			_add(str(choices[(cycle+i)%choices.size()]),float(skill.hits[i]))
	elif page==0 and catalog.actions.has(action):
		_add(str(catalog.actions[action]),0)
	fired.clear()

func _add(id: String, at: float):
	var clip: Dictionary=catalog.clips[id]
	if not streams.has(id):streams[id]=AudioStreamWAV.load_from_file(clip.file, {})
	cues.append({"id":id,"start":at,"end":at+float(clip.duration)})
	duration=maxf(duration,at+float(clip.duration))

func stop():
	for player in players:player.stop()

func sync(at: float, playing: bool):
	stop();fired.clear()
	for i in cues.size():
		var cue: Dictionary=cues[i]
		if at>=float(cue.start):fired.append(i)
		if playing and enabled and at>=float(cue.start) and at<float(cue.end):_play(cue,at-float(cue.start))

func advance(from: float, to: float, playing: bool):
	if not enabled or not playing:return
	for player in players:
		if player.playing and to>=float(player.get_meta("cue_end",INF)):player.stop()
	for i in cues.size():
		var cue: Dictionary=cues[i]
		if not i in fired and float(cue.start)>from and float(cue.start)<=to:
			fired.append(i)
			if to<float(cue.end):_play(cue,to-float(cue.start))

func _play(cue: Dictionary, offset: float):
	for player in players:
		if player.playing:continue
		player.stream=streams[cue.id];player.set_meta("cue_end",cue.end);player.play(maxf(0,offset));return

func update_volume(focused: bool):
	for player in players:player.volume_db=linear_to_db(maxf(.0001,gain)) if focused else -80.0

func playing_count() -> int:
	var count:=0
	for player in players:
		if player.playing:count+=1
	return count
