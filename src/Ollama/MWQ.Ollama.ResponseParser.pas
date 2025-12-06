unit MWQ.Ollama.ResponseParser;

interface

uses
  System.SysUtils, MWQ.Ollama.Types;

type
  TOllamaResponseParser = class
  private
    class function ExtractJSONValue(const Text, Key: string): string; static;
  public
    class function Parse(
      const Raw: string;
      const AEndPoint: TEndpointFlavor;
      var ResultContent: string
    ): Boolean; static;
  end;

implementation

{ TOllamaResponseParser }

{ Extract the value of a top-level JSON key (string or raw) }
class function TOllamaResponseParser.ExtractJSONValue(const Text, Key: string): string;
var
  P, PStart, PEnd: Integer;
begin
  Result := '';
  P := Pos('"' + Key + '":', Text);
  if P = 0 then Exit;

  P := P + Length(Key) + 3; // skip '"Key":'

  // skip whitespace and opening brace if present
  while (P <= Length(Text)) and (Text[P] in [' ', #9, #10, #13, '{']) do Inc(P);

  // string value
  if (P <= Length(Text)) and (Text[P] = '"') then
  begin
    Inc(P); // skip opening quote
    PStart := P;
    while (P <= Length(Text)) and (Text[P] <> '"') do Inc(P);
    PEnd := P - 1;
    Result := Copy(Text, PStart, PEnd - PStart + 1);
    Exit;
  end;

  // raw value (number, boolean)
  PStart := P;
  while (P <= Length(Text)) and not (Text[P] in [',', '}', ']']) do Inc(P);
  PEnd := P - 1;
  Result := Trim(Copy(Text, PStart, PEnd - PStart + 1));
end;

{ Parse Ollama response by endpoint flavor }
class function TOllamaResponseParser.Parse(
  const Raw: string;
  const AEndPoint: TEndpointFlavor;
  var ResultContent: string
): Boolean;
var
  Temp, S: string;
begin
  ResultContent := '';
  Result := False;
  if Raw = '' then Exit;

  case AEndPoint of
    efGenerate:
      begin
        // top-level 'response' key
        ResultContent := ExtractJSONValue(Raw, 'response');
        Result := ResultContent <> '';
      end;

    efChat:
      begin
        // get first message content: "messages":[{"content":"..."}]
        S := ExtractJSONValue(Raw, 'messages');
        if S <> '' then
        begin
          ResultContent := ExtractJSONValue(S, 'content');
          Result := ResultContent <> '';
        end;
      end;

    efOpenAIChat:
      begin
        // get first choice's message content: "choices":[{"message":{"content":"..."}}]
        S := ExtractJSONValue(Raw, 'choices');
        if S <> '' then
        begin
          Temp := ExtractJSONValue(S, 'message');
          if Temp <> '' then
          begin
            ResultContent := ExtractJSONValue(Temp, 'content');
            Result := ResultContent <> '';
          end;
        end;
      end;

    efRivaTemplate, efInstruction:
      begin
        // template-style responses
        ResultContent := ExtractJSONValue(Raw, 'content');
        Result := ResultContent <> '';
      end;

    efRaw:
      begin
        ResultContent := ExtractJSONValue(Raw, 'content');
        Result := ResultContent <> '';
      end;
  end;
end;

end.

