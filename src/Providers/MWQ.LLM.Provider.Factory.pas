unit MWQ.LLM.Provider.Factory;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  MWQ.LLM.Provider;

type
  TLLMProviderClass = class of TInterfacedObject;

  TLLMProviderFactory = class
  private
    class var FRegistry: TDictionary<string, TLLMProviderClass>;

  public
    class constructor Create;
    class destructor Destroy;

    // Register provider
    class procedure RegisterProvider(const AName: string; AClass: TLLMProviderClass);

    // Create provider instance
    class function CreateProvider(const AName: string): ILLMProvider;

    // List available providers
    class function GetRegisteredProviders: TArray<string>;
  end;

implementation

{------------------------------------------------------------------------------}
{ Lifecycle }
{------------------------------------------------------------------------------}

class constructor TLLMProviderFactory.Create;
begin
  FRegistry := TDictionary<string, TLLMProviderClass>.Create;
end;

class destructor TLLMProviderFactory.Destroy;
begin
  FRegistry.Free;
end;

{------------------------------------------------------------------------------}
{ Register }
{------------------------------------------------------------------------------}

class procedure TLLMProviderFactory.RegisterProvider(
  const AName: string;
  AClass: TLLMProviderClass
);
begin
  if not Assigned(AClass) then
    Exit;

  FRegistry.AddOrSetValue(AName.ToLower, AClass);
end;

{------------------------------------------------------------------------------}
{ Create }
{------------------------------------------------------------------------------}

class function TLLMProviderFactory.CreateProvider(
  const AName: string
): ILLMProvider;
var
  Cls: TLLMProviderClass;
  Obj: TInterfacedObject;
begin
  if not FRegistry.TryGetValue(AName.ToLower, Cls) then
    raise Exception.CreateFmt('LLM Provider "%s" not registered.', [AName]);

  Obj := Cls.Create;

  // SAFE cast via interface
  if not Supports(Obj, ILLMProvider, Result) then
    raise Exception.CreateFmt('Provider "%s" does not support ILLMProvider.', [AName]);
end;

{------------------------------------------------------------------------------}
{ List }
{------------------------------------------------------------------------------}

class function TLLMProviderFactory.GetRegisteredProviders: TArray<string>;
begin
  Result := FRegistry.Keys.ToArray;
end;

end.