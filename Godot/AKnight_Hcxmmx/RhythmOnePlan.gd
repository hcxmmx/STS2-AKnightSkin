extends RefCounted

# Source time stays explicit; each slash owns its FX and audio tail.
const NAMES=["一技能 · 第一刀","一技能 · 第二刀","一技能 · 第三刀","一技能 · 三刀连续接续","一技能 · 三次独立出手","二技能 · 取消蓄力直斩","施法 · 摸剑短动作","能力 · 举剑短动作","大招 · 第一刀快进快出","大招 · 第二刀与加速收尾"]
const FROM=[1.05,1.37,2.0]
const TO=[1.37,2.0,2.5]
const HITS=[1.1666667,1.4833333,2.1]
const GROUPS=[[[0,12],[24,33]],[[12,24],[33,43]],[[43,70]]]
const RETURN=.20
var mode:=3

func events() -> Array:
	if mode>=5:return []
	if mode<3:return [{"slash":mode,"start":.22}]
	if mode==3:return [{"slash":0,"start":.22},{"slash":1,"start":.54},{"slash":2,"start":1.17}]
	return [{"slash":0,"start":.22},{"slash":1,"start":1.35},{"slash":2,"start":2.80}]

func duration() -> float:
	if mode==8:return 1.35
	if mode==9:return 3.1
	return 5.0 if mode==4 else 3.3

func source(t: float) -> float:
	var elapsed=maxf(0,t-.22)
	match mode:
		5:return 1.85+elapsed
		6:return .2+elapsed
		7:return 1.05+elapsed
		8:return 6.1+elapsed
		9:return 8.17+minf(elapsed,.98)+maxf(0,elapsed-.98)*2.2
	return 0.0

func unique_wall(source_time: float) -> float:
	return .22+(source_time-8.17 if source_time<=9.15 else .98+(source_time-9.15)/2.2)

func groups(slash: int) -> Array:
	var ids: Array=[]
	for span in GROUPS[slash]:ids.append_array(range(span[0],span[1]))
	return ids

func sample(t: float) -> Dictionary:
	var selected: Dictionary={}
	for event in events():
		if t>=float(event.start):selected=event
	if selected.is_empty():return {"animation":"idle","at":t,"from":"","from_at":0.0,"mix":0.0,"mix_duration":.08,"slash":-1}
	var id: int=selected.slash;var elapsed: float=t-float(selected.start)
	var length: float=TO[id]-FROM[id]
	if elapsed<length:
		var previous="idle";var at=0.0;var blend=.08
		if mode==3 and id>0:
			previous="skill1_3";at=TO[id-1];blend=.045
		return {"animation":"skill1_3","at":FROM[id]+elapsed,"from":previous,"from_at":at,"mix":elapsed,"mix_duration":blend,"slash":id}
	return {"animation":"idle","at":elapsed-length,"from":"skill1_3","from_at":TO[id],"mix":elapsed-length,"mix_duration":RETURN,"slash":-1}
