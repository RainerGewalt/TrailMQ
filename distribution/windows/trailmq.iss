; TrailMQ — Windows installer definition (Inno Setup 6).
;
; Compiled in CI, never by hand:
;
;   ISCC /DAppVersion=3.2.0 /DPayloadDir=..\..\dist\TrailMQ-3.2.0-windows-x64 trailmq.iss
;
; Both defines are required and neither has a default. A version typed into
; this file would be one more place a release can drift from release.yaml, and
; the build script derives it from the contract instead.
;
; What this installs is a launcher and its read-only assets. The TrailMQ
; runtime itself stays in Docker: the installer never registers a service,
; never installs a driver, and never needs the machine restarted.

#ifndef AppVersion
  #error AppVersion is required: pass /DAppVersion=<version>
#endif
#ifndef PayloadDir
  #error PayloadDir is required: pass /DPayloadDir=<path to the staged payload>
#endif

#define AppName      "TrailMQ"
#define AppPublisher "TrailMQ"
#define AppURL       "https://trailmq.com"
#define LauncherExe  "trailmq.exe"

[Setup]
; Fixed for the lifetime of the product: this is how Windows recognises an
; upgrade rather than a second parallel installation.
AppId={{8E5F6C21-3B7A-4D19-9E4C-1A2B3C4D5E6F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL=https://github.com/RainerGewalt/TrailMQ
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename=TrailMQ-Setup-{#AppVersion}
OutputDir=.
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; x64 only: the TrailMQ runtime images are published for linux/amd64, so an
; ARM installation would run the whole evaluation under emulation without
; saying so.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-machine when elevated, per-user otherwise. Neither is required to be
; administrator, because nothing here touches the system.
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile={#PayloadDir}\START-HERE.md
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#LauncherExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "Add TrailMQ to PATH, so 'trailmq' works in any terminal"; Flags: checkedonce

[Files]
Source: "{#PayloadDir}\{#LauncherExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\release.yaml";   DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\START-HERE.md";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\recipes\*";      DestDir: "{app}\recipes";   Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PayloadDir}\scenarios\*";    DestDir: "{app}\scenarios"; Flags: ignoreversion recursesubdirs createallsubdirs

; The marker that tells the launcher this is an installation rather than an
; extracted archive. Without it, TrailMQ would try to keep the user's
; certificates and database inside Program Files.
Source: "installed.marker"; DestDir: "{app}"; DestName: ".trailmq-installed"; Flags: ignoreversion

[Icons]
; The four things someone actually does, in the order they do them. Each opens
; a console that stays open, because these commands report what happened and a
; window that closes on completion would hide it.
Name: "{group}\Start TrailMQ";  Filename: "{cmd}"; Parameters: "/k ""{app}\{#LauncherExe}"" quickstart"; WorkingDir: "{app}"
Name: "{group}\Run the demo";   Filename: "{cmd}"; Parameters: "/k ""{app}\{#LauncherExe}"" demo unauthorized-machine-command"; WorkingDir: "{app}"
Name: "{group}\Open TrailMQ";   Filename: "{app}\{#LauncherExe}"; Parameters: "open"; WorkingDir: "{app}"
Name: "{group}\Stop TrailMQ";   Filename: "{cmd}"; Parameters: "/k ""{app}\{#LauncherExe}"" stop"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
; Offered, never automatic. Docker Desktop may not be running yet, and a
; failed check at the end of a successful install reads as a failed install.
Filename: "{cmd}"; Parameters: "/k ""{app}\{#LauncherExe}"" doctor"; \
  Description: "Check whether this machine can run TrailMQ"; \
  Flags: postinstall skipifsilent

[UninstallDelete]
; Only what the launcher generates inside the installation. The user's
; evaluation data lives under their own profile and is deliberately left
; behind: an uninstaller that silently deletes recorded decisions and
; certificates would destroy the thing this product exists to keep.
Type: filesandordirs; Name: "{app}\recipes"
Type: filesandordirs; Name: "{app}\scenarios"
Type: files;          Name: "{app}\.trailmq-installed"

[Code]
const
  EnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function NeedsAddPath(Param: string): boolean;
var
  Existing: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Existing) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + UpperCase(Param) + ';', ';' + UpperCase(Existing) + ';') = 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Existing: string;
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
  begin
    if NeedsAddPath(ExpandConstant('{app}')) then
    begin
      if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Existing) then
        Existing := '';
      if (Existing <> '') and (Copy(Existing, Length(Existing), 1) <> ';') then
        Existing := Existing + ';';
      RegWriteExpandStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey,
        'Path', Existing + ExpandConstant('{app}'));
    end;
  end;
end;
