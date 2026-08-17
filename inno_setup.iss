[Setup]
AppId={{8A8C7B04-3F2C-4B9F-8A9C-7F9C6F123456}
AppName=SpDrop
AppVersion=2.0.0-Beta
AppPublisher=Sourav
DefaultDirName={autopf}\SpDrop
DefaultGroupName=SpDrop
OutputDir=.
OutputBaseFilename=SpDrop_Setup_V2.0.0Beta
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\p2p_sync_app.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.msix,*.pdb,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs


[Icons]
Name: "{group}\SpDrop"; Filename: "{app}\p2p_sync_app.exe"
Name: "{autodesktop}\SpDrop"; Filename: "{app}\p2p_sync_app.exe"; Tasks: desktopicon
Name: "{sendto}\SpDrop"; Filename: "{app}\p2p_sync_app.exe"

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""SpDrop"" dir=in action=allow program=""{app}\p2p_sync_app.exe"" enable=yes"; Flags: runhidden
Filename: "{app}\p2p_sync_app.exe"; Description: "{cm:LaunchProgram,SpDrop}"; Flags: nowait postinstall skipifsilent
