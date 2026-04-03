unit MWQ.Ollama.ResponseParser;

interface

uses
  System.SysUtils,
  MWQ.Ollama.Types;

type
  TOllamaResponseParser = class
  private
    class function ExtractJSONValue(const Text, Key: string): string; static;
  public
    class function Parse(
        const AModelType: TOllamaModelType;
        const Raw: string;
        const AEndPoint: TEndpointFlavor;
        var ResultContent: string
    ): Boolean; static;
  end;

implementation
uses
  MWQ.Ollama.PromptBuilder;

{ TOllamaResponseParser }

{ Extract the value of a top-level JSON key (string or raw) }
class function TOllamaResponseParser.ExtractJSONValue(const Text, Key: string): string;
var
  P, PStart, PEnd: Integer;
begin
  Result := '';
  P := Pos('"' + Key + '":', Text);
  if P = 0 then
    Exit;

  P := P + Length(Key) + 3; // skip '"Key":'

  // skip whitespace and opening brace if present
  while (P <= Length(Text)) and (Text[P] in [' ', #9, #10, #13, '{']) do
    Inc(P);

  // string value
  if (P <= Length(Text)) and (Text[P] = '"') then begin
    Inc(P); // skip opening quote
    PStart := P;
    while (P <= Length(Text)) and (Text[P] <> '"') do
      Inc(P);
    PEnd := P - 1;
    Result := Copy(Text, PStart, PEnd - PStart + 1);
    Exit;
  end;

  // raw value (number, boolean)
  PStart := P;
  while (P <= Length(Text)) and not (Text[P] in [',', '}', ']']) do
    Inc(P);
  PEnd := P - 1;
  Result := Trim(Copy(Text, PStart, PEnd - PStart + 1));
end;

{ Unified Parse: handles multiple models + endpoint flavors }
class function TOllamaResponseParser.Parse(
    const AModelType: TOllamaModelType;
    const Raw: string;
    const AEndPoint: TEndpointFlavor;
    var ResultContent: string
): Boolean;

  function JsonUnescape(const S: string): string;
  begin
    Result :=
        S
            .Replace('\n', #10, [rfReplaceAll])
            .Replace('\r', #13, [rfReplaceAll])
            .Replace('\"', '"', [rfReplaceAll])
            .Replace('\\', '\', [rfReplaceAll]);
  end;

var
  Temp, S: string;
begin
  ResultContent := '';
  Result := False;
  if Raw = '' then
    Exit;

  case AModelType of
    mtLlama:
      case AEndPoint of
        efGenerate: ResultContent := ExtractJSONValue(Raw, 'response'); // Llama3-style
        efChat: begin
          S := ExtractJSONValue(Raw, 'messages');
          if S <> '' then
            ResultContent := ExtractJSONValue(S, 'content');
        end;
        efOpenAIChat: begin
          S := ExtractJSONValue(Raw, 'choices');
          if S <> '' then begin
            Temp := ExtractJSONValue(S, 'message');
            if Temp <> '' then
              ResultContent := ExtractJSONValue(Temp, 'content');
          end;
        end;
      end;
    mtGemma: begin
      S := ExtractJSONValue(Raw, 'response');
      if S <> '' then
        ResultContent := JsonUnescape(S.Trim);
    end;

    mtTranslateGemma: begin
      // Ollama chat format
      S := ExtractJSONValue(Raw, 'content');
      if S <> '' then
        ResultContent := JsonUnescape(S.Trim);
    end;

    mtRiva: begin
      S := ExtractJSONValue(Raw, 'translation');
      if S <> '' then
        ResultContent := JsonUnescape(S.Trim);
    end;
  else
    // generic fallback: try endpoint flavor
    case AEndPoint of
      efGenerate: ResultContent := ExtractJSONValue(Raw, 'response');
      efChat: begin
        S := ExtractJSONValue(Raw, 'messages');
        if S <> '' then
          ResultContent := ExtractJSONValue(S, 'content');
      end;
      efOpenAIChat: begin
        S := ExtractJSONValue(Raw, 'choices');
        if S <> '' then begin
          Temp := ExtractJSONValue(S, 'message');
          if Temp <> '' then
            ResultContent := ExtractJSONValue(Temp, 'content');
        end;
      end;
      efRivaTemplate, efInstruction, efRaw: ResultContent := ExtractJSONValue(Raw, 'content');
    end;
  end;

  Result := ResultContent <> '';
end;

end.
