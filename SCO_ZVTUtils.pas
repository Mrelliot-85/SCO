unit SCO_ZVTUtils;

interface

uses
  System.Classes;

function ResolveZVTExePath(out TriedPaths: string): string;

implementation

uses
  System.SysUtils, Winapi.Windows, System.Win.Registry, SCO_CONFIG;

function AddTried(const Current, Value: string): string;
begin
  Result := Current;
  if Trim(Value) = '' then
    Exit;
  if Result <> '' then
    Result := Result + sLineBreak;
  Result := Result + Value;
end;

function RegistryZVTPath: string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\GUB\ZVT', False) then
    begin
      if Reg.ValueExists('START') then
        Result := Trim(Reg.ReadString('START'));
      if (Result = '') and Reg.ValueExists('START_UPDATE') then
        Result := Trim(Reg.ReadString('START_UPDATE'));
    end;
  finally
    Reg.Free;
  end;
end;

function ResolveZVTExePath(out TriedPaths: string): string;
var
  Candidates: TStringList;
  I: Integer;
  P: string;
begin
  Result := '';
  TriedPaths := '';
  Candidates := TStringList.Create;
  try
    Candidates.Duplicates := dupIgnore;
    Candidates.Sorted := False;
    if Trim(SCOConfig.ZVT_ExePath) <> '' then
      Candidates.Add(Trim(SCOConfig.ZVT_ExePath));
    P := RegistryZVTPath;
    if P <> '' then
      Candidates.Add(P);
    Candidates.Add(ExtractFilePath(ParamStr(0)) + 'EasyZVT.exe');
    Candidates.Add('C:\Foodware\EasyZVT.exe');

    for I := 0 to Candidates.Count - 1 do
    begin
      P := Trim(Candidates[I]);
      TriedPaths := AddTried(TriedPaths, P);
      if FileExists(P) then
      begin
        Result := P;
        Exit;
      end;
    end;

    if Candidates.Count > 0 then
      Result := Trim(Candidates[0])
    else
      Result := ExtractFilePath(ParamStr(0)) + 'EasyZVT.exe';
  finally
    Candidates.Free;
  end;
end;

end.

