#define MyAppName "ReelForge"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "ReelForge"
#define MyAppURL "https://reelforge.app"
#define MyAppExeName "ReelForge.exe"

[Setup]
AppId={{8C0E2C5A-6F1B-4C2E-9A11-REELFORGE0001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\ReelForge
DefaultGroupName=ReelForge
DisableProgramGroupPage=yes
OutputDir=..\dist-installer
OutputBaseFilename=ReelForge-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Extra shortcuts:"; Flags: unchecked

[Files]
Source: "..\dist\ReelForge\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch ReelForge"; Flags: nowait postinstall skipifsilent
