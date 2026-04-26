unit MWQ.LLM.ModelDetector;

interface

uses
  System.SysUtils,
  MWQ.LLM.Types;

type
  TLLMModelDetector = class
  public
    class function DetectModel(const Name: string): TLLMModelInfo; static;
  end;

implementation

{------------------------------------------------------------------------------}
{ DetectModelType }
{------------------------------------------------------------------------------}

class function TLLMModelDetector.DetectModel(const Name: string): TLLMModelInfo;
begin
  Result.RawName := Name.ToLower;

  if Result.RawName.Contains('translategemma') then begin
    Result.Family := 'translategemma';
    Result.IsTranslator := True;
    Result.Capabilities := [lcTranslate];
  end
  else if Result.RawName.Contains('gemma') then begin
    Result.Family := 'gemma';
    Result.IsTranslator := True;
    Result.Capabilities := [lcTranslate, lcChat, lcVision];
  end
  else if Result.RawName.Contains('llama') then begin
    Result.Family := 'llama';
    Result.IsTranslator := True;
    Result.Capabilities := [lcTranslate, lcChat, lcVision];
  end
  else if Result.RawName.Contains('qwen') then
    Result.Family := 'qwen'
  else
    Result.Family := 'generic';
end;

end.
