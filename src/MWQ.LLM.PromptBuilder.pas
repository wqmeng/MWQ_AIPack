unit MWQ.LLM.PromptBuilder;

interface

uses
  System.SysUtils,
  Spring.Collections,
  MWQ.LLM.Types;

type
  TMessagePair = TPair<string, string>;
  TMessageArray = TArray<TMessagePair>;

  TLLMPromptBuilder = class
  public
    // escaping
    class function JsonEscape(const S: string): string; static;

    class function BuildGenerate(const AModel, APrompt: string;
      AStream: Boolean): string; static;
    class function BuildChat(const AModel: string; const AMsg: TMessageArray;
      AStream: Boolean): string; static;
    // generic payloads (OpenAI-style = universal)
    class function BuildOpenAIChat(
      const AModel: string;
      const AMsg: TMessageArray;
      AStream: Boolean;
      MaxTokens: Integer = 256;
      Temperature: Double = 0.0
    ): string; static;


    // simple completion (llama.cpp / raw)
    class function BuildCompletion(
      const AModel, APrompt: string;
      AStream: Boolean
    ): string; static;

    // templates
    class function BuildRivaPrompt(const Sys, User: string): string; static;
    class function BuildInstruction(const Instruction, InputText: string): string; static;

    // dispatcher (core entry)
    class function BuildPayload(
      AFlavor: TEndpointFlavor;
      const AModel: string;
      const AMessages: TMessageArray;
      const SysPrompt, UserPrompt: string;
      AStream: Boolean
    ): string; static;

    // helpers
    class function MakeMessages(const ARolesAndContents: array of string): TMessageArray; static;
//    class function DetectPromptProfile(const AModel: string): TPromptProfile; static;

    class function BuildTranslatePrompt(
      AModelInfo: TLLMModelInfo;
      const AText, ASrcCode, ADstCode, ASrcName, ADstName: string
    ): string; static;

    class function BuildTranslateGemmaPayload(const AModel, Text, SrcCode,
      DstCode: string): string; static;
  end;

implementation

uses
  System.JSON;

{------------------------------------------------------------------------------}
{ JsonEscape }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.JsonEscape(const S: string): string;
var
  i: Integer;
  C: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      '/': Result := Result + '\/';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

class function TLLMPromptBuilder.BuildChat(
    const AModel: string;
    const AMsg: TMessageArray;
    AStream: Boolean
): string;
var
  I: Integer;
  MsgStr: string;
begin
  MsgStr := '';

  for I := 0 to High(AMsg) do begin
    if I > 0 then
      MsgStr := MsgStr + ',';
    MsgStr :=
        MsgStr
            + '{'
            + '"role":"'
            + JsonEscape(AMsg[I].Key)
            + '",'
            + '"content":"'
            + JsonEscape(AMsg[I].Value)
            + '"'
            + '}';
  end;

  Result :=
      '{'
          + '"model":"'
          + JsonEscape(AModel)
          + '",'
          + '"messages":['
          + MsgStr
          + '],'
          + '"stream":'
          + BoolToStr(AStream, True).ToLower
          + '}';
end;

{------------------------------------------------------------------------------}
{ \\ BuildGenerate:  { "model":"...", "prompt":"..." }
{------------------------------------------------------------------------------}

class function TLLMPromptBuilder.BuildGenerate(const AModel, APrompt: string; AStream: Boolean): string;
begin
  Result :=
      '{'
          + '"model":"'
          + JsonEscape(AModel)
          + '",'
          + '"prompt":"'
          + JsonEscape(APrompt)
          + '",'
          + '"stream":'
          + BoolToStr(AStream, True).ToLower
          + '}';
end;

{------------------------------------------------------------------------------}
{ OpenAI Chat (works for LM Studio + Ollama + many others) }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.BuildOpenAIChat(
  const AModel: string;
  const AMsg: TMessageArray;
  AStream: Boolean;
  MaxTokens: Integer;
  Temperature: Double
): string;
var
  I: Integer;
  M: string;
begin
  M := '';
  for I := 0 to High(AMsg) do
  begin
    if I > 0 then
      M := M + ',';
    M := M + '{"role":"' + JsonEscape(AMsg[I].Key) +
         '","content":"' + JsonEscape(AMsg[I].Value) + '"}';
  end;

  Result :=
    '{'
    + '"model":"' + JsonEscape(AModel) + '",'
    + '"messages":[' + M + '],'
    + '"max_tokens":' + IntToStr(MaxTokens) + ','
    + '"temperature":' + FormatFloat('0.0', Temperature) + ','
    + '"stream":' + BoolToStr(AStream, True).ToLower
    + '}';
end;

{------------------------------------------------------------------------------}
{ Completion (llama.cpp style) }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.BuildCompletion(
  const AModel, APrompt: string;
  AStream: Boolean
): string;
begin
  Result :=
    '{'
    + '"model":"' + JsonEscape(AModel) + '",'
    + '"prompt":"' + JsonEscape(APrompt) + '",'
    + '"stream":' + BoolToStr(AStream, True).ToLower
    + '}';
end;

{------------------------------------------------------------------------------}
{ Templates }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.BuildRivaPrompt(const Sys, User: string): string;
begin
  Result := '<s>System' + #10 + Sys + '</s>' + #10 +
            '<s>User' + #10 + User + '</s>' + #10 +
            '<s>Assistant' + #10;
end;

class function TLLMPromptBuilder.BuildInstruction(const Instruction, InputText: string): string;
begin
  Result :=
    '### Instruction:' + #10 + Instruction + #10#10 +
    '### Input:' + #10 + InputText + #10#10 +
    '### Response:' + #10;
end;

{------------------------------------------------------------------------------}
{ Dispatcher }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.BuildPayload(
  AFlavor: TEndpointFlavor;
  const AModel: string;
  const AMessages: TMessageArray;
  const SysPrompt, UserPrompt: string;
  AStream: Boolean
): string;
var
  P: string;
  Msgs: TMessageArray;
begin
  case AFlavor of

    efGenerate:
    begin
      P := SysPrompt + sLineBreak + UserPrompt;
      Exit(BuildCompletion(AModel, P, AStream));
    end;

    efChat, efOpenAIChat:
    begin
      if Length(AMessages) = 0 then
        Msgs := MakeMessages(['system', SysPrompt, 'user', UserPrompt])
      else
        Msgs := AMessages;

      Exit(BuildOpenAIChat(AModel, Msgs, AStream));
    end;

    efInstruction:
    begin
      P := BuildInstruction(SysPrompt, UserPrompt);
      Msgs := MakeMessages(['user', P]);
      Exit(BuildOpenAIChat(AModel, Msgs, AStream));
    end;

    efStructured:
    begin
      // used for models like TranslateGemma
      Msgs := MakeMessages(['user', UserPrompt]);
      Exit(BuildOpenAIChat(AModel, Msgs, AStream));
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
class function TLLMPromptBuilder.MakeMessages(const ARolesAndContents: array of string): TMessageArray;
var
  Count, I: Integer;
begin
  Count := Length(ARolesAndContents) div 2;
  SetLength(Result, Count);

  for I := 0 to Count - 1 do
    Result[I] := TMessagePair.Create(
      ARolesAndContents[I * 2],
      ARolesAndContents[I * 2 + 1]
    );
end;

{------------------------------------------------------------------------------}
{ Profile Detection }
{------------------------------------------------------------------------------}
//class function TLLMPromptBuilder.DetectPromptProfile(const AModel: string): TPromptProfile;
//var
//  L: string;
//begin
//  L := AModel.ToLower;
//
//  if L.Contains('translategemma') then
//    Exit(ppTranslateGemma);
//
//  if L.Contains('riva') then
//    Exit(ppRiva);
//
//  Result := ppGeneric;
//end;

{------------------------------------------------------------------------------}
{ Translate Prompt Builder }
{------------------------------------------------------------------------------}
class function TLLMPromptBuilder.BuildTranslatePrompt(
  AModelInfo: TLLMModelInfo;
  const AText, ASrcCode, ADstCode, ASrcName, ADstName: string
): string;
begin
  // --------------------------------------------------
  // 1. Translate-capable modern models (Gemma / Qwen / etc)
  // --------------------------------------------------
  if lcTranslate in AModelInfo.Capabilities then
  begin
    // Special case: TranslateGemma-style prompt (strict format matters)
    if SameText(AModelInfo.Family, 'translategemma') then
    begin
      Result :=
        Format(
          'You are a professional %s (%s) to %s (%s) translator.%s' +
          'Your goal is to accurately convey meaning and nuance.%s' +
          'Produce only the %s translation, without any explanations.%s%s%s',
          [
            ASrcName, ASrcCode,
            ADstName, ADstCode,
            sLineBreak,
            sLineBreak,
            ADstName,
            sLineBreak,
            sLineBreak,
            AText
          ]
        );
      Exit;
    end;

    // Generic translate-capable LLM (Qwen, Llama3, etc)
    Result :=
      Format(
        'Translate from %s (%s) to %s (%s).%s' +
        'Output ONLY the translation, no explanations.%s%s',
        [
          ASrcName, ASrcCode,
          ADstName, ADstCode,
          sLineBreak,
          sLineBreak,
          AText
        ]
      );
    Exit;
  end;

  // --------------------------------------------------
  // 2. Riva-style models (legacy / pipeline models)
  // --------------------------------------------------
  if SameText(AModelInfo.Family, 'riva') then
  begin
    Result :=
      Format(
        'Translate from %s to %s:%s%s',
        [
          ASrcName,
          ADstName,
          sLineBreak,
          AText
        ]
      );
    Exit;
  end;

  // --------------------------------------------------
  // 3. Fallback generic instruction
  // --------------------------------------------------
  Result :=
    Format(
      'Translate from %s to %s.%sOutput only the translation.%s%s',
      [
        ASrcName,
        ADstName,
        sLineBreak,
        sLineBreak,
        AText
      ]
    );
end;

class function TLLMPromptBuilder.BuildTranslateGemmaPayload(
  const AModel, Text, SrcCode, DstCode: string
): string;
var
  prompt: string;
begin
  prompt :=
    SrcCode + '¡ú' + DstCode + ':' + Text;

  Result :=
    '{' +
      '"model":"' + JsonEscape(AModel) + '",' +
      '"messages":[{' +
        '"role":"user",' +
        '"content":"' + JsonEscape(prompt) + '"' +
      '}],' +
      '"max_tokens":512,' +
      '"temperature":0.0,' +
      '"stream":false' +
    '}';
end;

end.
