extends "res://tests/test_tree.gd"
const Bank := preload("res://scripts/sound_bank.gd")
const OUT := "res://builds/qa/sound/preview/"
var bank: RefCounted
func _initialize() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	bank=Bank.new()
	bank.start()
	while not bank.snapshot().complete:
		test_progress()
		OS.delay_msec(2)
		await process_frame
	var streams: Dictionary=bank.collect()
	bank.shutdown()
	var sampler:=PackedByteArray()
	var table:="seconds\tID\n"
	var ids: Array=Bank.SOUNDS.keys()
	ids.sort()
	var files: Dictionary={}
	for id: String in ids:
		test_progress()
		var stream: AudioStreamWAV=streams[id]
		if id.begins_with("amb") or id in ["win","lose"]:
			if stream.save_to_wav(OUT+id+".wav")!=OK: quit(1); return
			files[id+".wav"]=FileAccess.get_file_as_bytes(OUT+id+".wav").size()
			continue
		table+="%.3f\t%s\n"%[sampler.size()/float(Bank.SE_RATE*2),id]
		sampler.append_array(stream.data)
		var silence:=PackedByteArray()
		silence.resize(int(Bank.SE_RATE*0.4)*2)
		sampler.append_array(silence)
	var se:=AudioStreamWAV.new()
	se.format=AudioStreamWAV.FORMAT_16_BITS
	se.mix_rate=Bank.SE_RATE
	se.data=sampler
	if se.save_to_wav(OUT+"se_sampler.wav")!=OK: quit(1); return
	files["se_sampler.wav"]=FileAccess.get_file_as_bytes(OUT+"se_sampler.wav").size()
	FileAccess.open(OUT+"se_sampler.txt",FileAccess.WRITE).store_string(table)
	for id: String in Bank.MUSIC_IDS:
		var stream: AudioStreamWAV=streams[id].duplicate()
		var twice:=stream.data
		twice.append_array(stream.data)
		stream.data=twice
		stream.loop_mode=AudioStreamWAV.LOOP_DISABLED
		if stream.save_to_wav(OUT+id+"-two-loops.wav")!=OK: quit(1); return
		files[id+"-two-loops.wav"]=FileAccess.get_file_as_bytes(OUT+id+"-two-loops.wav").size()
	var total:=0
	for bytes: int in files.values(): total+=bytes
	FileAccess.open(OUT+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"files":files,"total_bytes":total,"synthesis":bank.snapshot()},"\t"))
	print("AUDIO PREVIEW ",total," bytes; ",files)
	quit(0 if total<=30*1000*1000 else 1)
func _finalize() -> void:
	if bank!=null: bank.shutdown()
