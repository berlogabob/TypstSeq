class ProviderPreset {
  const ProviderPreset(this.kind, this.label, this.url, {this.cloud = false});

  final String kind;
  final String label;
  final String url;
  final bool cloud;
}

const providerPresets = <ProviderPreset>[
  ProviderPreset('openai-compatible', 'Ollama', 'http://localhost:11434/v1'),
  ProviderPreset(
    'openai-compatible',
    'Unsloth Studio',
    'http://<host>:8888/v1',
  ),
  ProviderPreset('openai-compatible', 'LM Studio', 'http://localhost:1234/v1'),
  ProviderPreset(
    'openai-compatible',
    'OpenAI',
    'https://api.openai.com/v1',
    cloud: true,
  ),
  ProviderPreset(
    'anthropic',
    'Claude (Anthropic)',
    'https://api.anthropic.com/v1',
    cloud: true,
  ),
  ProviderPreset(
    'openai-compatible',
    'Gemini',
    'https://generativelanguage.googleapis.com/v1beta/openai',
    cloud: true,
  ),
  ProviderPreset(
    'openai-compatible',
    'Mistral',
    'https://api.mistral.ai/v1',
    cloud: true,
  ),
  ProviderPreset(
    'openai-compatible',
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    cloud: true,
  ),
];
