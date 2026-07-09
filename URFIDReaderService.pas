unit URFIDReaderService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Winapi.Windows;

type
  TRFIDTagEvent = procedure(Sender: TObject; const AUID, ATagType: string) of object;
  TRFIDLogEvent = procedure(Sender: TObject; const AText: string) of object;

  TRFIDReaderService = class;

  TRFIDReaderThread = class(TThread)
  private
    FOwner: TRFIDReaderService;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TRFIDReaderService);
  end;

  TRFIDReaderService = class
  private
    FHandle: THandle;
    FLock: TCriticalSection;
    FThread: TRFIDReaderThread;
    FLastUID: string;
    FLastTagType: string;
    FLastError: string;
    FOnTag: TRFIDTagEvent;
    FOnLog: TRFIDLogEvent;

    procedure Log(const S: string);
    function IsOpen: Boolean;
    function XorChecksum(const ABytes: TBytes; ACount: Integer): Byte;
    function BytesToHex(const ABytes: TBytes; ACount: Integer = -1): string;
    function BuildTelegram(ACommand: Byte; const APayload: array of Byte): TBytes;
    function WriteBytes(const ABytes: TBytes): Boolean;
    function ReadTelegram(out ATelegram: TBytes; ATimeoutMS: Cardinal = 1000): Boolean;
    function SendCommand(ACommand: Byte; const APayload: array of Byte; out AReply: TBytes;
      ATimeoutMS: Cardinal = 1000): Boolean;
    function PayloadLength(const ATelegram: TBytes): Integer;
    function ParseUIDFromActivate(const ATelegram: TBytes; out AUID: string): Boolean;
    function ParseUIDFromAutolist(const ATelegram: TBytes; out AUID, ATagType: string): Boolean;
    procedure SetLastTag(const AUID, ATagType: string);
  public
    constructor Create;
    destructor Destroy; override;

    function Open(const AComPort: string; ABaud: Cardinal = CBR_9600): Boolean;
    procedure Close;

    function GetFirmware(out AFirmware: string): Boolean;
    function GetReaderUID(out AUID: string): Boolean;
    function ActivateCard(out AUID: string): Boolean;

    function StartAutoList(AIntervalMS: Byte = 100; AOnlyEnter: Boolean = True): Boolean;
    function StopAutoList: Boolean;

    function PiccTransfer(const APiccCommand: array of Byte; out AReplyPayload: TBytes): Boolean;
    function NTagGetVersion(out AVersionHex: string): Boolean;
    function NTagPwdAuth(const APwd: array of Byte; out APackHex: string): Boolean;
    function NTagReadPage(APage: Byte; out A16Bytes: TBytes): Boolean;
    function NTagWritePage(APage: Byte; const A4Bytes: array of Byte): Boolean;

    property LastUID: string read FLastUID;
    property LastTagType: string read FLastTagType;
    property LastError: string read FLastError;
    property OnTag: TRFIDTagEvent read FOnTag write FOnTag;
    property OnLog: TRFIDLogEvent read FOnLog write FOnLog;
  end;

implementation

constructor TRFIDReaderThread.Create(AOwner: TRFIDReaderService);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TRFIDReaderThread.Execute;
var
  T: TBytes;
  UID, TagType: string;
begin
  while not Terminated do
  begin
    if FOwner.ReadTelegram(T, 200) then
    begin
      FOwner.Log('RFID << ' + FOwner.BytesToHex(T));
      if FOwner.ParseUIDFromAutolist(T, UID, TagType) then
        FOwner.SetLastTag(UID, TagType);
    end;
    Sleep(10);
  end;
end;

constructor TRFIDReaderService.Create;
begin
  inherited Create;
  FHandle := INVALID_HANDLE_VALUE;
  FLock := TCriticalSection.Create;
end;

destructor TRFIDReaderService.Destroy;
begin
  Close;
  FLock.Free;
  inherited Destroy;
end;

procedure TRFIDReaderService.Log(const S: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - ' + S);
end;

function TRFIDReaderService.IsOpen: Boolean;
begin
  Result := FHandle <> INVALID_HANDLE_VALUE;
end;

function TRFIDReaderService.XorChecksum(const ABytes: TBytes; ACount: Integer): Byte;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ACount - 1 do
    Result := Result xor ABytes[I];
end;

function TRFIDReaderService.BytesToHex(const ABytes: TBytes; ACount: Integer): string;
var
  I, N: Integer;
begin
  Result := '';
  N := ACount;
  if N < 0 then
    N := Length(ABytes);
  for I := 0 to N - 1 do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + IntToHex(ABytes[I], 2);
  end;
end;

function TRFIDReaderService.BuildTelegram(ACommand: Byte; const APayload: array of Byte): TBytes;
var
  Len, I: Integer;
begin
  Len := Length(APayload);
  SetLength(Result, 5 + Len);
  Result[0] := $50;
  Result[1] := Byte((Len shr 8) and $FF);
  Result[2] := Byte(Len and $FF);
  Result[3] := ACommand;
  for I := 0 to Len - 1 do
    Result[4 + I] := APayload[I];
  Result[Length(Result) - 1] := XorChecksum(Result, Length(Result) - 1);
end;

function TRFIDReaderService.WriteBytes(const ABytes: TBytes): Boolean;
var
  Written: DWORD;
begin
  Result := False;
  if not IsOpen then Exit;
  Log('RFID >> ' + BytesToHex(ABytes));
  Result := WriteFile(FHandle, ABytes[0], Length(ABytes), Written, nil) and (Written = DWORD(Length(ABytes)));
  if not Result then
    FLastError := 'WriteFile fehlgeschlagen';
end;

function TRFIDReaderService.ReadTelegram(out ATelegram: TBytes; ATimeoutMS: Cardinal): Boolean;
var
  B: Byte;
  Readed: DWORD;
  StartTick: Cardinal;
  NeedLen, Len: Integer;
begin
  Result := False;
  SetLength(ATelegram, 0);
  if not IsOpen then Exit;

  StartTick := GetTickCount;
  NeedLen := -1;

  while GetTickCount - StartTick < ATimeoutMS do
  begin
    Readed := 0;
    if ReadFile(FHandle, B, 1, Readed, nil) and (Readed = 1) then
    begin
      if (Length(ATelegram) = 0) and not (B in [$50, $F0]) then
        Continue;

      SetLength(ATelegram, Length(ATelegram) + 1);
      ATelegram[High(ATelegram)] := B;

      if Length(ATelegram) = 3 then
      begin
        Len := (ATelegram[1] shl 8) + ATelegram[2];
        NeedLen := 1 + 2 + 1 + Len + 1;
      end;

      if (NeedLen > 0) and (Length(ATelegram) >= NeedLen) then
      begin
        Result := XorChecksum(ATelegram, Length(ATelegram) - 1) = ATelegram[High(ATelegram)];
        if not Result then
          FLastError := 'RFID Prüfsumme falsch: ' + BytesToHex(ATelegram);
        Exit;
      end;
    end
    else
      Sleep(2);
  end;

  FLastError := 'Timeout beim Lesen vom RFID-Reader';
end;

function TRFIDReaderService.SendCommand(ACommand: Byte; const APayload: array of Byte; out AReply: TBytes;
  ATimeoutMS: Cardinal): Boolean;
var
  T: TBytes;
begin
  Result := False;
  FLock.Enter;
  try
    T := BuildTelegram(ACommand, APayload);
    if not WriteBytes(T) then Exit;
    Result := ReadTelegram(AReply, ATimeoutMS);
    if Result then
    begin
      Log('RFID << ' + BytesToHex(AReply));
      if AReply[0] = $F0 then
      begin
        FLastError := 'RFID Fehlerantwort: ' + BytesToHex(AReply);
        Result := False;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRFIDReaderService.PayloadLength(const ATelegram: TBytes): Integer;
begin
  Result := 0;
  if Length(ATelegram) >= 5 then
    Result := (ATelegram[1] shl 8) + ATelegram[2];
end;

function TRFIDReaderService.Open(const AComPort: string; ABaud: Cardinal): Boolean;
var
  DCB: TDCB;
  Timeouts: TCommTimeouts;
  PortName: string;
begin
  Result := False;
  Close;

  PortName := AComPort;
  if Pos('\\.\', PortName) <> 1 then
    PortName := '\\.\' + PortName;

  FHandle := CreateFile(PChar(PortName), GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);

  if FHandle = INVALID_HANDLE_VALUE then
  begin
    FLastError := 'COM-Port kann nicht geöffnet werden: ' + AComPort;
    Exit;
  end;

  SetupComm(FHandle, 4096, 4096);
  PurgeComm(FHandle, PURGE_RXCLEAR or PURGE_TXCLEAR);

  FillChar(DCB, SizeOf(DCB), 0);
  DCB.DCBlength := SizeOf(DCB);
  GetCommState(FHandle, DCB);
  DCB.BaudRate := ABaud;
  DCB.ByteSize := 8;
  DCB.Parity := NOPARITY;
  DCB.StopBits := ONESTOPBIT;
  DCB.Flags := 1; // fBinary
  if not SetCommState(FHandle, DCB) then
  begin
    FLastError := 'SetCommState fehlgeschlagen';
    Close;
    Exit;
  end;

  FillChar(Timeouts, SizeOf(Timeouts), 0);
  Timeouts.ReadIntervalTimeout := 20;
  Timeouts.ReadTotalTimeoutConstant := 20;
  Timeouts.ReadTotalTimeoutMultiplier := 1;
  Timeouts.WriteTotalTimeoutConstant := 1000;
  Timeouts.WriteTotalTimeoutMultiplier := 1;
  SetCommTimeouts(FHandle, Timeouts);

  Result := True;
  Log('RFID COM geöffnet: ' + AComPort);
end;

procedure TRFIDReaderService.Close;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;

  if IsOpen then
  begin
    CloseHandle(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
end;

function TRFIDReaderService.GetFirmware(out AFirmware: string): Boolean;
var
  R: TBytes;
  I, L: Integer;
begin
  AFirmware := '';
  Result := SendCommand($04, [], R, 1000);
  if not Result then Exit;
  L := PayloadLength(R);
  for I := 4 to 4 + L - 1 do
  begin
    if (R[I] >= 32) and (R[I] <= 126) then
      AFirmware := AFirmware + Chr(R[I])
    else
    begin
      if AFirmware <> '' then AFirmware := AFirmware + ' ';
      AFirmware := AFirmware + IntToHex(R[I], 2);
    end;
  end;
end;

function TRFIDReaderService.GetReaderUID(out AUID: string): Boolean;
var
  R: TBytes;
begin
  AUID := '';
  Result := SendCommand($05, [], R, 1000);
  if Result then
    AUID := BytesToHex(Copy(R, 4, PayloadLength(R)));
end;

function TRFIDReaderService.ParseUIDFromActivate(const ATelegram: TBytes; out AUID: string): Boolean;
var
  ULen, I, P: Integer;
begin
  Result := False;
  AUID := '';
  if (Length(ATelegram) < 10) or (ATelegram[0] <> $50) or (ATelegram[3] <> $22) then Exit;
  P := 4;
  Inc(P, 2); // ATQ
  Inc(P, 1); // SAK
  ULen := ATelegram[P];
  Inc(P);
  if (ULen <= 0) or (P + ULen > Length(ATelegram) - 1) then Exit;
  for I := 0 to ULen - 1 do
  begin
    if AUID <> '' then AUID := AUID + '';
    AUID := AUID + IntToHex(ATelegram[P + I], 2);
  end;
  Result := True;
end;

function TRFIDReaderService.ActivateCard(out AUID: string): Boolean;
var
  R: TBytes;
begin
  AUID := '';
  Result := SendCommand($22, [$10, $26], R, 1000);
  if Result then
    Result := ParseUIDFromActivate(R, AUID);
  if Result then
    SetLastTag(AUID, 'ISO14443A');
end;

function TRFIDReaderService.StartAutoList(AIntervalMS: Byte; AOnlyEnter: Boolean): Boolean;
var
  R: TBytes;
  NotifyMode: Byte;
begin
  if Assigned(FThread) then
  begin
    Result := True;
    Exit;
  end;

  NotifyMode := $01;
  if not AOnlyEnter then
    NotifyMode := $04;

  // FF = alle Tagtypen, Intervall, Antenne 00, Modus, Reserved 00
  Result := SendCommand($23, [$FF, AIntervalMS, $00, NotifyMode, $00], R, 1000);
  if Result then
    FThread := TRFIDReaderThread.Create(Self);
end;

function TRFIDReaderService.StopAutoList: Boolean;
var
  R: TBytes;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  Result := SendCommand($23, [$FF, $00, $01, $01, $00], R, 1000);
end;

function TRFIDReaderService.ParseUIDFromAutolist(const ATelegram: TBytes; out AUID, ATagType: string): Boolean;
var
  TagByte, ULen, I, P: Integer;
begin
  Result := False;
  AUID := '';
  ATagType := '';
  if (Length(ATelegram) < 8) or (ATelegram[0] <> $50) or (ATelegram[3] <> $23) then Exit;

  TagByte := ATelegram[4];
  case TagByte of
    $01: ATagType := 'ISO14443A';
    $04: ATagType := 'ISO15693';
  else
    ATagType := 'Typ ' + IntToHex(TagByte, 2);
  end;

  if TagByte = $01 then
  begin
    P := 9; // ATQ ab 9, SAK 11, UID-Len 12
    if Length(ATelegram) < 14 then Exit;
    Inc(P, 2); // ATQ
    Inc(P, 1); // SAK
    ULen := ATelegram[P];
    Inc(P);
  end
  else if TagByte = $04 then
  begin
    P := 9;
    ULen := 8;
  end
  else Exit;

  if P + ULen > Length(ATelegram) - 1 then Exit;
  for I := 0 to ULen - 1 do
    AUID := AUID + IntToHex(ATelegram[P + I], 2);
  Result := AUID <> '';
end;

procedure TRFIDReaderService.SetLastTag(const AUID, ATagType: string);
begin
  FLastUID := AUID;
  FLastTagType := ATagType;
  if Assigned(FOnTag) then
    FOnTag(Self, AUID, ATagType);
end;

function TRFIDReaderService.PiccTransfer(const APiccCommand: array of Byte; out AReplyPayload: TBytes): Boolean;
var
  R: TBytes;
  I, L: Integer;
begin
  SetLength(AReplyPayload, 0);
  Result := SendCommand($2E, APiccCommand, R, 1000);
  if not Result then Exit;
  L := PayloadLength(R);
  SetLength(AReplyPayload, L);
  for I := 0 to L - 1 do
    AReplyPayload[I] := R[4 + I];
end;

function TRFIDReaderService.NTagGetVersion(out AVersionHex: string): Boolean;
var
  P: TBytes;
begin
  Result := PiccTransfer([$60], P);
  AVersionHex := BytesToHex(P);
end;

function TRFIDReaderService.NTagPwdAuth(const APwd: array of Byte; out APackHex: string): Boolean;
var
  P: TBytes;
begin
  APackHex := '';
  if Length(APwd) <> 4 then
  begin
    FLastError := 'PWD_AUTH benötigt 4 Bytes Passwort';
    Result := False;
    Exit;
  end;
  Result := PiccTransfer([$1B, APwd[0], APwd[1], APwd[2], APwd[3]], P);
  if Result then
    APackHex := BytesToHex(P);
end;

function TRFIDReaderService.NTagReadPage(APage: Byte; out A16Bytes: TBytes): Boolean;
begin
  // NTAG READ: 0x30 + Page, Antwort = 16 Bytes ab Page
  Result := PiccTransfer([$30, APage], A16Bytes);
end;

function TRFIDReaderService.NTagWritePage(APage: Byte; const A4Bytes: array of Byte): Boolean;
var
  P: TBytes;
begin
  if Length(A4Bytes) <> 4 then
  begin
    FLastError := 'NTAG WritePage benötigt exakt 4 Bytes';
    Result := False;
    Exit;
  end;
  // NTAG WRITE: 0xA2 + Page + 4 Datenbytes
  Result := PiccTransfer([$A2, APage, A4Bytes[0], A4Bytes[1], A4Bytes[2], A4Bytes[3]], P);
end;

end.
