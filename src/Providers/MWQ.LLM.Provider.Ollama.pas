unit MWQ.LLM.Provider.Ollama;

interface

uses
  System.SysUtils,
  Spring.Collections,
  MWQ.LLM.Types,
  MWQ.LLM.Provider,
  MWQ.LLM.Manager;

type
  TLLMProviderOllama = class(TBaseLLMProvider)
  public
    constructor Create(const AOwner: TObject); override;
    destructor Destroy; override;

    function SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean; override;

    function Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult; override;

    function Chat(
        const AModel: string;
        const AMessages: TArray<TPair<string, string>>;
        AFlavor: TEndpointFlavor
    ): TLLMResult; override;

    function Generate(const AModel: string; const APrompt: string; AFlavor: TEndpointFlavor): TLLMResult; override;

    function Translate(
        const AModel: string;
        const Text, SrcCode, DstCode, SrcName, DstName: string
    ): TLLMResult; override;

    function GetModels: TArray<string>; override;
  end;

implementation

uses
  System.Net.HttpClient,
  System.Classes,
  MWQ.LLM.PromptBuilder,
  MWQ.LLM.ResponseParser,
  MWQ.LLM.ModelDetector,
  MWQ.LLM.Provider.Factory,
  Neslib.Json,
  Quick.Logger;

{------------------------------------------------------------------------------}
function TLLMProviderOllama.SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean;
begin
  Result := AFlavor in [efGenerate, efChat, efOpenAIChat, efEmbeddings];
end;

constructor TLLMProviderOllama.Create(const AOwner: TObject);
begin
  inherited;
  FName := 'ollama';
  FBaseURL := 'http://localhost:11434';
  TLLMManager(AOwner).AddProvider(Self);
end;

destructor TLLMProviderOllama.Destroy;
begin
  FName := '';
  inherited;
end;

{------------------------------------------------------------------------------}
function TLLMProviderOllama.Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult;
begin
  Result := InternalExecute(AModel, APayload, AFlavor);
end;

{------------------------------------------------------------------------------}
function TLLMProviderOllama.Chat(
    const AModel: string;
    const AMessages: TArray<TPair<string, string>>;
    AFlavor: TEndpointFlavor
): TLLMResult;
var
  Payload: string;
  RawResult: TLLMResult;
  ModelInfo: TLLMModelInfo;
  Content, Err: string;
begin
  Result := TLLMResult.Fail('');

  // ---------------------------------
  // 1. build payload
  // ---------------------------------
  Payload := TLLMPromptBuilder.BuildChat(AModel, AMessages, False);

  // ---------------------------------
  // 2. call provider
  // ---------------------------------
  RawResult := InternalExecute(AModel, Payload, efChat);

  Result.Raw := RawResult.Raw;
  Result.StatusCode := RawResult.StatusCode;

  if not RawResult.Success then
  begin
    Result.ErrorMsg := RawResult.ErrorMsg;
    Exit;
  end;

  // ---------------------------------
  // 3. detect model
  // ---------------------------------
  ModelInfo := TLLMModelDetector.DetectModel(AModel);

  // ---------------------------------
  // 4. parse response
  // ---------------------------------
  if not TLLMResponseParser.Parse(
      ModelInfo,
      RawResult.Raw,
      efChat,
      Content,
      Err
  ) then
  begin
    Result.Success := False;
    Result.ErrorMsg := Err;
    Exit;
  end;

  // ---------------------------------
  // 5. success
  // ---------------------------------
  Result.Success := True;
  Result.Content := Content;
  Result.ErrorMsg := '';
end;

function TLLMProviderOllama.Generate(
  const AModel: string;
  const APrompt: string;
  AFlavor: TEndpointFlavor
): TLLMResult;
var
  Payload: string;
  RawResult: TLLMResult;
  ModelInfo: TLLMModelInfo;
  Content, Err: string;
begin
  Result := TLLMResult.Fail('');

  // ---------------------------------
  // 1. build payload (generate style)
  // ---------------------------------
  Payload := TLLMPromptBuilder.BuildGenerate(AModel, APrompt, False);

  // ---------------------------------
  // 2. execute
  // ---------------------------------
  RawResult := InternalExecute(AModel, Payload, efGenerate);

  Result.Raw := RawResult.Raw;
  Result.StatusCode := RawResult.StatusCode;

  if not RawResult.Success then
  begin
    Result.ErrorMsg := RawResult.ErrorMsg;
    Exit;
  end;

  // ---------------------------------
  // 3. detect model
  // ---------------------------------
  ModelInfo := TLLMModelDetector.DetectModel(AModel);

  // ---------------------------------
  // 4. parse response
  // ---------------------------------
  if not TLLMResponseParser.Parse(
      ModelInfo,
      RawResult.Raw,
      efGenerate,
      Content,
      Err
  ) then
  begin
    Result.Success := False;
    Result.ErrorMsg := Err;
    Exit;
  end;

  // ---------------------------------
  // 5. success
  // ---------------------------------
  Result.Success := True;
  Result.Content := Content;
  Result.ErrorMsg := '';
end;

function TLLMProviderOllama.GetModels: TArray<string>;
var
  Client: THttpClient;
  Resp: IHTTPResponse;
  doc: IJsonDocument;
  JsonArr, Item: TJsonValue;
  I: Integer;
begin
  SetLength(Result, 0);

  Client := THttpClient.Create;
  try
    try
      Resp := Client.Get(FBaseURL + '/api/tags');

      if (Resp = nil) or (Resp.StatusCode <> 200) then
        Exit;

      doc := TJsonDocument.Parse(Resp.ContentAsString);
      try
        if doc = nil then
          Exit;
        if doc.root.TryGetValue('models', JsonArr) then begin
          SetLength(Result, JsonArr.Count);

          for I := 0 to JsonArr.Count - 1 do begin
            Item := JsonArr[I];
            if not Item.IsNull then begin
              if Item.TryGetValue('name', Item) then
                Result[I] := Item.ToString();
            end;
          end;
        end;

      finally
        doc := nil;
      end;
    except
      // ignore
    end;
  finally
    Client.Free;
  end;
end;

function TLLMProviderOllama.Translate(
    const AModel: string;
    const Text, SrcCode, DstCode, SrcName, DstName: string
): TLLMResult;
var
  Prompt, Payload: string;
  Raw: TLLMResult;
  ModelInfo: TLLMModelInfo;
  Endpoint: TEndpointFlavor;
  Content, Err: string;
begin
  Result := TLLMResult.Fail('');

  ModelInfo := TLLMModelDetector.DetectModel(AModel);

  // --------------------------------------------------
  // 1. choose endpoint
  // --------------------------------------------------
  if SameText(ModelInfo.Family, 'translategemma') then
    Endpoint := efChat
  else
    Endpoint := efGenerate;

  // --------------------------------------------------
  // 2. build prompt
  // --------------------------------------------------
  Prompt := TLLMPromptBuilder.BuildTranslatePrompt(
    ModelInfo,
    Text,
    SrcCode,
    DstCode,
    SrcName,
    DstName
  );

  // --------------------------------------------------
  // 3. build payload
  // --------------------------------------------------
  case Endpoint of

    efGenerate:
      Payload := TLLMPromptBuilder.BuildPayload(
        efGenerate,
        AModel,
        nil,
        '',
        Prompt,
        False
      );

    efChat:
      Payload := TLLMPromptBuilder.BuildPayload(
        efChat,
        AModel,
        TLLMPromptBuilder.MakeMessages(['user', Prompt]),
        '',
        '',
        False
      );

  else
    Exit(TLLMResult.Fail('Unsupported endpoint'));
  end;

  // --------------------------------------------------
  // 4. execute
  // --------------------------------------------------
  Raw := InternalExecute(AModel, Payload, Endpoint);

  Result.Raw := Raw.Raw;
  Result.StatusCode := Raw.StatusCode;

  if not Raw.Success then
  begin
    Result := Raw;
    Exit;
  end;

  // --------------------------------------------------
  // 5. parse
  // --------------------------------------------------
  if not TLLMResponseParser.Parse(
      ModelInfo,
      Raw.Raw,
      Endpoint,
      Content,
      Err
  ) then
  begin
    Result := TLLMResult.Fail(Err);
    Exit;
  end;

  Result.Success := True;
  Result.Content := Content;
  Result.ErrorMsg := '';
  Result.Raw := Raw.Raw;
  Result.StatusCode := Raw.StatusCode;
end;

initialization
  TLLMProviderFactory.RegisterProvider('ollama', TLLMProviderOllama);
end.
