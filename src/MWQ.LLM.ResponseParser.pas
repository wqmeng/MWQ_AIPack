unit MWQ.LLM.ResponseParser;

interface

uses
  System.SysUtils,
  MWQ.LLM.Types;

type
  TLLMResponseParser = class
  private
    class function JsonUnescape(const S: string): string; static;
    class function ExtractError(const Text: string; var ErrorMsg: string): Boolean; static;
  public
    class function Parse(
        const ModelInfo: TLLMModelInfo;
        const Raw: string;
        const AEndPoint: TEndpointFlavor;
        var ResultContent: string;
        var ErrorMsg: string
    ): Boolean; static;
  end;

implementation
uses
  System.Classes,
  Neslib.Json;

{------------------------------------------------------------------------------}
{ JSON unescape }
{------------------------------------------------------------------------------}
class function TLLMResponseParser.JsonUnescape(const S: string): string;
begin
  Result :=
      S
          .Replace('\n', #10, [rfReplaceAll])
          .Replace('\r', #13, [rfReplaceAll])
          .Replace('\"', '"', [rfReplaceAll])
          .Replace('\\', '\', [rfReplaceAll]);
end;

class function TLLMResponseParser.ExtractError(const Text: string; var ErrorMsg: string): Boolean;
var
  Doc: IJsonDocument;
  ErrObj: TJsonValue;
begin
  Result := False;
  ErrorMsg := '';

  if Text = '' then
    Exit;

  Doc := TJsonDocument.Parse(Text);
  try
    if Doc.Root.TryGetValue('error', ErrObj) then begin
      if ErrObj.IsDictionary then
        ErrorMsg := ErrObj.Values['message']
      else
        ErrorMsg := ErrObj.ToString;

      Result := True;
    end;
  finally
    Doc := nil;
  end;
end;

class function TLLMResponseParser.Parse(
    const ModelInfo: TLLMModelInfo;
    const Raw: string;
    const AEndPoint: TEndpointFlavor;
    var ResultContent: string;
    var ErrorMsg: string
): Boolean;
var
  Doc: IJsonDocument;
  Root, Choices, Choice0, Msg, LVal: TJsonValue;
begin
  ResultContent := '';
  ErrorMsg := '';

  if Raw = '' then begin
    ErrorMsg := 'Empty response';
    Exit(False);
  end;

  // ------------------------------------
  // 1. Try parse error first
  // ------------------------------------
  if ExtractError(Raw, ErrorMsg) then
    Exit(False);

  try
    Doc := TJsonDocument.Parse(Raw);
    Root := Doc.Root;

    // ------------------------------------
    // OpenAI / LM Studio / Ollama chat format
    // ------------------------------------
    if Root.TryGetValue('choices', Choices) then begin
      if Choices.IsArray and (Choices.Count > 0) then begin
        Choice0 := Choices.Items[0];

        if Choice0.TryGetValue('message', Msg) then begin
          if Msg.TryGetValue('content', LVal) then
            ResultContent := LVal.ToString;
        end;
      end;
    end

    // ------------------------------------
    // llama.cpp / raw chat format
    // ------------------------------------
    else if Root.TryGetValue('message', Msg) then begin
      if Msg.TryGetValue('content', LVal) then
        ResultContent := LVal.ToString;;
    end

    // ------------------------------------
    // generate format (Ollama / raw completion)
    // ------------------------------------
    else if Root.TryGetValue('response', LVal) then
      ResultContent := LVal.ToString
    else if Root.TryGetValue('content', LVal) then
      ResultContent := LVal.ToString;

  except
    on E: Exception do begin
      ErrorMsg := 'Parse error: ' + E.Message;
      Exit(False);
    end;
  end;

  ResultContent := Trim(ResultContent);

  if ResultContent = '' then begin
    ErrorMsg := 'Empty content in response';
    Exit(False);
  end;

  // FIX: decode escape sequences
  ResultContent := JsonUnescape(ResultContent);

  Result := True;
end;

end.
