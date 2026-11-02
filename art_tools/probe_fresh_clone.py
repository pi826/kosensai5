"""Test raw PNG loading in a minimal project without .godot/imported.
Does not rename/delete the working project's cache or touch any external copy.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import os

ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'builds/qa/art/stage2'


def main():
    index=1
    while (QA/f'fresh-clone-{index}').exists(): index+=1
    fixture=QA/f'fresh-clone-{index}'
    fixture.mkdir()
    shutil.copytree(ROOT/'scripts',fixture/'scripts')
    for p in (ROOT/'assets/art').rglob('*'):
        if not p.is_file() or 'source' in p.relative_to(ROOT/'assets/art').parts: continue
        if p.suffix not in ('.png','.json'): continue
        dst=fixture/p.relative_to(ROOT); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,dst)
    (fixture/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Art fresh clone probe"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    (fixture/'probe.gd').write_text('''extends SceneTree
const Art = preload("res://scripts/sprite_art.gd")
func _initialize(): call_deferred("run")
func run():
    var imported_exists = DirAccess.dir_exists_absolute("res://.godot/imported")
    var shapes = OS.get_cmdline_user_args().has("--art-set=shapes")
    Art.prewarm()
    var deadline = Time.get_ticks_msec()+30000
    while not Art._pending.is_empty() and Time.get_ticks_msec()<deadline:
        Art.service_loading()
        await process_frame
    var im = Art.texture("res://assets/art/player/blue.png","res://assets/art/player/blue.png")
    var ok = not imported_exists and (im == null and Art.image_read_attempts == 0 and Art.selected_set() == "shapes" if shapes else im != null and im.get_width() == 768 and Art.image_read_attempts >= 1 and Art._pending.is_empty())
    FileAccess.open("res://probe-shapes.json" if shapes else "res://probe-result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"import_cache_exists":imported_exists,"image_reads":Art.image_read_attempts,"set":Art.selected_set()}))
    print("FRESH CLONE PNG: ",ok)
    Art.shutdown_loading()
    quit(0 if ok else 1)
''',encoding='utf-8')
    env=os.environ.copy(); env['APPDATA']=str(ROOT/'.userdata')
    result=subprocess.run([str(ROOT/'tools/godot/Godot_v4.7.2-stable_win64_console.exe'),
        '--audio-driver','Dummy','--path',str(fixture),'--script','probe.gd'],env=env,capture_output=True,text=True)
    shapes=subprocess.run([str(ROOT/'tools/godot/Godot_v4.7.2-stable_win64_console.exe'),
        '--audio-driver','Dummy','--path',str(fixture),'--script','probe.gd','--','--art-set=shapes'],env=env,capture_output=True,text=True)
    (QA/'fresh-clone.log').write_text(result.stdout+result.stderr+shapes.stdout+shapes.stderr,encoding='utf-8')
    report=json.loads((fixture/'probe-result.json').read_text(encoding='utf-8')) if (fixture/'probe-result.json').exists() else {'ok':False}
    report.update(exit_code=result.returncode,fixture=fixture.relative_to(ROOT).as_posix())
    report['cli_shapes']=json.loads((fixture/'probe-shapes.json').read_text(encoding='utf-8')) if (fixture/'probe-shapes.json').exists() else {'ok':False}
    report['cli_shapes_exit_code']=shapes.returncode
    (QA/'fresh-clone.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['ok'] and result.returncode==0 and report['cli_shapes']['ok'] and shapes.returncode==0 else 1


if __name__=='__main__': sys.exit(main())
