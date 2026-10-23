extends RefCounted

static var shared_data: Dictionary={}

var data: Dictionary = {}
var approximate := true

func initialize(folder: String):
	var path=folder+"particle_details.json"
	if not shared_data.has(path):
		shared_data[path]=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	data=shared_data[path]

func apply(frame: int, id: int, arrays: Array, world := PackedByteArray()) -> PackedByteArray:
	var item: Dictionary=data.get("frames",{}).get(str(frame),{}).get(str(id),{})
	if item.is_empty():return world
	var points: Array=item.approx if approximate else item.source
	var previous: PackedVector2Array=arrays[Mesh.ARRAY_VERTEX]
	var result:=PackedVector2Array();result.resize(points.size())
	for i in points.size():result[i]=Vector2(points[i][0],points[i][1])
	arrays[Mesh.ARRAY_VERTEX]=result
	if not world.is_empty():
		var positions=world.to_float32_array()
		for i in result.size():
			var delta=result[i]-previous[i]
			positions[i*4]-=delta.x;positions[i*4+1]-=delta.y
		world=positions.to_byte_array()
	return world
