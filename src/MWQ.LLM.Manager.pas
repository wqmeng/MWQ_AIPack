unit MWQ.LLM.Manager;

interface

uses
  System.SysUtils,
  System.Classes,
  Spring.Collections,
  System.Net.HttpClient,
  System.SyncObjs,
  MWQ.LLM.Types,
  MWQ.LLM.Provider,
  MWQ.Pool.HttpClientPool,
  MWQ.Limiter.RateLimiter;

type
  TLLMManager = class
  private
    FKeepAliveThread: TThread;
    FProviders: IList<ILLMProvider>;
    FHttpClientPool: THttpClientPool;
    FRateLimiter: TRateLimiter;
    FRateLimit: Integer;
    FLastRefill: TDateTime;
    FTokens: Integer;
    FRateLock: TObject;
  private
    class var
      FActiveModels: IList<string>;
    class var
      FKeepAliveEvent: TLightweightEvent;
    class var
      FTerminateKeepAlive: Boolean;
    class var
      FKeepAliveThreadStarted: Boolean;
  public
    // ----------------------------
    // Models (generic)
    // ----------------------------
    class procedure AddActiveModel(const ModelName: string);
    class procedure RemoveActiveModel(const ModelName: string);

    class function IsModelActive(const ModelName: string): Boolean;
    class function IsKeepAliveThreadStarted: Boolean;
    class function GetTranslateLanguages(const ModelInfo: TLLMModelInfo): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddProvider(const Provider: ILLMProvider);
    procedure RemoveProvider(const Provider: ILLMProvider);
    function GetProvider(const ProviderName: string): ILLMProvider;
    // ----------------------------
    // Init
    // ----------------------------
    function BuildUrl(const AFlavor: TEndpointFlavor; const ABaseUrl: string): string;
    function GetModelsList(const ABaseUrl: string): TArray<string>;
    // ----------------------------
    // Server
    // ----------------------------
    function IsServerRunning(const ABaseUrl: string): Boolean;
    procedure KeepAliveProc;
    // ----------------------------
    // Keep Alive
    // ----------------------------
    procedure StartKeepAlive;
    procedure StopKeepAlive;
    function Post(const Endpoint: TEndpointFlavor; const BaseUrl, Payload: string): TLLMResult;

    function GetProviderNames: TArray<string>;

    procedure SetRateLimit(const AMax: Integer);
  end;

implementation

uses
  Neslib.Json,
  MWQ.LLM.Model.Translate;

{------------------------------------------------------------------------------}
{ Constructor / Destructor }
{------------------------------------------------------------------------------}

function TLLMManager.BuildUrl(const AFlavor: TEndpointFlavor; const ABaseUrl: string): string;
var
  Url, CleanBase: string;
begin
  case AFlavor of
    efOpenAIChat: Url := 'v1/chat/completions';
    efChat: Url := 'api/chat';
    efGenerate: Url := 'api/generate';
  else
    Url := 'v1/chat/completions';
  end;

  if Url = '' then
    Exit(ABaseUrl);

  // Normalize base URL: remove trailing slash
  CleanBase := ABaseUrl;
  if CleanBase.EndsWith('/') then
    CleanBase := Copy(CleanBase, 1, Length(CleanBase) - 1);

  // Build final URL
  Result := CleanBase + '/' + Url;
end;

constructor TLLMManager.Create;
begin
  FActiveModels := TCollections.CreateList<string>;
  FKeepAliveEvent := TLightweightEvent.Create;
  FHttpClientPool := THttpClientPool.Create();
  FTerminateKeepAlive := False;
  FKeepAliveThreadStarted := False;

  FRateLock := TObject.Create;
  FRateLimit := 0; // 0 = unlimited
  FTokens := 0;
  FLastRefill := Now;

  FProviders := TCollections.CreateList<ILLMProvider>;
end;

destructor TLLMManager.Destroy;
begin
  StopKeepAlive;
  FActiveModels := nil;
  FKeepAliveEvent.Free;
  FHttpClientPool.Free;
  if Assigned(FRateLimiter) then
    FRateLimiter.Free;
  if Assigned(FRateLock) then
    FRateLock.Free;
  FProviders := nil;
end;

function TLLMManager.GetModelsList(const ABaseUrl: string): TArray<string>;
var
  Resp: IHTTPResponse;
  Doc: IJsonDocument;
  JsonArr, Item, LVal: TJsonValue;
  I, LCount: Integer;
  Client: THttpClient;
  Url: string;
begin
  SetLength(Result, 0);

  Client := FHttpClientPool.Acquire;
  try
    try
      Url := BuildUrl(efOpenAIChat, ABaseUrl);

      // Set headers explicitly (VERY IMPORTANT)
      Client.CustomHeaders['Accept'] := 'application/json';

      Resp := Client.Get(Url);

      if (Resp = nil) or (Resp.StatusCode <> 200) then
        Exit;

      Doc := TJsonDocument.Parse(Resp.ContentAsString);
      if Doc = nil then
        Exit;

      // Safer access
      if not Doc.Root.TryGetValue('models', JsonArr) then
        Exit;

      if not JsonArr.IsArray then
        Exit;

      SetLength(Result, JsonArr.Count);
      LCount := 0;
      for I := 0 to JsonArr.Count - 1 do begin
        Item := JsonArr.Items[I];

        if Item.IsNull then
          Continue;

        // safer extraction
        if Item.TryGetValue('name', LVal) then begin
          Result[LCount] := LVal.ToString;
          Inc(LCount);
        end
        else
          Result[I] := '';
      end;
      SetLength(Result, LCount);
    except
      // swallow errors (same behavior as your original)
    end;

  finally
    // MUST always release
    FHttpClientPool.Release(Client);
  end;
end;

{------------------------------------------------------------------------------}
{ Server Check }
{------------------------------------------------------------------------------}

function TLLMManager.IsServerRunning(const ABaseUrl: string): Boolean;
var
  Client: THttpClient;
  Resp: IHTTPResponse;
begin
  Client := THttpClient.Create;
  try
    try
      // OpenAI-compatible endpoint (LM Studio / Ollama v1)
      Resp := Client.Get(ABaseUrl + '/v1/models');
      Result := Assigned(Resp) and (Resp.StatusCode = 200);
    except
      Result := False;
    end;
  finally
    Client.Free;
  end;
end;

{------------------------------------------------------------------------------}
{ Active Models }
{------------------------------------------------------------------------------}

class procedure TLLMManager.AddActiveModel(const ModelName: string);
begin
  if not FActiveModels.Contains(ModelName) then
    FActiveModels.Add(ModelName);
end;

class procedure TLLMManager.RemoveActiveModel(const ModelName: string);
begin
  FActiveModels.Remove(ModelName);
end;

class function TLLMManager.IsModelActive(const ModelName: string): Boolean;
begin
  Result := FActiveModels.Contains(ModelName);
end;

{------------------------------------------------------------------------------}
{ Keep Alive Thread }
{------------------------------------------------------------------------------}

procedure TLLMManager.KeepAliveProc;
var
  Model: string;
  DummyJSON: string;
begin
  while not FTerminateKeepAlive do begin
    // wait up to 5 minutes
    if FKeepAliveEvent.WaitFor(5 * 60 * 1000) = wrSignaled then begin
      FKeepAliveEvent.ResetEvent;
      if FTerminateKeepAlive then
        Break;
    end;

    for Model in FActiveModels do begin
      try
        // OpenAI-style ping (LM Studio compatible)
        DummyJSON :=
            '{'
                + '"model":"'
                + Model
                + '",'
                + '"messages":[{"role":"user","content":"ping"}],'
                + '"max_tokens":1'
                + '}';

        Post(efOpenAIChat, '', DummyJSON);
      except
        // ignore errors
      end;
    end;
  end;

  FTerminateKeepAlive := False;
end;

procedure TLLMManager.SetRateLimit(const AMax: Integer);
begin
  TMonitor.Enter(FRateLock);
  try
    FRateLimit := AMax;
    if not Assigned(FRateLimiter) then begin
      FRateLimiter := TRateLimiter.Create(AMax, 1000);
    end;
  finally
    TMonitor.Exit(FRateLock);
  end;
end;

procedure TLLMManager.StartKeepAlive;
begin
  FKeepAliveThreadStarted := True;

  if FKeepAliveThread = nil then begin
    FKeepAliveThread := TThread.CreateAnonymousThread(KeepAliveProc);
    FKeepAliveThread.FreeOnTerminate := False;
    FKeepAliveThread.Start;
  end;
end;

procedure TLLMManager.StopKeepAlive;
begin
  if Assigned(FKeepAliveThread) then begin
    FTerminateKeepAlive := True;
    FKeepAliveEvent.SetEvent;
    FKeepAliveThread.WaitFor;
    FreeAndNil(FKeepAliveThread);
  end;

  FKeepAliveThreadStarted := False;
end;

class function TLLMManager.IsKeepAliveThreadStarted: Boolean;
begin
  Result := FKeepAliveThreadStarted;
end;

function TLLMManager.Post(const Endpoint: TEndpointFlavor; const BaseUrl, Payload: string): TLLMResult;
var
  Client: THttpClient;
  Url: string;
  Resp: IHTTPResponse;
  Stream: TStringStream;
begin
  Result := TLLMResult.Fail('');
  Result.Raw := '';
  Result.StatusCode := 0;

  if Assigned(FRateLimiter) then
    FRateLimiter.Acquire;

  Client := FHttpClientPool.Acquire;
  try
    Url := BuildUrl(Endpoint, BaseUrl);

    Stream := TStringStream.Create(Payload, TEncoding.UTF8);
    try
      if IsRawTextTransport(Endpoint) then begin
        Client.CustomHeaders['Content-Type'] := 'text/plain; charset=utf-8';
        Client.CustomHeaders['Accept'] := '*/*';
      end
      else begin
        Client.CustomHeaders['Content-Type'] := 'application/json';
        Client.CustomHeaders['Accept'] := 'application/json';
      end;

      Resp := Client.Post(Url, Stream);

      if not Assigned(Resp) then begin
        Result.ErrorMsg := 'No HTTP response';
        Exit;
      end;

      Result.StatusCode := Resp.StatusCode;
      Result.Raw := Resp.ContentAsString;

      if (Resp.StatusCode >= 200) and (Resp.StatusCode < 300) then begin
        Result.Success := True;
        Result.Content := Result.Raw;
      end
      else begin
        Result.Success := False;
        Result.ErrorMsg := Result.Raw;
      end;

    finally
      Stream.Free;
    end;

  finally
    FHttpClientPool.Release(Client);
  end;
end;

procedure TLLMManager.AddProvider(const Provider: ILLMProvider);
begin
  if not FProviders.Contains(Provider) then
    FProviders.Add(Provider);
end;
procedure TLLMManager.RemoveProvider(const Provider: ILLMProvider);
begin
  FProviders.Remove(Provider);
end;

function TLLMManager.GetProvider(const ProviderName: string): ILLMProvider;
var
  P: ILLMProvider;
begin
  Result := nil;
  for P in FProviders do begin
    if SameText(TBaseLLMProvider(P).Name, ProviderName) then begin
      Result := P;
      Exit;
    end;
  end;
end;

function TLLMManager.GetProviderNames: TArray<string>;
var
  I: Integer;
begin
  if FProviders = nil then begin
    Result := [];
    Exit;
  end;
  SetLength(Result, FProviders.Count);
  for I := 0 to FProviders.Count - 1 do begin
    Result[I] := FProviders.Items[I].GetName;
  end;
end;

class function TLLMManager.GetTranslateLanguages(const ModelInfo: TLLMModelInfo): string;
begin
  Result := GetLanguages(ModelInfo);
end;

end.
