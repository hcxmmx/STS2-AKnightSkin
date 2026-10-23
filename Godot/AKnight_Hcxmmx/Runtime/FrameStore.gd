extends RefCounted

# One small shared cache for repeated geometry. Dynamic groups remain streaming;
# parsed mesh caches and their existing budgets are owned by the players.
const REPEATED_BYTES:=4*1024*1024
static var repeated:Dictionary={}
static var repeated_bytes:=0
var file:FileAccess
var key:String
var meta:Dictionary
var storage:Dictionary
var offsets:Dictionary={}
var frame_start:=0
var frame_end:=0
var cursor:=0
var count_data:=PackedByteArray()
var ids:Array=[]
var starts:Array[int]=[]
var ends:Array[int]=[]
var segment:=0
var header_id:=-1
var header:=PackedByteArray()
var body_id:=-1
var body:=PackedByteArray()
var raw_mode:=false

static func open(folder:String,details:Dictionary):
	var stream=load("res://AKnight_Hcxmmx/Runtime/FrameStore.gd").new()
	stream.configure(folder,details)
	return stream

func configure(folder:String,details:Dictionary)->void:
	meta=details
	if not meta.has("storage"):
		raw_mode=true;file=FileAccess.open(folder+"frames.bin",FileAccess.READ);assert(file!=null);return
	storage=meta.storage
	assert(storage.format=="group_blocks_v1")
	key=folder+str(storage.file)
	file=FileAccess.open(key,FileAccess.READ);assert(file!=null)
	for i in meta.frames.size():offsets[int(meta.frames[i].offset)]=i

func seek(position:int)->void:
	if raw_mode:file.seek(position);return
	if offsets.has(position):
		var index:int=offsets[position]
		frame_start=position;frame_end=position+int(meta.frames[index].bytes)
		ids=storage.frames[index];starts.clear();ends.clear()
		var at:=position+4
		for id in ids:
			var block:Array=storage.blocks[int(id)]
			starts.append(at);at+=str(block[3]).length()/2+int(block[2]);ends.append(at)
		assert(at==frame_end)
		count_data.resize(4);count_data.encode_u32(0,ids.size())
	assert(position>=frame_start and position<=frame_end)
	cursor=position;segment=0
	while segment<ends.size() and cursor>=ends[segment]:segment+=1

func get_position()->int:return file.get_position() if raw_mode else cursor
func get_32()->int:return get_buffer(4).decode_u32(0)
func get_float()->float:return get_buffer(4).decode_float(0)

func _body(id:int)->PackedByteArray:
	if body_id==id:return body
	var block:Array=storage.blocks[id]
	var cache_key:=key+":"+str(id)
	if repeated.has(cache_key):
		body=repeated[cache_key]
	else:
		file.seek(int(block[0]));var packed:=file.get_buffer(int(block[1]))
		body=packed.decompress(int(block[2]),FileAccess.COMPRESSION_DEFLATE) if int(block[5])==1 else packed
		assert(body.size()==int(block[2]))
		if int(block[4])>1 and body.size()<=REPEATED_BYTES:
			while not repeated.is_empty() and repeated_bytes+body.size()>REPEATED_BYTES:
				var oldest=repeated.keys()[0];repeated_bytes-=repeated[oldest].size();repeated.erase(oldest)
			repeated[cache_key]=body;repeated_bytes+=body.size()
	body_id=id
	return body

func get_buffer(length:int)->PackedByteArray:
	if raw_mode:return file.get_buffer(length)
	assert(length>=0 and cursor+length<=frame_end)
	var result:=PackedByteArray()
	while length>0:
		var data:PackedByteArray
		var local:int
		if cursor<frame_start+4:
			data=count_data;local=cursor-frame_start
		else:
			while segment<ends.size() and cursor>=ends[segment]:segment+=1
			assert(segment<ids.size())
			var id:=int(ids[segment])
			if header_id!=id:header=str(storage.blocks[id][3]).hex_decode();header_id=id
			local=cursor-starts[segment]
			if local<header.size():data=header
			else:data=_body(id);local-=header.size()
		var take:=mini(length,data.size()-local);assert(take>0)
		if take==length and result.is_empty():
			cursor+=take;return data.slice(local,local+take)
		result.append_array(data.slice(local,local+take));cursor+=take;length-=take
	return result
