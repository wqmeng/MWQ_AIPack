unit MWQ.Ollama.Manager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Net.HttpClient, MWQ.Ollama.Types, System.SyncObjs;

type
  TOllamaManager = class
  private
    class var FBaseURL: string;
    class var FActiveModels: TList<string>;
    class var FKeepAliveThread: TThread;
    class var FKeepAliveEvent: TLightweightEvent;
    class var FTerminateKeepAlive: Boolean;
    class var FKeepAliveThreadStarted: Boolean;

    class procedure KeepAliveProc;

    class constructor Create;
    class destructor Destroy;

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

    class procedure StartKeepAlive;
    class procedure StopKeepAlive;
    class function IsKeepAliveThreadStarted: Boolean;
  end;

implementation

uses
  System.JSON, System.SysConst, System.DateUtils;

{ TOllamaManager }

{ --- Active models management --- }
class procedure TOllamaManager.AddActiveModel(const ModelName: string);
begin
  if not FActiveModels.Contains(ModelName) then
    FActiveModels.Add(ModelName);
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
  Client: THttpClient;
begin
  while not FTerminateKeepAlive do
  begin
    // Wait up to 5 minutes, or until SetEvent is called
    if FKeepAliveEvent.WaitFor(5 * 60 * 1000) = wrSignaled then
    begin
      FKeepAliveEvent.ResetEvent;
      if FTerminateKeepAlive then
        Break;
    end;

    Client := THttpClient.Create;
    try
      for Model in FActiveModels do
      begin
        try
          LBody := TStringStream.Create(Format('{"model":"%s","prompt":"Ping","stream":false}', [Model]), TEncoding.UTF8);
          try
            Client.Post(BuildOllamaUrl(efGenerate), LBody);
          finally
            LBody.Free;
          end;
        except
          // ignore
        end;
      end;
    finally
      Client.Free;
    end;
  end;

  FTerminateKeepAlive := False;
end;

class procedure TOllamaManager.StartKeepAlive;
begin
  FKeepAliveThreadStarted := True;
  if FKeepAliveThread = nil then
  begin
    FKeepAliveThread := TThread.CreateAnonymousThread(KeepAliveProc);
    FKeepAliveThread.FreeOnTerminate := False;
    FKeepAliveThread.Start;
  end;
end;

class procedure TOllamaManager.StopKeepAlive;
begin
  if Assigned(FKeepAliveThread) then
  begin
    FTerminateKeepAlive := True;
    FKeepAliveEvent.SetEvent; // wake up thread immediately
    FKeepAliveThread.WaitFor; // wait efficiently for thread to finish
    FreeAndNil(FKeepAliveThread);
  end;
  FKeepAliveThreadStarted := False;
end;

class constructor TOllamaManager.Create;
begin
  FActiveModels := TList<string>.Create;
  FKeepAliveEvent := TLightweightEvent.Create;
  FKeepAliveThreadStarted := False;
  FTerminateKeepAlive := False;
end;

class destructor TOllamaManager.Destroy;
begin
  StopKeepAlive;
  FActiveModels.Free;
  FKeepAliveEvent.Free;
end;

class procedure TOllamaManager.Init(const BaseURL: string);
begin
  FBaseURL := BaseURL;
end;

{ --- Server --- }
class function TOllamaManager.IsServerRunning: Boolean;
var
  Resp: IHTTPResponse;
  Client: THttpClient;
begin
  Client := THttpClient.Create;
  try
    try
      Resp := Client.Get(BuildOllamaUrl('api/version'));
      Result := Assigned(Resp) and (Resp.StatusCode = 200);
    except
      Result := False;
    end;
  finally
    Client.Free;
  end;
end;

{ --- Models --- }
class function TOllamaManager.GetModelsList: TArray<string>;
var
  Resp: IHTTPResponse;
  JsonObj: TJSONObject;
  JsonArr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Client: THttpClient;
begin
  SetLength(Result, 0);
  Client := THttpClient.Create;
  try
    try
      Resp := Client.Get(BuildOllamaUrl(OLLAMA_API_TAGS));
      if (Resp = nil) or (Resp.StatusCode <> 200) then Exit;

      JsonObj := TJSONObject.ParseJSONValue(Resp.ContentAsString) as TJSONObject;
      try
        if JsonObj = nil then Exit;
        JsonArr := JsonObj.GetValue<TJSONArray>('models');
        if JsonArr = nil then Exit;

        SetLength(Result, JsonArr.Count);
        for I := 0 to JsonArr.Count - 1 do
        begin
          Item := JsonArr.Items[I] as TJSONObject;
          if Assigned(Item) then
            Result[I] := Item.GetValue<string>('name');
        end;
      finally
        JsonObj.Free;
      end;
    except
      // ignore
    end;
  finally
    Client.Free;
  end;
end;

class function TOllamaManager.IsModelActive(const ModelName: string): Boolean;
var
  Resp: IHTTPResponse;
  JsonObj: TJSONObject;
  Client: THttpClient;
begin
  Result := False;
  Client := THttpClient.Create;
  try
    try
      Resp := Client.Get(BuildOllamaUrl(OLLAMA_API_PS));
      if (Resp = nil) or (Resp.StatusCode <> 200) then Exit;

      JsonObj := TJSONObject.ParseJSONValue(Resp.ContentAsString) as TJSONObject;
      try
        if JsonObj = nil then Exit;
        Result := JsonObj.GetValue(ModelName) <> nil;
      finally
        JsonObj.Free;
      end;
    except
      Result := False;
    end;
  finally
    Client.Free;
  end;
end;

class function TOllamaManager.StartModel(const ModelName: string): Boolean;
var
  LBody: TStringStream;
  Resp: IHTTPResponse;
  Client: THttpClient;
  DummyPrompt: string;
begin
  DummyPrompt := '{"model":"' + ModelName + '","prompt":"Hello","stream":false}';
  Client := THttpClient.Create;
  try
    LBody := TStringStream.Create(DummyPrompt, TEncoding.UTF8);
    try
      try
        Resp := Client.Post(BuildOllamaUrl(efGenerate), LBody);
        Result := Assigned(Resp) and (Resp.StatusCode = 200);
      except
        Result := False;
      end;
    finally
      LBody.Free;
    end;
  finally
    Client.Free;
  end;
end;

class function TOllamaManager.IsKeepAliveThreadStarted: Boolean;
begin
  Result := FKeepAliveThreadStarted;
end;

end.
