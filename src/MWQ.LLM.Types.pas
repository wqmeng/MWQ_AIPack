unit MWQ.LLM.Types;

interface

type
  TPayloadType = (ptJson, ptText, ptForm);
  // ----------------------------
  // Provider Type
  // ----------------------------
  TLLMProviderType = (ptUnknown, ptOllama, ptLMStudio, ptLlamaCpp);

  // ----------------------------
  // Endpoint Flavor (provider-agnostic)
  // ----------------------------
  TEndpointFlavor = (
      // --- Standard capabilities ---
      efGenerate, // text completion
      efChat, // chat completion
      efEmbeddings, // embeddings
      // --- OpenAI-compatible ---
      efOpenAIChat, // /v1/chat/completions
      efOpenAICompletion, // /v1/completions
      // --- Template-only ---
      efInstruction, // instruction prompt
      efStructured, // structured input (e.g. TranslateGemma)
      // --- Raw ---
      efRaw // caller provides everything
  );

const
  EndpointFlavorNames: array[TEndpointFlavor] of string = (
      'efGenerate',
      'efChat',
      'efEmbeddings',
      'efOpenAIChat',
      'efOpenAICompletion',
      'efInstruction',
      'efStructured',
      'efRaw'
  );

type
  // ----------------------------
  // Model Type (capability-based)
  // ----------------------------
  TLLMModelType = (mtGeneric, mtChat, mtInstruct, mtEmbedding, mtTranslate, mtVision);

  // ----------------------------
  // Chat Message
  // ----------------------------
  TChatRole = (crSystem, crUser, crAssistant);

  TChatMessage = record
    Role: TChatRole;
    Content: string;
  end;

  // ----------------------------
  // Chat Request
  // ----------------------------
  TChatRequest = record
    Provider: TLLMProviderType;
    Model: string;
    Messages: TArray<TChatMessage>;
    Temperature: Double;
    MaxTokens: Integer;
    EndpointFlavor: TEndpointFlavor;
  end;

  // ----------------------------
  // Chat Response
  // ----------------------------
  TChatResponse = record
    Content: string;
    RawJson: string;
  end;

  // ----------------------------
  // Embedding Request
  // ----------------------------
  TEmbeddingRequest = record
    Model: string;
    Input: string;
  end;

  // ----------------------------
  // Embedding Response
  // ----------------------------
  TEmbeddingResponse = record
    Vector: TArray<Double>;
    RawJson: string;
  end;

  // ----------------------------
  // Provider Config
  // ----------------------------
  TLLMProviderConfig = record
    Provider: TLLMProviderType;
    BaseUrl: string;
    ApiKey: string; // optional (LM Studio = empty)
  end;

  TLLMCapability = (lcChat, lcTranslate, lcEmbed, lcVision);
  TLLMModelInfo = record
    RawName: string;

    Family: string; // llama, qwen, gemma, etc.
    Variant: string; // instruct, chat, base, etc.
    ProviderHint: string; // ollama, lmstudio, openai
    IsTranslator: Boolean;
    Capabilities: set of TLLMCapability;
  end;

// ----------------------------
// Helper Functions
// ----------------------------

function IsRawTextTransport(const E: TEndpointFlavor): Boolean;
function IsOpenAICompatible(const E: TEndpointFlavor): Boolean;
function IsJsonTransport(const E: TEndpointFlavor): Boolean;
function ChatRoleToString(ARole: TChatRole): string;

implementation

function IsOpenAICompatible(const E: TEndpointFlavor): Boolean;
begin
  Result := E in [efOpenAIChat, efOpenAICompletion, efEmbeddings];
end;

function IsJsonTransport(const E: TEndpointFlavor): Boolean;
begin
  Result := E in [
    efGenerate,
    efOpenAIChat,
    efOpenAICompletion,
    efEmbeddings,
    efChat,
    efStructured
  ];
end;

function IsRawTextTransport(const E: TEndpointFlavor): Boolean;
begin
  Result := (E = efRaw);
end;

function ChatRoleToString(ARole: TChatRole): string;
begin
  case ARole of
    crSystem: Result := 'system';
    crUser: Result := 'user';
    crAssistant: Result := 'assistant';
  else
    Result := 'user';
  end;
end;

end.
