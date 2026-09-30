unit SingleInstance;

{ Keeps one running copy: a second launch (e.g. from Explorer's context menu)
  hands its folder argument to the running instance via WM_COPYDATA and exits. }

interface

uses
  Winapi.Windows, Winapi.Messages;

const
  MainWindowClass = 'SoundsBrowse.MainWindow';
  CopyDataOpenFolder = $53424F46;   // 'SBOF'

// Folder passed on the command line, or '' if none
function CommandLineFolder: string;

// True if another instance took over (the caller should exit)
function ForwardToRunningInstance(const Folder: string): Boolean;

implementation

var
  GMutex: THandle;

function CommandLineFolder: string;
begin
  if ParamCount >= 1 then
    Result := ParamStr(1)
  else
    Result := '';
end;

function ForwardToRunningInstance(const Folder: string): Boolean;
var
  Wnd: HWND;
  PID: DWORD;
  Data: TCopyDataStruct;
  Res: DWORD_PTR;
  I: Integer;
begin
  Result := False;
  GMutex := CreateMutex(nil, False, 'SoundsBrowse.SingleInstance');
  if GetLastError <> ERROR_ALREADY_EXISTS then
    Exit;

  // The first instance may still be starting up
  Wnd := 0;
  for I := 1 to 30 do
  begin
    Wnd := FindWindow(MainWindowClass, nil);
    if Wnd <> 0 then
      Break;
    Sleep(100);
  end;
  if Wnd = 0 then
    Exit;

  // We were just launched by the foreground app (Explorer), so we may pass
  // on the right to come to the front
  PID := 0;
  GetWindowThreadProcessId(Wnd, PID);
  AllowSetForegroundWindow(PID);

  Data.dwData := CopyDataOpenFolder;
  Data.cbData := (Length(Folder) + 1) * SizeOf(Char);
  Data.lpData := PChar(Folder);
  Result := SendMessageTimeout(Wnd, WM_COPYDATA, 0, LPARAM(@Data),
    SMTO_ABORTIFHUNG, 5000, @Res) <> 0;
end;

initialization

finalization
  if GMutex <> 0 then
    CloseHandle(GMutex);

end.
