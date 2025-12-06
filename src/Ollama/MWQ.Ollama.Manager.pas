unit MWQ.Ollama.Manager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Net.HttpClient, MWQ.Ollama.Types, System.SyncObjs;

type
  TOllamaManager = class
  private
    class var FHttpClient: THttpClient;
    class var FBaseURL: string;
    class var FActiveModels: TList<string>;
    class var FKeepAliveThread: TThread;
    class var FKeepAliveEvent: TLightweightEvent;
    class var FTerminateKeepAlive: Boolean;
    class var FKeepAliveThreadStarted: Boolean;

    class procedure KeepAliveProc;

    class constructor Create;
    class destructor Destroy;

    class function GetClient: THttpClient; static;
  public
    class procedure Init(const BaseURL: string); static;

    // --- Server ---
    class function IsServerRunning: Boolean; static;

    // --- Models ---
    class function GetModelsList: TArray<string>; static;
    class function IsModelActive(const ModelName: string): Boolean; static;

    // --- Control ---
    class function StartModel(const ModelName: string): Boolean; static;

    class procedure AddActiveModel(const ModelName: string);
    class procedure RemoveActiveModel(const ModelName: string);

    class procedure StartKeepAlive;   // start periodic keep-alive
    class procedure StopKeepAlive;    // stop periodic keep-alive
    class function IsKeepAliveThreadStarted: Boolean;
  end;

implementation

uses
  System.JSON;

{ TOllamaManager }

{ --- Active models management --- }
class procedure TOllamaManager.AddActiveModel(const ModelName: string);
begin
  if not TOllamaManager.FActiveModels.Contains(ModelName) then
    TOllamaManager.FActiveModels.Add(ModelName);
end;

class procedure TOllamaManager.RemoveActiveModel(const ModelName: string);
begin
  FActiveModels.Remove(ModelName);
end;

{ --- Keep-alive thread --- }
class procedure TOllamaManager.KeepAliveProc;
var
  Model: string;
  LBody: TStringStream;
begin
  while not FTerminateKeepAlive do
  begin
    FKeepAliveEvent.WaitFor(5 * 60 * 1000); // 5 minutes
    if FTerminateKeepAlive then begin
      Break;
    end;
    FKeepAliveEvent.ResetEvent;

    for Model in FActiveModels do
    begin
      try
        LBody := TStringStream.Create(Format('{"model":"%s","prompt":"Ping","stream":false}', [Model]), TEncoding.UTF8);
        try
          FHttpClient.Post(BuildOllamaUrl(efGenerate), LBody);
        finally
          LBody.Free;
        end;
      except
        on E: Exception do
          ; // ignore, just keep alive
      end;
    end;
  end;

  FTerminateKeepAlive := false;  // Set thread exit flag
end;

class procedure TOllamaManager.StartKeepAlive;
begin
  FKeepAliveThreadStarted := True;
  if FKeepAliveThread = nil then
    FKeepAliveThread := TThread.CreateAnonymousThread(TOllamaManager.KeepAliveProc);
  FKeepAliveThread.Start;
end;

class procedure TOllamaManager.StopKeepAlive;
begin
  if Assigned(FKeepAliveThread) then
  begin
    FTerminateKeepAlive := True;
    FKeepAliveEvent.SetEvent;
    while not FTerminateKeepAlive do  // Wait until thread KeepAlive exit;
      Sleep(1);
  end;
  FKeepAliveThreadStarted := false;
end;

class constructor TOllamaManager.Create;
begin
  FKeepAliveEvent := TLightweightEvent.Create;
  FKeepAliveThreadStarted := false;
  FHttpClient := THttpClient.Create;
  FActiveModels := TList<string>.Create;
  FTerminateKeepAlive := false;
end;

class destructor TOllamaManager.Destroy;
begin
  StopKeepAlive;
  FActiveModels.Free;
  FHttpClient.Free;
  FKeepAliveEvent.Free;
end;

class procedure TOllamaManager.Init(const BaseURL: string);
begin
  FBaseURL := BaseURL;
end;

class function TOllamaManager.GetClient: THttpClient;
begin
  if FHttpClient = nil then
    FHttpClient := THttpClient.Create;
  Result := FHttpClient;
end;

class function TOllamaManager.IsServerRunning: Boolean;
var
  Resp: IHTTPResponse;
begin
  Result := False;
  try
    Resp := FHttpClient.Get(BuildOllamaUrl('api/version'));
    Result := Resp.StatusCode = 200;
  except
    Result := False;
  end;
end;

class function TOllamaManager.GetModelsList: TArray<string>;
var
  Resp: IHTTPResponse;
  JsonObj: TJSONObject;
  JsonArr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
begin
  SetLength(Result, 0);
  try
    Resp := FHttpClient.Get(BuildOllamaUrl(OLLAMA_API_TAGS));
    if (Resp = nil) or (Resp.StatusCode <> 200) then
      Exit;

    JsonObj := TJSONObject.ParseJSONValue(Resp.ContentAsString) as TJSONObject;
    try
      if JsonObj = nil then Exit;

      JsonArr := JsonObj.GetValue<TJSONArray>('models'); // <- changed from 'tags'
      if JsonArr = nil then Exit;

      SetLength(Result, JsonArr.Count);
      for I := 0 to JsonArr.Count - 1 do
      begin
        Item := JsonArr.Items[I] as TJSONObject;
        if Assigned(Item) then
          Result[I] := Item.GetValue<string>('name'); // <- get model name
      end;
    finally
      JsonObj.Free;
    end;
  except
    // optionally log the exception
  end;
end;

class function TOllamaManager.IsKeepAliveThreadStarted: Boolean;
begin
  Result := TOllamaManager.FKeepAliveThreadStarted;
end;

class function TOllamaManager.IsModelActive(const ModelName: string): Boolean;
var
  Resp: IHTTPResponse;
  JsonObj: TJSONObject;
begin
  Result := False;
  try
    Resp := FHttpClient.Get(BuildOllamaUrl(OLLAMA_API_PS));
    if Resp.StatusCode <> 200 then Exit;

    JsonObj := TJSONObject.ParseJSONValue(Resp.ContentAsString) as TJSONObject;
    try
      if JsonObj = nil then Exit;
      Result := JsonObj.GetValue(ModelName) <> nil;
    finally
      JsonObj.Free;
    end;
  except
  end;
end;

class function TOllamaManager.StartModel(const ModelName: string): Boolean;
var
  Resp: IHTTPResponse;
  LBody: TStringStream;
  DummyPrompt: string;
begin
  Result := False;

  // Send a tiny prompt just to load the model
  DummyPrompt := '{"model":"' + ModelName + '","prompt":"Hello","stream":false}';
  LBody := TStringStream.Create(DummyPrompt, TEncoding.UTF8);
  try
    try
      Resp := FHttpClient.Post(BuildOllamaUrl(efGenerate), LBody);
      Result := Resp.StatusCode = 200;
    except
      Result := False;
    end;
  finally
    LBody.Free;
  end;
end;

end.
