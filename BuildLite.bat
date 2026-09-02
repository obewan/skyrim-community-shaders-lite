@echo off
rem One-click lite build: optimized DLL + trimmed AIO folder in build\LITE\aio,
rem ready to copy into a mod folder.
rem
rem Differs from BuildDev.bat in two ways:
rem   * LITE_PACKAGE=ON drops the plugin PDB and the bundled renderdoc.dll
rem     (~113 MB) and the shipped SettingsDefault.json disables 11 of 39
rem     features at boot, leaving 28 enabled. Note the startup saving comes
rem     from the bundled precompiled ShaderCache, not from the disabled
rem     features -- feature gating alone is worth only a few percent.
rem   * Always configures. The AIO file list is globbed at configure time, so a
rem     warm-folder skip would silently omit newly added package files.
setlocal
call "%~dp0BuildRelease.bat" LITE LITE
set "exit_code=%ERRORLEVEL%"
endlocal & exit /b %exit_code%
