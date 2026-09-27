# AI chat integration

The platform uses one RAG protocol: the RAG service's synchronous `POST /chat`
endpoint. The backend stores its response as a normal platform chat message.
There is no `/triage` endpoint, callback, transcript-replay protocol, or separate
AI worker contract.

## Configuration

| Variable | Effect |
|---|---|
| `AI_SERVICE_URL` | Unset → the labelled local stub is used. Set → the backend posts to `{AI_SERVICE_URL}/chat`. |
| `AI_SERVICE_TOKEN` | Optional `Authorization: Bearer …` token sent to the RAG service. |
| `AI_TIMEOUT_MS` | Chat request timeout; defaults to `20000`. |

## Request

```http
POST {AI_SERVICE_URL}/chat
Content-Type: application/json
```

```json
{
  "session_id": "0c8f7ce8-963b-4fc3-9c6f-4685c096035d",
  "user_query": "My stomach hurts since this morning."
}
```

`session_id` is the platform conversation ID. The RAG service persists the
conversation history for that ID, so the backend forwards only the most recent
patient message.

## Response

For a follow-up question:

```json
{
  "session_id": "0c8f7ce8-963b-4fc3-9c6f-4685c096035d",
  "timestamp": "2026-09-27T05:30:00Z",
  "response_type": "mcq",
  "content": {
    "question": "How severe is the pain?",
    "options": ["Mild", "Moderate", "Severe"]
  }
}
```

For a completed response:

```json
{
  "session_id": "0c8f7ce8-963b-4fc3-9c6f-4685c096035d",
  "timestamp": "2026-09-27T05:31:00Z",
  "response_type": "text",
  "content": "Your preliminary report is ready."
}
```

`backend/src/lib/ai.js` is the only adapter: it maps an `mcq` response to the
platform's stored question message and a `text` response to a platform text
message. It does not infer clinical fields or reconstruct a different request.

## Verification

Run the backend and RAG focused checks:

```bash
cd backend && npm test
cd ../RAG && uv run pytest tests/test_schemas.py tests/test_routes.py -q
```
