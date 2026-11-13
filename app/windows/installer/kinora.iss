; Kinora's Windows installer (Inno Setup 6), built in CI:
;   iscc /DAppVersion=X.Y.Z windows\installer\kinora.iss
; It installs for the current user (no admin prompt) into
; %LOCALAPPDATA%\Programs\Kinora. Kinora keeps its library and settings in
; the user's own folders, so updating or uninstalling leaves them alone.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change: Windows knows the installed Kinora by it.
AppId={{74FF434E-0BEC-4D73-9EE6-2C0D38B42E1A}
AppName=Kinora
AppVersion={#AppVersion}
AppVerName=Kinora {#AppVersion}
AppPublisher=Spacie
AppPublisherURL=https://github.com/abdvlrqhman/kinora
AppSupportURL=https://github.com/abdvlrqhman/kinora/issues
AppUpdatesURL=https://github.com/abdvlrqhman/kinora/releases
DefaultDirName={autopf}\Kinora
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Kinora-Setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Kinora.exe
UninstallDisplayName=Kinora
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; An update closes the running Kinora first, then opens the new one.
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\dist\Kinora\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Files a previous version had but this one doesn't.
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\Kinora"; Filename: "{app}\Kinora.exe"
Name: "{autodesktop}\Kinora"; Filename: "{app}\Kinora.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Kinora.exe"; Description: "{cm:LaunchProgram,Kinora}"; Flags: nowait postinstall skipifsilent
