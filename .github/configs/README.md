# Build Configuration Files

This directory contains configuration files used by the CI/CD pipeline for build validation and testing.

## Files

-   `shader-validation.yaml`: Configuration for shader compilation validation using hlslkit (Skyrim SE)

## Generating Configuration Files

These configuration files can be regenerated using the `generate-shader-configs.ps1` script in this directory. This script requires:

1. A valid Skyrim Special Edition installation
2. The [hlslkit](https://github.com/alandtse/hlslkit) package installed (`pip install hlslkit`)
3. Community Shaders to be run once with specific settings to generate the required log data

### Prerequisites

Before running the generation script, you must run Skyrim SE **once** with the following Community Shaders settings:

1. **Set Debug Log Level**: In the Community Shaders menu, set the log level to "Debug" or "Trace"
2. **Clear Disk Cache**: Clear the shader disk cache before running
3. **Enable Disk Cache**: Ensure disk cache is enabled and will be saved
4. **Run the Game**: Launch and wait for compilation to complete to generate shader compilation logs

> **Debug log level deoptimizes shaders.** `State::IsDeveloperMode()` is true whenever the log
> level is debug or lower, which swaps `D3DCOMPILE_OPTIMIZATION_LEVEL3` for `D3DCOMPILE_DEBUG` and
> `D3DCOMPILE_SKIP_OPTIMIZATION`. The capture run is therefore slow, plays badly, and leaves an
> unoptimized shader cache on disk. **Delete `Data/ShaderCache` once you have the log**, before
> doing anything that snapshots or ships that cache (on the lite branch, before
> `SNAPSHOT_LITE_CACHE`). This is unavoidable: the `Compiling ...` lines the generator parses are
> themselves logged at debug level.

The required log file will be created at:

-   **Skyrim SE**: `%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\CommunityShaders.log`

### Running the Script

```powershell
# From the repository root
.\.github\configs\generate-shader-configs.ps1

# Or from the configs directory
cd .github\configs
.\generate-shader-configs.ps1
```

The script will:

1. Detect available Skyrim installations
2. Check for required log files, rejecting any log with no `[D] Compiling` lines
3. Generate configuration files using hlslkit into a temporary file
4. Validate that the result actually lists shaders, then move it into `.github\configs\`

Steps 2 and 4 exist because `hlslkit-generate` exits `0` and writes a well-formed but **empty**
YAML when the log has no compilation lines. An info-level log still mentions "shader" and "cache"
on hundreds of lines, so it looks valid on a loose keyword check. Without these guards, running
the script after an ordinary play session silently replaces the checked-in config with one that
validates nothing, and CI keeps passing. A rejected run leaves the existing config untouched.

### Manual Generation

You can also generate the files manually using hlslkit:

```bash
hlslkit-generate --log "%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\CommunityShaders.log" --output .\.github\configs\shader-validation.yaml
```

## Usage in CI/CD

These files are automatically used by the GitHub Actions workflows during shader validation. They define:

-   Common shader compilation defines
-   Expected warnings (with suppression)
-   Shader file configurations
-   Compilation parameters

The files should be regenerated when:

-   New shaders are added to the project
-   Shader compilation behavior changes
-   New warnings need to be suppressed
-   Build configurations are modified
