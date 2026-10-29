; Installer for the Windows build. Version, stage folder, and output dir come from ISCC /D.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Stage
  #define Stage "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{8F4C1A2E-6B7D-4C9A-9E11-2A6D5F0C8B34}}
AppName=zaevis
AppVersion={#AppVersion}
AppPublisher=zae-park
DefaultDirName={localappdata}\zaevis
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir={#OutputDir}
OutputBaseFilename=zaevis-{#AppVersion}-win-x64
Compression=zip
SolidCompression=no
WizardStyle=modern
CloseApplications=no
UninstallDisplayIcon={app}\zaevis.exe

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\zaevis"; Filename: "{app}\zaevis.exe"

[Run]
Filename: "{app}\zaevis.exe"; Description: "{cm:LaunchProgram,zaevis}"; Flags: nowait postinstall skipifsilent
