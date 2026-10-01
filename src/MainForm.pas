unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Winapi.ShLwApi, Winapi.ActiveX,
  System.SysUtils, System.Classes, System.Math, System.IniFiles, System.Types, System.UITypes,
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Menus, Vcl.Shell.ShellCtrls, Vcl.Themes,
  AudioEngine, Workers, Waveform, DragOut, SingleInstance, ShellIntegration;

const
  WM_OPEN_FOLDER = WM_APP + 3;

type
  // Interposer: report when the native list view starts dragging items
  TListView = class(Vcl.ComCtrls.TListView)
  private
    FOnBeginItemDrag: TNotifyEvent;
    procedure CNNotify(var Message: TWMNotifyLV); message CN_NOTIFY;
  public
    property OnBeginItemDrag: TNotifyEvent read FOnBeginItemDrag write FOnBeginItemDrag;
  end;

  TFileEntry = record
    Name: string;
    Ext: string;
    Size: Int64;
    Info: TAudioInfo;
    Scanned: Boolean;
  end;

  // Order matches the list view columns
  TSortColumn = (scName, scLength, scRate, scBits, scChannels, scType, scSize);

  TfrmMain = class(TForm)
    pnlTree: TPanel;
    splTree: TSplitter;
    pnlRight: TPanel;
    pnlFiles: TPanel;
    pnlFilter: TPanel;
    edtFilter: TEdit;
    lvFiles: TListView;
    splWave: TSplitter;
    pnlWave: TPanel;
    pnlTransport: TPanel;
    btnPlay: TButton;
    btnStop: TButton;
    chkLoop: TCheckBox;
    chkAutoPlay: TCheckBox;
    lblTime: TLabel;
    lblVolume: TLabel;
    tbVolume: TTrackBar;
    sbMain: TStatusBar;
    tmrPosition: TTimer;
    tmrSelect: TTimer;
    mnuMain: TMainMenu;
    mnuFile: TMenuItem;
    mnuFileExit: TMenuItem;
    mnuOptions: TMenuItem;
    mnuExplorerMenu: TMenuItem;
    mnuOptionsSep1: TMenuItem;
    mnuSoundFont: TMenuItem;
    mnuSoundFontBundled: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure edtFilterChange(Sender: TObject);
    procedure edtFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure lvFilesData(Sender: TObject; Item: TListItem);
    procedure lvFilesColumnClick(Sender: TObject; Column: TListColumn);
    procedure lvFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvFilesClick(Sender: TObject);
    procedure lvFilesDblClick(Sender: TObject);
    procedure btnPlayClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure chkLoopClick(Sender: TObject);
    procedure tbVolumeChange(Sender: TObject);
    procedure tmrPositionTimer(Sender: TObject);
    procedure tmrSelectTimer(Sender: TObject);
    procedure mnuFileExitClick(Sender: TObject);
    procedure mnuOptionsClick(Sender: TObject);
    procedure mnuExplorerMenuClick(Sender: TObject);
    procedure mnuSoundFontClick(Sender: TObject);
    procedure mnuSoundFontBundledClick(Sender: TObject);
  private
    FEngine: TAudioEngine;
    FTree: TShellTreeView;
    FWave: TWaveformView;
    FFolder: string;
    FAll: TArray<TFileEntry>;
    FView: TArray<Integer>;      // indices into FAll, filtered + sorted
    FSortCol: TSortColumn;
    FSortDesc: Boolean;
    FScanJob: IScanJob;
    FCurrentFile: string;
    FCurrentIdx: Integer;
    FCue: Double;
    FWasPlaying: Boolean;
    FUpdatingList: Boolean;
    FIniFile: string;
    FSoundFont: string;   // [MIDI] SoundFont override from the ini, '' = bundled
    FPendingFolder: string;
    procedure WMCopyData(var Msg: TWMCopyData); message WM_COPYDATA;
    procedure WMOpenFolder(var Msg: TMessage); message WM_OPEN_FOLDER;
    procedure WMScanProgress(var Msg: TMessage); message WM_SCAN_PROGRESS;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure FilesBeginDrag(Sender: TObject);
    procedure WaveSeek(Sender: TObject; Sec: Double);
    procedure WaveSelect(Sender: TObject; StartSec, EndSec: Double);
    procedure NavigateTo(const Folder: string);
    procedure LoadFolder(const Folder: string);
    procedure RebuildView(KeepFocused: Boolean);
    procedure SortView;
    procedure UpdateSortIndicator;
    function CompareEntries(A, B: Integer): Integer;
    function FocusedEntry: Integer;
    procedure OpenFocused;
    procedure PlayFromCue;
    procedure StopPlayback;
    procedure TogglePlay;
    procedure SeekRelative(Delta: Double);
    procedure UpdateTimeLabel;
    procedure UpdateStatus;
    procedure CreateBanner;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ApplySoundFont(const FileName: string);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  frmMain: TfrmMain;

implementation

{$WARN SYMBOL_PLATFORM OFF}

{$R *.dfm}

function FormatRate(Rate: Cardinal): string;
begin
  if Rate mod 1000 = 0 then
    Result := IntToStr(Rate div 1000) + 'k'
  else
    Result := FormatFloat('0.#', Rate / 1000) + 'k';
end;

function FormatBits(const Info: TAudioInfo): string;
begin
  if Info.IsFloat then
    Result := IntToStr(Info.Bits) + 'f'
  else if Info.Bits > 0 then
    Result := IntToStr(Info.Bits)
  else
    Result := '';
end;

function FormatSize(Size: Int64): string;
begin
  if Size < 1024 * 1024 then
    Result := Format('%d KB', [(Size + 1023) div 1024])
  else
    Result := Format('%.1f MB', [Size / (1024 * 1024)]);
end;

function FormatChannels(Chans: Cardinal): string;
begin
  case Chans of
    1: Result := 'mono';
    2: Result := 'stereo';
  else
    Result := IntToStr(Chans) + ' ch';
  end;
end;

{ TListView }

procedure TListView.CNNotify(var Message: TWMNotifyLV);
begin
  if (Message.NMHdr.code = LVN_BEGINDRAG) and Assigned(FOnBeginItemDrag) then
    FOnBeginItemDrag(Self)
  else
    inherited;
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  OleInitialize(nil);   // needed for DoDragDrop
  FIniFile := ChangeFileExt(ParamStr(0), '.ini');
  FCurrentIdx := -1;

  FEngine := TAudioEngine.Create;
  if not FEngine.Init(Handle) then
    MessageDlg('Could not initialise audio output.', mtWarning, [mbOK], 0);

  CreateBanner;

  FTree := TShellTreeView.Create(Self);
  FTree.Parent := pnlTree;   // must come first: setting ObjectTypes rebuilds the tree
  FTree.ObjectTypes := [otFolders];
  FTree.Align := alClient;
  FTree.BorderStyle := bsNone;
  FTree.HideSelection := False;
  FTree.ChangeDelay := 150;
  FTree.OnChange := TreeChange;

  FWave := TWaveformView.Create(Self);
  FWave.Parent := pnlWave;
  FWave.Align := alClient;
  FWave.OnSeek := WaveSeek;
  FWave.OnSelect := WaveSelect;

  lvFiles.OnBeginItemDrag := FilesBeginDrag;
  FSortCol := scName;
  LoadSettings;
  UpdateSortIndicator;
  UpdateTimeLabel;
  UpdateStatus;
end;

procedure TfrmMain.CreateBanner;
var
  Banner: TPanel;
  Divider: TShape;
  Logo: TImage;
  Pic: TWICImage;
  Title: TLabel;
  MinWidth: Integer;
begin
  Banner := TPanel.Create(Self);
  Banner.Parent := pnlTree;
  Banner.Align := alTop;
  Banner.BevelOuter := bvNone;
  Banner.ShowCaption := False;
  Banner.Height := ScaleValue(64);

  // TShape isn't styled, so take the line colour from the style
  Divider := TShape.Create(Self);
  Divider.Parent := Banner;
  Divider.Align := alBottom;
  Divider.Height := Max(1, ScaleValue(1));
  Divider.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
  Divider.Brush.Color := Divider.Pen.Color;

  // LOGO is res\Logo.png, linked in via res\Logo.res
  Logo := TImage.Create(Self);
  Logo.Parent := Banner;
  Logo.AlignWithMargins := True;
  Logo.Margins.SetBounds(ScaleValue(10), ScaleValue(8), 0, ScaleValue(8));
  Logo.Width := ScaleValue(48);
  Logo.Align := alLeft;
  Logo.Stretch := True;
  Logo.Proportional := True;
  Logo.Center := True;
  Pic := TWICImage.Create;
  try
    Pic.LoadFromResourceName(HInstance, 'LOGO');
    Pic.InterpolationMode := wipmHighQualityCubic;   // smooth downscaling
    Logo.Picture.Assign(Pic);
  finally
    Pic.Free;
  end;

  Title := TLabel.Create(Self);
  Title.Parent := Banner;
  Title.AlignWithMargins := True;
  Title.Margins.SetBounds(ScaleValue(10), 0, ScaleValue(4), 0);
  Title.Align := alClient;
  Title.Layout := tlCenter;
  Title.ParentFont := False;
  Title.Font.Assign(Font);
  Title.Font.Name := 'Segoe UI Semibold';
  Title.Font.Height := MulDiv(Font.Height, 22, 12);   // Font is already DPI-scaled
  Title.Caption := 'SoundsBrowse';

  // Don't let the tree get narrower than the banner contents. Both values
  // are rescaled by the VCL on DPI changes.
  Title.Canvas.Font := Title.Font;
  MinWidth := Logo.Margins.Left + Logo.Width + Title.Margins.Left +
    Title.Canvas.TextWidth(Title.Caption) + Title.Margins.Right;
  pnlTree.Constraints.MinWidth := MinWidth;
  splTree.MinSize := MinWidth;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  SaveSettings;
  tmrPosition.Enabled := False;
  if FScanJob <> nil then
    FScanJob.Cancel;
  FScanJob := nil;
  FWave.SetPeaks(nil);   // cancels a running peak job
  WaitForWorkers(3000);
  FEngine.Free;
  OleUninitialize;
end;

procedure TfrmMain.LoadSettings;
var
  Ini: TMemIniFile;
  Folder: string;
  I: Integer;
begin
  Ini := TMemIniFile.Create(FIniFile, TEncoding.UTF8);
  try
    if Ini.ValueExists('Window', 'Width') then
    begin
      Position := poDesigned;
      SetBounds(Ini.ReadInteger('Window', 'Left', Left), Ini.ReadInteger('Window', 'Top', Top),
        Ini.ReadInteger('Window', 'Width', Width), Ini.ReadInteger('Window', 'Height', Height));
      MakeFullyVisible;
    end;
    if Ini.ReadBool('Window', 'Maximized', False) then
      WindowState := wsMaximized;
    pnlTree.Width := Ini.ReadInteger('Window', 'TreeWidth', pnlTree.Width);
    pnlWave.Height := Ini.ReadInteger('Window', 'WaveHeight', pnlWave.Height);
    for I := 0 to lvFiles.Columns.Count - 1 do
      lvFiles.Columns[I].Width := Ini.ReadInteger('Columns', 'Width' + IntToStr(I), lvFiles.Columns[I].Width);

    tbVolume.Position := Ini.ReadInteger('Playback', 'Volume', tbVolume.Position);
    chkLoop.Checked := Ini.ReadBool('Playback', 'Loop', False);
    chkAutoPlay.Checked := Ini.ReadBool('Playback', 'AutoPlay', True);
    FSortCol := TSortColumn(EnsureRange(Ini.ReadInteger('Browse', 'SortColumn', 0), 0, Ord(High(TSortColumn))));
    FSortDesc := Ini.ReadBool('Browse', 'SortDesc', False);
    Folder := Ini.ReadString('Browse', 'Folder', '');
    FSoundFont := Ini.ReadString('MIDI', 'SoundFont', '');
  finally
    Ini.Free;
  end;
  // Before NavigateTo, so no MIDI stream exists yet when the font changes
  if (FSoundFont <> '') and FEngine.MidiSupported and not FEngine.SetSoundFont(FSoundFont) then
    MessageDlg(Format('Could not load the soundfont "%s" set in %s.',
      [FSoundFont, ExtractFileName(FIniFile)]), mtWarning, [mbOK], 0);
  FEngine.Volume := Sqr(tbVolume.Position / tbVolume.Max);
  FEngine.Loop := chkLoop.Checked;

  // A folder on the command line (e.g. from Explorer) wins over the last one
  if CommandLineFolder <> '' then
    Folder := CommandLineFolder;
  NavigateTo(Folder);
end;

procedure TfrmMain.SaveSettings;
var
  Ini: TMemIniFile;
  WP: TWindowPlacement;
  I: Integer;
begin
  Ini := TMemIniFile.Create(FIniFile, TEncoding.UTF8);
  try
    WP.length := SizeOf(WP);
    if GetWindowPlacement(Handle, @WP) then
    begin
      Ini.WriteInteger('Window', 'Left', WP.rcNormalPosition.Left);
      Ini.WriteInteger('Window', 'Top', WP.rcNormalPosition.Top);
      Ini.WriteInteger('Window', 'Width', WP.rcNormalPosition.Width);
      Ini.WriteInteger('Window', 'Height', WP.rcNormalPosition.Height);
    end;
    Ini.WriteBool('Window', 'Maximized', WindowState = wsMaximized);
    Ini.WriteInteger('Window', 'TreeWidth', pnlTree.Width);
    Ini.WriteInteger('Window', 'WaveHeight', pnlWave.Height);
    for I := 0 to lvFiles.Columns.Count - 1 do
      Ini.WriteInteger('Columns', 'Width' + IntToStr(I), lvFiles.Columns[I].Width);
    Ini.WriteInteger('Playback', 'Volume', tbVolume.Position);
    Ini.WriteBool('Playback', 'Loop', chkLoop.Checked);
    Ini.WriteBool('Playback', 'AutoPlay', chkAutoPlay.Checked);
    Ini.WriteInteger('Browse', 'SortColumn', Ord(FSortCol));
    Ini.WriteBool('Browse', 'SortDesc', FSortDesc);
    Ini.WriteString('Browse', 'Folder', FFolder);
    Ini.WriteString('MIDI', 'SoundFont', FSoundFont);   // kept even if empty, so it's discoverable
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

{ Single instance / Explorer integration }

procedure TfrmMain.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Unique class name so a second instance can find us (see SingleInstance)
  StrPLCopy(Params.WinClassName, MainWindowClass, High(Params.WinClassName));
end;

procedure TfrmMain.WMCopyData(var Msg: TWMCopyData);
var
  Data: PCopyDataStruct;
begin
  Data := Msg.CopyDataStruct;
  if (Data = nil) or (Data.dwData <> CopyDataOpenFolder) then
  begin
    inherited;
    Exit;
  end;
  if Data.cbData >= SizeOf(Char) then
    SetString(FPendingFolder, PChar(Data.lpData), Data.cbData div SizeOf(Char) - 1)
  else
    FPendingFolder := '';
  // Return to the sending process right away; do the work afterwards
  PostMessage(Handle, WM_OPEN_FOLDER, 0, 0);
  Msg.Result := 1;
end;

procedure TfrmMain.WMOpenFolder(var Msg: TMessage);
begin
  if WindowState = wsMinimized then
    WindowState := wsNormal;
  SetForegroundWindow(Handle);
  NavigateTo(FPendingFolder);
  if lvFiles.CanFocus then
    lvFiles.SetFocus;
end;

procedure TfrmMain.NavigateTo(const Folder: string);
begin
  if (Folder = '') or not DirectoryExists(Folder) then
    Exit;
  try
    FTree.HandleNeeded;
    FTree.Path := Folder;
  except
    // Tree could not navigate there; the file list still works
  end;
  if not SameText(ExcludeTrailingPathDelimiter(Folder), ExcludeTrailingPathDelimiter(FFolder)) then
    LoadFolder(Folder);
end;

procedure TfrmMain.mnuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.mnuOptionsClick(Sender: TObject);
begin
  mnuExplorerMenu.Checked := IsContextMenuRegistered;
  mnuSoundFont.Enabled := FEngine.MidiSupported;
  mnuSoundFontBundled.Enabled := FEngine.MidiSupported and (FSoundFont <> '');
end;

procedure TfrmMain.mnuExplorerMenuClick(Sender: TObject);
begin
  try
    if IsContextMenuRegistered then
    begin
      UnregisterContextMenu;
      sbMain.Panels[0].Text := 'Removed from the Explorer context menu';
    end
    else
    begin
      RegisterContextMenu;
      sbMain.Panels[0].Text := 'Added to the Explorer context menu';
    end;
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TfrmMain.mnuSoundFontClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  ExeDir, Path: string;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Choose MIDI soundfont';
    Dlg.Filter := 'SoundFonts (*.sf2;*.sf3)|*.sf2;*.sf3|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofPathMustExist, ofFileMustExist];
    if FEngine.SoundFont <> '' then
    begin
      Dlg.InitialDir := ExtractFilePath(FEngine.SoundFont);
      Dlg.FileName := ExtractFileName(FEngine.SoundFont);
    end;
    if not Dlg.Execute(Handle) then
      Exit;
    Path := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  // Store fonts inside the app folder relative to it, so a portable copy
  // keeps working when moved
  ExeDir := ExtractFilePath(ParamStr(0));
  if SameText(Copy(Path, 1, Length(ExeDir)), ExeDir) then
    Path := Copy(Path, Length(ExeDir) + 1, MaxInt);
  ApplySoundFont(Path);
end;

procedure TfrmMain.mnuSoundFontBundledClick(Sender: TObject);
begin
  ApplySoundFont('');
end;

procedure TfrmMain.ApplySoundFont(const FileName: string);
var
  Ini: TMemIniFile;
  WasPlaying: Boolean;
begin
  if not FEngine.SetSoundFont(FileName) then
  begin
    if FileName = '' then
      MessageDlg('Could not load the bundled soundfont.', mtError, [mbOK], 0)
    else
      MessageDlg(Format('Could not load the soundfont "%s".', [FileName]), mtError, [mbOK], 0);
    Exit;
  end;
  FSoundFont := FileName;

  // Saved right away rather than only on exit
  Ini := TMemIniFile.Create(FIniFile, TEncoding.UTF8);
  try
    Ini.WriteString('MIDI', 'SoundFont', FSoundFont);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  // A loaded MIDI file was rendered (stream and waveform) with the old font
  if (FCurrentFile <> '') and (FCurrentIdx >= 0) and (FCurrentIdx <= High(FAll)) and
     FAll[FCurrentIdx].Info.IsMidi then
  begin
    WasPlaying := FEngine.IsPlaying;
    StopPlayback;
    FEngine.Open(FCurrentFile);
    FCue := 0;
    FWave.SetPeaks(StartPeakJob(FCurrentFile, FWave.Handle));
    if WasPlaying then
      PlayFromCue;
  end;
  UpdateStatus;
end;

{ Folder / file list }

procedure TfrmMain.TreeChange(Sender: TObject; Node: TTreeNode);
var
  P: string;
begin
  try
    P := FTree.Path;
  except
    P := '';
  end;
  if not SameText(ExcludeTrailingPathDelimiter(P), ExcludeTrailingPathDelimiter(FFolder)) then
    LoadFolder(P);
end;

procedure TfrmMain.LoadFolder(const Folder: string);
var
  SR: TSearchRec;
  List: TList<TFileEntry>;
  E: TFileEntry;
  Files: TArray<string>;
  Dir: string;
  I: Integer;
begin
  if FScanJob <> nil then
    FScanJob.Cancel;
  FScanJob := nil;
  FFolder := Folder;
  FAll := nil;
  FCurrentIdx := -1;
  FCurrentFile := '';   // re-selecting the playing file after returning should reopen it

  if (Folder <> '') and DirectoryExists(Folder) then
  begin
    Dir := IncludeTrailingPathDelimiter(Folder);
    List := TList<TFileEntry>.Create;
    try
      if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
      try
        repeat
          if ((SR.Attr and (faDirectory or faHidden)) = 0) and
             (Copy(SR.Name, 1, 2) <> '._') and       // macOS resource-fork litter
             FEngine.IsSupportedFile(SR.Name) then
          begin
            E := Default(TFileEntry);
            E.Name := SR.Name;
            E.Ext := UpperCase(Copy(ExtractFileExt(SR.Name), 2, MaxInt));
            E.Size := SR.Size;
            E.Info.Duration := -1;
            List.Add(E);
          end;
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
      FAll := List.ToArray;
    finally
      List.Free;
    end;

    SetLength(Files, Length(FAll));
    for I := 0 to High(FAll) do
      Files[I] := Dir + FAll[I].Name;
    if Length(Files) > 0 then
      FScanJob := StartScanJob(Files, Handle);
  end;

  RebuildView(False);
  if Length(FView) > 0 then
    lvFiles.Items[0].MakeVisible(False);
  UpdateStatus;
end;

procedure TfrmMain.WMScanProgress(var Msg: TMessage);
var
  R: TScanResult;
begin
  if FScanJob = nil then
    Exit;
  for R in FScanJob.TakeResults do
    if R.Index <= High(FAll) then
    begin
      FAll[R.Index].Info := R.Info;
      FAll[R.Index].Scanned := True;
    end;
  if FScanJob.Finished then
  begin
    FScanJob := nil;
    if FSortCol in [scLength, scRate, scBits, scChannels] then
      RebuildView(True);
  end;
  lvFiles.Invalidate;
  UpdateStatus;
end;

function TfrmMain.CompareEntries(A, B: Integer): Integer;
var
  EA, EB: ^TFileEntry;
begin
  EA := @FAll[A];
  EB := @FAll[B];
  case FSortCol of
    scLength:   Result := CompareValue(EA.Info.Duration, EB.Info.Duration);
    scRate:     Result := CompareValue(Int64(EA.Info.SampleRate), Int64(EB.Info.SampleRate));
    scBits:     Result := CompareValue(Int64(EA.Info.Bits), Int64(EB.Info.Bits));
    scChannels: Result := CompareValue(Int64(EA.Info.Channels), Int64(EB.Info.Channels));
    scType:     Result := CompareText(EA.Ext, EB.Ext);
    scSize:     Result := CompareValue(EA.Size, EB.Size);
  else
    Result := 0;
  end;
  if Result = 0 then
    Result := StrCmpLogicalW(PChar(EA.Name), PChar(EB.Name));   // Explorer-style "2" < "10"
  if FSortDesc then
    Result := -Result;
end;

procedure TfrmMain.SortView;
begin
  TArray.Sort<Integer>(FView, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := CompareEntries(A, B);
    end));
end;

procedure TfrmMain.UpdateSortIndicator;
var
  Header: HWND;
  Item: THDItem;
  I: Integer;
begin
  Header := ListView_GetHeader(lvFiles.Handle);
  for I := 0 to lvFiles.Columns.Count - 1 do
  begin
    FillChar(Item, SizeOf(Item), 0);
    Item.Mask := HDI_FORMAT;
    Header_GetItem(Header, I, Item);
    Item.fmt := Item.fmt and not (HDF_SORTUP or HDF_SORTDOWN);
    if I = Ord(FSortCol) then
      if FSortDesc then
        Item.fmt := Item.fmt or HDF_SORTDOWN
      else
        Item.fmt := Item.fmt or HDF_SORTUP;
    Header_SetItem(Header, I, Item);
  end;
end;

procedure TfrmMain.RebuildView(KeepFocused: Boolean);
var
  Words: TArray<string>;
  L: TList<Integer>;
  I, J, FocusIdx: Integer;
  Name: string;
  Match: Boolean;
begin
  FocusIdx := -1;
  if KeepFocused then
    FocusIdx := FocusedEntry;

  Words := LowerCase(Trim(edtFilter.Text)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  L := TList<Integer>.Create;
  try
    for I := 0 to High(FAll) do
    begin
      Name := LowerCase(FAll[I].Name);
      Match := True;
      for J := 0 to High(Words) do
        if Pos(Words[J], Name) = 0 then
        begin
          Match := False;
          Break;
        end;
      if Match then
        L.Add(I);
    end;
    FView := L.ToArray;
  finally
    L.Free;
  end;
  SortView;

  FUpdatingList := True;
  try
    lvFiles.Items.BeginUpdate;
    try
      lvFiles.ClearSelection;
      lvFiles.Items.Count := Length(FView);
    finally
      lvFiles.Items.EndUpdate;
    end;
    if FocusIdx >= 0 then
      for I := 0 to High(FView) do
        if FView[I] = FocusIdx then
        begin
          lvFiles.Items[I].Selected := True;
          lvFiles.ItemFocused := lvFiles.Items[I];
          lvFiles.Items[I].MakeVisible(False);
          Break;
        end;
  finally
    FUpdatingList := False;
  end;
  lvFiles.Invalidate;
  UpdateStatus;
end;

procedure TfrmMain.lvFilesData(Sender: TObject; Item: TListItem);
var
  E: TFileEntry;
begin
  if (Item.Index < 0) or (Item.Index > High(FView)) then
    Exit;
  E := FAll[FView[Item.Index]];
  Item.Caption := E.Name;
  if E.Scanned and E.Info.Valid and E.Info.IsMidi then
  begin
    Item.SubItems.Add(FormatDuration(E.Info.Duration));
    Item.SubItems.Add('');
    Item.SubItems.Add('');
    Item.SubItems.Add('');
  end
  else if E.Scanned and E.Info.Valid then
  begin
    Item.SubItems.Add(FormatDuration(E.Info.Duration));
    Item.SubItems.Add(FormatRate(E.Info.SampleRate));
    Item.SubItems.Add(FormatBits(E.Info));
    Item.SubItems.Add(IntToStr(E.Info.Channels));
  end
  else
  begin
    if E.Scanned then
      Item.SubItems.Add('n/a')
    else
      Item.SubItems.Add('');
    Item.SubItems.Add('');
    Item.SubItems.Add('');
    Item.SubItems.Add('');
  end;
  Item.SubItems.Add(E.Ext);
  Item.SubItems.Add(FormatSize(E.Size));
end;

procedure TfrmMain.lvFilesColumnClick(Sender: TObject; Column: TListColumn);
var
  Col: TSortColumn;
begin
  if Column.Index > Ord(High(TSortColumn)) then
    Exit;
  Col := TSortColumn(Column.Index);
  if Col = FSortCol then
    FSortDesc := not FSortDesc
  else
  begin
    FSortCol := Col;
    FSortDesc := False;
  end;
  UpdateSortIndicator;
  RebuildView(True);
end;

function TfrmMain.FocusedEntry: Integer;
var
  I: Integer;
begin
  Result := -1;
  I := ListView_GetNextItem(lvFiles.Handle, -1, LVNI_FOCUSED);
  if I < 0 then
    I := ListView_GetNextItem(lvFiles.Handle, -1, LVNI_SELECTED);
  if (I >= 0) and (I <= High(FView)) then
    Result := FView[I];
end;

procedure TfrmMain.lvFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FUpdatingList then
    Exit;
  // Debounce so holding an arrow key doesn't start dozens of streams
  tmrSelect.Enabled := False;
  tmrSelect.Enabled := True;
end;

procedure TfrmMain.tmrSelectTimer(Sender: TObject);
begin
  tmrSelect.Enabled := False;
  OpenFocused;
end;

procedure TfrmMain.lvFilesClick(Sender: TObject);
var
  Idx: Integer;
begin
  // Clicking the file that's already loaded replays it
  Idx := FocusedEntry;
  if (Idx >= 0) and (Idx = FCurrentIdx) and not tmrSelect.Enabled then
    PlayFromCue;
end;

procedure TfrmMain.lvFilesDblClick(Sender: TObject);
begin
  if FCurrentIdx >= 0 then
  begin
    FCue := 0;
    FWave.SetCue(0);
    PlayFromCue;
  end;
end;

procedure TfrmMain.FilesBeginDrag(Sender: TObject);
var
  Names: TList<string>;
  I: Integer;
begin
  Names := TList<string>.Create;
  try
    I := ListView_GetNextItem(lvFiles.Handle, -1, LVNI_SELECTED);
    while I >= 0 do
    begin
      if I <= High(FView) then
        Names.Add(FAll[FView[I]].Name);
      I := ListView_GetNextItem(lvFiles.Handle, I, LVNI_SELECTED);
    end;
    DragFilesOut(FFolder, Names.ToArray);
  finally
    Names.Free;
  end;
end;

procedure TfrmMain.edtFilterChange(Sender: TObject);
begin
  RebuildView(True);
end;

procedure TfrmMain.edtFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        edtFilter.Clear;
        Key := 0;
      end;
    VK_DOWN, VK_RETURN:
      begin
        lvFiles.SetFocus;
        if (lvFiles.ItemFocused = nil) and (lvFiles.Items.Count > 0) then
        begin
          lvFiles.Items[0].Selected := True;
          lvFiles.ItemFocused := lvFiles.Items[0];
        end;
        Key := 0;
      end;
  end;
end;

{ Playback }

procedure TfrmMain.OpenFocused;
var
  Idx: Integer;
  Path: string;
begin
  Idx := FocusedEntry;
  if Idx < 0 then
    Exit;
  Path := IncludeTrailingPathDelimiter(FFolder) + FAll[Idx].Name;
  if SameText(Path, FCurrentFile) then
    Exit;
  FCurrentFile := Path;
  FCurrentIdx := Idx;
  FEngine.Open(Path);
  FCue := 0;
  FWasPlaying := False;
  FWave.SetPeaks(StartPeakJob(Path, FWave.Handle));
  if chkAutoPlay.Checked then
    PlayFromCue;
  UpdateTimeLabel;
  UpdateStatus;
end;

procedure TfrmMain.PlayFromCue;
begin
  if FCurrentFile = '' then
    OpenFocused;
  if FCurrentFile = '' then
    Exit;
  FEngine.Play(FCue);
  FWave.SetCue(FCue);
end;

procedure TfrmMain.StopPlayback;
begin
  FEngine.Stop;
  FWasPlaying := False;
  FWave.SetCursor(-1);
  UpdateTimeLabel;
end;

procedure TfrmMain.TogglePlay;
begin
  if FEngine.IsPlaying then
    StopPlayback
  else
    PlayFromCue;
end;

procedure TfrmMain.SeekRelative(Delta: Double);
var
  Pos: Double;
begin
  if FCurrentFile = '' then
    Exit;
  if FEngine.IsPlaying then
    Pos := FEngine.Position
  else
    Pos := FCue;
  FCue := EnsureRange(Pos + Delta, 0.0, Max(0.0, FWave.Duration - 0.01));
  FWave.SetCue(FCue);
  if FEngine.IsPlaying then
    PlayFromCue;
  UpdateTimeLabel;
end;

procedure TfrmMain.WaveSeek(Sender: TObject; Sec: Double);
begin
  FCue := Sec;
  PlayFromCue;
end;

procedure TfrmMain.WaveSelect(Sender: TObject; StartSec, EndSec: Double);
begin
  FEngine.SetSelection(StartSec, EndSec);
  if EndSec > StartSec then
  begin
    FCue := StartSec;
    PlayFromCue;
  end;
end;

procedure TfrmMain.btnPlayClick(Sender: TObject);
begin
  PlayFromCue;
end;

procedure TfrmMain.btnStopClick(Sender: TObject);
begin
  StopPlayback;
end;

procedure TfrmMain.chkLoopClick(Sender: TObject);
begin
  FEngine.Loop := chkLoop.Checked;
end;

procedure TfrmMain.tbVolumeChange(Sender: TObject);
begin
  // Squared for a more natural-feeling fader
  FEngine.Volume := Sqr(tbVolume.Position / tbVolume.Max);
end;

procedure TfrmMain.tmrPositionTimer(Sender: TObject);
begin
  if FEngine.IsPlaying then
  begin
    FWave.SetCursor(FEngine.Position);
    FWasPlaying := True;
    UpdateTimeLabel;
  end
  else if FWasPlaying then
    StopPlayback;   // reached the end
end;

procedure TfrmMain.UpdateTimeLabel;
var
  Pos: Double;
  S: string;
begin
  if FEngine.IsPlaying then
    Pos := FEngine.Position
  else
    Pos := FCue;
  S := FormatDuration(Pos, True) + ' / ' + FormatDuration(FWave.Duration, True);
  if lblTime.Caption <> S then
    lblTime.Caption := S;
end;

procedure TfrmMain.UpdateStatus;
var
  S: string;
begin
  sbMain.Panels[0].Text := FFolder;
  S := Format('%d files', [Length(FAll)]);
  if Length(FView) <> Length(FAll) then
    S := Format('%d of %d files', [Length(FView), Length(FAll)]);
  if FScanJob <> nil then
    S := S + ' (scanning...)';
  sbMain.Panels[1].Text := S;
  S := '';
  if (FCurrentIdx >= 0) and (FCurrentIdx <= High(FAll)) then
    with FAll[FCurrentIdx] do
      if Scanned and Info.Valid and Info.IsMidi then
      begin
        if FEngine.SoundFont <> '' then
          S := Format('%s  %s', [Ext, ExtractFileName(FEngine.SoundFont)])
        else
          S := Ext + '  no soundfont';
      end
      else if Scanned and Info.Valid then
      begin
        S := Format('%s  %s Hz', [Ext, FormatFloat('#,##0', Info.SampleRate)]);
        if FormatBits(Info) <> '' then
          S := S + '  ' + FormatBits(Info) + '-bit';
        S := S + '  ' + FormatChannels(Info.Channels);
      end;
  sbMain.Panels[2].Text := S;
  sbMain.Panels[3].Text := Format('BASS + %d add-ons', [FEngine.Plugins.Count]);
end;

{ Keyboard / mouse }

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Delta: Double;
begin
  if (Key = Ord('F')) and (ssCtrl in Shift) then
  begin
    edtFilter.SetFocus;
    edtFilter.SelectAll;
    Key := 0;
    Exit;
  end;
  if ActiveControl = edtFilter then
    Exit;
  case Key of
    VK_SPACE:
      begin
        TogglePlay;
        Key := 0;
      end;
    VK_RETURN:
      if ActiveControl = lvFiles then
      begin
        lvFilesDblClick(nil);
        Key := 0;
      end;
    VK_LEFT, VK_RIGHT:
      if ActiveControl <> FTree then
      begin
        if ssShift in Shift then Delta := 10 else Delta := 2;
        if Key = VK_LEFT then Delta := -Delta;
        SeekRelative(Delta);
        Key := 0;
      end;
  end;
end;

procedure TfrmMain.FormKeyPress(Sender: TObject; var Key: Char);
begin
  // Swallow the WM_CHAR that follows handled Space/Enter so the list view
  // doesn't treat it as incremental search input
  if (ActiveControl <> edtFilter) and CharInSet(Key, [' ', #13]) then
    Key := #0;
end;

procedure TfrmMain.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  if PtInRect(FWave.ClientRect, FWave.ScreenToClient(MousePos)) then
  begin
    FWave.WheelAt(Shift, WheelDelta, MousePos);
    Handled := True;
  end;
end;

end.
