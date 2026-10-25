# Build the Windows installer, RoboCore-Setup-<version>.exe, with Inno Setup (windows/installer/robocore.iss).
#
# Usage (PowerShell, from anywhere):
#   powershell -ExecutionPolicy Bypass -File tools\package_windows.ps1            # builds the app with Flutter, then the installer
#   powershell -ExecutionPolicy Bypass -File tools\package_windows.ps1 -NoBuild   # packages the existing Release folder
#
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup). The installer lands in build\windows\installer.
param([switch]$NoBuild)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Version from pubspec.yaml (1.0.0+1 -> 1.0.0).
$raw = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$version = $raw.Split('+')[0]

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not $NoBuild) {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}
if (-not (Test-Path (Join-Path $release 'RoboCore.exe'))) { throw "RoboCore.exe not found in $release" }

$iscc = @(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source,
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is not installed. Install it with: winget install JRSoftware.InnoSetup' }

$out = Join-Path $root 'build\windows\installer'
& $iscc "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$out" (Join-Path $root 'windows\installer\robocore.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Write-Host "Built installer: $out\RoboCore-Setup-$version.exe"
