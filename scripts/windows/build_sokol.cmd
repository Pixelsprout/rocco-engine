@echo off
rem Builds the four sokol D3D11 libraries the engine links, debug and release,
rem under the names that sokol-odin and the inputs step read.
rem
rem /Zl leaves out the default CRT library names, so the link picks no
rem Visual Studio CRT. /GS- leaves out the stack cookie, which only the Visual
rem Studio CRT defines. Odin's host build bundles these libraries into host.lib.
rem
rem Run from the repository root in a cmd window where vcvars64.bat has run.
setlocal
set out=build\sokol
if not exist %out% mkdir %out%
for %%s in (log app gfx glue) do (
    cl /nologo /c /Zl /GS- /D_DEBUG /DIMPL /DSOKOL_D3D11 sokol-odin\sokol\c\sokol_%%s.c /Z7 /Fo%out%\sokol_%%s.obj || exit /b 1
    lib /nologo /OUT:sokol-odin\sokol\%%s\sokol_%%s_windows_x64_d3d11_debug.lib %out%\sokol_%%s.obj || exit /b 1
    cl /nologo /c /Zl /GS- /O2 /DNDEBUG /DIMPL /DSOKOL_D3D11 sokol-odin\sokol\c\sokol_%%s.c /Fo%out%\sokol_%%s.obj || exit /b 1
    lib /nologo /OUT:sokol-odin\sokol\%%s\sokol_%%s_windows_x64_d3d11_release.lib %out%\sokol_%%s.obj || exit /b 1
)
