@echo off
rem Builds the miniaudio library, debug and release, from
rem scripts\miniaudio\rocco_miniaudio.c into build\miniaudio\, with the same
rem flags as scripts\windows\build_sokol.cmd. /Zl leaves out the default CRT
rem library names and /GS- leaves out the stack cookie, so the Roc link needs
rem no Visual Studio CRT. miniaudio opens WASAPI and ole32.dll at run time.
rem
rem Run from the repository root in a cmd window where vcvars64.bat has run.
setlocal
set out=build\miniaudio
if not exist %out% mkdir %out%
cl /nologo /c /Zl /GS- /D_DEBUG scripts\miniaudio\rocco_miniaudio.c /Z7 /Fo%out%\miniaudio.obj || exit /b 1
lib /nologo /OUT:%out%\miniaudio_windows_x64_debug.lib %out%\miniaudio.obj || exit /b 1
cl /nologo /c /Zl /GS- /O2 /DNDEBUG scripts\miniaudio\rocco_miniaudio.c /Fo%out%\miniaudio.obj || exit /b 1
lib /nologo /OUT:%out%\miniaudio_windows_x64_release.lib %out%\miniaudio.obj || exit /b 1
