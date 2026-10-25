; Inno Setup script for the RoboCore IDE Windows installer (RoboCore-Setup-<version>.exe).
; Built by tools/package_windows.ps1 (and the release job in .github/workflows/build.yml):
;   iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=<folder> windows\installer\robocore.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

[Setup]
; Keep AppId the same in every release: Windows uses it to upgrade and uninstall RoboCore.
AppId={{0DAD47AE-4F85-4B94-A4EC-A9C841C88E68}
AppName=RoboCore
AppVersion={#AppVersion}
AppVerName=RoboCore {#AppVersion}
AppPublisher=Plastal-Bot Builders
AppPublisherURL=https://github.com/Plastal-Bot-Builders/robocore-ide
AppSupportURL=https://github.com/Plastal-Bot-Builders/robocore-ide/issues
AppUpdatesURL=https://github.com/Plastal-Bot-Builders/robocore-ide/releases
DefaultDirName={autopf}\RoboCore
DefaultGroupName=RoboCore
DisableProgramGroupPage=yes
; Installs for the current user without asking for an administrator; the user can choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=RoboCore-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\RoboCore.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\RoboCore"; Filename: "{app}\RoboCore.exe"
Name: "{group}\Uninstall RoboCore"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RoboCore"; Filename: "{app}\RoboCore.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\RoboCore.exe"; Description: "{cm:LaunchProgram,RoboCore}"; Flags: nowait postinstall skipifsilent
