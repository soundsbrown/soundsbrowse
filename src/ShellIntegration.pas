unit ShellIntegration;

{ "Open in SoundsBrowse" entry in Explorer's context menu for folders, the
  background of an open folder, and drives. Registered per user under
  HKCU\Software\Classes, so no admin rights or installer are needed.

  On Windows 11 these classic verbs appear under "Show more options"; the new
  top-level menu only accepts packaged (MSIX) apps. }

interface

// True if registered and pointing at this exe (a moved exe counts as not registered)
function IsContextMenuRegistered: Boolean;
procedure RegisterContextMenu;
procedure UnregisterContextMenu;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, System.SysUtils, System.Win.Registry;

const
  VerbKey = 'SoundsBrowse';
  VerbCaption = 'Open in SoundsBrowse';

type
  TShellTarget = record
    Key: string;
    Arg: string;   // %1 = the clicked item, %V = the folder whose background was clicked
  end;

const
  Targets: array[0..2] of TShellTarget = (
    (Key: 'Software\Classes\Directory\shell\';            Arg: '%1'),
    (Key: 'Software\Classes\Directory\Background\shell\'; Arg: '%V'),
    (Key: 'Software\Classes\Drive\shell\';                Arg: '%1'));

function CommandLine(const Target: TShellTarget): string;
begin
  Result := Format('"%s" "%s"', [ParamStr(0), Target.Arg]);
end;

procedure NotifyShell;
begin
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
end;

function IsContextMenuRegistered: Boolean;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Result := Reg.OpenKeyReadOnly(Targets[0].Key + VerbKey + '\command') and
              SameText(Reg.ReadString(''), CommandLine(Targets[0]));
  finally
    Reg.Free;
  end;
end;

procedure RegisterContextMenu;
var
  Reg: TRegistry;
  T: TShellTarget;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for T in Targets do
    begin
      if not Reg.OpenKey(T.Key + VerbKey, True) then
        raise Exception.Create('Could not create registry key HKCU\' + T.Key + VerbKey);
      Reg.WriteString('', VerbCaption);
      Reg.WriteString('Icon', ParamStr(0) + ',0');
      Reg.CloseKey;
      if not Reg.OpenKey(T.Key + VerbKey + '\command', True) then
        raise Exception.Create('Could not create registry key HKCU\' + T.Key + VerbKey + '\command');
      Reg.WriteString('', CommandLine(T));
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  NotifyShell;
end;

procedure UnregisterContextMenu;
var
  Reg: TRegistry;
  T: TShellTarget;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for T in Targets do
      if Reg.KeyExists(T.Key + VerbKey) then
        Reg.DeleteKey(T.Key + VerbKey);   // recursive
  finally
    Reg.Free;
  end;
  NotifyShell;
end;

end.
