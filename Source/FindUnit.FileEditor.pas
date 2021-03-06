unit FindUnit.FileEditor;

interface

uses
  ToolsApi, SimpleParser.Lexer.Types, DelphiAST.Classes, FindUnit.OtaUtils, Classes, DesignEditors, Graphics,
  FindUnit.Header, FindUnit.FormMessage;

type
  TCharPosition = record
    StartLine: Integer;
    StartPos: Integer;

    EndLine: Integer;
    EndPos: Integer;
  end;

  TFileRegion = class(TObject)
  private
    FSource: IOTASourceEditor;
    FUses: TStringList;
    FUsesPosition: TCharPosition;
    FRegionPosition: TCharPosition;
    FFullFileText: TStringList;

    function RemoveUsesFromList(UsesList: TStrings; ItemToRemove: string): string;

    procedure DeleteInformationFrom(FromLine, ToLine: integer);
    procedure WriteInformationAtPostion(Line, Position: Integer; const Information: string);
  public
    constructor Create(SourceEditor: IOTASourceEditor);
    destructor Destroy; override;

    function HaveUses: Boolean;

    property RegionPosition: TCharPosition read FRegionPosition write FRegionPosition;
    property UsesPosition: TCharPosition read FUsesPosition write FUsesPosition;

    procedure GetUsesFromText(FullFileText: TStringList);
    function UsesExists(UseUnit: string): Boolean;
    procedure RemoveUses(UseUnit: string);
  end;

  TSourceFileEditor = class(TObject)
  private
    FSource: IOTASourceEditor;
    FFileContent: TStringList;
    FInterfaceRegion: TFileRegion;
    FImplementationRegion: TFileRegion;

    procedure ParseInformations;
    function GetInformationsFor(Token: string; SearchForEnd: Boolean; StartLine, EndLine: Integer): TCharPosition;
    procedure GetInfos;

    function AddUsesToRegion(Region: TFileRegion; UseUnit: string): Boolean;
    procedure WriteInformationAtPostion(Line, Position: Integer; const Information: string);
  public
    constructor Create(SourceEditor: IOTASourceEditor);
    destructor Destroy; override;

    function Prepare: Boolean;

    function AddUsesToInterface(const UseUnit: string): Boolean;
    function AddUsesToImplementation(const UseUnit: string): Boolean;

    procedure RemoveUsesFromInterface(const UseUnit: string);
    procedure RemoveUsesFromImplementation(const UseUnit: string);

    function IsLineOnImplementationSection(Line: Integer): Boolean;

    procedure AddUnit(UnitInfo: TStringPosition; ShowMessageOnAdd: Boolean = True);
  end;

implementation

uses
  SysUtils, FindUnit.Utils, RegExpr;

{ TSourceFileEditor }

procedure TSourceFileEditor.AddUnit(UnitInfo: TStringPosition; ShowMessageOnAdd: Boolean);
var
  MessageText: string;
begin
  MessageText := '';
  if IsLineOnImplementationSection(UnitInfo.Line) then
  begin
    if AddUsesToImplementation(UnitInfo.Value) then
      MessageText := 'Unit ' + UnitInfo.Value + ' added to implementation''s uses.';
  end
  else
  begin
    if AddUsesToInterface(UnitInfo.Value) then
      MessageText := 'Unit ' + UnitInfo.Value + ' added to interface''s uses.';
  end;

  if (MessageText <> '') and ShowMessageOnAdd then
    TfrmMessage.ShowInfoToUser(MessageText);
end;

function TSourceFileEditor.AddUsesToImplementation(const UseUnit: string): Boolean;
begin
  RemoveUsesFromInterface(UseUnit);
  Result := AddUsesToRegion(FImplementationRegion, UseUnit);
end;

function TSourceFileEditor.AddUsesToInterface(const UseUnit: string): Boolean;
begin
  RemoveUsesFromImplementation(UseUnit);
  Result := AddUsesToRegion(FInterfaceRegion, UseUnit);
end;

function TSourceFileEditor.AddUsesToRegion(Region: TFileRegion; UseUnit: string): Boolean;
var
  Line: Integer;
  PosChar: Integer;
begin
  Result := False;
  if Region.UsesExists(UseUnit) then
    Exit;

  Result := True;
  Line := Region.UsesPosition.EndLine;
  PosChar := Region.UsesPosition.EndPos -1;
  if not Region.HaveUses then
  begin
    Line := Region.RegionPosition.StartLine + 1;
    PosChar := 0;

    UseUnit := #13#10 + 'uses' + #13#10 + #9 + UseUnit + ';' + #13#10
  end
  else
  begin
    if PosChar > 80 then
      UseUnit := ', ' + #13#10 + '  ' + UseUnit
    else
      UseUnit := ', ' + UseUnit;
  end;

  WriteInformationAtPostion(Line, PosChar, UseUnit);
end;

constructor TSourceFileEditor.Create(SourceEditor: IOTASourceEditor);
begin
  FInterfaceRegion := TFileRegion.Create(SourceEditor);
  FImplementationRegion := TFileRegion.Create(SourceEditor);
  FFileContent := TStringList.Create;
  FSource := SourceEditor;
end;

destructor TSourceFileEditor.Destroy;
begin
  FInterfaceRegion.Destroy;
  FImplementationRegion.Destroy;
  FFileContent.Free;
  inherited;
end;

function TSourceFileEditor.GetInformationsFor(Token: string; SearchForEnd: Boolean; StartLine, EndLine: Integer): TCharPosition;
var
  I: Integer;
  OutPosition: Integer;
  OutLine: Integer;

  function GetPositionOfString(SearchString: string; iStart, IEnd: Integer; out FoundLine, FoundPosition: Integer): Boolean;
  var
    Line: string;
    Position: Integer;
  begin
    Result := False;
    for iStart := iStart to IEnd do
    begin
      Line := UpperCase(FFileContent[iStart]);
      Position := Pos(SearchString, Line);

      if Position  = 0 then
        Continue;

      if (SearchString <> ';')
        and (Length(Line) > Length(SearchString))
        and (Line[Length(Line)] <> '') then
        Continue;

      FoundLine := iStart;
      FoundPosition := Position;
      Result := True;
      Break;
    end;
  end;
begin
  Result.StartLine := -1;
  Token := UpperCase(Token);
  if not GetPositionOfString(Token, StartLine, EndLine, OutLine, OutPosition) then
    Exit;

  Result.StartLine := OutLine;
  Result.StartPos := OutPosition;

  if SearchForEnd then
  begin
    if GetPositionOfString(';', OutLine, EndLine, OutLine, OutPosition) then
    begin
      Result.EndLine := OutLine;
      Result.EndPos := OutPosition;
    end;
  end;
end;

procedure TSourceFileEditor.GetInfos;
var
  InterfaceEnd: Integer;
begin
  FInterfaceRegion.RegionPosition := GetInformationsFor('interface', False, 0, FFileContent.Count -1);
  FImplementationRegion.RegionPosition := GetInformationsFor('implementation', False, 0, FFileContent.Count -1);

  if FImplementationRegion.RegionPosition.StartLine > -1 then
    InterfaceEnd := FImplementationRegion.RegionPosition.StartLine
  else
    InterfaceEnd := FFileContent.Count -1;

  FInterfaceRegion.UsesPosition := GetInformationsFor('uses', True, FInterfaceRegion.RegionPosition.StartLine, InterfaceEnd);

  if FImplementationRegion.RegionPosition.StartLine > -1 then
    FImplementationRegion.UsesPosition := GetInformationsFor('uses', True, FImplementationRegion.RegionPosition.StartLine, FFileContent.Count -1);

  FImplementationRegion.GetUsesFromText(FFileContent);
  FInterfaceRegion.GetUsesFromText(FFileContent);
end;

function TSourceFileEditor.IsLineOnImplementationSection(Line: Integer): Boolean;
begin
  Result := Line > FImplementationRegion.RegionPosition.StartLine;
end;

procedure TSourceFileEditor.ParseInformations;
begin
  GetInfos;
end;

function TSourceFileEditor.Prepare: Boolean;
begin
  try
    Result := True;
    FFileContent.Text := EditorAsString(FSource);
    ParseInformations;
  except
    Result := False;
  end;
end;

procedure TSourceFileEditor.RemoveUsesFromImplementation(const UseUnit: string);
begin
  FImplementationRegion.RemoveUses(UseUnit);
end;

procedure TSourceFileEditor.RemoveUsesFromInterface(const UseUnit: string);
begin
  FInterfaceRegion.RemoveUses(UseUnit);
end;

procedure TSourceFileEditor.WriteInformationAtPostion(Line, Position: Integer; const Information: string);
var
  InfoPosition: TOTACharPos;
  FileWriter: IOTAEditWriter;
  SetPosition: Integer;
begin
  if Information = '' then
    Exit;

  Line := Line + 1;
  InfoPosition.Line := Line;
  InfoPosition.CharIndex := Position;

  SetPosition := FSource.EditViews[0].CharPosToPos(InfoPosition);

  FileWriter := FSource.CreateUndoableWriter;
  try
    FileWriter.CopyTo(SetPosition);
    FileWriter.Insert(PAnsiChar(AnsiString(Information)));
  finally
    FileWriter := nil;
  end;
end;

{ TFileRegion }

procedure TFileRegion.DeleteInformationFrom(FromLine, ToLine: integer);
var
  StartPosition, EndPosition: TOTACharPos;
  FileWriter: IOTAEditWriter;
  StartPos: Integer;
  EndPos: Integer;
begin
  Inc(FromLine);
  StartPosition.Line := FromLine;
  StartPosition.CharIndex := 0;

  Inc(ToLine);
  Inc(ToLine);
  EndPosition.Line := ToLine;
  EndPosition.CharIndex := 0;

  StartPos := FSource.EditViews[0].CharPosToPos(StartPosition);
  EndPos := FSource.EditViews[0].CharPosToPos(EndPosition);

  FileWriter := FSource.CreateUndoableWriter;
  try
    FileWriter.CopyTo(StartPos);
    FileWriter.DeleteTo(EndPos);
  finally
    FileWriter := nil;
  end;
end;

constructor TFileRegion.Create(SourceEditor: IOTASourceEditor);
begin
  FUses := TStringList.Create;
  FUses.Duplicates := dupIgnore;
  FUses.Sorted := True;
  FSource := SourceEditor;
end;

destructor TFileRegion.Destroy;
begin
  FUses.Free;
  inherited;
end;

procedure TFileRegion.GetUsesFromText(FullFileText: TStringList);
var
  I: Integer;
  LocalUses: TStringList;
  Line: string;
  Item: string;
begin
  FFullFileText := FullFileText;
  if not HaveUses then
    Exit;

  LocalUses := TStringList.Create;
  try
    for I := FUsesPosition.StartLine to FUsesPosition.EndLine do
      LocalUses.Add(Trim(FullFileText[I]));

    LocalUses.Text := StringReplace(LocalUses.Text,' ',',', [rfReplaceAll]);
    LocalUses.Text := StringReplace(LocalUses.Text,';',',', [rfReplaceAll]);

    for I := 0 to LocalUses.Count -1 do
    begin
      Line := LocalUses[i];
      while Line <> '' do
      begin
        Item := Fetch(Line, ',');
        FUses.Add(UpperCase(Item));
      end;
    end;
  finally
    LocalUses.Free;
  end;
end;

function TFileRegion.HaveUses: Boolean;
begin
  Result := UsesPosition.StartLine > 0;
end;

procedure TFileRegion.RemoveUses(UseUnit: string);
var
  I: Integer;
  LocalUses: TStringList;
begin
  if not UsesExists(UseUnit) then
    Exit;

  FFullFileText.Text := EditorAsString(ActiveSourceEditor);
  LocalUses := TStringList.Create;
  try
    for I := FUsesPosition.StartLine to FUsesPosition.EndLine do
      LocalUses.Add(FFullFileText[I]);

    LocalUses.Text := RemoveUsesFromList(LocalUses, UseUnit);
    DeleteInformationFrom(FUsesPosition.StartLine, FUsesPosition.EndLine);
    if UpperCase(Trim(LocalUses.Text)) <> 'USES'  then
      WriteInformationAtPostion(FUsesPosition.StartLine, 0, LocalUses.Text);
  finally
    LocalUses.Free;
  end;
end;

function TFileRegion.RemoveUsesFromList(UsesList: TStrings; ItemToRemove: string): string;
const
  Mask = '[^a-zA-Z0-9]%s[^a-zA-Z0-9]';
var
  Regex: TRegExpr;
  MaskFilter: string;
begin
  MaskFilter := Format(Mask, [ItemToRemove]);
  Regex := TRegExpr.Create;
  Regex.Expression := MaskFilter;

  Result :=  Trim(Regex.Replace(UsesList.Text, '', True));
  if Result[Length(Result)] = ',' then
  begin
    Delete(Result, Length(Result), 1);
    Result := Result + ';';
  end;
end;

function TFileRegion.UsesExists(UseUnit: string): Boolean;
begin
  Result := FUses.IndexOf(UpperCase(UseUnit)) > -1;
end;

procedure TFileRegion.WriteInformationAtPostion(Line, Position: Integer; const Information: string);
var
  InfoPosition: TOTACharPos;
  FileWriter: IOTAEditWriter;
  SetPosition: Integer;
begin
  if Information = '' then
    Exit;

  Line := Line + 1;
  InfoPosition.Line := Line;
  InfoPosition.CharIndex := Position;

  SetPosition := FSource.EditViews[0].CharPosToPos(InfoPosition);

  FileWriter := FSource.CreateUndoableWriter;
  try
    FileWriter.CopyTo(SetPosition);
    FileWriter.Insert(PAnsiChar(AnsiString(Information)));
  finally
    FileWriter := nil;
  end;
end;

end.
