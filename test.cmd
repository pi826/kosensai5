@echo off
cd /d "%~dp0"
set "APPDATA=%~dp0.userdata"
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/generation_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/run_tests.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/movement_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/key_bindings_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/tile_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/seamless_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/camera_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/playthrough.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/enemy_types_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/terrain_change_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/cave_world_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/sector_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/streaming_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/streaming_performance.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/rewards_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/boss_cycle_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/tutorial_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/origin_shift_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/test_guard_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/ability_physics_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/abilities_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/ability_generation_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/merchant_generation_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/equipment_physics_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/merchant_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/boss_arrow_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/ui_map_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/enhancer_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/loop_scaling_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/streaming_performance.gd -- --loop-three
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/diagonal_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/diagonal_physics_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/shaft_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/stream_redraw_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/audio_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/impact_effect_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/boss_arena_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/boss_patterns_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/gravity_test.gd
if errorlevel 1 goto failed
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --audio-driver Dummy --path . --fixed-fps 60 --script tests/perf_behavior_test.gd
if errorlevel 1 goto failed
echo All checks passed. (40 runs)
pause
exit /b 0
:failed
echo A check failed. See the messages above.
pause
exit /b 1
