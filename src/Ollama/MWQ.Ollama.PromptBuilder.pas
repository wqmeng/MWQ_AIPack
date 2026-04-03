unit MWQ.Ollama.PromptBuilder;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  MWQ.Ollama.Types;

type
  TMessagePair = TPair<string, string>;
  TMessageArray = TArray<TMessagePair>;

  TOllamaPromptProfile = (
      oppGeneric, // llama3, mistral, qwen
      oppTranslateGemma, // google/translategemma
      oppRiva // riva-translate
  );

  TOllamaPromptBuilder = class
  private
  public
    // escaping
    class function JsonEscape(const S: string): string; static;

    // simple generate endpoint
    class function BuildGenerate(const AModel, APrompt: string; AStream: Boolean): string; static;

    // chat endpoint
    class function BuildChat(const AModel: string; const AMsg: TMessageArray; AStream: Boolean): string; static;

    // openai style
    class function BuildOpenAIChat(
        const AModel: string;
        const AMsg: TMessageArray;
        AStream: Boolean;
        MaxTokens: Integer = 200;
        Temperature: Double = 0.0
    ): string; static;

    // templates
    class function BuildRivaPrompt(const Sys, User: string): string; static;
    class function BuildOllamaInstruction(const Instruction, InputText: string): string; static;

    // dispatcher
    class function BuildPayload(
        AFlavor: TEndpointFlavor;
        const AModel: string;
        const AMessages: TMessageArray;
        const SysPrompt, UserPrompt: string;
        AStream: Boolean
    ): string; static;

    // helpers
    class function MakeMessages(const ARolesAndContents: array of string): TMessageArray; static;
    class function DetectPromptProfile(const AModel: string): TOllamaPromptProfile; static;
    class function BuildTranslatePrompt(
        AProfile: TOllamaPromptProfile;
        const AText, ASrcCode, ADstCode, ASrcName, ADstName: string
    ): string; static;
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
  for i := 1 to Length(S) do begin
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

{------------------------------------------------------------------------------}
{ \\ BuildGenerate:  { "model":"...", "prompt":"..." }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildGenerate(const AModel, APrompt: string; AStream: Boolean): string;
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
{ \\ BuildChat:  { "model":"...", "messages":[...], "stream":false }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildChat(
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
{ BuildOpenAIChat: /v1/chat/completions }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildOpenAIChat(
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
  for I := 0 to High(AMsg) do begin
    if I > 0 then
      M := M + ',';
    M := M + '{"role":"' + JsonEscape(AMsg[I].Key) + '","content":"' + JsonEscape(AMsg[I].Value) + '"}';
  end;

  Result :=
      '{'
          + '"model":"'
          + JsonEscape(AModel)
          + '",'
          + '"messages":['
          + M
          + '],'
          + '"max_tokens":'
          + IntToStr(MaxTokens)
          + ','
          + '"temperature":'
          + FormatFloat('0.0', Temperature)
          + ','
          + '"stream":'
          + BoolToStr(AStream, True).ToLower
          + '}';
end;

{------------------------------------------------------------------------------}
{ Templates }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildRivaPrompt(const Sys, User: string): string;
begin
  Result := '<s>System' + #10 + Sys + '</s>' + #10 + '<s>User' + #10 + User + '</s>' + #10 + '<s>Assistant' + #10;
end;

class function TOllamaPromptBuilder.BuildOllamaInstruction(const Instruction, InputText: string): string;
begin
  Result :=
      '### Instruction:' + #10 + Instruction + #10#10 + '### Input:' + #10 + InputText + #10#10 + '### Response:' + #10;
end;

{------------------------------------------------------------------------------}
{ Dispatcher }
{------------------------------------------------------------------------------}

class function TOllamaPromptBuilder.BuildPayload(
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

    efGenerate: begin
      P := SysPrompt;
      if P <> '' then
        P := P + #10;
      P := P + UserPrompt;
      Exit(BuildGenerate(AModel, P, AStream));
    end;

    efChat: begin
      if Length(AMessages) = 0 then
        Msgs := MakeMessages(['system', SysPrompt, 'user', UserPrompt])
      else
        Msgs := AMessages;

      Exit(BuildChat(AModel, Msgs, AStream));
    end;

    efOpenAIChat: begin
      if Length(AMessages) = 0 then
        Msgs := MakeMessages(['system', SysPrompt, 'user', UserPrompt])
      else
        Msgs := AMessages;

      Exit(BuildOpenAIChat(AModel, Msgs, AStream, 256, 0.0));
    end;

    efRivaTemplate: begin
      P := BuildRivaPrompt(SysPrompt, UserPrompt);
      Exit(BuildGenerate(AModel, P, AStream));
    end;

    efInstruction: begin
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

class function TOllamaPromptBuilder.MakeMessages(const ARolesAndContents: array of string): TMessageArray;
var
  Count, I: Integer;
begin
  Count := Length(ARolesAndContents) div 2;
  SetLength(Result, Count);

  for I := 0 to Count - 1 do
    Result[I] := TMessagePair.Create(ARolesAndContents[I * 2], ARolesAndContents[I * 2 + 1]);
end;

{------------------------------------------------------------------------------}
{ Model Detector }
{------------------------------------------------------------------------------}

class function TOllamaModelDetector.DetectModelType(const AModel: string): TOllamaModelType;
var
  L: string;
begin
  L := AModel.ToLower;

  // 必须放最前面
  if L.Contains('translategemma') then
    Exit(mtTranslateGemma);

  if L.Contains('qwen') then
    Exit(mtQwen);

  if L.Contains('llama') then
    Exit(mtLlama);

  if L.Contains('mistral') or L.Contains('mixtral') then
    Exit(mtMistral);

  if L.Contains('gemma') then
    Exit(mtGemma);

  if L.Contains('riva-translate') then
    Exit(mtRiva);

  Result := mtGeneric;
end;

class function TOllamaPromptBuilder.DetectPromptProfile(const AModel: string): TOllamaPromptProfile;
var
  MT: TOllamaModelType;
begin
  MT := TOllamaModelDetector.DetectModelType(AModel);

  case MT of
    mtTranslateGemma:
      if AModel.ToLower.Contains('translategemma') then
        Exit(oppTranslateGemma)
      else
        Exit(oppGeneric);

    mtRiva: Exit(oppRiva);

  else
    Exit(oppGeneric);
  end;
end;

class function TOllamaPromptBuilder.BuildTranslatePrompt(
    AProfile: TOllamaPromptProfile;
    const AText, ASrcCode, ADstCode, ASrcName, ADstName: string
): string;
begin
  case AProfile of

    // ----- TranslateGemma -----
    oppTranslateGemma:
      (*
        https://ollama.com/library/translategemma

        Prompt Guide
        Prompt Format

        TranslateGemma expects a single user message with this structure:

        You are a professional {SOURCE_LANG} ({SOURCE_CODE}) to {TARGET_LANG} ({TARGET_CODE}) translator. Your goal is to accurately convey the meaning and nuances of the original {SOURCE_LANG} text while adhering to {TARGET_LANG} grammar, vocabulary, and cultural sensitivities.
        Produce only the {TARGET_LANG} translation, without any additional explanations or commentary. Please translate the following {SOURCE_LANG} text into {TARGET_LANG}:


        {TEXT}

        Important: There are two blank lines before the text to translate.
        Examples
        English to Spanish

        You are a professional English (en) to Spanish (es) translator. Your goal is to accurately convey the meaning and nuances of the original English text while adhering to Spanish grammar, vocabulary, and cultural sensitivities.
        Produce only the Spanish translation, without any additional explanations or commentary. Please translate the following English text into Spanish:


        Hello, how are you?

      *)
      // For Google TranslateGemma, construct a message array
      Result :=
          Format(
              'You are a professional %s (%s) to %s (%s) translator.%s'
                  + 'Your goal is to accurately convey the meaning and nuances of the original %s text '
                  + 'while adhering to %s grammar, vocabulary, and cultural sensitivities.%s'
                  + 'Produce only the %s translation, without any additional explanations or commentary.%s'
                  + 'Please translate the following %s text into %s:%s%s%s',
              [
                  ASrcName,
                  ASrcCode,
                  ADstName,
                  ADstCode,
                  sLineBreak,
                  ASrcName,
                  ADstName,
                  sLineBreak,
                  ADstName,
                  sLineBreak,
                  ASrcName,
                  ADstName,
                  // THIS IS CRITICAL
                  sLineBreak, // first blank line
                  sLineBreak, // second blank line
                  AText
              ]
          );

    // ----- Riva-style -----
    oppRiva: Result := Format('Translate from %s to %s:%s%s', [ASrcName, ADstName, sLineBreak, AText]);

    // ----- Generic (llama3, mistral, qwen) -----
  else
    Result :=
        Format(
            'Translate from %s to %s.%sOutput ONLY the translation, no explanations.%s%s',
            [ASrcName, ADstName, sLineBreak, sLineBreak, AText]
        );
  end;
end;

end.
