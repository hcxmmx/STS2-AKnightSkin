extends SceneTree

func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Expected output PCK path");quit(1);return
	var runtime=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime_files.json"))
	var files:Dictionary={}
	for relative in runtime:
		var path:="res://"+str(relative)
		if not FileAccess.file_exists(path):
			push_error("Missing runtime file: "+path);quit(1);return
		files[path]=true
		if path.get_extension() in ["png","ttf","otf"]:
			var imported:=path+".import"
			var config:=ConfigFile.new()
			if config.load(imported)!=OK:
				push_error("Missing import: "+path);quit(1);return
			var data:String=config.get_value("remap","path","")
			if not data.begins_with("res://.godot/imported/") or not FileAccess.file_exists(data):
				push_error("Invalid import mapping: "+path);quit(1);return
			files[imported]=true;files[data]=true
	var packer:=PCKPacker.new()
	if packer.pck_start(args[0])!=OK:
		push_error("Cannot create output pack");quit(1);return
	for path in files:
		if packer.add_file(path,path)!=OK:
			push_error("Cannot pack "+path);quit(1);return
	if packer.flush()!=OK:
		push_error("PCK flush failed");quit(1);return
	print("AKNIGHT_SOURCE_PACKED ",files.size()," files")
	quit()
