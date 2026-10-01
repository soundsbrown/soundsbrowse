unit AudioEngine;

{ Thin wrapper around BASS: device init, add-on loading, file probing and
  playback of a single file with optional selection / loop range. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, bass;

type
  TAudioInfo = record
    Valid: Boolean;
    SampleRate: Cardinal;
    Channels: Cardinal;
    Bits: Cardinal;      // 0 = not applicable (lossy codecs)
    IsFloat: Boolean;
    IsMidi: Boolean;     // rate/channels/bits are the synth's output, so left 0
    Duration: Double;    // seconds, < 0 if unknown
  end;

  TAudioEngine = class
  private
    FInitialized: Boolean;
    FStream: HSTREAM;
    FFileName: string;
    FSelStart, FSelEnd: Double;
    FLoop: Boolean;
    FVolume: Single;
    FExtensions: TStringList;
    FPlugins: TStringList;
    FMidi: Boolean;
    FSoundFont: string;
    procedure LoadPlugins;
    class function BundledSoundFont: string; static;
    procedure AddExtensions(const Filter: string);
    procedure FreeStream;
    procedure ApplyLoop;
    function HasSelection: Boolean;
    procedure SetLoop(Value: Boolean);
    procedure SetVolume(Value: Single);
  public
    constructor Create;
    destructor Destroy; override;
    function Init(Wnd: HWND): Boolean;
    function IsSupportedFile(const FileName: string): Boolean;
    class function Probe(const FileName: string): TAudioInfo; static;
    function SetSoundFont(const FileName: string): Boolean;   // '' = bundled

    procedure Open(const FileName: string);
    procedure Play(FromSec: Double);
    procedure Stop;
    function IsPlaying: Boolean;
    function Position: Double;
    procedure SetSelection(AStart, AEnd: Double);

    property FileName: string read FFileName;
    property Loop: Boolean read FLoop write SetLoop;
    property Volume: Single read FVolume write SetVolume;
    property SelStart: Double read FSelStart;
    property SelEnd: Double read FSelEnd;
    property Extensions: TStringList read FExtensions;
    property Plugins: TStringList read FPlugins;
    property MidiSupported: Boolean read FMidi;
    property SoundFont: string read FSoundFont;
  end;

function FormatDuration(Sec: Double; WithMillis: Boolean = False): string;

implementation

const
  // Formats BASS handles itself; the m4a/aac/wma/mp4 group goes through
  // Media Foundation, which BASS uses automatically when available.
  BuiltInFormats = '*.wav;*.wave;*.bwf;*.aif;*.aiff;*.aifc;*.mp3;*.mp2;*.mp1;*.ogg;' +
                   '*.m4a;*.aac;*.mp4;*.wma';

  // From bassmidi.h; only these are needed, so bassmidi.pas isn't pulled in
  BASS_CONFIG_MIDI_DEFFONT = $10403;
  BASS_CTYPE_STREAM_MIDI   = $10D00;

  SoundFontMasks: array[0..1] of string = ('*.sf2', '*.sf3');

function FormatDuration(Sec: Double; WithMillis: Boolean): string;
var
  Total, M, S, Ms: Int64;
begin
  if Sec < 0 then
    Exit('');
  Total := Round(Sec * 1000);
  Ms := Total mod 1000;
  S := (Total div 1000) mod 60;
  M := Total div 60000;
  if WithMillis then
    Result := Format('%d:%.2d.%.3d', [M, S, Ms])
  else if (M = 0) and (S < 10) then
    Result := Format('%d.%.2d', [S, Ms div 10])   // short samples: 2.35
  else
    Result := Format('%d:%.2d', [M, S]);
end;

{ TAudioEngine }

constructor TAudioEngine.Create;
begin
  inherited;
  FVolume := 1.0;
  FExtensions := TStringList.Create;
  FExtensions.Sorted := True;
  FExtensions.Duplicates := dupIgnore;
  FExtensions.CaseSensitive := False;
  FPlugins := TStringList.Create;
end;

destructor TAudioEngine.Destroy;
begin
  FreeStream;
  if FInitialized then
  begin
    BASS_PluginFree(0);
    BASS_Free;
  end;
  FPlugins.Free;
  FExtensions.Free;
  inherited;
end;

function TAudioEngine.Init(Wnd: HWND): Boolean;
begin
  if HiWord(BASS_GetVersion) <> BASSVERSION then
    raise Exception.Create('Wrong bass.dll version');
  // Default device; fall back to the "no sound" device so that at least
  // decoding (waveforms, file info) keeps working.
  FInitialized := BASS_Init(-1, 44100, 0, Wnd, nil) or
                  (BASS_ErrorGetCode = BASS_ERROR_ALREADY) or
                  BASS_Init(0, 44100, 0, Wnd, nil);
  Result := FInitialized;
  AddExtensions(BuiltInFormats);
  if FInitialized then
    LoadPlugins;
  // Read-ahead for the playback stream (BASS_ASYNCFILE in Play), so that
  // disk stalls caused by other I/O don't make playback stutter. 2 MB is
  // about 12 s of CD-quality WAV. Only one playback stream exists at a time.
  BASS_SetConfig(BASS_CONFIG_ASYNCFILE_BUFFER, 2 * 1024 * 1024);
  // BASSMIDI has no instruments of its own: default to the soundfont that
  // ships next to the exe. The ini can override it later via SetSoundFont.
  if FMidi then
    SetSoundFont('');
end;

procedure TAudioEngine.AddExtensions(const Filter: string);
var
  Part: string;
begin
  for Part in Filter.Split([';']) do
    if Part.Trim.StartsWith('*.') then
      FExtensions.Add(LowerCase(Part.Trim.Substring(1)));   // '.flac'
end;

procedure TAudioEngine.LoadPlugins;
var
  Dir: string;
  SR: TSearchRec;
  Plugin: HPLUGIN;
  Info: PBASS_PLUGININFO;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  if FindFirst(Dir + 'bass*.dll', faAnyFile, SR) = 0 then
  try
    repeat
      if SameText(SR.Name, 'bass.dll') then
        Continue;
      Plugin := BASS_PluginLoad(PChar(Dir + SR.Name), BASS_UNICODE);
      if Plugin = 0 then
        Continue;
      FPlugins.Add(ChangeFileExt(SR.Name, ''));
      if SameText(SR.Name, 'bassmidi.dll') then
        FMidi := True;
      Info := BASS_PluginGetInfo(Plugin);
      if Info <> nil then
        for I := 0 to Integer(Info^.formatc) - 1 do
          AddExtensions(string(AnsiString(Info^.formats^[I].exts)));
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

class function TAudioEngine.BundledSoundFont: string;
var
  Dir, Mask: string;
  SR: TSearchRec;
begin
  Result := '';
  Dir := ExtractFilePath(ParamStr(0));
  for Mask in SoundFontMasks do
    if FindFirst(Dir + Mask, faAnyFile, SR) = 0 then
    begin
      FindClose(SR);
      Exit(Dir + SR.Name);
    end;
end;

function TAudioEngine.SetSoundFont(const FileName: string): Boolean;
var
  Path: string;
begin
  // '' means the bundled soundfont. Relative paths are relative to the exe,
  // so a portable copy keeps working.
  if FileName = '' then
    Path := BundledSoundFont
  else
    Path := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)), FileName, False));
  // If the font can't be loaded, BASSMIDI keeps the previous one
  Result := FMidi and (Path <> '') and FileExists(Path) and
    BASS_SetConfigPtr(BASS_CONFIG_MIDI_DEFFONT or BASS_UNICODE, PChar(Path));
  if Result then
    FSoundFont := Path;
end;

function TAudioEngine.IsSupportedFile(const FileName: string): Boolean;
begin
  Result := FExtensions.IndexOf(ExtractFileExt(FileName)) >= 0;
end;

class function TAudioEngine.Probe(const FileName: string): TAudioInfo;
var
  H: HSTREAM;
  CI: BASS_CHANNELINFO;
  Len: QWORD;
begin
  Result := Default(TAudioInfo);
  Result.Duration := -1;
  H := BASS_StreamCreateFile(BASS_FILE_NAME, PChar(FileName), 0, 0,
    BASS_STREAM_DECODE or BASS_SAMPLE_FLOAT or BASS_UNICODE);
  if H = 0 then
    Exit;
  try
    if BASS_ChannelGetInfo(H, CI) then
    begin
      Result.Valid := True;
      Result.IsMidi := CI.ctype = BASS_CTYPE_STREAM_MIDI;
      if not Result.IsMidi then
      begin
        Result.SampleRate := CI.freq;
        Result.Channels := CI.chans;
        Result.Bits := CI.origres and $FFFF;
        Result.IsFloat := (CI.origres and BASS_ORIGRES_FLOAT) <> 0;
      end;
      Len := BASS_ChannelGetLength(H, BASS_POS_BYTE);
      if Len <> QW_ERROR then
        Result.Duration := BASS_ChannelBytes2Seconds(H, Len);
    end;
  finally
    BASS_StreamFree(H);
  end;
end;

procedure TAudioEngine.FreeStream;
begin
  if FStream <> 0 then
  begin
    BASS_StreamFree(FStream);
    FStream := 0;
  end;
end;

procedure TAudioEngine.Open(const FileName: string);
begin
  FreeStream;
  FFileName := FileName;
  FSelStart := 0;
  FSelEnd := 0;
end;

function TAudioEngine.HasSelection: Boolean;
begin
  Result := FSelEnd > FSelStart;
end;

procedure TAudioEngine.SetSelection(AStart, AEnd: Double);
begin
  FSelStart := AStart;
  FSelEnd := AEnd;
end;

procedure TAudioEngine.Play(FromSec: Double);
begin
  // A fresh stream per Play keeps the end/loop trimming logic trivial:
  // nothing has to be "untrimmed" when the selection changes.
  FreeStream;
  if FFileName = '' then
    Exit;
  FStream := BASS_StreamCreateFile(BASS_FILE_NAME, PChar(FFileName), 0, 0,
    BASS_SAMPLE_FLOAT or BASS_ASYNCFILE or BASS_UNICODE);
  if FStream = 0 then
    Exit;
  if HasSelection then
  begin
    if (FromSec < FSelStart) or (FromSec >= FSelEnd) then
      FromSec := FSelStart;
    BASS_ChannelSetPosition(FStream, BASS_ChannelSeconds2Bytes(FStream, FSelEnd), BASS_POS_END);
  end;
  if FromSec > 0 then
    BASS_ChannelSetPosition(FStream, BASS_ChannelSeconds2Bytes(FStream, FromSec), BASS_POS_BYTE);
  ApplyLoop;
  BASS_ChannelSetAttribute(FStream, BASS_ATTRIB_VOL, FVolume);
  BASS_ChannelPlay(FStream, False);
end;

procedure TAudioEngine.ApplyLoop;
begin
  if FStream = 0 then
    Exit;
  if FLoop then
  begin
    BASS_ChannelFlags(FStream, BASS_SAMPLE_LOOP, BASS_SAMPLE_LOOP);
    if HasSelection then
      BASS_ChannelSetPosition(FStream, BASS_ChannelSeconds2Bytes(FStream, FSelStart), BASS_POS_LOOP)
    else
      BASS_ChannelSetPosition(FStream, 0, BASS_POS_LOOP);
  end
  else
    BASS_ChannelFlags(FStream, 0, BASS_SAMPLE_LOOP);
end;

procedure TAudioEngine.Stop;
begin
  FreeStream;
end;

function TAudioEngine.IsPlaying: Boolean;
begin
  Result := (FStream <> 0) and (BASS_ChannelIsActive(FStream) = BASS_ACTIVE_PLAYING);
end;

function TAudioEngine.Position: Double;
begin
  if FStream = 0 then
    Exit(-1);
  Result := BASS_ChannelBytes2Seconds(FStream, BASS_ChannelGetPosition(FStream, BASS_POS_BYTE));
end;

procedure TAudioEngine.SetLoop(Value: Boolean);
begin
  FLoop := Value;
  ApplyLoop;
end;

procedure TAudioEngine.SetVolume(Value: Single);
begin
  FVolume := Value;
  if FStream <> 0 then
    BASS_ChannelSetAttribute(FStream, BASS_ATTRIB_VOL, FVolume);
end;

end.
