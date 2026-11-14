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

# Press a button by its name through Windows UI Automation (Flutter's accessibility tree), else click it at [x, y].
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
}
'@
function Press([string]$name, [int]$x, [int]$y) {
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($el) {
      $r = $el.Current.BoundingRectangle
      [Mouse]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
      Write-Host "pressed '$name' (found)"
      return
    }
  } catch {}
  [Mouse]::Click($x, $y)
  Write-Host "pressed '$name' at $x,$y"
}

Press 'Use Documents\RoboCore' 654 483
Start-Sleep 8
Shot 'win-2-home'

# Open from computer: Windows' own file dialog.
Press 'Open from computer' 637 315
Start-Sleep 5
Shot 'win-4-open-dialog'
$ws = New-Object -ComObject WScript.Shell
$ws.SendKeys('{ESC}')
Start-Sleep 2

$docs = [Environment]::GetFolderPath('MyDocuments')
Get-ChildItem -Recurse -Force (Join-Path $docs 'RoboCore') | ForEach-Object { $_.FullName.Substring($docs.Length) } | Out-File -Encoding utf8 (Join-Path $Out 'win-files.txt')
Start-Process explorer.exe (Join-Path $docs 'RoboCore\Blink')
Start-Sleep 6
Shot 'win-3-explorer'
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
