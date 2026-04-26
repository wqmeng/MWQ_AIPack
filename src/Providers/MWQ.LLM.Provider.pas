unit MWQ.LLM.Provider;

interface

uses
  MWQ.LLM.Types,
  Spring.Collections;

type
  TLLMResult = record
    Success: Boolean;

    Content: string; // 解析后的内容
    ErrorMsg: string; // 错误信息

    Raw: string; // 原始返回（调试必备）
    StatusCode: Integer; // HTTP 状态码

    // 可选扩展（以后用）
    FinishReason: string;
    TokensUsed: Integer;

    class function Ok(const AContent: string): TLLMResult; static; inline;
    class function Fail(const AError: string): TLLMResult; static; inline;
  end;

  ILLMProvider = interface
    ['{A3F6B9C2-8D41-4F2E-9C91-1B2F8A77E001}']

    // ----------------------------
    // Core Info
    // ----------------------------
    function GetName: string;
    function GetBaseURL: string;
    procedure SetBaseURL(const Value: string);

    // ----------------------------
    // Capability
    // ----------------------------
    function SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean;

    // ----------------------------
    // Raw Execution
    // ----------------------------
    function Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult;

    // ----------------------------
    // High-Level Chat
    // ----------------------------
    function Chat(
        const AModel: string;
        const AMessages: TArray<TPair<string, string>>;
        AFlavor: TEndpointFlavor
    ): TLLMResult;

    // ----------------------------
    // Generate (completion)
    // ----------------------------
    function Generate(const AModel: string; const APrompt: string; AFlavor: TEndpointFlavor): TLLMResult;

    // ----------------------------
    // Translate (special helper)
    // ----------------------------
    function Translate(const AModel: string; const Text, SrcCode, DstCode, SrcName, DstName: string): TLLMResult;

    function GetModels(): TArray<string>;
  end;

  TBaseLLMProvider = class(TInterfacedObject, ILLMProvider)
  protected
    FBaseURL: string;
    FOwner: TObject;
    FName: string;

    function InternalExecute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult;
    // ----------------------------
    // Execution
    // ----------------------------
//    function Post(const Endpoint: TEndpointFlavor; const Payload: string): string;
  public
    constructor Create(const AOwner: TObject); virtual;
    destructor Destroy; override;
    // ----------------------------
    // Core Info
    // ----------------------------
    function GetName: string;

    function GetBaseURL: string; virtual;
    procedure SetBaseURL(const Value: string); virtual;

    // ----------------------------
    // Capability
    // ----------------------------
    function SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean; virtual;

    // ----------------------------
    // Raw Execution
    // ----------------------------
    function Execute(const AModel: string; const APayload: string; AFlavor: TEndpointFlavor): TLLMResult; virtual;

    // ----------------------------
    // High-Level Chat
    // ----------------------------
    function Chat(
        const AModel: string;
        const AMessages: TArray<TPair<string, string>>;
        AFlavor: TEndpointFlavor
    ): TLLMResult; virtual;

    // ----------------------------
    // Generate (completion)
    // ----------------------------
    function Generate(const AModel: string; const APrompt: string; AFlavor: TEndpointFlavor): TLLMResult; virtual;

    // ----------------------------
    // Translate (special helper)
    // ----------------------------
    function Translate(
        const AModel: string;
        const Text, SrcCode, DstCode, SrcName, DstName: string
    ): TLLMResult; virtual;
    // ----------------------------
    function GetModels: TArray<string>; virtual;

    property Name: string read FName write FName;
  end;

implementation
uses
  System.Net.HttpClient,
  System.Classes,
  MWQ.LLM.PromptBuilder,
  MWQ.LLM.ResponseParser,
  MWQ.LLM.ModelDetector,
  MWQ.LLM.Manager,
  System.SysUtils;

constructor TBaseLLMProvider.Create(const AOwner: TObject);
begin
  inherited Create;
  // Optionally, you can store a reference to the manager if needed
  FName := 'base';
  FOwner := AOwner;
end;

destructor TBaseLLMProvider.Destroy;
begin
  // Clean up any resources if necessary
  inherited Destroy;
end;

{------------------------------------------------------------------------------}
function TBaseLLMProvider.Chat(
    const AModel: string;
    const AMessages: TArray<TPair<string, string>>;
    AFlavor: TEndpointFlavor
): TLLMResult;
begin
  Result := TLLMResult.Fail(Format('Provider [%s] does not support chat endpoint', [GetName]));
end;

function TBaseLLMProvider.Execute(const AModel, APayload: string; AFlavor: TEndpointFlavor): TLLMResult;
begin
  Result := TLLMResult.Fail(Format('Provider [%s] does not support execute endpoint', [GetName]));
end;

function TBaseLLMProvider.Generate(const AModel, APrompt: string; AFlavor: TEndpointFlavor): TLLMResult;
begin
  Result := TLLMResult.Fail(Format('Provider [%s] does not support generate endpoint', [GetName]));
end;

function TBaseLLMProvider.GetBaseURL: string;
begin
  Result := FBaseURL;
end;

function TBaseLLMProvider.GetModels: TArray<string>;
begin
  //  Result := TLLMManager(Self.FOwner).GetModelsList(Self.FBaseUrl);
  Result := [];
end;

function TBaseLLMProvider.GetName: string;
begin
  Result := FName;
end;

function TBaseLLMProvider.InternalExecute(const AModel, APayload: string; AFlavor: TEndpointFlavor): TLLMResult;
begin
  Result := TLLMManager(FOwner).Post(AFlavor, FBaseUrl, APayload);
end;

procedure TBaseLLMProvider.SetBaseURL(const Value: string);
begin
  FBaseURL := Value;
end;

function TBaseLLMProvider.SupportsEndpoint(AFlavor: TEndpointFlavor): Boolean;
begin
  // By default, assume all endpoints are supported. Override in specific providers.
  Result := True;
end;

function TBaseLLMProvider.Translate(
    const AModel: string;
    const Text, SrcCode, DstCode, SrcName, DstName: string
): TLLMResult;
begin
  Result := TLLMResult.Fail(Format('Provider [%s] does not support Translate', [GetName]));
end;

{ TLLMResult }

class function TLLMResult.Fail(const AError: string): TLLMResult;
begin
  Result := Default(TLLMResult);
  Result.Success := False;
  Result.Content := '';
  Result.ErrorMsg := AError;
end;

class function TLLMResult.Ok(const AContent: string): TLLMResult;
begin
  Result := Default(TLLMResult);
  Result.Success := True;
  Result.Content := AContent;
  Result.ErrorMsg := '';
end;

end.
