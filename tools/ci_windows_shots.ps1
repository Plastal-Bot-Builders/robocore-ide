# Screenshots of the Windows app for a pull request (build.yml, Windows job): first start with the projects-folder
# question, the projects as files in File Explorer, and Home. Usage: ci_windows_shots.ps1 <RoboCore.exe> <out dir>
param([string]$Exe, [string]$Out)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Shot([string]$name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "saved $name.png"
}

# A returning user (no welcome screen), on the preview board, with the starter projects.
$prefs = Join-Path $env:APPDATA 'Plastal-Bot Builders\RoboCore'
New-Item -ItemType Directory -Force $prefs | Out-Null
$store = '{"v":1,"profile":true,"user":"Fredo","board":"v2","port":"sim","baud":115200,"connected":true,"settings":{},"libs":{},"projects":[]}'
@{ 'flutter.robocore-ide-v1' = $store } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $prefs 'shared_preferences.json')

$p = Start-Process $Exe -PassThru
Start-Sleep 35
Shot 'win-1-first-start'

# Enter presses the question's main button: Use Documents\RoboCore.
$ws = New-Object -ComObject WScript.Shell
$null = $ws.AppActivate($p.Id)
Start-Sleep 1
$ws.SendKeys('{ENTER}')
Start-Sleep 8
Shot 'win-2-home'

$docs = [Environment]::GetFolderPath('MyDocuments')
Get-ChildItem -Recurse -Force (Join-Path $docs 'RoboCore') | ForEach-Object { $_.FullName.Substring($docs.Length) } | Out-File -Encoding utf8 (Join-Path $Out 'win-files.txt')
Start-Process explorer.exe (Join-Path $docs 'RoboCore\Blink')
Start-Sleep 6
Shot 'win-3-explorer'
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
