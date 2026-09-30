program SoundsBrowse;

{$R *.res}
{$R 'res\Styles.res'}
{$R 'res\Logo.res'}

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  bass in 'lib\bass\bass.pas',
  AudioEngine in 'src\AudioEngine.pas',
  Workers in 'src\Workers.pas',
  Waveform in 'src\Waveform.pas',
  DragOut in 'src\DragOut.pas',
  SingleInstance in 'src\SingleInstance.pas',
  ShellIntegration in 'src\ShellIntegration.pas',
  DarkMode in 'src\DarkMode.pas',
  MainForm in 'src\MainForm.pas' {frmMain};

procedure ApplyDarkStyle;
var
  Name: string;
begin
  // res\Styles.res embeds a single dark style; activate whatever it is
  for Name in TStyleManager.StyleNames do
    if not SameText(Name, 'Windows') then
    begin
      TStyleManager.TrySetStyle(Name);
      Exit;
    end;
end;

begin
  if ForwardToRunningInstance(CommandLineFolder) then
    Exit;
  ReportMemoryLeaksOnShutdown := DebugHook <> 0;
  ForceDarkMode;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  ApplyDarkStyle;
  Application.Title := 'SoundsBrowse';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
