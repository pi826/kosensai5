@echo off
cd /d "%~dp0"
set "APPDATA=%~dp0.userdata"
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/generation_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/run_tests.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/movement_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/key_bindings_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/tile_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/seamless_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/camera_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/playthrough.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/enemy_types_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/terrain_change_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/cave_world_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/sector_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/streaming_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/streaming_performance.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/rewards_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/boss_cycle_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/tutorial_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/origin_shift_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --fixed-fps 60 --script tests/test_guard_test.gd
if errorlevel 1 goto failed
echo All checks passed.
pause
exit /b 0
:failed
echo A check failed. See the messages above.
pause
exit /b 1
