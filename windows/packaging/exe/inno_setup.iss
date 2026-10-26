[Setup]
AppId=B9F6E402-0CAE-4045-BDE6-14BD6C39C4EA
AppVersion=1.3.1
AppName=Velqi
AppPublisher=Lupyther
AppPublisherURL=https://velqi.netlify.app
AppSupportURL=https://velqi.netlify.app
AppUpdatesURL=https://velqi.netlify.app
DefaultDirName={autopf}\Velqi
DisableProgramGroupPage=yes
OutputDir=..\..\..\windows\packaging\exe
OutputBaseFilename=Velqi-1.3.1-Setup
Compression=lzma
SolidCompression=yes
SetupIconFile=..\..\runner\resources\app_icon.ico
WizardStyle=modern
PrivilegesRequired=lowest
LicenseFile=..\..\..\LICENSE
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\..\build\windows\x64\runner\Release\velqi.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Velqi"; Filename: "{app}\velqi.exe"
Name: "{autodesktop}\Velqi"; Filename: "{app}\velqi.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\velqi.exe"; Description: "{cm:LaunchProgram,{#StringChange('Velqi', '&', '&&')}}"; Flags: nowait postinstall skipifsilent
