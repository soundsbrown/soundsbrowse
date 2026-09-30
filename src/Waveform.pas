unit Waveform;

{ Waveform peak data (built progressively on a worker thread) and the
  TWaveformView control that displays it. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, bass, Workers, AudioEngine;

type
  IWavePeaks = interface
    ['{8C1F0A57-3B2E-4D7A-A5E4-0F6B9D2C7E13}']
    procedure Cancel;
    function Ready: Boolean;        // format known, arrays allocated
    function Finished: Boolean;
    function Failed: Boolean;
    function Channels: Integer;
    function SampleRate: Integer;
    function TotalFrames: Int64;
    function FramesPerBucket: Integer;
    function BucketsDone: Integer;
    // Min/max over buckets [FromBucket, ToBucket)
    procedure GetMinMax(Channel, FromBucket, ToBucket: Integer; out AMin, AMax: Single);
  end;

  TSeekEvent = procedure(Sender: TObject; Sec: Double) of object;
  TSelectEvent = procedure(Sender: TObject; StartSec, EndSec: Double) of object;

  TWaveformView = class(TCustomControl)
  private
    FPeaks: IWavePeaks;
    FViewStart: Double;       // first visible frame
    FFramesPerPixel: Double;
    FAutoFit: Boolean;
    FCursorSec: Double;       // play position, < 0 = hidden
    FCueSec: Double;          // where playback (re)starts
    FSelStart, FSelEnd: Double;
    FCache: TBitmap;
    FCacheValid: Boolean;
    FMouseDown, FDragging, FPanning: Boolean;
    FDownX: Integer;
    FPanStartView: Double;
    FMessageText: string;
    FOnSeek: TSeekEvent;
    FOnSelect: TSelectEvent;
    procedure WMPeaksProgress(var Msg: TMessage); message WM_PEAKS_PROGRESS;
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
    function HasData: Boolean;
    function SampleRate: Integer;
    function TotalFrames: Int64;
    function XToSec(X: Integer): Double;
    function SecToX(Sec: Double): Integer;
    function MinFramesPerPixel: Double;
    function MaxFramesPerPixel: Double;
    procedure ClampView;
    procedure FitAll;
    procedure InvalidateCache;
    procedure RenderCache;
    procedure DrawRuler(C: TCanvas; W: Integer);
    procedure DrawChannel(C: TCanvas; Ch, Top, Height, W: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetPeaks(const Peaks: IWavePeaks; const MessageText: string = '');
    procedure SetCursor(Sec: Double);
    procedure SetCue(Sec: Double);
    procedure SetSelection(AStart, AEnd: Double);
    procedure ZoomBy(Factor: Double; AnchorX: Integer);
    procedure ScrollBy(Pixels: Integer);
    procedure WheelAt(Shift: TShiftState; WheelDelta: Integer; ScreenPos: TPoint);
    function Duration: Double;
    property Peaks: IWavePeaks read FPeaks;
    property SelStart: Double read FSelStart;
    property SelEnd: Double read FSelEnd;
    property OnSeek: TSeekEvent read FOnSeek write FOnSeek;
    property OnSelect: TSelectEvent read FOnSelect write FOnSelect;
  end;

function StartPeakJob(const FileName: string; NotifyWnd: HWND): IWavePeaks;

implementation

function Clamp(V, Lo, Hi: Double): Double; inline;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

const
  TargetBuckets = 500000;   // caps memory use for very long files
  RulerHeight = 18;

  // Colours are TColor ($00BBGGRR)
  clWaveBg     = $001E1E1E;
  clRulerBg    = $00161616;
  clRulerText  = $009A9A9A;
  clRulerTick  = $00505050;
  clLaneLine   = $00383838;
  clWave       = $00A8C860;   // teal-green
  clWaveSel    = $00D8F090;
  clSelBg      = $00503A28;   // muted blue
  clCursor     = $003CC8FF;   // amber
  clCue        = $00707070;
  clMessage    = $00808080;

type
  TWavePeaks = class(TInterfacedObject, IWavePeaks)
  private
    FFileName: string;
    FNotifyWnd: HWND;
    FMin, FMax: TArray<Single>;
    FCapacity: Integer;
    FChannels: Integer;
    FSampleRate: Integer;
    FTotalFrames: Int64;
    FFramesPerBucket: Integer;
    FBucketsDone: Integer;
    FReady, FFinished, FFailed, FCancelled: Boolean;
    procedure Notify;
  public
    constructor Create(const FileName: string; NotifyWnd: HWND);
    procedure Run;
    procedure Cancel;
    function Ready: Boolean;
    function Finished: Boolean;
    function Failed: Boolean;
    function Channels: Integer;
    function SampleRate: Integer;
    function TotalFrames: Int64;
    function FramesPerBucket: Integer;
    function BucketsDone: Integer;
    procedure GetMinMax(Channel, FromBucket, ToBucket: Integer; out AMin, AMax: Single);
  end;

  TPeakThread = class(TWorkerThread)
  private
    FPeaks: IWavePeaks;
  protected
    procedure Execute; override;
  public
    constructor Create(const Peaks: IWavePeaks);
  end;

function StartPeakJob(const FileName: string; NotifyWnd: HWND): IWavePeaks;
begin
  Result := TWavePeaks.Create(FileName, NotifyWnd);
  TPeakThread.Create(Result).Start;
end;

{ TPeakThread }

constructor TPeakThread.Create(const Peaks: IWavePeaks);
begin
  inherited Create;
  FPeaks := Peaks;
end;

procedure TPeakThread.Execute;
begin
  (FPeaks as TWavePeaks).Run;
  FPeaks := nil;
end;

{ TWavePeaks }

constructor TWavePeaks.Create(const FileName: string; NotifyWnd: HWND);
begin
  inherited Create;
  FFileName := FileName;
  FNotifyWnd := NotifyWnd;
end;

procedure TWavePeaks.Notify;
begin
  if not FCancelled then
    PostMessage(FNotifyWnd, WM_PEAKS_PROGRESS, 0, 0);
end;

procedure TWavePeaks.Run;
const
  BlockFrames = 16384;
var
  H: HSTREAM;
  CI: BASS_CHANNELINFO;
  Len: QWORD;
  Buf, AccMin, AccMax: TArray<Single>;
  Got: DWORD;
  Frames, F, C, InBucket, Bucket, Base: Integer;
  P: PSingle;
  V: Single;
  LastPost: UInt64;

  procedure ResetAcc;
  var
    I: Integer;
  begin
    for I := 0 to FChannels - 1 do
    begin
      AccMin[I] := 1e30;
      AccMax[I] := -1e30;
    end;
    InBucket := 0;
  end;

  procedure StoreBucket;
  var
    I: Integer;
  begin
    if Bucket < FCapacity then
    begin
      Base := Bucket * FChannels;
      for I := 0 to FChannels - 1 do
      begin
        FMin[Base + I] := AccMin[I];
        FMax[Base + I] := AccMax[I];
      end;
      Inc(Bucket);
    end;
    ResetAcc;
  end;

begin
  // PRESCAN gives exact length and seek tables for VBR MP3/Ogg; it costs a
  // full file pass, which is acceptable here since we decode it all anyway.
  H := BASS_StreamCreateFile(BASS_FILE_NAME, PChar(FFileName), 0, 0,
    BASS_STREAM_DECODE or BASS_SAMPLE_FLOAT or BASS_STREAM_PRESCAN or BASS_UNICODE);
  if H = 0 then
  begin
    FFailed := True;
    Notify;
    Exit;
  end;
  try
    Len := BASS_ChannelGetLength(H, BASS_POS_BYTE);
    if not BASS_ChannelGetInfo(H, CI) or (CI.chans = 0) or (Len = QW_ERROR) or (Len = 0) then
    begin
      FFailed := True;
      Notify;
      Exit;
    end;
    FChannels := CI.chans;
    FSampleRate := CI.freq;
    FTotalFrames := Len div (SizeOf(Single) * FChannels);
    FFramesPerBucket := Max(1, Ceil(FTotalFrames / TargetBuckets));
    FCapacity := FTotalFrames div FFramesPerBucket + 2;
    SetLength(FMin, FCapacity * FChannels);
    SetLength(FMax, FCapacity * FChannels);
    SetLength(AccMin, FChannels);
    SetLength(AccMax, FChannels);
    SetLength(Buf, BlockFrames * FChannels);
    FReady := True;
    Notify;

    Bucket := 0;
    ResetAcc;
    LastPost := GetTickCount64;
    while not FCancelled do
    begin
      Got := BASS_ChannelGetData(H, @Buf[0], BlockFrames * FChannels * SizeOf(Single));
      if (Got = $FFFFFFFF) or (Got = 0) then
        Break;
      Frames := Got div DWORD(SizeOf(Single) * FChannels);
      P := @Buf[0];
      for F := 0 to Frames - 1 do
      begin
        for C := 0 to FChannels - 1 do
        begin
          V := P^;
          Inc(P);
          if V < AccMin[C] then AccMin[C] := V;
          if V > AccMax[C] then AccMax[C] := V;
        end;
        Inc(InBucket);
        if InBucket = FFramesPerBucket then
          StoreBucket;
      end;
      FBucketsDone := Bucket;
      if GetTickCount64 - LastPost > 60 then
      begin
        Notify;
        LastPost := GetTickCount64;
      end;
    end;
    if FCancelled then
      Exit;
    if InBucket > 0 then
      StoreBucket;
    FBucketsDone := Bucket;
    FFinished := True;
    Notify;
  finally
    BASS_StreamFree(H);
  end;
end;

procedure TWavePeaks.Cancel;
begin
  FCancelled := True;
end;

function TWavePeaks.Ready: Boolean;
begin
  Result := FReady;
end;

function TWavePeaks.Finished: Boolean;
begin
  Result := FFinished;
end;

function TWavePeaks.Failed: Boolean;
begin
  Result := FFailed;
end;

function TWavePeaks.Channels: Integer;
begin
  Result := FChannels;
end;

function TWavePeaks.SampleRate: Integer;
begin
  Result := FSampleRate;
end;

function TWavePeaks.TotalFrames: Int64;
begin
  Result := FTotalFrames;
end;

function TWavePeaks.FramesPerBucket: Integer;
begin
  Result := FFramesPerBucket;
end;

function TWavePeaks.BucketsDone: Integer;
begin
  Result := FBucketsDone;
end;

procedure TWavePeaks.GetMinMax(Channel, FromBucket, ToBucket: Integer; out AMin, AMax: Single);
var
  I, Idx: Integer;
begin
  AMin := 1e30;
  AMax := -1e30;
  Idx := FromBucket * FChannels + Channel;
  for I := FromBucket to ToBucket - 1 do
  begin
    if FMin[Idx] < AMin then AMin := FMin[Idx];
    if FMax[Idx] > AMax then AMax := FMax[Idx];
    Inc(Idx, FChannels);
  end;
end;

{ TWaveformView }

constructor TWaveformView.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  StyleElements := [];
  FCache := TBitmap.Create;
  FCache.PixelFormat := pf32bit;
  FCursorSec := -1;
  FAutoFit := True;
end;

destructor TWaveformView.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TWaveformView.HasData: Boolean;
begin
  Result := (FPeaks <> nil) and FPeaks.Ready and (FPeaks.TotalFrames > 0);
end;

function TWaveformView.SampleRate: Integer;
begin
  if HasData then Result := FPeaks.SampleRate else Result := 44100;
end;

function TWaveformView.TotalFrames: Int64;
begin
  if HasData then Result := FPeaks.TotalFrames else Result := 0;
end;

function TWaveformView.Duration: Double;
begin
  Result := TotalFrames / SampleRate;
end;

function TWaveformView.XToSec(X: Integer): Double;
begin
  Result := Clamp((FViewStart + X * FFramesPerPixel) / SampleRate, 0, Duration);
end;

function TWaveformView.SecToX(Sec: Double): Integer;
begin
  if FFramesPerPixel <= 0 then
    Exit(-1);
  Result := Round((Sec * SampleRate - FViewStart) / FFramesPerPixel);
end;

function TWaveformView.MinFramesPerPixel: Double;
begin
  if HasData then
    Result := Max(FPeaks.FramesPerBucket / 8, 1 / 32)
  else
    Result := 1;
end;

function TWaveformView.MaxFramesPerPixel: Double;
begin
  Result := Max(TotalFrames / Max(1, ClientWidth), MinFramesPerPixel);
end;

procedure TWaveformView.ClampView;
begin
  FFramesPerPixel := Clamp(FFramesPerPixel, MinFramesPerPixel, MaxFramesPerPixel);
  FViewStart := Clamp(FViewStart, 0, Max(0.0, TotalFrames - ClientWidth * FFramesPerPixel));
end;

procedure TWaveformView.FitAll;
begin
  FFramesPerPixel := MaxFramesPerPixel;
  FViewStart := 0;
  FAutoFit := True;
  InvalidateCache;
end;

procedure TWaveformView.InvalidateCache;
begin
  FCacheValid := False;
  Invalidate;
end;

procedure TWaveformView.SetPeaks(const Peaks: IWavePeaks; const MessageText: string);
begin
  if (FPeaks <> nil) and (FPeaks <> Peaks) then
    FPeaks.Cancel;
  FPeaks := Peaks;
  FMessageText := MessageText;
  FSelStart := 0;
  FSelEnd := 0;
  FCueSec := 0;
  FCursorSec := -1;
  FViewStart := 0;
  FFramesPerPixel := 0;
  FAutoFit := True;
  if HasData then
    FitAll;
  InvalidateCache;
end;

procedure TWaveformView.WMPeaksProgress(var Msg: TMessage);
begin
  if HasData and (FAutoFit or (FFramesPerPixel <= 0)) then
    FitAll;
  InvalidateCache;
end;

procedure TWaveformView.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;
end;

procedure TWaveformView.SetCursor(Sec: Double);
var
  OldX, NewX, W: Integer;
begin
  OldX := SecToX(FCursorSec);
  FCursorSec := Sec;
  NewX := SecToX(Sec);
  W := ClientWidth;
  // Page along with the playhead when zoomed in
  if (Sec >= 0) and not FAutoFit and HasData and ((NewX >= W) or (NewX < 0)) then
  begin
    FViewStart := Sec * SampleRate - W * FFramesPerPixel * 0.05;
    ClampView;
    InvalidateCache;
  end
  else if OldX <> NewX then
    Invalidate;
end;

procedure TWaveformView.SetCue(Sec: Double);
begin
  FCueSec := Sec;
  Invalidate;
end;

procedure TWaveformView.SetSelection(AStart, AEnd: Double);
begin
  FSelStart := AStart;
  FSelEnd := AEnd;
  InvalidateCache;
end;

procedure TWaveformView.ZoomBy(Factor: Double; AnchorX: Integer);
var
  AnchorFrame: Double;
begin
  if not HasData then
    Exit;
  AnchorFrame := FViewStart + AnchorX * FFramesPerPixel;
  FFramesPerPixel := FFramesPerPixel * Factor;
  ClampView;
  FViewStart := AnchorFrame - AnchorX * FFramesPerPixel;
  ClampView;
  FAutoFit := SameValue(FFramesPerPixel, MaxFramesPerPixel, 1e-9);
  InvalidateCache;
end;

procedure TWaveformView.ScrollBy(Pixels: Integer);
begin
  if not HasData then
    Exit;
  FViewStart := FViewStart + Pixels * FFramesPerPixel;
  ClampView;
  InvalidateCache;
end;

procedure TWaveformView.Resize;
begin
  inherited;
  if FAutoFit then
    FitAll
  else
  begin
    ClampView;
    InvalidateCache;
  end;
end;

procedure TWaveformView.DrawRuler(C: TCanvas; W: Integer);
const
  Steps: array[0..21] of Double = (0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5,
    1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600);
var
  SecPerPixel, Step, T, T0, T1: Double;
  I, X: Integer;
  S: string;
begin
  C.Brush.Color := clRulerBg;
  C.FillRect(Rect(0, 0, W, RulerHeight));
  if not HasData then
    Exit;
  SecPerPixel := FFramesPerPixel / SampleRate;
  Step := Steps[High(Steps)];
  for I := 0 to High(Steps) do
    if Steps[I] / SecPerPixel >= 80 then
    begin
      Step := Steps[I];
      Break;
    end;
  T0 := FViewStart / SampleRate;
  T1 := T0 + W * SecPerPixel;
  C.Font.Color := clRulerText;
  C.Brush.Style := bsClear;
  C.Pen.Color := clRulerTick;
  T := Floor(T0 / Step) * Step;
  while T <= T1 do
  begin
    X := SecToX(T);
    if X >= 0 then
    begin
      C.MoveTo(X, RulerHeight - 5);
      C.LineTo(X, RulerHeight);
      S := FormatDuration(T, Step < 1);
      C.TextOut(X + 3, 2, S);
    end;
    T := T + Step;
  end;
  C.Brush.Style := bsSolid;
end;

procedure TWaveformView.DrawChannel(C: TCanvas; Ch, Top, Height, W: Integer);
var
  Mid, Half, X, Y1, Y2, B0, B1, Done, FPB: Integer;
  F0: Double;
  MinV, MaxV: Single;
  SelX1, SelX2: Integer;
  HasSel: Boolean;
begin
  Mid := Top + Height div 2;
  Half := Max(1, Height div 2 - 2);
  C.Pen.Color := clLaneLine;
  C.MoveTo(0, Mid);
  C.LineTo(W, Mid);
  if Ch > 0 then
  begin
    C.MoveTo(0, Top);
    C.LineTo(W, Top);
  end;

  Done := FPeaks.BucketsDone;
  FPB := FPeaks.FramesPerBucket;
  HasSel := FSelEnd > FSelStart;
  SelX1 := SecToX(FSelStart);
  SelX2 := SecToX(FSelEnd);
  for X := 0 to W - 1 do
  begin
    F0 := FViewStart + X * FFramesPerPixel;
    B0 := Trunc(F0 / FPB);
    B1 := Trunc((F0 + FFramesPerPixel) / FPB);
    if B1 <= B0 then
      B1 := B0 + 1;
    if B0 >= Done then
      Break;
    if B1 > Done then
      B1 := Done;
    FPeaks.GetMinMax(Ch, B0, B1, MinV, MaxV);
    MinV := Clamp(MinV, -1, 1);
    MaxV := Clamp(MaxV, -1, 1);
    Y1 := Mid - Round(MaxV * Half);
    Y2 := Mid - Round(MinV * Half);
    if HasSel and (X >= SelX1) and (X <= SelX2) then
      C.Pen.Color := clWaveSel
    else
      C.Pen.Color := clWave;
    C.MoveTo(X, Y1);
    C.LineTo(X, Y2 + 1);
  end;
end;

procedure TWaveformView.RenderCache;
var
  C: TCanvas;
  W, H, Ch, Lanes, LaneTop, LaneH, X1, X2: Integer;
  Msg: string;
begin
  W := ClientWidth;
  H := ClientHeight;
  FCache.SetSize(Max(W, 1), Max(H, 1));
  C := FCache.Canvas;
  C.Font.Assign(Font);
  C.Brush.Color := clWaveBg;
  C.FillRect(Rect(0, 0, W, H));
  DrawRuler(C, W);

  if HasData then
  begin
    if FSelEnd > FSelStart then
    begin
      X1 := Max(0, SecToX(FSelStart));
      X2 := Min(W, SecToX(FSelEnd) + 1);
      C.Brush.Color := clSelBg;
      C.FillRect(Rect(X1, RulerHeight, X2, H));
    end;
    Lanes := FPeaks.Channels;
    LaneH := (H - RulerHeight) div Lanes;
    for Ch := 0 to Lanes - 1 do
    begin
      LaneTop := RulerHeight + Ch * LaneH;
      DrawChannel(C, Ch, LaneTop, LaneH, W);
    end;
  end
  else
  begin
    Msg := FMessageText;
    if (Msg = '') and (FPeaks <> nil) then
      if FPeaks.Failed then
        Msg := 'Cannot decode this file'
      else
        Msg := 'Loading...';
    if Msg <> '' then
    begin
      C.Font.Color := clMessage;
      C.Brush.Style := bsClear;
      C.TextOut((W - C.TextWidth(Msg)) div 2, (H - C.TextHeight(Msg)) div 2, Msg);
      C.Brush.Style := bsSolid;
    end;
  end;
  FCacheValid := True;
end;

procedure TWaveformView.Paint;
var
  X: Integer;
begin
  if not FCacheValid or (FCache.Width <> ClientWidth) or (FCache.Height <> ClientHeight) then
    RenderCache;
  Canvas.Draw(0, 0, FCache);
  if not HasData then
    Exit;
  X := SecToX(FCueSec);
  if (X >= 0) and (X < ClientWidth) then
  begin
    Canvas.Pen.Color := clCue;
    Canvas.MoveTo(X, 0);
    Canvas.LineTo(X, ClientHeight);
  end;
  if FCursorSec >= 0 then
  begin
    X := SecToX(FCursorSec);
    if (X >= 0) and (X < ClientWidth) then
    begin
      Canvas.Pen.Color := clCursor;
      Canvas.MoveTo(X, 0);
      Canvas.LineTo(X, ClientHeight);
    end;
  end;
end;

procedure TWaveformView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not HasData then
    Exit;
  if Button = mbLeft then
  begin
    FMouseDown := True;
    FDragging := False;
    FDownX := X;
    MouseCapture := True;
  end
  else if Button = mbRight then
  begin
    FPanning := True;
    FDownX := X;
    FPanStartView := FViewStart;
    MouseCapture := True;
  end;
end;

procedure TWaveformView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  A, B: Double;
begin
  inherited;
  if FPanning then
  begin
    FViewStart := FPanStartView - (X - FDownX) * FFramesPerPixel;
    ClampView;
    FAutoFit := False;
    InvalidateCache;
  end
  else if FMouseDown then
  begin
    if not FDragging and (Abs(X - FDownX) > 3) then
      FDragging := True;
    if FDragging then
    begin
      A := XToSec(FDownX);
      B := XToSec(X);
      SetSelection(Min(A, B), Max(A, B));
    end;
  end;
end;

procedure TWaveformView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Sec: Double;
begin
  inherited;
  if (Button = mbRight) and FPanning then
  begin
    FPanning := False;
    MouseCapture := False;
  end
  else if (Button = mbLeft) and FMouseDown then
  begin
    FMouseDown := False;
    MouseCapture := False;
    if FDragging then
    begin
      FDragging := False;
      if Assigned(FOnSelect) then
        FOnSelect(Self, FSelStart, FSelEnd);
    end
    else
    begin
      Sec := XToSec(X);
      // Clicking outside the selection drops it; inside keeps it
      if (FSelEnd > FSelStart) and ((Sec < FSelStart) or (Sec > FSelEnd)) then
      begin
        SetSelection(0, 0);
        if Assigned(FOnSelect) then
          FOnSelect(Self, 0, 0);
      end;
      if Assigned(FOnSeek) then
        FOnSeek(Self, Sec);
    end;
  end;
end;

procedure TWaveformView.DblClick;
begin
  inherited;
  FitAll;
end;

function TWaveformView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  WheelAt(Shift, WheelDelta, MousePos);
  Result := True;
end;

procedure TWaveformView.WheelAt(Shift: TShiftState; WheelDelta: Integer; ScreenPos: TPoint);
var
  P: TPoint;
begin
  if not HasData then
    Exit;
  if ssShift in Shift then
    ScrollBy(-Sign(WheelDelta) * ClientWidth div 8)
  else
  begin
    P := ScreenToClient(ScreenPos);
    if WheelDelta > 0 then
      ZoomBy(1 / 1.5, P.X)
    else
      ZoomBy(1.5, P.X);
  end;
end;

end.
