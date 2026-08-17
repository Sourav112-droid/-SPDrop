[Setup]
AppName=SpDrop
AppVersion=2.0.0-Beta
DefaultDirName={autopf}\SpDrop
DefaultGroupName=SpDrop
OutputDir=.
OutputBaseFilename=SpDrop_V2.0.0Beta_Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin

[Files]
Source: "build\windows\x64\runner\Release\p2p_sync_app.exe"; DestDir: "{app}"; DestName: "SpDrop.exe"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SpDrop"; Filename: "{app}\SpDrop.exe"
Name: "{autodesktop}\SpDrop"; Filename: "{app}\SpDrop.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""SpDrop"" dir=in action=allow program=""{app}\SpDrop.exe"" enable=yes"; Flags: runhidden
