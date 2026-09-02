#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates shader validation configuration files for Community Shaders.

.DESCRIPTION
    This script generates shader-validation.yaml by analyzing Community Shaders log files from
    Skyrim Special Edition installations. It requires hlslkit to be installed and Skyrim Special
    Edition to have been run with specific settings.

.PARAMETER OutputDir
    Directory where the generated YAML files will be saved. Defaults to current directory.

.PARAMETER Force
    Force generation even if log files are not recent.

.PARAMETER LogFile
    Process a specific log file directly instead of searching for Skyrim installations.
    When used, also specify -OutputName for the generated config file name.

.PARAMETER OutputName
    Name of the output YAML file when using -LogFile. Defaults to "shader-validation.yaml".

.EXAMPLE
    .\generate-shader-configs.ps1

.EXAMPLE
    .\generate-shader-configs.ps1 -OutputDir "custom/path" -Force

.EXAMPLE
    .\generate-shader-configs.ps1 -LogFile "C:\Path\To\CommunityShaders.log" -OutputName "my-validation.yaml"

.NOTES
    Prerequisites:
    1. Install hlslkit: pip install hlslkit
    2. For automatic detection (default mode):
       a. For each Skyrim version you want to generate configs for:
          - Clear the disk cache (Community Shaders menu -> Advanced -> Clear Disk Cache)
          - Set log level to Debug or Trace (Community Shaders menu -> Advanced -> Log Level)
          - Enable disk cache if not already enabled
          - Run the game and wait for shader compilation to complete.
       b. The log files should be recent (generated after clearing cache)
    3. For direct log file processing:
       - Use -LogFile parameter to specify the path to a Community Shaders log file
       - Use -OutputName to specify the name of the generated config file
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = ".",

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [string]$LogFile,

    [Parameter(Mandatory=$false)]
    [string]$OutputName = "shader-validation.yaml"
)

# Check if hlslkit is installed
try {
    $null = Get-Command "hlslkit-generate" -ErrorAction Stop
    Write-Host "hlslkit-generate found" -ForegroundColor Green
} catch {
    Write-Error "hlslkit-generate not found. Please install hlslkit: pip install hlslkit"
    exit 1
}

# Function to find Skyrim installation paths
function Find-SkyrimPaths {
    $paths = @()

    # Check common document locations
    $documentsPath = [Environment]::GetFolderPath("MyDocuments")
    $myGamesPath = Join-Path $documentsPath "My Games"

    # Check for Skyrim Special Edition
    $sePath = Join-Path $myGamesPath "Skyrim Special Edition"
    if (Test-Path $sePath) {
        $paths += @{
            Name = "Skyrim Special Edition"
            Path = $sePath
            LogPath = Join-Path $sePath "SKSE\CommunityShaders.log"
            ConfigName = "shader-validation.yaml"
            Type = "SE"
        }
    }

    # Check CommunityShadersOutputDir environment variable
    $outputDir = $env:CommunityShadersOutputDir
    if ($outputDir -and (Test-Path $outputDir)) {
        Write-Host "Found CommunityShadersOutputDir: $outputDir" -ForegroundColor Yellow

        $skyrimExe = Get-ChildItem -Path $outputDir -Recurse -Name "SkyrimSE.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($skyrimExe) {
            Write-Host "Detected Skyrim SE installation in CommunityShadersOutputDir" -ForegroundColor Green
        }
    }

    return $paths
}

# Function to check if log file is recent and valid
function Test-LogFile {
    param(
        [string]$LogPath,
        [string]$GameName
    )

    if (-not (Test-Path $LogPath)) {
        Write-Warning "Log file not found for $GameName`: $LogPath"
        return $false
    }

    $logFile = Get-Item $LogPath
    $age = (Get-Date) - $logFile.LastWriteTime

    if ($age.TotalHours -gt 24 -and -not $Force) {
        Write-Warning "Log file for $GameName is older than 24 hours. Use -Force to generate anyway."
        Write-Host "Log file age: $($age.TotalHours.ToString('F1')) hours" -ForegroundColor Yellow
        return $false
    }

    # Check the log holds the lines hlslkit-generate actually parses.
    # These are logged at debug level. A log captured at the default info level still
    # mentions "shader"/"cache" on hundreds of lines, so a loose keyword match passes
    # while the generator happily emits an empty config.
    $compileLines = @(Select-String -Path $LogPath -Pattern "[D] Compiling" -SimpleMatch -List).Count
    if ($compileLines -eq 0) {
        Write-Warning "Log file for $GameName contains no shader compilation lines."
        Write-Host "hlslkit-generate reads the debug-level 'Compiling <shader>' lines, and this log has none." -ForegroundColor Yellow
        Write-Host "In the Community Shaders menu set Log Level to Debug (or Trace), clear the shader disk" -ForegroundColor Yellow
        Write-Host "cache, then relaunch and let compilation finish before regenerating." -ForegroundColor Yellow
        if (-not $Force) {
            return $false
        }
    }

    Write-Host "Log file for $GameName is valid" -ForegroundColor Green
    return $true
}

# Function to verify a generated config actually captured shader variants.
# hlslkit-generate exits 0 and writes a well-formed but empty YAML when the source log
# has no compilation lines, so the exit code alone is not enough to trust the result.
function Test-GeneratedConfig {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "Generator reported success but produced no file: $Path"
        return $false
    }

    $entries = @(Select-String -Path $Path -Pattern "^\s*- file:").Count
    if ($entries -eq 0) {
        Write-Error "Generated config lists no shaders - discarding it."
        Write-Host "The source log had no debug-level compilation lines. See the log level note above." -ForegroundColor Yellow
        return $false
    }

    Write-Host "Validated generated config: $entries shader file(s)" -ForegroundColor Green
    return $true
}

# Main script
Write-Host "Community Shaders Configuration Generator" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Handle direct log file processing
if ($LogFile) {
    Write-Host "Processing log file directly: $LogFile" -ForegroundColor Yellow

    if (-not (Test-Path $LogFile)) {
        Write-Error "Log file not found: $LogFile"
        exit 1
    }

    if (-not (Test-LogFile -LogPath $LogFile -GameName "Direct Log File")) {
        Write-Host "Log file validation failed. Use -Force to process anyway." -ForegroundColor Red
        if (-not $Force) {
            exit 1
        }
    }

    $outputPath = Join-Path $OutputDir $OutputName
    try {
        Write-Host "Generating $OutputName..." -ForegroundColor Blue
        Write-Host "Running: hlslkit-generate --log `"$LogFile`" --output `"$outputPath`"" -ForegroundColor Gray

        # Generate to a temporary file and only move it into place once validated, so a
        # bad run cannot overwrite the checked-in config with an empty one.
        $tempPath = "$outputPath.tmp"
        & hlslkit-generate --log $LogFile --output $tempPath

        if ($LASTEXITCODE -eq 0 -and (Test-GeneratedConfig -Path $tempPath)) {
            Move-Item -Path $tempPath -Destination $outputPath -Force
            Write-Host "Successfully generated $OutputName" -ForegroundColor Green
            Write-Host "File saved to: $outputPath" -ForegroundColor Gray
        } else {
            if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            Write-Error "Failed to generate $OutputName (exit code: $LASTEXITCODE)"
            Write-Host "Existing $OutputName left untouched." -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Error "Error generating $OutputName`: $($_.Exception.Message)"
        exit 1
    }

    exit 0
}

# Find Skyrim installations
$skyrimPaths = Find-SkyrimPaths

if ($skyrimPaths.Count -eq 0) {
    Write-Error "No Skyrim installations found. Please ensure Skyrim Special Edition is installed."
    exit 1
}

Write-Host "Found $($skyrimPaths.Count) Skyrim installation(s):" -ForegroundColor Green
foreach ($path in $skyrimPaths) {
    Write-Host "  - $($path.Name): $($path.Path)" -ForegroundColor Gray
}

# Process each installation
$generated = 0
foreach ($skyrim in $skyrimPaths) {
    Write-Host "`nProcessing $($skyrim.Name)..." -ForegroundColor Yellow

    if (-not (Test-LogFile -LogPath $skyrim.LogPath -GameName $skyrim.Name)) {
        Write-Host "Skipping $($skyrim.Name) due to invalid/missing log file." -ForegroundColor Red
        continue    }

    $outputPath = Join-Path $OutputDir $skyrim.ConfigName

    try {
        Write-Host "Generating $($skyrim.ConfigName)..." -ForegroundColor Blue
        Write-Host "Running: hlslkit-generate --log `"$($skyrim.LogPath)`" --output `"$outputPath`"" -ForegroundColor Gray

        # Same temp-then-validate dance as the direct path above.
        $tempPath = "$outputPath.tmp"
        & hlslkit-generate --log $skyrim.LogPath --output $tempPath

        if ($LASTEXITCODE -eq 0 -and (Test-GeneratedConfig -Path $tempPath)) {
            Move-Item -Path $tempPath -Destination $outputPath -Force
            Write-Host "Successfully generated $($skyrim.ConfigName)" -ForegroundColor Green
            $generated++
        } else {
            if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            Write-Error "Failed to generate $($skyrim.ConfigName) (exit code: $LASTEXITCODE)"
            Write-Host "Existing $($skyrim.ConfigName) left untouched." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Error generating $($skyrim.ConfigName): $($_.Exception.Message)"
    }
}

Write-Host "`n=========================================" -ForegroundColor Cyan
if ($generated -gt 0) {
    Write-Host "Successfully generated $generated configuration file(s)" -ForegroundColor Green
    Write-Host "Files saved to: $OutputDir" -ForegroundColor Gray
} else {
    Write-Host "No configuration files were generated" -ForegroundColor Red
    Write-Host "To generate shader validation configs:" -ForegroundColor Yellow
    Write-Host "1. Clear the disk cache in Community Shaders menu" -ForegroundColor Gray
    Write-Host "2. Set log level to Debug in Community Shaders menu" -ForegroundColor Gray
    Write-Host "3. Run the game and load a save to trigger shader compilation" -ForegroundColor Gray
    Write-Host "4. Run this script again" -ForegroundColor Gray
}
