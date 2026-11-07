@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0.userdata"
set "MUSIC_SET="
if not "%~1"=="" (
  call :resolve "%~1"
  if defined MUSIC_SET goto launch
)
:menu
echo BGM set (default 1 in 10 s)
echo   1  Standard  - HydroGene, bright
echo   2  Dark      - HydroGene, dark
echo   3  Junkala   - Juhani Junkala (8-bit)
choice /c 123 /n /t 10 /d 1
if errorlevel 3 set "MUSIC_SET=junkala"
if errorlevel 2 if not errorlevel 3 set "MUSIC_SET=dark"
if errorlevel 1 if not errorlevel 2 set "MUSIC_SET=standard"
:launch
if not defined MUSIC_SET set "MUSIC_SET=standard"
echo BGM set: %MUSIC_SET%
start "" "tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --rendering-driver opengl3_angle -- --music-set=%MUSIC_SET%
exit /b 0
:resolve
if /i "%~1"=="1" set "MUSIC_SET=standard"
if /i "%~1"=="2" set "MUSIC_SET=dark"
if /i "%~1"=="3" set "MUSIC_SET=junkala"
if /i "%~1"=="standard" set "MUSIC_SET=standard"
if /i "%~1"=="dark" set "MUSIC_SET=dark"
if /i "%~1"=="junkala" set "MUSIC_SET=junkala"
exit /b 0
