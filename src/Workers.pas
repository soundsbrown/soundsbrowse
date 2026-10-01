unit Workers;

{ Background jobs. Worker threads free themselves; the UI only talks to them
  through reference-counted job objects and posted window messages, so it never
  has to block waiting for a thread (e.g. one stuck in a slow file open). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections, AudioEngine;

const
  WM_SCAN_PROGRESS  = WM_APP + 1;
  WM_PEAKS_PROGRESS = WM_APP + 2;

type
  TWorkerThread = class(TThread)
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TScanResult = record
    Index: Integer;
    Info: TAudioInfo;
  end;

  // Probes a list of files (sample rate, length, ...) in the background.
  IScanJob = interface
    ['{2B6E53B1-7F47-4F0E-9C0D-6A1C3B8E4F21}']
    procedure Cancel;
    function Cancelled: Boolean;
    function TakeResults: TArray<TScanResult>;
    function Finished: Boolean;
  end;

function StartScanJob(const Files: TArray<string>; NotifyWnd: HWND): IScanJob;

// Called on shutdown after cancelling all jobs.
procedure WaitForWorkers(TimeoutMs: Cardinal);

implementation

const
  THREAD_MODE_BACKGROUND_BEGIN = $00010000;   // not in Winapi.Windows

var
  GActiveWorkers: Integer;

type
  TScanJob = class(TInterfacedObject, IScanJob)
  private
    FFiles: TArray<string>;
    FNotifyWnd: HWND;
    FLock: TCriticalSection;
    FResults: TList<TScanResult>;
    FCancelled: Boolean;
    FFinished: Boolean;
  public
    constructor Create(const Files: TArray<string>; NotifyWnd: HWND);
    destructor Destroy; override;
    procedure Cancel;
    function Cancelled: Boolean;
    function TakeResults: TArray<TScanResult>;
    function Finished: Boolean;
    procedure Run;
  end;

  TScanThread = class(TWorkerThread)
  private
    FJob: IScanJob;
  protected
    procedure Execute; override;
  public
    constructor Create(const Job: IScanJob);
  end;

procedure WaitForWorkers(TimeoutMs: Cardinal);
var
  Start: UInt64;
begin
  Start := GetTickCount64;
  while (TInterlocked.CompareExchange(GActiveWorkers, 0, 0) > 0) and
        (GetTickCount64 - Start < TimeoutMs) do
    Sleep(10);
end;

{ TWorkerThread }

constructor TWorkerThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := True;
  TInterlocked.Increment(GActiveWorkers);
end;

destructor TWorkerThread.Destroy;
begin
  TInterlocked.Decrement(GActiveWorkers);
  inherited;
end;

{ TScanJob }

constructor TScanJob.Create(const Files: TArray<string>; NotifyWnd: HWND);
begin
  inherited Create;
  FFiles := Files;
  FNotifyWnd := NotifyWnd;
  FLock := TCriticalSection.Create;
  FResults := TList<TScanResult>.Create;
end;

destructor TScanJob.Destroy;
begin
  FResults.Free;
  FLock.Free;
  inherited;
end;

procedure TScanJob.Cancel;
begin
  FCancelled := True;
end;

function TScanJob.Cancelled: Boolean;
begin
  Result := FCancelled;
end;

function TScanJob.Finished: Boolean;
begin
  Result := FFinished;
end;

function TScanJob.TakeResults: TArray<TScanResult>;
begin
  FLock.Enter;
  try
    Result := FResults.ToArray;
    FResults.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TScanJob.Run;
var
  I: Integer;
  R: TScanResult;
  LastPost: UInt64;
begin
  LastPost := GetTickCount64;
  for I := 0 to High(FFiles) do
  begin
    if FCancelled then
      Exit;
    R.Index := I;
    R.Info := TAudioEngine.Probe(FFiles[I]);
    FLock.Enter;
    try
      FResults.Add(R);
    finally
      FLock.Leave;
    end;
    if GetTickCount64 - LastPost > 100 then
    begin
      PostMessage(FNotifyWnd, WM_SCAN_PROGRESS, 0, 0);
      LastPost := GetTickCount64;
    end;
  end;
  FFinished := True;
  PostMessage(FNotifyWnd, WM_SCAN_PROGRESS, 1, 0);
end;

{ TScanThread }

constructor TScanThread.Create(const Job: IScanJob);
begin
  inherited Create;
  FJob := Job;
end;

procedure TScanThread.Execute;
begin
  // Low CPU and I/O priority: opening every file in a folder must not starve
  // the playing stream of disk reads, especially on a hard disk
  SetThreadPriority(GetCurrentThread, THREAD_MODE_BACKGROUND_BEGIN);
  (FJob as TScanJob).Run;
  FJob := nil;
end;

function StartScanJob(const Files: TArray<string>; NotifyWnd: HWND): IScanJob;
begin
  Result := TScanJob.Create(Files, NotifyWnd);
  TScanThread.Create(Result).Start;
end;

end.
