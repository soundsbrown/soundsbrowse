unit DragOut;

{ Drag files out of the app into Explorer, DAWs, samplers, ...
  Uses the shell's own IDataObject so targets get everything they expect
  (CF_HDROP, shell ID lists, file contents). }

interface

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, System.SysUtils;

// All files must live in the same folder.
procedure DragFilesOut(const Folder: string; const FileNames: TArray<string>);

implementation

type
  TDropSource = class(TInterfacedObject, IDropSource)
    function QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: Longint): HResult; stdcall;
    function GiveFeedback(dwEffect: Longint): HResult; stdcall;
  end;

function TDropSource.QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: Longint): HResult;
begin
  if fEscapePressed then
    Result := DRAGDROP_S_CANCEL
  else if (grfKeyState and MK_LBUTTON) = 0 then
    Result := DRAGDROP_S_DROP
  else
    Result := S_OK;
end;

function TDropSource.GiveFeedback(dwEffect: Longint): HResult;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

procedure DragFilesOut(const Folder: string; const FileNames: TArray<string>);
var
  Desktop, Parent: IShellFolder;
  FolderPidl: PItemIDList;
  Pidls: TArray<PItemIDList>;
  Eaten, Attrs: ULONG;
  DataObj: IDataObject;
  Effect: Longint;
  I, Count: Integer;
begin
  if Length(FileNames) = 0 then
    Exit;
  if Failed(SHGetDesktopFolder(Desktop)) then
    Exit;
  Attrs := 0;
  if Failed(Desktop.ParseDisplayName(0, nil, PChar(ExcludeTrailingPathDelimiter(Folder)),
    Eaten, FolderPidl, Attrs)) then
    Exit;
  try
    if Failed(Desktop.BindToObject(FolderPidl, nil, IShellFolder, Parent)) then
      Exit;
    SetLength(Pidls, Length(FileNames));
    Count := 0;
    try
      for I := 0 to High(FileNames) do
      begin
        Attrs := 0;
        if Succeeded(Parent.ParseDisplayName(0, nil, PChar(FileNames[I]), Eaten, Pidls[Count], Attrs)) then
          Inc(Count);
      end;
      if Count = 0 then
        Exit;
      if Succeeded(Parent.GetUIObjectOf(0, Count, Pidls[0], IDataObject, nil, DataObj)) then
        DoDragDrop(DataObj, TDropSource.Create, DROPEFFECT_COPY or DROPEFFECT_LINK, Effect);
    finally
      for I := 0 to Count - 1 do
        CoTaskMemFree(Pidls[I]);
    end;
  finally
    CoTaskMemFree(FolderPidl);
  end;
end;

end.
