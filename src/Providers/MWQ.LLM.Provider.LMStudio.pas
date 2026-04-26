unit MWQ.LLM.Provider.LMStudio;

interface

uses
  System.SysUtils,
  Spring.Collections,
  System.Net.HttpClient,
  MWQ.LLM.Types,
  MWQ.LLM.Manager,
  MWQ.LLM.Provider;

type
  TLLMProviderLMStudio = class(TBaseLLMProvider)
  public
    constructor Create(const AOwner: TObject); override;
    destructor Destroy; override;

    // ----------------------------
    // Capability
    // ----------------------------
    function SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean; override;

    // ----------------------------
    // Raw Execution
    // ----------------------------
    function Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult; override;

    // ----------------------------
    // Chat
    // ----------------------------
    function Chat(
        const AModel: string;
        const AMessages: TArray<TPair<string, string>>;
        AFlavor: TEndpointFlavor = efOpenAIChat
    ): TLLMResult; override;

    // ----------------------------
    // Generate
    // ----------------------------
    function Generate(
        const AModel: string;
        const APrompt: string;
        AFlavor: TEndpointFlavor = efGenerate
    ): TLLMResult; override;

    // ----------------------------
    // Translate
    // ----------------------------
    function Translate(
        const AModel: string;
        const Text, SrcCode, DstCode, SrcName, DstName: string
    ): TLLMResult; override;

    function GetModels: TArray<string>; override;
  end;

implementation

uses
  MWQ.LLM.PromptBuilder,
  MWQ.LLM.ResponseParser,
  MWQ.LLM.Provider.Factory,
  MWQ.LLM.ModelDetector,
  Neslib.Json,
  Quick.Logger;

{------------------------------------------------------------------------------}
{ Capabilities }
{------------------------------------------------------------------------------}

function TLLMProviderLMStudio.SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean;
begin
  // LM Studio supports OpenAI-style endpoints primarily
  Result := AFlavor in [efOpenAIChat, efGenerate, efChat];
end;

constructor TLLMProviderLMStudio.Create(const AOwner: TObject);
begin
  inherited;
  FName := 'lmstudio';
  FBaseURL := 'http://localhost:1234';
  TLLMManager(AOwner).AddProvider(Self);
end;

destructor TLLMProviderLMStudio.Destroy;
begin
  FName := '';
  inherited;
end;

{------------------------------------------------------------------------------}
{ Execute }
{------------------------------------------------------------------------------}

function TLLMProviderLMStudio.Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult;
begin
  Result := InternalExecute(AModel, APayload, AFlavor);
end;

{------------------------------------------------------------------------------}
{ Chat }
{------------------------------------------------------------------------------}

function TLLMProviderLMStudio.Chat(
    const AModel: string;
    const AMessages: TArray<TPair<string, string>>;
    AFlavor: TEndpointFlavor
): TLLMResult;
var
  Payload: string;
  Raw: TLLMResult;
  Parsed: string;
  ErrorMsg: string;
begin
  Result := TLLMResult.Fail('init');

  // -------------------------
  // 1. Build payload
  // -------------------------
  Payload :=
    TLLMPromptBuilder.BuildOpenAIChat(
      AModel,
      AMessages,
      False,
      512,
      0.0
    );

  // -------------------------
  // 2. Execute (IMPORTANT: returns TLLMResult now)
  // -------------------------
  Raw := InternalExecute(AModel, Payload, efOpenAIChat);

  Result := Raw; // preserve HTTP + raw + error

  // -------------------------
  // 3. Parse
  // -------------------------
  if not TLLMResponseParser.Parse(
        TLLMModelDetector.DetectModel(AModel),
        Raw.Content,
        efOpenAIChat,
        Parsed,
        ErrorMsg
     ) then
  begin
    Result.Success := False;
    Result.ErrorMsg := ErrorMsg;
    Exit;
  end;

  // -------------------------
  // 4. success
  // -------------------------
  Result.Success := True;
  Result.Content := Parsed;
end;

{------------------------------------------------------------------------------}
{ Generate }
{------------------------------------------------------------------------------}

function TLLMProviderLMStudio.Generate(const AModel: string; const APrompt: string; AFlavor: TEndpointFlavor): TLLMResult;
var
  Msgs: TArray<TPair<string, string>>;
begin
  // LM Studio prefers chat format even for completion
  Msgs := TLLMPromptBuilder.MakeMessages(['user', APrompt]);
  Result := Chat(AModel, Msgs, efOpenAIChat);
end;

function TLLMProviderLMStudio.GetModels: TArray<string>;
var
  Client: THttpClient;
  Resp: IHTTPResponse;
  doc: IJsonDocument;
  JsonArr: TJsonValue;
  Item: TJsonValue;
  I: Integer;
  Url: string;
begin
  SetLength(Result, 0);

  Client := THttpClient.Create;
  try
    try
      // Build correct endpoint: /v1/models
      Url := FBaseURL;
      if Url.EndsWith('/') then
        Url := Copy(Url, 1, Length(Url) - 1);

      Url := Url + '/v1/models';

      Resp := Client.Get(Url);
      if (Resp = nil) or (Resp.StatusCode <> 200) then
        Exit;

      doc := TJsonDocument.Parse(Resp.ContentAsString);
      try
        if doc = nil then
          Exit;

        // LM Studio uses OpenAI format: { "data": [...] }
        JsonArr := doc.Root.Values['data'];
        if JsonArr.IsNull then
          Exit;

        SetLength(Result, JsonArr.Count);

        for I := 0 to JsonArr.Count - 1 do begin
          Item := JsonArr.Items[I];
          if not Item.IsNull then begin
            Item := Item.Values['id']; // model name
            Result[I] := Item.ToString();
          end;
        end;

      finally
        doc := nil;
      end;
    except
      // swallow errors, return empty array
    end;
  finally
    Client.Free;
  end;
end;

{------------------------------------------------------------------------------}
{ Translate }
{------------------------------------------------------------------------------}
function TLLMProviderLMStudio.Translate(
    const AModel: string;
    const Text, SrcCode, DstCode, SrcName, DstName: string
): TLLMResult;
var
  Payload: string;
  RawResult: TLLMResult;
  ModelInfo: TLLMModelInfo;
  ParsedContent: string;
  ErrorMsg: string;
begin
  Result := TLLMResult.Fail('init');

  ModelInfo := TLLMModelDetector.DetectModel(AModel);

  // --------------------------------------------------
  // 1. Build Prompt
  // --------------------------------------------------
  if SameText(ModelInfo.Family, 'translategemma') then
  begin
    Payload := TLLMPromptBuilder.BuildTranslateGemmaPayload(
      AModel, Text, SrcCode, DstCode
    );

    RawResult := InternalExecute(AModel, Payload, efOpenAIChat);
  end
  else
  begin
    Payload :=
      TLLMPromptBuilder.BuildPayload(
        efGenerate,
        AModel,
        nil,
        '',
        TLLMPromptBuilder.BuildTranslatePrompt(
          ModelInfo, Text, SrcCode, DstCode, SrcName, DstName
        ),
        False
      );

    RawResult := InternalExecute(AModel, Payload, efGenerate);
  end;

  // --------------------------------------------------
  // 2. Parse (IMPORTANT: now returns full TLLMResult info)
  // --------------------------------------------------
  if not TLLMResponseParser.Parse(
    ModelInfo,
    RawResult.Raw,
    efGenerate,
    ParsedContent,
    ErrorMsg
  ) then
  begin
    Result := TLLMResult.Fail(ErrorMsg);
    Exit;
  end;

  // --------------------------------------------------
  // 3. Success
  // --------------------------------------------------
  Result := TLLMResult.Ok(ParsedContent);
  Result.Raw := RawResult.Raw;
  Result.StatusCode := RawResult.StatusCode;
end;

initialization
  TLLMProviderFactory.RegisterProvider('lmstudio', TLLMProviderLMStudio);
end.
