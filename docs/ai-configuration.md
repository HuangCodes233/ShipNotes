# AI endpoint configuration

Text AI and Vision AI use separate credentials, models, Base URLs, and API
formats. In Settings, choose an OpenAI-compatible provider and select either
**Chat Completions (`/chat/completions`)** or **Responses (`/responses`)**.
Anthropic profiles continue to use the Messages API.

Existing profiles without an API-format setting default to Chat Completions.
Changing the format does not move credentials or alter local sync history.
Save the profile before testing it; the connection test uses the saved settings.
The vision connection test sends only a small fixed text prompt. It checks
credentials and endpoint access without reading images, and does not establish
that the model supports image recognition.

## Request URLs

The form previews the resolved request URL. Examples for Responses:

| Base URL | Request URL |
| --- | --- |
| `https://api.openai.com` | `https://api.openai.com/v1/responses` |
| `https://api.openai.com/v1` | `https://api.openai.com/v1/responses` |
| `https://api.deepseek.com` | `https://api.deepseek.com/responses` |
| `https://gateway.example.com/v1` | `https://gateway.example.com/v1/responses` |
| `https://gateway.example.com/custom/responses` | `https://gateway.example.com/custom/responses` |

For custom gateways whose paths do not follow the default `/v1` convention,
enter the complete endpoint. Switching formats replaces an existing
`/chat/completions` or `/responses` suffix instead of appending another endpoint.
Use a model available from that provider; selecting a format does not change the
model or make a text-only model accept images.

## Supported behavior

Both OpenAI-compatible formats support release-note parsing, translation,
store-copy extraction and optimization, and screenshot language matching.
Responses requests use JSON output, send images as `input_image` parts, and set
`store: false`. ShipNotes reads text from the response's `output` items and
rejects incomplete, failed, refused, or empty output before applying results.

This integration uses complete HTTP responses. It does not enable streaming,
background responses, tool calls, or server-side conversation storage. Tests
use synthetic payloads and a local HTTP test double; they do not establish
availability for a particular account, model, or gateway.

Protocol references checked on 2026-11-06:

- [OpenAI Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [DeepSeek Responses compatibility guide](https://api-docs.deepseek.com/guides/responses_api/)

See also [credentials and data flow](privacy-and-data.md).
