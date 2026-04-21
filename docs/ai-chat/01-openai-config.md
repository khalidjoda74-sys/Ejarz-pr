# OpenAI Config

## Recommended production setup

Use a server-side proxy or Cloud Function and pass it at build time:

```bash
flutter run \
  --dart-define=DARFO_AI_PROXY_URL=https://your-domain.example.com/ai/chat
```

The mobile app should not contain a production OpenAI API key.

## Development-only direct setup

For local testing only:

```bash
flutter run \
  --dart-define=ALLOW_CLIENT_OPENAI_DIRECT=true \
  --dart-define=OPENAI_API_KEY=sk-...
```

Legacy Firestore fallback is still supported through `_meta/openai.api_key`. It can be disabled with:

```bash
--dart-define=ALLOW_FIRESTORE_OPENAI_KEY_FALLBACK=false
```

## Environment variables

- `DARFO_AI_PROXY_URL` preferred production endpoint.
- `OPENAI_API_KEY` development-only direct key.
- `ALLOW_CLIENT_OPENAI_DIRECT` default: `false`.
- `ALLOW_FIRESTORE_OPENAI_KEY_FALLBACK` default: `true` for backward compatibility.
- `OPENAI_MODEL_FAST` default: `gpt-5.4`.
- `OPENAI_MODEL_DEFAULT` default: `gpt-5.4`.
- `OPENAI_MODEL_REASONING` default: `gpt-5.4`.
- `OPENAI_MODEL_REPORTS` default: `gpt-5.4`.
- `OPENAI_API_URL` default: `https://api.openai.com/v1/chat/completions`.
- `OPENAI_TEMPERATURE` default: `0.1`.
- `OPENAI_MAX_TOOL_STEPS` default: `2`.
- `OPENAI_TIMEOUT_MS` default: `45000`.

## Model routing

- Help and navigation: fast model.
- General lookups: default model.
- Contracts, payments, maintenance, and linking logic: reasoning model.
- Reports and financial summaries: reports model.

## Runtime notes

- The chat now reads compile-time proxy/key settings before trying Firestore fallback.
- Streaming and non-streaming calls share the same headers and timeout.
- Tool loops are capped by `OPENAI_MAX_TOOL_STEPS` to prevent repeated tool-call loops.
- Some dashboard/list/report/navigation commands can run locally through app tools even before OpenAI is configured.
