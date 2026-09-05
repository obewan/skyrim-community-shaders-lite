@echo off
rem One-click lite build: optimized DLL + trimmed AIO folder in build\LITE\aio,
rem ready to copy into a mod folder.
rem
rem Differs from BuildDev.bat in two ways:
rem   * LITE_PACKAGE=ON drops the plugin PDB and the bundled renderdoc.dll
rem     (~113 MB) and the shipped SettingsDefault.json disables 8 of 39
rem     features at boot, leaving 31 enabled -- 30 in practice, since
rem     Effects11 is enabled but not redistributed. Note the startup saving
rem     comes from the bundled precompiled ShaderCache, not from the disabled
rem     features -- feature gating alone is worth only a few percent.
rem
rem     Three lists decide what ships and what runs: SettingsDefault.json
rem     (boot state), LITE_UNSHIPPED_FEATURES (stripped but left on, for
rem     payload we may not redistribute) and LITE_SHIPPED_DISABLED_FEATURES
rem     (shipped but left off, for CORE pre-release features).
rem   * Always configures. The AIO file list is globbed at configure time, so a
rem     warm-folder skip would silently omit newly added package files.
setlocal
call "%~dp0BuildRelease.bat" LITE LITE
set "exit_code=%ERRORLEVEL%"
endlocal & exit /b %exit_code%
