unit MWQ.Ollama.Types;

interface

{

[GIN-debug] HEAD   /                         --> github.com/ollama/ollama/server.(*Server).GenerateRoutes.func1 (5 handlers)
[GIN-debug] GET    /                         --> github.com/ollama/ollama/server.(*Server).GenerateRoutes.func2 (5 handlers)
[GIN-debug] HEAD   /api/version              --> github.com/ollama/ollama/server.(*Server).GenerateRoutes.func3 (5 handlers)
[GIN-debug] GET    /api/version              --> github.com/ollama/ollama/server.(*Server).GenerateRoutes.func4 (5 handlers)
[GIN-debug] POST   /api/pull                 --> github.com/ollama/ollama/server.(*Server).PullHandler-fm (5 handlers)
[GIN-debug] POST   /api/push                 --> github.com/ollama/ollama/server.(*Server).PushHandler-fm (5 handlers)
[GIN-debug] HEAD   /api/tags                 --> github.com/ollama/ollama/server.(*Server).ListHandler-fm (5 handlers)
[GIN-debug] GET    /api/tags                 --> github.com/ollama/ollama/server.(*Server).ListHandler-fm (5 handlers)
[GIN-debug] POST   /api/show                 --> github.com/ollama/ollama/server.(*Server).ShowHandler-fm (5 handlers)
[GIN-debug] DELETE /api/delete               --> github.com/ollama/ollama/server.(*Server).DeleteHandler-fm (5 handlers)
[GIN-debug] POST   /api/create               --> github.com/ollama/ollama/server.(*Server).CreateHandler-fm (5 handlers)
[GIN-debug] POST   /api/blobs/:digest        --> github.com/ollama/ollama/server.(*Server).CreateBlobHandler-fm (5 handlers)
[GIN-debug] HEAD   /api/blobs/:digest        --> github.com/ollama/ollama/server.(*Server).HeadBlobHandler-fm (5 handlers)
[GIN-debug] POST   /api/copy                 --> github.com/ollama/ollama/server.(*Server).CopyHandler-fm (5 handlers)
[GIN-debug] GET    /api/ps                   --> github.com/ollama/ollama/server.(*Server).PsHandler-fm (5 handlers)
[GIN-debug] POST   /api/generate             --> github.com/ollama/ollama/server.(*Server).GenerateHandler-fm (5 handlers)
[GIN-debug] POST   /api/chat                 --> github.com/ollama/ollama/server.(*Server).ChatHandler-fm (5 handlers)
[GIN-debug] POST   /api/embed                --> github.com/ollama/ollama/server.(*Server).EmbedHandler-fm (5 handlers)
[GIN-debug] POST   /api/embeddings           --> github.com/ollama/ollama/server.(*Server).EmbeddingsHandler-fm (5 handlers)
[GIN-debug] POST   /v1/chat/completions      --> github.com/ollama/ollama/server.(*Server).ChatHandler-fm (6 handlers)
[GIN-debug] POST   /v1/completions           --> github.com/ollama/ollama/server.(*Server).GenerateHandler-fm (6 handlers)
[GIN-debug] POST   /v1/embeddings            --> github.com/ollama/ollama/server.(*Server).EmbedHandler-fm (6 handlers)
[GIN-debug] GET    /v1/models                --> github.com/ollama/ollama/server.(*Server).ListHandler-fm (6 handlers)
[GIN-debug] GET    /v1/models/:model         --> github.com/ollama/ollama/server.(*Server).ShowHandler-fm (6 handlers)

}

const
  OLLAMA_BASE_URL = 'http://localhost:11434/';
  // ----------------------------
  // Core Model Interaction APIs
  // ----------------------------

  OLLAMA_API_GENERATE        = 'api/generate';
  OLLAMA_API_CHAT            = 'api/chat';
  OLLAMA_API_EMBED           = 'api/embed';
  OLLAMA_API_EMBEDDINGS      = 'api/embeddings';  // alias

  // OpenAI-compatible endpoints
  OLLAMA_V1_CHAT_COMPLETIONS = 'v1/chat/completions';
  OLLAMA_V1_COMPLETIONS      = 'v1/completions';
  OLLAMA_V1_EMBEDDINGS       = 'v1/embeddings';
  OLLAMA_V1_MODELS           = 'v1/models';         // GET list
  OLLAMA_V1_MODEL            = 'v1/models/:model';  // GET info

  // ----------------------------
  // Model Management APIs
  // ----------------------------

  OLLAMA_API_PULL            = 'api/pull';
  OLLAMA_API_PUSH            = 'api/push';
  OLLAMA_API_TAGS            = 'api/tags';          // list installed models
  OLLAMA_API_SHOW            = 'api/show';          // model manifest
  OLLAMA_API_DELETE          = 'api/delete';        // delete model
  OLLAMA_API_CREATE          = 'api/create';        // create/import model
  OLLAMA_API_COPY            = 'api/copy';          // rename model
  OLLAMA_API_BLOBS           = 'api/blobs/:digest'; // upload chunks

  // ----------------------------
  // System / Server Information
  // ----------------------------

  OLLAMA_API_VERSION         = 'api/version';
  OLLAMA_API_PS              = 'api/ps';            // running models

type
  // Types of payload formats we can generate.
  TEndpointFlavor = (
    // --- Real HTTP Payload Types ---
    efGenerate,          // /api/generate
    efChat,              // /api/chat
    efOpenAIChat,        // /v1/chat/completions
    efEmbeddings,        // /api/embed

    // --- Template-only formats ---
    efRivaTemplate,      // build Riva template (no endpoint)
    efInstruction,       // instruction-style template (no endpoint)

    // --- Raw ---
    efRaw                // caller-provided payload + URL
  );

  TOllamaModelType = (
    mtGeneric,
    mtQwen,
    mtLlama,
    mtMistral,
    mtGemma,
    mtRiva
  );

function EndpointFromFlavor(AFlavor: TEndpointFlavor): string;
function BuildOllamaUrl(const AFlavor: TEndpointFlavor): string; overload;
function BuildOllamaUrl(const AFlavorStr: string): string; overload;

const
    // String names corresponding to TEndpointFlavor (same order!)
  EndpointFlavorNames: array[TEndpointFlavor] of string = (
    'efGenerate',
    'efChat',
    'efOpenAIChat',
    'efEmbeddings',
    'efRivaTemplate',
    'efInstruction',
    'efRaw'
  );

var
  VOllama_Base_Url: String;

implementation
uses
  System.SysUtils;

function EndpointFromFlavor(AFlavor: TEndpointFlavor): string;
begin
  case AFlavor of
    efGenerate   : Result := OLLAMA_API_GENERATE;        // api/generate
    efChat       : Result := OLLAMA_API_CHAT;            // api/chat
    efOpenAIChat : Result := OLLAMA_V1_CHAT_COMPLETIONS; // v1/chat/completions
    efEmbeddings : Result := OLLAMA_API_EMBED;           // api/embed
  else
    Result := ''; // Template-only or Raw flavor
  end;
end;

function BuildOllamaUrl(const AFlavor: TEndpointFlavor): string; overload;
var
  CleanBase: string;
  Endpoint: string;
begin
  Endpoint := EndpointFromFlavor(AFlavor);

  // If endpoint has no HTTP path (templates, raw mode)
  if Endpoint = '' then
    Exit('');

  // Normalize base URL: remove trailing slash
  CleanBase := VOllama_Base_Url;
  if CleanBase.EndsWith('/') then
    CleanBase := Copy(CleanBase, 1, Length(CleanBase)-1);

  // Build final URL
  Result := CleanBase + '/' + Endpoint;
end;

function BuildOllamaUrl(const AFlavorStr: string): string; overload;
var
  CleanBase: string;
begin
  if AFlavorStr = '' then
    Exit(VOllama_Base_Url);

  // Normalize base URL: remove trailing slash
  CleanBase := VOllama_Base_Url;
  if CleanBase.EndsWith('/') then
    CleanBase := Copy(CleanBase, 1, Length(CleanBase)-1);

  // Build final URL
  Result := CleanBase + '/' + AFlavorStr;
end;

initialization
  // Set default Ollama base URL on startup
  VOllama_Base_Url := OLLAMA_BASE_URL;

end.

