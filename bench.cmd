@echo off
cd /d "%~dp0"
set "APPDATA=%~dp0.userdata"
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" %* --audio-driver Dummy --path . --fixed-fps 60 --script tests/perf_return_bench.gd -- field
pause
