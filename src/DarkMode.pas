unit DarkMode;

// The VCL style only covers VCL-painted controls. Native UI (shell context
// menus, the system menu, some tooltips) follows the Windows light/dark
// setting instead. This forces the process into Windows' own dark mode via
// the undocumented uxtheme exports that Explorer uses (Windows 10 1903+).
// On older builds the ordinals mean something else or are missing, so it is
// skipped there.

interface

procedure ForceDarkMode;

implementation

uses
  Winapi.Windows, System.SysUtils;

type
  TSetPreferredAppMode = function(Mode: Integer): Integer; stdcall;
  TFlushMenuThemes = procedure; stdcall;

const
  ForceDark = 2; // PreferredAppMode: Default, AllowDark, ForceDark, ForceLight

procedure ForceDarkMode;
var
  UxTheme: HMODULE;
  SetPreferredAppMode: TSetPreferredAppMode;
  FlushMenuThemes: TFlushMenuThemes;
begin
  // Ordinal 135 was AllowDarkModeForApp(BOOL) before build 18362
  if not CheckWin32Version(10) or (TOSVersion.Build < 18362) then
    Exit;
  UxTheme := LoadLibrary('uxtheme.dll');
  if UxTheme = 0 then
    Exit;
  @SetPreferredAppMode := GetProcAddress(UxTheme, LPCSTR(NativeUInt(135)));
  @FlushMenuThemes := GetProcAddress(UxTheme, LPCSTR(NativeUInt(136)));
  if Assigned(SetPreferredAppMode) then
    SetPreferredAppMode(ForceDark);
  if Assigned(FlushMenuThemes) then
    FlushMenuThemes;
  // uxtheme stays loaded; the setting is held in its process state
end;

end.
