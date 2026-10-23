extends RefCounted

# Clip the three large cut planes in world space before their canvas projection.
# Clamping behind-camera vertices to a small positive depth is not clipping.
static func clipped(source: Array,world: PackedFloat32Array,eye: Vector3) -> Dictionary:
	var source_uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV]
	var source_color: PackedColorArray=source[Mesh.ARRAY_COLOR]
	var source_indices: PackedInt32Array=source[Mesh.ARRAY_INDEX]
	var vertices:=PackedVector2Array();var uv:=PackedVector2Array();var colors:=PackedColorArray()
	var indices:=PackedInt32Array();var data:=PackedFloat32Array()
	var near_z:=eye.z+0.05
	for triangle in range(0,source_indices.size(),3):
		var polygon: Array=[]
		var piece: float=float(source_indices[triangle]/4)+1.0
		for k in 3:
			var i:=source_indices[triangle+k]
			polygon.append({"world":Vector3(world[i*4],world[i*4+1],world[i*4+2]),"uv":source_uv[i],"color":source_color[i]})
		var clipped_polygon: Array=[]
		var previous: Dictionary=polygon[-1]
		for current: Dictionary in polygon:
			var previous_inside: bool=previous.world.z>=near_z
			var current_inside: bool=current.world.z>=near_z
			if previous_inside!=current_inside:
				var weight: float=(near_z-previous.world.z)/(current.world.z-previous.world.z)
				var point: Vector3=previous.world.lerp(current.world,weight);point.z=near_z
				clipped_polygon.append({"world":point,"uv":previous.uv.lerp(current.uv,weight),"color":previous.color.lerp(current.color,weight)})
			if current_inside:clipped_polygon.append(current)
			previous=current
		for k in range(1,clipped_polygon.size()-1):
			for v: Dictionary in [clipped_polygon[0],clipped_polygon[k],clipped_polygon[k+1]]:
				var point: Vector3=v.world
				indices.append(vertices.size());vertices.append(Vector2(-point.x,-point.y-.32*point.z))
				uv.append(v.uv);colors.append(v.color);data.append_array(PackedFloat32Array([point.x,point.y,point.z,piece]))
	if vertices.is_empty():return {}
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var rows:=ceili(float(vertices.size())/1024.0);data.resize(rows*1024*4)
	var texture:=ImageTexture.create_from_image(Image.create_from_data(1024,rows,false,Image.FORMAT_RGBAF,data.to_byte_array()))
	return {"mesh":mesh,"vertex_data":texture}
