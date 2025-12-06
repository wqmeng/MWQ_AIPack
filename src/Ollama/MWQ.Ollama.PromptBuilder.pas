unit MWQ.Ollama.PromptBuilder;

interface

uses
  System.SysUtils, System.Generics.Collections, MWQ.Ollama.Types;

type
  TMessagePair = TPair<string,string>;
  TMessageArray = TArray<TMessagePair>;

  TOllamaPromptBuilder = class
  public
    // escaping
    class function JsonEscape(const S: string): string; static;

    // simple generate endpoint
    class function BuildGenerate(const AModel, APrompt: string; AStream: Boolean): string; static;

    // chat endpoint
    class function BuildChat(const AModel: string; const AMsg: TMessageArray; AStream: Boolean): string; static;

    // openai style
    class function BuildOpenAIChat(const AModel: string; const AMsg: TMessageArray;
      AStream: Boolean; MaxTokens: Integer = 200; Temperature: Double = 0.0): string; static;

    // templates
    class function BuildRivaPrompt(const Sys, User: string): string; static;
    class function BuildOllamaInstruction(const Instruction, InputText: string): string; static;

    // dispatcher
    class function BuildPayload(AFlavor: TEndpointFlavor; const AModel: string;
      const AMessages: TMessageArray; const SysPrompt, UserPrompt: string;
      AStream: Boolean): string; static;

    // helpers
    class function MakeMessages(const ARolesAndContents: array of string): TMessageArray; static;
  end;

  TOllamaModelDetector = class
  public
    class function DetectModelType(const AModel: string): TOllamaModelType;
  end;

implementation

{------------------------------------------------------------------------------}
{ JsonEscape }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.JsonEscape(const S: string): string;
var
  i: Integer;
  C: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case C of
      '"' : Result := Result + '\"';
      '\' : Result := Result + '\\';
      '/' : Result := Result + '\/';
      #8  : Result := Result + '\b';
      #9  : Result := Result + '\t';
      #10 : Result := Result + '\n';
      #12 : Result := Result + '\f';
      #13 : Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C),4)
      else
        Result := Result + C;
    end;
  end;
end;

{------------------------------------------------------------------------------}
{ \\ BuildGenerate:  { "model":"...", "prompt":"..." }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildGenerate(
  const AModel, APrompt: string; AStream: Boolean): string;
begin
  Result :=
    '{' +
      '"model":"' + JsonEscape(AModel) + '",' +
      '"prompt":"' + JsonEscape(APrompt) + '",' +
      '"stream":' + BoolToStr(AStream, True).ToLower +
    '}';
end;

{------------------------------------------------------------------------------}
{ \\ BuildChat:  { "model":"...", "messages":[...], "stream":false }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildChat(
  const AModel: string; const AMsg: TMessageArray; AStream: Boolean): string;
var
  I: Integer;
  MsgStr: string;
begin
  MsgStr := '';

  for I := 0 to High(AMsg) do
  begin
    if I > 0 then MsgStr := MsgStr + ',';
    MsgStr := MsgStr + '{' +
                '"role":"' + JsonEscape(AMsg[I].Key) + '",' +
                '"content":"' + JsonEscape(AMsg[I].Value) + '"' +
               '}';
  end;

  Result :=
    '{' +
      '"model":"' + JsonEscape(AModel) + '",' +
      '"messages":[' + MsgStr + '],' +
      '"stream":' + BoolToStr(AStream, True).ToLower +
    '}';
end;

{------------------------------------------------------------------------------}
{ BuildOpenAIChat: /v1/chat/completions }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildOpenAIChat(
  const AModel: string; const AMsg: TMessageArray;
  AStream: Boolean; MaxTokens: Integer; Temperature: Double): string;
var
  I: Integer;
  M: string;
begin
  M := '';
  for I := 0 to High(AMsg) do
  begin
    if I > 0 then M := M + ',';
    M := M + '{"role":"' + JsonEscape(AMsg[I].Key) +
         '","content":"' + JsonEscape(AMsg[I].Value) + '"}';
  end;

  Result :=
    '{' +
      '"model":"' + JsonEscape(AModel) + '",' +
      '"messages":[' + M + '],' +
      '"max_tokens":' + IntToStr(MaxTokens) + ',' +
      '"temperature":' + FormatFloat('0.0', Temperature) + ',' +
      '"stream":' + BoolToStr(AStream, True).ToLower +
    '}';
end;

{------------------------------------------------------------------------------}
{ Templates }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildRivaPrompt(
  const Sys, User: string): string;
begin
  Result :=
    '<s>System' + #10 +
    Sys + '</s>' + #10 +
    '<s>User' + #10 +
    User + '</s>' + #10 +
    '<s>Assistant' + #10;
end;

class function TOllamaPromptBuilder.BuildOllamaInstruction(
  const Instruction, InputText: string): string;
begin
  Result :=
    '### Instruction:' + #10 +
    Instruction + #10#10 +
    '### Input:' + #10 +
    InputText + #10#10 +
    '### Response:' + #10;
end;

{------------------------------------------------------------------------------}
{ Dispatcher }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildPayload(
  AFlavor: TEndpointFlavor; const AModel: string;
  const AMessages: TMessageArray;
  const SysPrompt, UserPrompt: string; AStream: Boolean): string;
var
  P: string;
  Msgs: TMessageArray;
begin
  case AFlavor of

    efGenerate:
      begin
        P := SysPrompt;
        if P <> '' then P := P + #10;
        P := P + UserPrompt;
        Exit(BuildGenerate(AModel, P, AStream));
      end;

    efChat:
      begin
        if Length(AMessages) = 0 then
          Msgs := MakeMessages(['system', SysPrompt, 'user', UserPrompt])
        else
          Msgs := AMessages;

        Exit(BuildChat(AModel, Msgs, AStream));
      end;

    efOpenAIChat:
      begin
        if Length(AMessages) = 0 then
          Msgs := MakeMessages(['system', SysPrompt, 'user', UserPrompt])
        else
          Msgs := AMessages;

        Exit(BuildOpenAIChat(AModel, Msgs, AStream, 256, 0.0));
      end;

    efRivaTemplate:
      begin
        P := BuildRivaPrompt(SysPrompt, UserPrompt);
        Exit(BuildGenerate(AModel, P, AStream));
      end;

    efInstruction:
      begin
        P := BuildOllamaInstruction(SysPrompt, UserPrompt);
        Msgs := MakeMessages(['user', P]);
        Exit(BuildChat(AModel, Msgs, AStream));
      end;

    efRaw:
      if Length(AMessages) > 0 then
        Exit(AMessages[0].Value)
      else
        Exit('{}');
  end;

  Result := '{}';
end;

{------------------------------------------------------------------------------}
{ Helpers }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.MakeMessages(
  const ARolesAndContents: array of string): TMessageArray;
var
  Count, I: Integer;
begin
  Count := Length(ARolesAndContents) div 2;
  SetLength(Result, Count);

  for I := 0 to Count - 1 do
    Result[I] := TMessagePair.Create(
      ARolesAndContents[I*2],
      ARolesAndContents[I*2 + 1]
    );
end;

{------------------------------------------------------------------------------}
{ Model Detector }
{------------------------------------------------------------------------------}

class function TOllamaModelDetector.DetectModelType(
  const AModel: string): TOllamaModelType;
var
  L: string;
begin
  L := AModel.ToLower;

  if L.Contains('qwen')    then Exit(mtQwen);
  if L.Contains('llama')   then Exit(mtLlama);
  if L.Contains('mistral') or L.Contains('mixtral') then Exit(mtMistral);
  if L.Contains('gemma')   then Exit(mtGemma);
  if L.Contains('riva-translate') then Exit(mtRiva);

  Result := mtGeneric;
end;

end.
